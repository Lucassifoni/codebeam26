defmodule Bbparty.PrintEffectTest do
  use Bbparty.DataCase, async: false

  alias Bbparty.Layout
  alias Bbparty.RenderState
  alias Hardware.Components.Printer
  alias Hardware.PhysicalComponent

  @printer :printer

  setup do
    render = Bbparty.RenderStateServer.get_state()

    on_exit(fn ->
      PhysicalComponent.stop(@printer)
      :sys.replace_state(Bbparty.RenderStateServer, &%{&1 | render: render})
    end)

    :ok
  end

  defp start_printer do
    {:ok, _} = Layout.create_component(@printer, Printer, %{})
    {:ok, _} = PhysicalComponent.start(@printer, Layout.get_component(@printer))
    :ok
  end

  defp print_impls(impls) do
    previous = Application.get_env(:bbparty, :print_impls)
    Application.put_env(:bbparty, :print_impls, impls)
    on_exit(fn -> Application.put_env(:bbparty, :print_impls, previous) end)
  end

  defp press_print do
    Phoenix.PubSub.broadcast(
      Bbparty.PubSub,
      "events",
      {:component_event, :print_button, :key_down, %{char: nil, shift: nil, action: "print"}}
    )
  end

  describe "the preview" do
    setup do
      Bbparty.Print.Preview.clear()
      Bbparty.Print.Cooldown.reset()
      on_exit(fn -> Bbparty.Print.Preview.clear() end)
      :ok
    end

    test "a capture that failed to print is still shown" do
      Bbparty.Print.Preview.put("captured-but-not-sent",
        width: 1181,
        height: 591,
        printed?: false
      )

      assert %{printed?: false, png: "captured-but-not-sent"} = Bbparty.Print.Preview.last()
    end

    test "and is marked as not printed, since a dry run looks identical" do
      Bbparty.Print.Preview.put("sent", printed?: true)
      assert Bbparty.Print.Preview.last().printed?

      Bbparty.Print.Preview.put("not sent", printed?: false)
      refute Bbparty.Print.Preview.last().printed?
    end
  end

  describe "the cooldown" do
    setup do
      Bbparty.Print.Cooldown.reset()
      on_exit(fn -> Bbparty.Print.Cooldown.reset() end)
      :ok
    end

    test "a second print inside the window costs no sticker" do
      test_pid = self()

      print_impls([
        fn _ ->
          case Bbparty.Print.Cooldown.claim() do
            :ok -> send(test_pid, :printed)
            {:error, _} -> send(test_pid, :refused)
          end
        end
      ])

      start_printer()

      press_print()
      assert_receive :printed, 1_000

      press_print()
      assert_receive :refused, 1_000
    end
  end

  describe "a PRINT press" do
    test "reaches the configured print implementation" do
      test_pid = self()
      print_impls([fn render -> send(test_pid, {:printed, render}) end])
      start_printer()

      press_print()

      assert_receive {:printed, %RenderState{}}, 1_000
    end

    test "hands the implementation the render state as it stood at the press" do
      test_pid = self()
      print_impls([fn render -> send(test_pid, {:printed, render.text}) end])
      start_printer()

      Phoenix.PubSub.broadcast(
        Bbparty.PubSub,
        "events",
        {:component_event, :a_key, :key_down, %{char: "x", shift: nil, action: nil}}
      )

      press_print()

      assert_receive {:printed, text}, 1_000
      assert String.ends_with?(text, "x")
    end

    test "fires every configured implementation" do
      test_pid = self()

      print_impls([
        fn _ -> send(test_pid, {:printed, :first}) end,
        fn _ -> send(test_pid, {:printed, :second}) end
      ])

      start_printer()

      press_print()

      assert_receive {:printed, :first}, 1_000
      assert_receive {:printed, :second}, 1_000
    end

    test "an implementation that raises does not kill the printer component" do
      test_pid = self()

      print_impls([
        fn _ -> raise "printer on fire" end,
        fn _ -> send(test_pid, {:printed, :after_the_failure}) end
      ])

      start_printer()

      press_print()

      assert_receive {:printed, :after_the_failure}, 1_000
      assert PhysicalComponent.running?(@printer)
    end

    test "is harmless when no printer component exists" do
      print_impls([fn _ -> raise "should never run" end])
      server = Process.whereis(Bbparty.RenderStateServer)

      press_print()
      Process.sleep(50)

      assert Process.alive?(server)
    end

    test "leaves the render state alone" do
      print_impls([])
      start_printer()
      before = Bbparty.RenderStateServer.get_state()

      press_print()
      Process.sleep(50)

      assert Bbparty.RenderStateServer.get_state() == before
    end
  end
end
