defmodule Hardware.Components.PushButtonTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Hardware.Components.PushButton

  describe "new/1" do
    test "defaults to released and unassigned" do
      b = PushButton.new([])
      assert b.pushed == false
      assert b.char == nil and b.shift == nil and b.action == nil
      assert b.red == false
    end

    test "takes its meaning from attrs" do
      b = PushButton.new(char: "a", shift: "A", action: "reset")
      assert b.char == "a" and b.shift == "A" and b.action == "reset"
    end
  end

  describe "handle_event/3" do
    test "a press emits the button's own meaning, not the payload" do
      b = PushButton.new(char: "a", shift: "A")

      assert {:ok, pushed, [{:key_down, meaning}]} = PushButton.handle_event(b, :key_down, nil)
      assert meaning == %{char: "a", shift: "A", action: nil}
      assert pushed.pushed == true
    end

    test "an incoming payload is ignored — the component is the source of truth" do
      b = PushButton.new(char: "a")

      assert {:ok, _state, [{:key_down, %{char: "a"}}]} =
               PushButton.handle_event(b, :key_down, "zzz")
    end

    test "an unassigned key says nothing on either edge but still tracks its state" do
      b = PushButton.new([])

      assert {:ok, pushed, []} = PushButton.handle_event(b, :key_down, nil)
      assert pushed.pushed == true
      assert {:ok, released, []} = PushButton.handle_event(pushed, :key_up, nil)
      assert released.pushed == false
    end

    test "a release reports the same meaning, so a modifier can announce it" do
      b = PushButton.new(action: "shift") |> then(&%{&1 | pushed: true})

      assert {:ok, released, [{:key_up, meaning}]} = PushButton.handle_event(b, :key_up, nil)
      assert meaning == %{char: nil, shift: nil, action: "shift"}
      assert released.pushed == false
    end

    test "a key with only an action still speaks, despite having no char" do
      b = PushButton.new(action: "backspace")

      assert {:ok, _state, [{:key_down, %{action: "backspace"}}]} =
               PushButton.handle_event(b, :key_down, nil)
    end
  end

  describe "declaration" do
    test "handles the two key edges and a board's committed state" do
      assert PushButton.events() == [:key_up, :key_down, :set_pushed]
    end

    test "set_pushed moves the state and emits nothing" do
      button = PushButton.new(char: "a")

      assert {:ok, %PushButton{pushed: true}, []} =
               PushButton.handle_event(button, :set_pushed, true)

      assert {:ok, %PushButton{pushed: false}, []} =
               PushButton.handle_event(%{button | pushed: true}, :set_pushed, false)
    end

    test "meaning is editable in the control panel" do
      assert Keyword.keys(PushButton.editable_fields()) == [:char, :shift, :action, :red]
      assert PushButton.editable_fields()[:red] == :boolean
    end

    test "red is a cap colour and never reaches the fold" do
      button = PushButton.new(char: "a", shift: "A", red: true)

      assert button.red == true
      assert PushButton.meaning(button) == %{char: "a", shift: "A", action: nil}

      assert {:ok, _state, [{:key_down, meaning}]} =
               PushButton.handle_event(button, :key_down, nil)

      refute Map.has_key?(meaning, :red)
    end

    test "a cap is black unless it says otherwise, whatever shape the attr is" do
      for opts <- [[], [red: false], [red: nil]] do
        assert PushButton.new(opts).red == false
      end
    end
  end

  describe "the key on the canvas" do
    defp cap(opts),
      do: render_component(&PushButton.Display.render/1, id: :key_1_2, data: PushButton.new(opts))

    defp legend(opts) do
      cap(opts)
      |> String.replace(~r{<script.*?</script>}s, "")
      |> String.replace(~r{<[^>]*>}, " ")
      |> String.split()
      |> Enum.join(" ")
    end

    test "carries both glyphs, so an unassigned shift is visible as one" do
      assert legend(char: "a", shift: "A") == "A a"
      assert legend(char: "a") == "a"
    end

    test "a key with no shift draws no shift glyph" do
      refute cap(char: "a") =~ "left-0.5"
      assert cap(char: "a", shift: "A") =~ "left-0.5"
    end

    test "a blank shift is the same as none" do
      refute cap(char: "a", shift: "") =~ "left-0.5"
    end

    test "a dead key shows its mark, not the word dead" do
      html = cap(char: "´", action: "dead")

      assert html =~ "´"
      refute html =~ "dead"
    end

    test "an action key shows the action, in words" do
      assert cap(char: "x", action: "capslock") =~ "capslock"
      assert cap(action: "align_left") =~ "align left"
    end

    test "an unassigned key says so rather than showing an empty cap" do
      assert cap([]) =~ "—"
    end

    test "red caps are red and the rest are not" do
      assert cap(char: "a", red: true) =~ "bg-red-400"
      refute cap(char: "a") =~ "bg-red-400"
    end
  end
end
