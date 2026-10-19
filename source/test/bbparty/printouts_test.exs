defmodule Bbparty.PrintoutsTest do
  use Bbparty.DataCase, async: true

  alias Bbparty.Printouts
  alias Bbparty.Printouts.Printout
  alias Bbparty.RenderState

  defp render(overrides), do: struct(RenderState.new(), overrides)

  describe "Printout.changeset/2" do
    test "stores every field of the render state, and the time it was given" do
      at = ~U[2026-09-21 20:00:00.123456Z]
      changeset = Printout.changeset(render(text: "bonjour", selected_font: "ABC"), at)

      assert changeset.valid?
      assert get_change(changeset, :printed_at) == at

      state = get_change(changeset, :state)

      assert Map.keys(state) |> Enum.sort() ==
               Map.keys(Map.from_struct(RenderState.new())) |> Enum.sort()

      assert state.text == "bonjour"
      assert state.selected_font == "ABC"
    end
  end

  describe "get!/1" do
    test "fetches one printout by id, as an integer or as the string a route carries" do
      {:ok, printout} = Printouts.record(render(text: "un"), ~U[2026-09-21 20:00:00.000000Z])

      assert Printouts.get!(printout.id).id == printout.id
      assert Printouts.get!(Integer.to_string(printout.id)).id == printout.id
    end

    test "raises on an unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Printouts.get!(0) end
    end
  end

  describe "record/2" do
    test "persists the state and its timestamp" do
      at = ~U[2026-09-21 20:00:00.123456Z]

      assert {:ok, %Printout{id: id}} =
               Printouts.record(
                 render(text: "salut", text_source: :alpha_upper, cumulative_features: ["liga"]),
                 at
               )

      printout = Repo.get!(Printout, id)
      assert printout.printed_at == at
      assert printout.state["text"] == "salut"
      assert printout.state["text_source"] == "alpha_upper"
      assert printout.state["cumulative_features"] == ["liga"]
    end

    test "stamps the current time when none is given" do
      before = DateTime.utc_now()
      {:ok, printout} = Printouts.record(RenderState.new())

      assert DateTime.compare(printout.printed_at, before) in [:gt, :eq]
    end
  end

  describe "list/0" do
    test "returns printouts oldest first" do
      {:ok, _} = Printouts.record(render(text: "second"), ~U[2026-09-21 20:00:01.000000Z])
      {:ok, _} = Printouts.record(render(text: "first"), ~U[2026-09-21 20:00:00.000000Z])

      assert Enum.map(Printouts.list(), & &1.state["text"]) == ["first", "second"]
    end
  end

  describe "page/1" do
    defp texts(printouts), do: Enum.map(printouts, & &1.state["text"])

    setup do
      for {text, second} <- [{"a", 1}, {"b", 2}, {"c", 3}, {"d", 4}, {"e", 5}] do
        {:ok, _} =
          Printouts.record(
            render(text: text),
            DateTime.new!(~D[2026-09-21], ~T[20:00:00.000000], "Etc/UTC") |> DateTime.add(second)
          )
      end

      :ok
    end

    test "returns printouts newest first, limited" do
      assert texts(Printouts.page(limit: 2)) == ["e", "d"]
    end

    test "continues after the last printout of the previous page" do
      first = Printouts.page(limit: 2)
      second = Printouts.page(limit: 2, after: List.last(first))
      third = Printouts.page(limit: 2, after: List.last(second))

      assert texts(second) == ["c", "b"]
      assert texts(third) == ["a"]
      assert Printouts.page(limit: 2, after: List.last(third)) == []
    end

    test "neither skips nor repeats printouts sharing a timestamp" do
      at = ~U[2026-09-21 20:00:03.000000Z]
      {:ok, _} = Printouts.record(render(text: "c2"), at)
      {:ok, _} = Printouts.record(render(text: "c3"), at)

      pages =
        Stream.unfold(nil, fn after_printout ->
          case Printouts.page(limit: 2, after: after_printout) do
            [] -> nil
            page -> {page, List.last(page)}
          end
        end)

      assert pages |> Enum.flat_map(&texts/1) == ["e", "d", "c3", "c2", "c", "b", "a"]
    end

    test "count/0 counts them all" do
      assert Printouts.count() == 5
    end
  end
end
