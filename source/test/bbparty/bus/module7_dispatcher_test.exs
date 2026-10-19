defmodule Bbparty.Bus.Module7DispatcherTest do
  use Bbparty.DataCase, async: false

  alias Bbparty.Bus.Module7Dispatcher
  alias Bbparty.Layout
  alias Bbparty.SwitchPanel
  alias Hardware.Components.SwitchWithTwoLeds
  alias Hardware.PhysicalComponent

  @board 0x07
  @drive 2
  @sense 4

  setup do
    id = String.to_atom(SwitchPanel.switch_id(@drive, @sense))
    on_exit(fn -> PhysicalComponent.stop(id) end)
    %{id: id}
  end

  defp key_frame(drive, sense, pressed), do: {:frame, @board, <<0x82, drive, sense, pressed>>}

  defp snapshot_frame(crosspoints) do
    bits =
      Enum.reduce(crosspoints, 0, fn {drive, sense}, acc ->
        Bitwise.bor(acc, Bitwise.bsl(1, drive * SwitchPanel.senses() + sense))
      end)

    {:frame, @board, <<0x88, bits::little-integer-size(64)>>}
  end

  defp dispatch(message), do: Module7Dispatcher.handle_info(message, new_state())
  defp new_state, do: %{warned: MapSet.new()}

  defp autoregister(value) do
    previous = Application.get_env(:bbparty, :key_autoregister)
    Application.put_env(:bbparty, :key_autoregister, value)
    on_exit(fn -> Application.put_env(:bbparty, :key_autoregister, previous) end)
  end

  defp registered?(id) do
    Enum.any?(Layout.list_components(), &(&1.component_id == id))
  end

  defp start_switch(id, attrs) do
    {:ok, _} = Layout.create_component(id, SwitchWithTwoLeds, attrs, %{"x" => 0, "y" => 0})
    {:ok, _pid} = PhysicalComponent.start(id, Layout.get_component(id))
    :ok
  end

  describe "auto-registration" do
    test "an unknown crosspoint registers one switch, carrying only its board", %{id: id} do
      autoregister(true)

      assert {:noreply, _} = dispatch(key_frame(@drive, @sense, 1))

      instance = Layout.get_component(id)
      assert instance.module == SwitchWithTwoLeds
      assert instance.attrs.module == @board
      assert instance.position == SwitchPanel.default_position(@drive, @sense)
    end

    test "nothing about the switch's meaning is guessed", %{id: id} do
      autoregister(true)
      dispatch(key_frame(@drive, @sense, 1))

      attrs = Layout.get_component(id).attrs
      assert attrs.feature == nil
      assert attrs.mode == nil
      assert attrs.status_led == nil
      assert attrs.available_led == nil
    end

    test "a switch thrown *up* commissions just as well", %{id: id} do
      autoregister(true)

      assert {:noreply, _} = dispatch(key_frame(@drive, @sense, 0))

      assert Layout.get_component(id).module == SwitchWithTwoLeds
      assert PhysicalComponent.running?(id)
    end

    test "announces the registration so an open control panel can show it", %{id: id} do
      autoregister(true)
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")

      dispatch(key_frame(@drive, @sense, 1))

      assert_receive {:component_registered, ^id}
      assert PhysicalComponent.running?(id), "announced before the process exists"
    end

    test "the registered switch is running and got the transition", %{id: id} do
      autoregister(true)
      dispatch(key_frame(@drive, @sense, 1))

      assert %SwitchWithTwoLeds{position: true} = PhysicalComponent.query_state(id)
    end

    test "off in the installation: an unknown crosspoint registers nothing", %{id: id} do
      autoregister(false)

      assert {:noreply, _} = dispatch(key_frame(@drive, @sense, 1))

      refute registered?(id)
      refute PhysicalComponent.running?(id)
    end

    test "a crosspoint on a spare line is still a switch", %{} do
      autoregister(true)
      id = String.to_atom(SwitchPanel.switch_id(7, 7))
      on_exit(fn -> PhysicalComponent.stop(id) end)

      dispatch(key_frame(7, 7, 1))

      assert Layout.get_component(id).module == SwitchWithTwoLeds
    end

    test "an address outside the bus registers nothing and warns once" do
      autoregister(true)

      {:noreply, state} = dispatch(key_frame(200, 200, 1))
      assert MapSet.member?(state.warned, {200, 200})
      refute registered?(:switch_200_200)

      {:noreply, again} = Module7Dispatcher.handle_info(key_frame(200, 200, 1), state)
      assert again.warned == state.warned
    end
  end

  describe "delivering transitions" do
    test "a known switch gets both edges", %{id: id} do
      start_switch(id, %{feature: "liga", mode: "toggle", module: @board})
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(key_frame(@drive, @sense, 1))
      assert_receive {:component_event, ^id, :toggle_feature, "liga"}

      dispatch(key_frame(@drive, @sense, 0))
      assert_receive {:component_event, ^id, :toggle_feature, "liga"}
    end
  end

  describe "a snapshot" do
    test "never reaches a toggle switch as a feature event", %{id: id} do
      start_switch(id, %{feature: "liga", mode: "toggle", module: @board})
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(snapshot_frame([{@drive, @sense}]))

      refute_receive {:component_event, ^id, :toggle_feature, _}, 50
      assert %SwitchWithTwoLeds{position: true} = PhysicalComponent.query_state(id)
    end

    test "sets the feature on a value switch, as state", %{id: id} do
      start_switch(id, %{feature: "dlig", mode: "position", module: @board})
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(snapshot_frame([{@drive, @sense}]))

      assert_receive {:component_event, ^id, :set_feature, {"dlig", true}}
    end

    test "an open switch is reported as open, not omitted", %{id: id} do
      start_switch(id, %{feature: "dlig", mode: "position", module: @board})
      PhysicalComponent.handle_event(id, :key_down, nil)
      assert %SwitchWithTwoLeds{position: true} = PhysicalComponent.query_state(id)

      dispatch(snapshot_frame([]))

      assert %SwitchWithTwoLeds{position: false} = PhysicalComponent.query_state(id)
    end

    test "registers nothing", %{id: id} do
      autoregister(true)

      dispatch(snapshot_frame([{@drive, @sense}]))

      refute registered?(id)
    end
  end

  describe "the topic" do
    test "decoded events are broadcast" do
      Module7Dispatcher.subscribe()
      on_exit(&Module7Dispatcher.unsubscribe/0)

      dispatch(key_frame(@drive, @sense, 1))

      assert_receive {:module7, {:key_event, @drive, @sense, true}}
    end

    test "unsubscribe/0 drops every subscription this process holds" do
      Module7Dispatcher.subscribe()
      Module7Dispatcher.subscribe()

      dispatch(key_frame(@drive, @sense, 1))
      assert_receive {:module7, {:key_event, @drive, @sense, true}}
      assert_receive {:module7, {:key_event, @drive, @sense, true}}

      Module7Dispatcher.unsubscribe()
      dispatch(key_frame(@drive, @sense, 1))
      refute_receive {:module7, _}, 50
    end

    test "a frame from another board is ignored" do
      Module7Dispatcher.subscribe()
      on_exit(&Module7Dispatcher.unsubscribe/0)

      assert {:noreply, _} = dispatch({:frame, 0x03, <<0x82, 1, 1, 1>>})
      refute_receive {:module7, _}, 50
    end

    test "a corrupt body is dropped, not decoded" do
      Module7Dispatcher.subscribe()
      on_exit(&Module7Dispatcher.unsubscribe/0)

      assert {:noreply, _} = dispatch({:frame, @board, <<0x82, 1, 1, 9>>})
      refute_receive {:module7, _}, 50
    end
  end

  describe "a board reset" do
    test "hello schedules one resync, however many hellos arrive" do
      {:noreply, state} = dispatch({:frame, @board, <<0x01>>})
      assert state.resync_timer

      {:noreply, again} = Module7Dispatcher.handle_info({:frame, @board, <<0x01>>}, state)
      assert again.resync_timer
      refute again.resync_timer == state.resync_timer

      Process.cancel_timer(again.resync_timer)
    end

    test "hello clears the warned set so a re-wired line reports again" do
      {:noreply, warned} = dispatch(key_frame(200, 200, 1))
      {:noreply, state} = Module7Dispatcher.handle_info({:frame, @board, <<0x01>>}, warned)

      assert MapSet.size(state.warned) == 0
      Process.cancel_timer(state.resync_timer)
    end
  end
end
