defmodule Bbparty.KeyboardTest do
  use ExUnit.Case, async: true

  alias Bbparty.Keyboard

  defp line_at(column), do: Enum.at(Keyboard.sense_lines(), column)
  defp rail_at(row), do: Enum.at(Keyboard.drive_lines(), row)
  defp key_at(row, column), do: "key_#{rail_at(row)}_#{line_at(column)}"

  defp addresses do
    for drive <- Keyboard.drive_lines(),
        sense <- Keyboard.sense_lines(),
        do: {drive, sense}
  end

  describe "char_addresses/1" do
    test "inverts default_char/2 for every wired crosspoint" do
      assert Enum.all?(addresses(), fn {d, s} ->
               {d, s} in Keyboard.char_addresses(Keyboard.default_char(d, s))
             end)
    end

    test "returns every candidate, since the alphabet is shorter than the panel" do
      assert Keyboard.char_addresses("!") == [
               {rail_at(0), line_at(0)},
               {rail_at(3), line_at(10)},
               {rail_at(6), line_at(20)}
             ]
    end

    test "names the chip a spammed run lands on" do
      top = rail_at(0)

      senses =
        ~w(" # $)
        |> Enum.flat_map(&Keyboard.char_addresses/1)
        |> Enum.filter(fn {drive, _} -> drive == top end)
        |> Enum.map(fn {_, sense} -> sense end)

      assert senses == Enum.map(1..3, &line_at/1),
             "consecutive glyphs name consecutive panel columns, not consecutive lines"

      assert Enum.all?(senses, &(Keyboard.sense_chip(&1) != nil))
    end

    test "a character outside the alphabet maps nowhere" do
      assert Keyboard.char_addresses(" ") == []
      assert Keyboard.char_addresses("ß") == []
    end
  end

  describe "row/1 and column/1" do
    test "map a line to where it sits on the panel" do
      assert Keyboard.row(rail_at(0)) == {:ok, 0}
      assert Keyboard.row(rail_at(8)) == {:ok, 8}
      assert Keyboard.column(line_at(0)) == {:ok, 0}
      assert Keyboard.column(line_at(26)) == {:ok, 26}
      assert Keyboard.column(line_at(27)) == {:ok, 27}
    end

    test "refuse a line that carries nothing" do
      assert Keyboard.column(26) == :error
      assert Keyboard.column(30) == :error
      assert Keyboard.row(6) == :error
      assert Keyboard.row(7) == :error, "D7 is alive but carries no rail"
    end
  end

  describe "sense_chip/1 and drive_chip/1" do
    test "name the chip each line lands on, per the chain order" do
      assert Keyboard.sense_chip(0) == "U6"
      assert Keyboard.sense_chip(7) == "U6"
      assert Keyboard.sense_chip(8) == "U5"
      assert Keyboard.sense_chip(16) == "U4"
      assert Keyboard.sense_chip(27) == "U3"

      assert Keyboard.drive_chip(0) == "U2"
      assert Keyboard.drive_chip(7) == "U2"
      assert Keyboard.drive_chip(8) == "U1"
    end
  end

  describe "lines_in_press_order/1" do
    test "reports lines in the order they were first pressed" do
      events = [{12, 4, true}, {12, 4, false}, {9, 4, true}, {9, 4, false}, {12, 7, true}]

      assert Keyboard.lines_in_press_order(events) == %{drives: [12, 9], senses: [4, 7]}
    end

    test "ignores releases, which would double every entry" do
      assert Keyboard.lines_in_press_order([{3, 5, false}]) == %{drives: [], senses: []}
    end

    test "does not care whether the lines are contiguous or on one chip" do
      events = for drive <- [12, 13, 2, 3], do: {drive, 0, true}

      assert %{drives: [12, 13, 2, 3]} = Keyboard.lines_in_press_order(events)
    end

    test "nothing pressed, nothing reported" do
      assert Keyboard.lines_in_press_order([]) == %{drives: [], senses: []}
    end
  end

  describe "summarise/1" do
    test "collapses a capture to one row per crosspoint" do
      events = [{10, 12, 8, true}, {20, 12, 8, false}, {30, 12, 8, true}, {40, 11, 3, true}]

      assert [
               %{drive: 11, sense: 3, presses: 1, releases: 0},
               %{drive: 12, sense: 8, presses: 2, releases: 1, first_ms: 10, last_ms: 30}
             ] = Keyboard.summarise(events)
    end

    test "accepts untimestamped events, leaving the stamps nil" do
      assert [%{drive: 12, sense: 8, presses: 1, first_ms: nil, last_ms: nil}] =
               Keyboard.summarise([{12, 8, true}])
    end

    test "nothing captured, nothing summarised" do
      assert Keyboard.summarise([]) == []
    end
  end

  describe "event_grid/1" do
    @header 4

    defp grid_rows(events), do: events |> Keyboard.event_grid() |> String.split("\n")
    defp drive_row(rows, drive), do: Enum.at(rows, @header + drive)

    defp cell(row, sense), do: String.at(row, 5 + sense + div(sense, 8))

    test "draws the full scanned matrix, not just the wired part" do
      rows = grid_rows([])

      assert length(rows) == @header + 16
      assert Enum.all?(Enum.drop(rows, @header), &(String.length(&1) == 5 + 32 + 3))
    end

    test "marks a crosspoint with its press count" do
      row = [{12, 8, true}, {12, 8, false}, {12, 8, true}] |> grid_rows() |> drive_row(12)

      assert cell(row, 8) == "2"
      assert cell(row, 7) == "."
    end

    test "caps a busy crosspoint rather than widening the column" do
      events = for _ <- 1..30, do: {12, 8, true}

      assert events |> grid_rows() |> drive_row(12) |> cell(8) == "+"
    end

    test "separates adjacent counts, which would otherwise read as one number" do
      row = [{12, 15, true}, {12, 16, true}] |> grid_rows() |> drive_row(12)

      assert cell(row, 15) == "1"
      assert cell(row, 16) == "1"
      assert String.at(row, 5 + 15 + div(15, 8) + 1) == " ", "a gap falls between them"
    end

    test "names the chip above each group of eight" do
      chips = grid_rows([]) |> Enum.at(0)

      assert String.trim(chips) == "U6       U5       U4       U3"
    end

    test "flags which lines carry wiring, so a spare-line fault reads as one" do
      rows = grid_rows([])
      wired = Enum.at(rows, 3)

      assert cell(wired, 26) == " ", "S26 carries no column"
      assert cell(wired, 28) == "-", "S28 carries panel column 26"
      assert String.at(drive_row(rows, 15), 4) == "|", "D15 carries the top row"
      assert String.at(drive_row(rows, 7), 4) == " ", "D7 carries no rail"
    end
  end

  describe "describe_address/2" do
    test "names the chip behind an unwired drive" do
      message = Keyboard.describe_address(3, 4)

      assert message =~ "drive 3 (U2)"
      refute message =~ "sense 4"
    end

    test "names the chip behind an unwired sense" do
      assert Keyboard.describe_address(12, 26) =~ "sense 26 (U3)"
    end

    test "says so when the index is off the chain entirely" do
      assert Keyboard.describe_address(200, 200) =~ "corrupt frame"
      assert Keyboard.drive_chip(200) == nil
      assert Keyboard.sense_chip(200) == nil
    end

    test "names both when both are off the set" do
      message = Keyboard.describe_address(3, 30)

      assert message =~ "drive 3 (U2)"
      assert message =~ "sense 30 (U3)"
    end

    test "does not claim a wired address is broken" do
      assert Keyboard.describe_address(12, 4) == "address (12, 4) is on wired lines"
    end
  end

  describe "sense_pin/1 and drive_pin/1" do
    test "resolve a line to its chip and physical pin" do
      assert Keyboard.sense_pin(24) == {"U3", 11}
      assert Keyboard.sense_pin(0) == {"U6", 11}
      assert Keyboard.sense_pin(7) == {"U6", 6}
      assert Keyboard.sense_pin(28) == {"U3", 3}

      assert Keyboard.drive_pin(15) == {"U1", 7}
      assert Keyboard.drive_pin(8) == {"U1", 15}
      assert Keyboard.drive_pin(1) == {"U2", 1}
    end

    test "every wired line resolves to a real DIP pin" do
      pins =
        Enum.map(Keyboard.sense_lines(), &Keyboard.sense_pin/1) ++
          Enum.map(Keyboard.drive_lines(), &Keyboard.drive_pin/1)

      assert Enum.all?(pins, fn {chip, pin} -> is_binary(chip) and pin in 1..16 end)
    end

    test "refuse an index the chain does not reach" do
      assert Keyboard.sense_pin(32) == :error
      assert Keyboard.drive_pin(16) == :error
    end
  end

  describe "suspect_lines/1" do
    defp floating_sense(sense) do
      for drive <- Keyboard.drive_lines(), do: {drive, sense, true}
    end

    test "flags a sense line that reports against every drive" do
      assert %{senses: [{5, "U6"}], drives: []} = Keyboard.suspect_lines(floating_sense(5))
    end

    test "flags a whole chip's worth, which is what an unlanded pull-up looks like" do
      events = Enum.flat_map(8..15, &floating_sense/1)

      assert %{senses: senses} = Keyboard.suspect_lines(events)
      assert senses == Enum.map(8..15, &{&1, "U5"})
    end

    test "a real key press is not a suspect, however often it repeats" do
      events = for _ <- 1..50, do: {12, 12, true}

      assert Keyboard.suspect_lines(events) == %{senses: [], drives: []}
    end

    test "a whole row pressed at once is still not a suspect sense line" do
      events = for sense <- Keyboard.sense_lines(), do: {12, sense, true}

      assert %{senses: [], drives: [{12, "U1"}]} = Keyboard.suspect_lines(events)
    end

    test "nothing observed, nothing suspected" do
      assert Keyboard.suspect_lines([]) == %{senses: [], drives: []}
    end
  end

  describe "grid_plan/2" do
    test "lays every key on the grid its address names" do
      ids = Enum.map(addresses(), fn {d, s} -> Keyboard.key_id(d, s) end)
      plan = Keyboard.grid_plan(ids)

      assert length(plan) == length(ids)
      assert {key_at(0, 0), %{"x" => 0, "y" => 0}} in plan
      assert {key_at(1, 2), %{"x" => 240, "y" => 120}} in plan
    end

    test "agrees with default_position/2, so registering and re-arranging match" do
      key = key_at(2, 7)

      assert Keyboard.grid_plan([key]) ==
               [{key, Keyboard.default_position(rail_at(2), line_at(7))}]
    end

    test "honours an explicit pitch" do
      key = key_at(2, 3)

      assert Keyboard.grid_plan([key], 40) == [{key, %{"x" => 120, "y" => 80}}]
    end

    test "drops ids that are not keys, so the whole component list is safe to pass" do
      key = key_at(0, 1)

      assert Keyboard.grid_plan([:font_size_gauge, key, "joystick_a"]) ==
               [{key, %{"x" => 120, "y" => 0}}]
    end

    test "keeps ids as given, atom or string" do
      key = String.to_atom(key_at(0, 1))

      assert [{^key, _}] = Keyboard.grid_plan([key])
    end
  end

  describe "default_char/2" do
    test "is a single printable character for every wired crosspoint" do
      assert Enum.all?(addresses(), fn {d, s} ->
               <<code>> = Keyboard.default_char(d, s)
               code > 0x20 and code < 0x7F
             end)
    end

    test "gives a panel row a distinct character per column" do
      row = Enum.map(Keyboard.sense_lines(), &Keyboard.default_char(13, &1))

      assert length(Enum.uniq(row)) == Keyboard.senses()
    end

    test "runs consecutively across a gap in the wiring" do
      codes =
        Enum.map(20..24, fn column ->
          <<code>> = Keyboard.default_char(rail_at(0), line_at(column))
          code
        end)

      assert codes == Enum.to_list(Enum.at(codes, 0)..(Enum.at(codes, 0) + 4)),
             "adjacent panel columns type adjacent glyphs whatever lines they are on"
    end

    test "runs consecutively along a row, so typing one reads as a sequence" do
      chars = Enum.map(0..4, fn column -> Keyboard.default_char(rail_at(0), line_at(column)) end)

      assert chars == ~w(! " # $ %)
    end
  end

  describe "valid_address?/2" do
    test "matches the wired panel, not the scanned matrix" do
      assert {Keyboard.drives(), Keyboard.senses()} == {9, 28}
    end

    test "the top row is at the far end of the '595 chain" do
      assert List.first(Keyboard.drive_lines()) == 15
      assert Keyboard.drive_chip(15) == "U1"

      assert Keyboard.drive_chip(List.last(Keyboard.drive_lines())) == "U2",
             "the ninth row crosses onto the second '595"
    end

    test "accepts every wired crosspoint" do
      assert Enum.all?(addresses(), fn {d, s} -> Keyboard.valid_address?(d, s) end)
    end

    test "rejects a spare line the firmware still scans" do
      refute Keyboard.valid_address?(3, 4), "drive 3 is scanned but carries no rail"
      refute Keyboard.valid_address?(12, 30), "sense 30 is scanned but carries no column"
    end

    test "follows the wiring rather than a count, gaps included" do
      refute Keyboard.valid_address?(12, 26), "S26 carries no run, though it is below 28"
      refute Keyboard.valid_address?(12, 27), "S27 carries no run, though it is below 28"
      assert Keyboard.valid_address?(12, 28), "S28 carries panel column 26"
      assert Keyboard.valid_address?(12, 29), "S29 carries panel column 27"
      refute Keyboard.valid_address?(0, 4), "D0 carries no rail, though it is below 9"
    end

    test "rejects addresses outside the matrix" do
      refute Keyboard.valid_address?(6, 0), "one below the lowest wired rail"
      refute Keyboard.valid_address?(15, 30), "one above the highest wired column"
      refute Keyboard.valid_address?(-1, 0)
      refute Keyboard.valid_address?(0, -1)
      refute Keyboard.valid_address?(255, 255)
    end

    test "rejects non-integers rather than raising" do
      refute Keyboard.valid_address?(nil, 0)
      refute Keyboard.valid_address?("1", 2)
    end
  end

  describe "key_id/2" do
    test "reads as the address" do
      assert Keyboard.key_id(10, 25) == "key_10_25"
      assert Keyboard.key_id(0, 0) == "key_0_0"
    end

    test "is distinct for every crosspoint" do
      ids = Enum.map(addresses(), fn {d, s} -> Keyboard.key_id(d, s) end)
      assert length(Enum.uniq(ids)) == length(ids)
    end
  end

  describe "address/1" do
    test "round-trips every crosspoint, as a string or an atom" do
      for {drive, sense} <- addresses() do
        id = Keyboard.key_id(drive, sense)
        assert Keyboard.address(id) == {:ok, {drive, sense}}
        assert Keyboard.address(String.to_atom(id)) == {:ok, {drive, sense}}
      end
    end

    test "rejects ids that are not keys" do
      assert Keyboard.address("font_size_gauge") == :error
      assert Keyboard.address(:font_size_joystick) == :error
      assert Keyboard.address("key_") == :error
      assert Keyboard.address("key_1") == :error
      assert Keyboard.address("key_1_2_3") == :error
      assert Keyboard.address("key_a_b") == :error
      assert Keyboard.address("key_1_2x") == :error
    end

    test "rejects a well-formed id addressing outside the matrix" do
      assert Keyboard.address("key_99_99") == :error
    end
  end

  describe "default_position/2" do
    test "lays the matrix out as a grid, senses across and drives down" do
      [top, next | _] = Keyboard.drive_lines()
      [left, right_line | _] = Keyboard.sense_lines()

      origin = Keyboard.default_position(top, left)
      right = Keyboard.default_position(top, right_line)
      down = Keyboard.default_position(next, left)

      assert origin["x"] == 0 and origin["y"] == 0
      assert right["x"] > origin["x"] and right["y"] == origin["y"]
      assert down["y"] > origin["y"] and down["x"] == origin["x"]
    end

    test "no two keys land on the same spot" do
      positions = Enum.map(addresses(), fn {d, s} -> Keyboard.default_position(d, s) end)
      assert length(Enum.uniq(positions)) == length(positions)
    end

    test "keys are the shape a ComponentInstance position takes" do
      assert %{"x" => x, "y" => y} = Keyboard.default_position(13, 4)
      assert is_integer(x) and is_integer(y)
    end
  end
end
