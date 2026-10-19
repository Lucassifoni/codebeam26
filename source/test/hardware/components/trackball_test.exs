defmodule Hardware.Components.TrackballTest do
  use ExUnit.Case, async: true

  alias Hardware.Components.Trackball

  describe "new/1" do
    test "starts un-rolled" do
      assert %Trackball{intensity: 0, rolls: 0} = Trackball.new([])
    end
  end

  describe ":activity — the physical ball" do
    test "emits a roll carrying the pulse count" do
      assert {:ok, _state, [{:roll, 12}]} =
               Trackball.handle_event(Trackball.new([]), :activity, 12)
    end

    test "records the intensity and counts the roll" do
      {:ok, state, _} = Trackball.handle_event(Trackball.new([]), :activity, 40)

      assert %Trackball{intensity: 40, rolls: 1} = state
    end

    test "the counter advances even when the intensity repeats" do
      {:ok, state, _} = Trackball.handle_event(Trackball.new([]), :activity, 40)
      {:ok, state, _} = Trackball.handle_event(state, :activity, 40)

      assert %Trackball{intensity: 40, rolls: 2} = state
    end

    test "clamps to the byte the wire can carry" do
      assert {:ok, %Trackball{intensity: 255}, [{:roll, 255}]} =
               Trackball.handle_event(Trackball.new([]), :activity, 9000)

      assert {:ok, %Trackball{intensity: 0}, [{:roll, 0}]} =
               Trackball.handle_event(Trackball.new([]), :activity, -5)
    end
  end

  describe ":spin — the on-screen die" do
    test "emits the same roll as the physical ball" do
      {:ok, state, emits} = Trackball.handle_event(Trackball.new([]), :spin, nil)

      assert [{:roll, intensity}] = emits
      assert intensity in 0..255
      assert %Trackball{rolls: 1} = state
    end

    test "a payload from the browser does not have to be a number" do
      assert {:ok, %Trackball{rolls: 1}, [{:roll, _}]} =
               Trackball.handle_event(Trackball.new([]), :spin, "not a count")
    end
  end

  describe "the display" do
    test "renders from the bare assigns map the control panel passes" do
      {:ok, state, _} = Trackball.handle_event(Trackball.new([]), :activity, 200)

      html =
        %{id: :m4_trackball, attrs: %{}, data: state}
        |> Hardware.Components.Trackball.Display.render()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      assert html =~ "m4_trackball"
      assert html =~ "🎲"
    end
  end

  describe "the component contract" do
    test "declares only the two input events" do
      assert Enum.sort(Trackball.events()) == [:activity, :spin]
    end

    test "claims the ball of the board it is wired to" do
      assert Trackball.input_binding(Trackball.new(module: 4)) == {:trackball, 4}
    end

    test "an unwired ball is virtual only" do
      assert Trackball.input_binding(Trackball.new([])) == nil
    end

    test "the board is a layout attribute" do
      assert Trackball.editable_fields() == [module: :integer]
    end

    test "carries physical dimensions, for the panel cutout" do
      assert {w, h} = Trackball.dimensions()
      assert w > 0 and h > 0
    end
  end
end
