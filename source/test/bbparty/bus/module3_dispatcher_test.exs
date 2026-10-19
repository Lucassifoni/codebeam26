defmodule Bbparty.Bus.Module3DispatcherTest do
  use Bbparty.DataCase, async: false

  alias Bbparty.Bus.Module3Dispatcher
  alias Bbparty.Keyboard
  alias Bbparty.Layout
  alias Hardware.Components.PushButton
  alias Hardware.PhysicalComponent

  @drive 12
  @sense 25

  setup do
    id = String.to_atom(Keyboard.key_id(@drive, @sense))
    on_exit(fn -> PhysicalComponent.stop(id) end)
    %{id: id}
  end

  defp frame(drive, sense, pressed), do: {:frame, 0x03, <<0x82, drive, sense, pressed>>}

  defp dispatch(message), do: Module3Dispatcher.handle_info(message, new_state())
  defp new_state, do: %{warned: MapSet.new()}

  defp autoregister(value) do
    previous = Application.get_env(:bbparty, :key_autoregister)
    Application.put_env(:bbparty, :key_autoregister, value)
    on_exit(fn -> Application.put_env(:bbparty, :key_autoregister, previous) end)
  end

  describe "auto-registration" do
    test "announces the registration so an open control panel can show it", %{id: id} do
      autoregister(true)
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")

      dispatch(frame(@drive, @sense, 1))

      assert_receive {:component_registered, ^id}
      assert PhysicalComponent.running?(id), "announced before the process exists"
    end

    test "a press at an unknown crosspoint registers one component", %{id: id} do
      autoregister(true)

      assert {:noreply, _} = dispatch(frame(@drive, @sense, 1))

      instance = Layout.get_component(id)
      assert instance.module == PushButton

      assert instance.attrs == %{
               char: Keyboard.default_char(@drive, @sense),
               shift: nil,
               action: nil,
               red: nil
             }

      assert instance.position == Keyboard.default_position(@drive, @sense)
    end

    test "the registered component is running and got the press", %{id: id} do
      autoregister(true)
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")

      dispatch(frame(@drive, @sense, 1))

      assert_receive {:component_changed, ^id, %PushButton{pushed: true}}
    end

    test "a just-registered key types straight away", %{id: id} do
      autoregister(true)
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")
      char = Keyboard.default_char(@drive, @sense)

      dispatch(frame(@drive, @sense, 1))

      assert_receive {:component_event, ^id, :key_down, %{char: ^char}}
    end

    test "pressing the same key again does not register a second time", %{id: id} do
      autoregister(true)

      dispatch(frame(@drive, @sense, 1))
      dispatch(frame(@drive, @sense, 0))
      dispatch(frame(@drive, @sense, 1))

      assert [%{component_id: ^id}] = Layout.list_components()
    end

    test "a release at an unknown crosspoint registers nothing" do
      autoregister(true)

      dispatch(frame(@drive, @sense, 0))

      assert Layout.list_components() == []
    end

    test "nothing is registered when auto-registration is off" do
      autoregister(false)

      dispatch(frame(@drive, @sense, 1))

      assert Layout.list_components() == []
    end

    test "an address outside the matrix is dropped, not registered" do
      autoregister(true)

      assert {:noreply, _} = dispatch(frame(200, 200, 1))
      assert Layout.list_components() == []
    end
  end

  describe "warnings about unwired lines" do
    import ExUnit.CaptureLog

    test "name the chip behind the bad line" do
      log = capture_log(fn -> dispatch(frame(3, 4, 1)) end)

      assert log =~ "drive 3 (U2)"
    end

    test "are emitted once per address, not once per scan" do
      log =
        capture_log(fn ->
          Enum.reduce(1..20, new_state(), fn _, state ->
            {:noreply, state} = Module3Dispatcher.handle_info(frame(3, 4, 1), state)
            state
          end)
        end)

      assert log |> String.split("outside the matrix") |> length() == 2
    end

    test "distinct addresses each get their own warning" do
      log =
        capture_log(fn ->
          {:noreply, state} = Module3Dispatcher.handle_info(frame(3, 4, 1), new_state())
          Module3Dispatcher.handle_info(frame(3, 5, 1), state)
        end)

      assert log =~ "(3, 4)"
      assert log =~ "(3, 5)"
    end

    test "the board's Hello clears them, so a reboot reads fresh" do
      {:noreply, state} = Module3Dispatcher.handle_info(frame(3, 4, 1), new_state())
      {:noreply, state} = Module3Dispatcher.handle_info({:frame, 0x03, <<0x01>>}, state)

      log = capture_log(fn -> Module3Dispatcher.handle_info(frame(3, 4, 1), state) end)

      assert log =~ "(3, 4)"
    end
  end

  describe "delivery to an existing component" do
    setup %{id: id} do
      {:ok, _} = Layout.create_component(id, PushButton, %{char: "a"})
      {:ok, _} = PhysicalComponent.start(id, Layout.get_component(id))
      :ok
    end

    test "a press reaches the component and emits its meaning", %{id: id} do
      autoregister(false)
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(frame(@drive, @sense, 1))

      assert_receive {:component_changed, ^id, %PushButton{pushed: true}}
      assert_receive {:component_event, ^id, :key_down, %{char: "a", shift: nil, action: nil}}
    end

    test "a release reaches the component and reports it too", %{id: id} do
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(frame(@drive, @sense, 1))
      assert_receive {:component_event, ^id, :key_down, %{char: "a"}}

      dispatch(frame(@drive, @sense, 0))
      assert_receive {:component_changed, ^id, %PushButton{pushed: false}}
      assert_receive {:component_event, ^id, :key_up, %{char: "a"}}
    end

    test "no duplicate component is created for a known crosspoint" do
      autoregister(true)

      dispatch(frame(@drive, @sense, 1))

      assert length(Layout.list_components()) == 1
    end
  end

  describe "frame handling" do
    test "decoded events are broadcast on the module_3 topic" do
      autoregister(false)
      Module3Dispatcher.subscribe()

      dispatch(frame(@drive, @sense, 1))

      assert_receive {:module3, {:key_event, @drive, @sense, true}}
    end

    test "a reboot Hello is announced but triggers no resync" do
      Module3Dispatcher.subscribe()

      assert {:noreply, _} = dispatch({:frame, 0x03, <<0x01>>})
      assert_receive {:module3, {:hello}}
    end

    test "undecodable bodies and other modules' frames are ignored" do
      assert {:noreply, _} = dispatch({:frame, 0x03, <<0x99, 1, 2>>})
      assert {:noreply, _} = dispatch({:frame, 0x02, <<0x82, 1>>})
      assert {:noreply, _} = dispatch(:something_else)
      assert Layout.list_components() == []
    end
  end
end
