defmodule Bbparty.RenderStateRestoreTest do
  use ExUnit.Case, async: true

  alias Bbparty.RenderState
  alias Bbparty.RenderState.Restore

  defp round_trip(state),
    do: state |> Map.from_struct() |> Jason.encode!() |> Jason.decode!()

  test "a stored state comes back as the state that was stored" do
    state = %{
      RenderState.new()
      | text: "bonjour\nà tous",
        zoom: 0.4,
        kerning: 0.12,
        leading: 1.5,
        selected_font: "ABC Diatype",
        text_source: :alpha_lower,
        alignment: :center,
        transform_toupper: true,
        cumulative_features: ["liga", "ss01"],
        text_quantity: 12,
        pending_diacritic: "´"
    }

    assert Restore.from_stored(round_trip(state)) == state
  end

  test "every text source survives the trip" do
    for source <- [:user, :font_name, :alpha_upper, :alpha_lower, :numbers] do
      state = %{RenderState.new() | text_source: source}
      assert Restore.from_stored(round_trip(state)).text_source == source
    end
  end

  test "atom-keyed maps are accepted as well" do
    state = %{RenderState.new() | text: "déjà", alignment: :center}

    assert Restore.from_stored(Map.from_struct(state)) == state
  end

  test "fields missing from an older record take their default" do
    restored = Restore.from_stored(%{"text" => "vieux"})

    assert restored == %{RenderState.new() | text: "vieux"}
  end

  test "unknown keys are dropped" do
    restored = Restore.from_stored(%{"text" => "x", "no_such_field" => 1})

    refute Map.has_key?(restored, :no_such_field)
    refute Map.has_key?(restored, "no_such_field")
  end

  test "unrecognised atom values fall back rather than minting atoms" do
    restored =
      Restore.from_stored(%{"text_source" => "from_outer_space", "alignment" => "justify"})

    assert restored.text_source == :user
    assert restored.alignment == :left
  end
end
