defmodule Bbparty.RenderState.ProjectionsTest do
  use ExUnit.Case, async: true

  alias Bbparty.FontMap
  alias Bbparty.RenderState
  alias Bbparty.RenderState.Projections

  @rich "Boogy Brut Bold"

  defp targets(commands), do: commands |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

  describe "propagate/2" do
    test "an unchanged state projects nothing" do
      state = RenderState.new()

      assert Projections.propagate(state, state) == []
    end

    test "a field that projects nothing when it changes projects nothing" do
      state = RenderState.new()

      assert Projections.propagate(state, %{state | text: "typography", cursor: 10}) == []
    end

    test "only the changed field is projected" do
      state = RenderState.new()

      assert Projections.propagate(state, %{state | alignment: :center}) == [
               {{:action, :align_left}, {:set_lit, false}},
               {{:action, :align_center}, {:set_lit, true}}
             ]
    end

    test "projects the new value, whatever the old one was" do
      centred = %{RenderState.new() | alignment: :center}
      uppercase = %{centred | transform_toupper: true}

      assert Projections.propagate(centred, uppercase) ==
               Projections.propagate(RenderState.new(), %{
                 RenderState.new()
                 | transform_toupper: true
               })
    end
  end

  describe "sync/1" do
    test "projects fields even when nothing changed, as after a board reboot" do
      state = RenderState.new()

      assert Projections.propagate(state, state) == []
      assert {{:action, :align_left}, {:set_lit, true}} in Projections.sync(state)
      assert {{:field, :text_quantity}, {:set_quantity, 0}} in Projections.sync(state)
      assert {{:field, :selected_font}, {:set_font, nil}} in Projections.sync(state)
    end

    test "is what a panel needs to leave the default state" do
      state = %{RenderState.new() | alignment: :center, selected_font: @rich, zoom: 1.0}

      for command <- Projections.propagate(RenderState.new(), state) do
        assert command in Projections.sync(state)
      end
    end
  end

  describe "addressing" do
    test "only gauges are addressed by id, everything else by meaning" do
      state = %{RenderState.new() | selected_font: @rich, cumulative_features: ["liga"]}
      ids = MapSet.new(Projections.referenced_ids())

      for target <- targets(Projections.sync(state)) do
        assert match?({kind, _} when kind in [:action, :feature, :field], target) or
                 MapSet.member?(ids, to_string(target))
      end
    end

    test "every lever feature hears both its halves" do
      commands = Projections.sync(%{RenderState.new() | selected_font: @rich})

      for feature <- FontMap.all_features() do
        assert Enum.count(commands, &match?({{:feature, ^feature}, _}, &1)) == 2
      end
    end
  end

  describe "percentile/2" do
    test "maps the bounds onto 0..100" do
      assert Projections.percentile(-2.0, {-2.0, 2.0}) == 0.0
      assert Projections.percentile(0.0, {-2.0, 2.0}) == 50.0
      assert Projections.percentile(2.0, {-2.0, 2.0}) == 100.0
    end
  end
end
