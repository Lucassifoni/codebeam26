defmodule Bbparty.PanelLampsTest do
  use Bbparty.DataCase, async: false

  alias Bbparty.Bus.LedShadow
  alias Bbparty.Bus.LedShadow.Frame
  alias Bbparty.Layout
  alias Bbparty.RenderState
  alias Bbparty.RenderStateServer
  alias Hardware.Components.PushButtonWithLed, as: Key
  alias Hardware.PhysicalComponent

  @keys [
    {:button_0, "align_left", 0},
    {:button_1, "align_center", 1},
    {:button_2, "uppercase", 2},
    {:button_3, "source_user", 3},
    {:button_4, "source_font_name", 4},
    {:button_5, "source_alpha_upper", 5},
    {:button_6, "source_alpha_lower", 6},
    {:button_7, "source_numbers", 7}
  ]

  setup do
    reset_render = fn ->
      :sys.replace_state(RenderStateServer, fn state ->
        %{state | render: RenderState.new()}
      end)
    end

    reset_render.()

    :sys.replace_state(LedShadow, fn state ->
      frames = Map.new(LedShadow.boards(), fn {id, %{width: w}} -> {id, Frame.new(w)} end)
      %{state | frames: frames, dirty: MapSet.new()}
    end)

    for {id, action, led} <- @keys do
      {:ok, _} = Layout.create_component(id, Key, %{action: action, module: 2, led: led})
      {:ok, _} = PhysicalComponent.start(id, Layout.get_component(id))
    end

    RenderStateServer.sync()
    Enum.each(@keys, fn {id, _, _} -> PhysicalComponent.query_state(id) end)

    on_exit(fn -> Enum.each(@keys, fn {id, _, _} -> PhysicalComponent.stop(id) end) end)
    on_exit(reset_render)

    :ok
  end

  defp press(id) do
    PhysicalComponent.handle_event(id, :key_down, nil)

    PhysicalComponent.query_state(id)
    RenderStateServer.get_state()
    Enum.each(@keys, fn {key, _, _} -> PhysicalComponent.query_state(key) end)
  end

  defp lit(id), do: PhysicalComponent.query_state(id).lit

  describe "the alignment pair" do
    test "lighting one darkens the other, with nothing coordinating them" do
      press(:button_1)

      assert lit(:button_1)
      refute lit(:button_0)

      press(:button_0)

      assert lit(:button_0)
      refute lit(:button_1)
    end
  end

  describe "the uppercase toggle" do
    test "follows the field it toggles" do
      press(:button_2)
      assert lit(:button_2)

      press(:button_2)
      refute lit(:button_2)
    end
  end

  describe "the five sources" do
    test "exactly one is lit, always" do
      for {id, _action, _led} <- Enum.slice(@keys, 3..7) do
        press(id)

        source_keys = Enum.slice(@keys, 3..7)
        assert lit(id)

        for {other, _, _} <- source_keys, other != id do
          refute lit(other), "#{other} should be dark while #{id} is chosen"
        end
      end
    end
  end

  describe "the panel and the board agree" do
    test "the lamps reach the board's picture on their own channels" do
      press(:button_7)

      frame = LedShadow.frame(2)

      assert Frame.lit?(frame, 7)
      assert Frame.lit?(frame, 0), "alignment starts left, so its lamp is lit from the start"
      refute Frame.lit?(frame, 4)
    end
  end

  describe "a change no key made" do
    test "still moves the lamps" do
      press(:button_7)
      press(:button_1)
      assert lit(:button_7)
      assert lit(:button_1)

      PhysicalComponent.handle_event(:button_0, :key_down, nil)
      RenderStateServer.get_state()

      RenderStateServer.get_state()
      :sys.replace_state(RenderStateServer, fn state -> %{state | render: RenderState.new()} end)
      RenderStateServer.sync()

      _ = :sys.get_state(RenderStateServer)

      Enum.each(@keys, fn {key, _, _} -> PhysicalComponent.query_state(key) end)

      assert lit(:button_3), "user text is the default source"
      refute lit(:button_7)
      refute lit(:button_2)
    end
  end
end
