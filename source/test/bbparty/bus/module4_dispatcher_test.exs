defmodule Bbparty.Bus.Module4DispatcherTest do
  use Bbparty.DataCase, async: false

  alias Bbparty.Bus.Module4Dispatcher
  alias Bbparty.Layout
  alias Bbparty.TrackballPanel
  alias Hardware.Components.{PushButton, Trackball}
  alias Hardware.PhysicalComponent

  setup do
    button = String.to_atom(TrackballPanel.button_id(0))
    other = String.to_atom(TrackballPanel.button_id(1))
    ball = String.to_atom(TrackballPanel.trackball_id())

    on_exit(fn -> Enum.each([button, other, ball], &PhysicalComponent.stop/1) end)

    %{button: button, other: other, ball: ball}
  end

  defp buttons(bits), do: {:frame, 0x04, <<0x82, bits>>}
  defp activity(count), do: {:frame, 0x04, <<0x83, count>>}

  defp dispatch(message), do: Module4Dispatcher.handle_info(message, new_state())
  defp new_state, do: %{buttons: 0}

  defp autoregister(value) do
    previous = Application.get_env(:bbparty, :key_autoregister)
    Application.put_env(:bbparty, :key_autoregister, value)
    on_exit(fn -> Application.put_env(:bbparty, :key_autoregister, previous) end)
  end

  describe "button edges from the bitfield" do
    setup do
      autoregister(false)
      :ok
    end

    setup %{button: button} do
      {:ok, _} = Layout.create_component(button, PushButton, %{char: "a"})
      {:ok, _} = PhysicalComponent.start(button, Layout.get_component(button))
      :ok
    end

    test "a bit going up is a press", %{button: button} do
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")

      dispatch(buttons(0b01))

      assert_receive {:component_changed, ^button, %PushButton{pushed: true}}
    end

    test "the remembered field makes the next frame a release", %{button: button} do
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")

      {:noreply, state} = Module4Dispatcher.handle_info(buttons(0b01), new_state())
      assert_receive {:component_changed, ^button, %PushButton{pushed: true}}

      Module4Dispatcher.handle_info(buttons(0b00), state)
      assert_receive {:component_changed, ^button, %PushButton{pushed: false}}
    end

    test "a repeated identical field delivers nothing", %{button: button} do
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")

      {:noreply, state} = Module4Dispatcher.handle_info(buttons(0b01), new_state())
      assert_receive {:component_changed, ^button, %PushButton{pushed: true}}

      Module4Dispatcher.handle_info(buttons(0b01), state)
      refute_receive {:component_changed, ^button, _}
    end

    test "the press reaches the fold as the button's meaning", %{button: button} do
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(buttons(0b01))

      assert_receive {:component_event, ^button, :key_down, %{char: "a"}}
    end

    test "the board's Hello clears the remembered field", %{button: button} do
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")

      {:noreply, state} = Module4Dispatcher.handle_info(buttons(0b01), new_state())
      assert_receive {:component_changed, ^button, %PushButton{pushed: true}}

      {:noreply, state} = Module4Dispatcher.handle_info({:frame, 0x04, <<0x01>>}, state)
      assert state.buttons == 0

      Module4Dispatcher.handle_info(buttons(0b01), state)
      assert_receive {:component_changed, ^button, %PushButton{pushed: true}}
    end
  end

  describe "auto-registration" do
    test "a press on an unknown button registers one component", %{button: button} do
      autoregister(true)

      assert {:noreply, _} = dispatch(buttons(0b01))

      instance = Layout.get_component(button)
      assert instance.module == PushButton
      assert instance.position == TrackballPanel.button_default_position(0)
    end

    test "a registered button is inert until it is given meaning", %{button: button} do
      autoregister(true)
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(buttons(0b01))

      assert Layout.get_component(button).attrs == %{char: nil, shift: nil, action: nil, red: nil}
      refute_receive {:component_event, ^button, :key_down, _}
    end

    test "the registration is announced before the process exists", %{button: button} do
      autoregister(true)
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")

      dispatch(buttons(0b01))

      assert_receive {:component_registered, ^button}
      assert PhysicalComponent.running?(button)
    end

    test "a release on an unknown button registers nothing" do
      autoregister(true)

      {:noreply, state} = Module4Dispatcher.handle_info(buttons(0b01), %{buttons: 0b01})
      assert state.buttons == 0b01

      Module4Dispatcher.handle_info(buttons(0b00), %{buttons: 0b01})

      assert Layout.list_components() == []
    end

    test "the first spin registers the ball", %{ball: ball} do
      autoregister(true)

      dispatch(activity(30))

      instance = Layout.get_component(ball)
      assert instance.module == Trackball
      assert instance.attrs.module == 0x04
      assert instance.position == TrackballPanel.trackball_default_position()

      assert PhysicalComponent.query_state(ball) == %Trackball{
               intensity: 30,
               rolls: 1,
               module: 0x04
             }
    end

    test "spinning again does not register a second ball", %{ball: ball} do
      autoregister(true)

      dispatch(activity(30))
      dispatch(activity(40))

      assert [%{component_id: ^ball}] = Layout.list_components()
      assert %Trackball{rolls: 2} = PhysicalComponent.query_state(ball)
    end

    test "nothing is registered when auto-registration is off" do
      autoregister(false)

      dispatch(buttons(0b01))
      dispatch(activity(30))

      assert Layout.list_components() == []
    end

    test "both buttons in one frame register both", %{button: button, other: other} do
      autoregister(true)

      dispatch(buttons(0b11))

      ids = Layout.list_components() |> Enum.map(& &1.component_id) |> Enum.sort()
      assert ids == Enum.sort([button, other])
    end
  end

  describe "the trackball" do
    setup %{ball: ball} do
      autoregister(false)
      {:ok, _} = Layout.create_component(ball, Trackball, %{module: 0x04})
      {:ok, _} = PhysicalComponent.start(ball, Layout.get_component(ball))
      :ok
    end

    test "a spin emits a roll carrying its intensity", %{ball: ball} do
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(activity(77))

      assert_receive {:component_event, ^ball, :roll, 77}
    end

    test "the render state ignores a roll" do
      state = Bbparty.RenderState.new()

      assert {^state, [], []} = Bbparty.RenderState.apply(state, {:m4_trackball, :roll, 77})
    end
  end

  describe "a ball found by its claim" do
    setup do
      autoregister(false)
      on_exit(fn -> Enum.each([:lobby_ball, :other_board_ball], &PhysicalComponent.stop/1) end)
      :ok
    end

    test "is reached whatever the layout calls it" do
      {:ok, _} = Layout.create_component(:lobby_ball, Trackball, %{module: 0x04})
      {:ok, _} = PhysicalComponent.start(:lobby_ball, Layout.get_component(:lobby_ball))
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(activity(77))

      assert_receive {:component_event, :lobby_ball, :roll, 77}
    end

    test "a ball wired to another board hears nothing" do
      {:ok, _} = Layout.create_component(:other_board_ball, Trackball, %{module: 0x09})

      {:ok, _} =
        PhysicalComponent.start(:other_board_ball, Layout.get_component(:other_board_ball))

      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(activity(77))

      refute_receive {:component_event, :other_board_ball, _event, _payload}, 50
      assert %Trackball{rolls: 0} = PhysicalComponent.query_state(:other_board_ball)
    end
  end

  describe "frame handling" do
    setup do
      autoregister(false)
      :ok
    end

    test "decoded events are broadcast on the module_4 topic" do
      Module4Dispatcher.subscribe()

      dispatch(buttons(0b01))
      dispatch(activity(5))

      assert_receive {:module4, {:buttons, 1}}
      assert_receive {:module4, {:activity, 5}}
    end

    test "a reboot Hello is announced" do
      Module4Dispatcher.subscribe()

      assert {:noreply, _} = dispatch({:frame, 0x04, <<0x01>>})
      assert_receive {:module4, {:hello}}
    end

    test "a corrupt button field is dropped, not routed" do
      autoregister(true)

      assert {:noreply, state} = dispatch(buttons(0b100))

      assert state.buttons == 0
      assert Layout.list_components() == []
    end

    test "another board's frames are ignored" do
      Module4Dispatcher.subscribe()

      assert {:noreply, _} = dispatch({:frame, 0x03, <<0x82, 1, 2, 1>>})
      refute_receive {:module4, _}
    end
  end
end
