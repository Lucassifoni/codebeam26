defmodule Bbparty.FontSelectorProjectionTest do
  use ExUnit.Case, async: false

  alias Bbparty.Bus.Module2Dispatcher
  alias Bbparty.Layout.ComponentInstance
  alias Bbparty.RenderState
  alias Bbparty.RenderStateServer
  alias Hardware.Components.FontSelector
  alias Hardware.PhysicalComponent

  @id :any_name_the_layout_gives_it
  @board 0x02
  @font "Boogy Brut Bold"

  setup do
    reset_render = fn ->
      :sys.replace_state(RenderStateServer, fn state -> %{state | render: RenderState.new()} end)
    end

    reset_render.()

    {:ok, _} =
      PhysicalComponent.start(@id, %ComponentInstance{
        module: FontSelector,
        attrs: %{module: @board}
      })

    on_exit(fn -> PhysicalComponent.stop(@id) end)
    on_exit(reset_render)
    Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")
    :ok
  end

  defp tag_frame(text) do
    uid = <<0x04, 0x5A, 0x21, 0xB2, 0x6F, 0x61, 0x80>>
    {:frame, @board, <<0x85, byte_size(uid), uid::binary, 0, byte_size(text), text::binary>>}
  end

  describe "a tag on the physical reader" do
    test "reaches the control panel once the core has chosen the font" do
      Module2Dispatcher.handle_info(tag_frame(@font), %{})

      assert_receive {:component_changed, @id, %FontSelector{selected_font: @font}}
      assert RenderStateServer.get_state().selected_font == @font
    end

    test "an unknown tag moves neither the core nor the highlight" do
      Module2Dispatcher.handle_info(tag_frame("not-a-font"), %{})

      assert %FontSelector{selected_font: nil} = PhysicalComponent.query_state(@id)
      assert RenderStateServer.get_state().selected_font == nil
      refute_receive {:component_changed, _id, %FontSelector{}}, 50
    end
  end
end
