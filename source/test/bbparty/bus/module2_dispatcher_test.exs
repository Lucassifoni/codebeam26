defmodule Bbparty.Bus.Module2DispatcherTest do
  use Bbparty.DataCase, async: false

  alias Bbparty.Bus.Module2Dispatcher
  alias Bbparty.Layout
  alias Hardware.Components.{FontSelector, Joystick, PushButton, PushButtonWithLed, RotaryEncoder}
  alias Hardware.PhysicalComponent

  @knob :text_quantity
  @stick :font_size_joystick
  @reader :font_selector

  setup do
    on_exit(fn -> Enum.each([@knob, @stick, @reader], &PhysicalComponent.stop/1) end)
    :ok
  end

  defp start(id, module, attrs) do
    {:ok, _} = Layout.create_component(id, module, attrs)
    {:ok, _} = PhysicalComponent.start(id, Layout.get_component(id))
    :ok
  end

  defp dispatch(body), do: Module2Dispatcher.handle_info({:frame, 0x02, body}, %{})

  defp encoder(detents), do: <<0x84, detents::signed-integer-8>>

  defp autoregister(value) do
    previous = Application.get_env(:bbparty, :key_autoregister)
    Application.put_env(:bbparty, :key_autoregister, value)
    on_exit(fn -> Application.put_env(:bbparty, :key_autoregister, previous) end)
  end

  defp tag_read(id, uid \\ <<1, 2, 3, 4>>) do
    <<0x85, byte_size(uid), uid::binary, 0x00, byte_size(id), id::binary>>
  end

  describe "key_index/1" do
    test "inverts key_id/1, from strings and atoms" do
      assert Module2Dispatcher.key_index(Module2Dispatcher.key_id(6)) == {:ok, 6}
      assert Module2Dispatcher.key_index(:button_5) == {:ok, 5}
    end

    test "rejects ids outside the namespace or the wire range" do
      for id <- ["key_3", "button_", "button_x", "button_6a", "button_256", :switch_0_0] do
        assert Module2Dispatcher.key_index(id) == :error, inspect(id)
      end
    end
  end

  describe "encoder detents" do
    setup do
      start(@knob, RotaryEncoder, %{module: 2})
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")
      :ok
    end

    test "reach the component bound to the board" do
      dispatch(encoder(1))

      assert_receive {:component_event, @knob, :nudge_quantity, 1}
    end

    test "carry their sign" do
      dispatch(encoder(-2))

      assert_receive {:component_event, @knob, :nudge_quantity, -2}
    end
  end

  describe "encoder detents from a knob wired backwards" do
    test "are oriented before they reach the fold" do
      start(@knob, RotaryEncoder, %{module: 2, invert: true})
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(encoder(1))

      assert_receive {:component_event, @knob, :nudge_quantity, -1}
    end
  end

  describe "with nothing bound to the encoder" do
    test "a detent is dropped rather than raised" do
      assert {:noreply, %{}} = dispatch(encoder(1))
    end

    test "an unbound encoder is not addressed" do
      start(@knob, RotaryEncoder, %{})
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(encoder(1))

      refute_receive {:component_event, @knob, :nudge_quantity, _}, 100
    end
  end

  describe "a tag on the reader" do
    setup do
      start(@reader, FontSelector, %{module: 2})
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")
      :ok
    end

    test "reaches the selector bound to the board" do
      dispatch(tag_read("Chalkboard"))

      assert_receive {:component_event, @reader, :select_font, "Chalkboard"}
    end

    test "the tag topic still carries the whole read" do
      Bbparty.Bus.Module2Dispatcher.subscribe_tags()

      dispatch(tag_read("Arial"))

      assert_receive {:module2, {:tag_read, %{uid: <<1, 2, 3, 4>>, text: "Arial"}}}
    end

    test "an id nobody knows reaches nothing" do
      dispatch(tag_read("not-a-font"))

      refute_receive {:component_event, @reader, :select_font, _}, 100
    end

    test "taking the tag off does not put the font back" do
      dispatch(tag_read("Papyrus"))
      assert_receive {:component_event, @reader, :select_font, "Papyrus"}

      dispatch(<<0x86>>)

      refute_receive {:component_event, @reader, :select_font, _}, 100
    end
  end

  describe "a key on the 4x2 panel" do
    setup do
      autoregister(false)
      {:ok, _} = Layout.create_component(:button_3, PushButton, %{action: "align_center"})
      {:ok, _} = PhysicalComponent.start(:button_3, Layout.get_component(:button_3))
      on_exit(fn -> PhysicalComponent.stop(:button_3) end)
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")
      :ok
    end

    test "a press reaches the component at its address" do
      dispatch(<<0x82, 3, 1>>)

      assert_receive {:component_event, :button_3, :key_down, %{action: "align_center"}}
    end

    test "a release too" do
      dispatch(<<0x82, 3, 0>>)

      assert_receive {:component_event, :button_3, :key_up, %{action: "align_center"}}
    end

    test "an address nobody has registered is dropped when commissioning is off" do
      dispatch(<<0x82, 6, 1>>)

      refute_receive {:component_event, :button_6, _, _}, 100
      refute PhysicalComponent.running?(:button_6)
    end
  end

  describe "commissioning a key" do
    setup do
      autoregister(true)
      on_exit(fn -> PhysicalComponent.stop(:button_6) end)
      :ok
    end

    test "a press registers it as a key with a lamp, on this board" do
      dispatch(<<0x82, 6, 1>>)

      assert PhysicalComponent.running?(:button_6)
      assert Layout.get_component(:button_6).module == PushButtonWithLed
      assert Layout.get_component(:button_6).attrs.module == 2
    end

    test "with neither its meaning nor its lamp guessed" do
      dispatch(<<0x82, 6, 1>>)

      attrs = Layout.get_component(:button_6).attrs

      assert attrs.action == nil
      assert attrs.led == nil
    end

    test "somewhere it can be told apart from its neighbours" do
      dispatch(<<0x82, 6, 1>>)

      assert Layout.get_component(:button_6).position == %{"x" => 140, "y" => 770}
    end

    test "a release from an unknown address registers nothing" do
      dispatch(<<0x82, 6, 0>>)

      refute PhysicalComponent.running?(:button_6)
    end
  end

  describe "a snapshot" do
    setup do
      autoregister(false)

      for id <- [:button_0, :button_1] do
        {:ok, _} = Layout.create_component(id, PushButton, %{char: "a"})
        {:ok, _} = PhysicalComponent.start(id, Layout.get_component(id))
      end

      on_exit(fn -> Enum.each([:button_0, :button_1], &PhysicalComponent.stop/1) end)
      :ok
    end

    test "is applied as state, never as a press" do
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(<<0x88, 0b01>>)

      assert PhysicalComponent.query_state(:button_0).pushed
      refute PhysicalComponent.query_state(:button_1).pushed
      refute_receive {:component_event, :button_0, :key_down, _}, 100
    end

    test "clears a key the board no longer reports as held" do
      dispatch(<<0x88, 0b01>>)
      assert PhysicalComponent.query_state(:button_0).pushed

      dispatch(<<0x88, 0b00>>)
      refute PhysicalComponent.query_state(:button_0).pushed
    end
  end

  describe "axis samples" do
    test "reach the joystick bound to that axis" do
      start(@stick, Joystick, %{module: 2, axis: 0, center: 2000, deadzone: 10, smoothing: 1.0})
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(<<0x83, 4000::16, 0::16, 0::16>>)

      assert_receive {:component_event, @stick, :nudge, _words}
    end

    test "an inverted stick nudges the other way" do
      attrs = %{module: 2, axis: 0, center: 2000, deadzone: 10, smoothing: 1.0, invert: true}
      start(@stick, Joystick, attrs)
      Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")

      dispatch(<<0x83, 4000::16, 0::16, 0::16>>)

      assert_receive {:component_event, @stick, :nudge, nudge}
      assert nudge < 0
    end
  end
end
