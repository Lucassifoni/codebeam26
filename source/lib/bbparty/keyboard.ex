defmodule Bbparty.Keyboard do
  @drive_lines [15, 14, 13, 12, 11, 10, 9, 8, 1]
  @sense_lines [
    20,
    25,
    24,
    21,
    22,
    12,
    16,
    17,
    18,
    19,
    23,
    9,
    14,
    15,
    13,
    10,
    11,
    3,
    7,
    6,
    5,
    4,
    8,
    29,
    28,
    0,
    1,
    2
  ]

  @pitch 120

  @first_char 0x21
  @char_count 0x7E - 0x21 + 1

  @spec drive_lines() :: [non_neg_integer()]
  def drive_lines, do: @drive_lines

  @spec sense_lines() :: [non_neg_integer()]
  def sense_lines, do: @sense_lines

  @spec drives() :: pos_integer()
  def drives, do: length(@drive_lines)

  @spec senses() :: pos_integer()
  def senses, do: length(@sense_lines)

  @spec pitch() :: pos_integer()
  def pitch, do: @pitch

  @spec valid_address?(integer(), integer()) :: boolean()
  def valid_address?(drive, sense) when is_integer(drive) and is_integer(sense) do
    drive in @drive_lines and sense in @sense_lines
  end

  def valid_address?(_drive, _sense), do: false

  @spec row(integer()) :: {:ok, non_neg_integer()} | :error
  def row(drive), do: ordinal(@drive_lines, drive)

  @spec column(integer()) :: {:ok, non_neg_integer()} | :error
  def column(sense), do: ordinal(@sense_lines, sense)

  defp ordinal(lines, line) do
    case Enum.find_index(lines, &(&1 == line)) do
      nil -> :error
      index -> {:ok, index}
    end
  end

  @spec key_id(non_neg_integer(), non_neg_integer()) :: String.t()
  def key_id(drive, sense), do: "key_#{drive}_#{sense}"

  @spec address(String.t() | atom()) :: {:ok, {non_neg_integer(), non_neg_integer()}} | :error
  def address(id) when is_atom(id), do: address(Atom.to_string(id))

  def address("key_" <> rest) do
    with [drive, sense] <- String.split(rest, "_"),
         {drive, ""} <- Integer.parse(drive),
         {sense, ""} <- Integer.parse(sense),
         true <- valid_address?(drive, sense) do
      {:ok, {drive, sense}}
    else
      _ -> :error
    end
  end

  def address(_id), do: :error

  @spec default_position(non_neg_integer(), non_neg_integer()) :: %{String.t() => integer()}
  def default_position(drive, sense), do: position(drive, sense, @pitch)

  @spec grid_plan([String.t() | atom()], pos_integer()) ::
          [{String.t() | atom(), %{String.t() => integer()}}]
  def grid_plan(ids, pitch \\ @pitch) do
    Enum.flat_map(ids, fn id ->
      case address(id) do
        {:ok, {drive, sense}} -> [{id, position(drive, sense, pitch)}]
        :error -> []
      end
    end)
  end

  defp position(drive, sense, pitch) do
    {:ok, row} = row(drive)
    {:ok, column} = column(sense)
    %{"x" => column * pitch, "y" => row * pitch}
  end

  @spec default_char(non_neg_integer(), non_neg_integer()) :: String.t()
  def default_char(drive, sense) do
    {:ok, row} = row(drive)
    {:ok, column} = column(sense)
    <<@first_char + rem(row * senses() + column, @char_count)>>
  end

  @spec char_addresses(String.t()) :: [{non_neg_integer(), non_neg_integer()}]
  def char_addresses(<<code>>) when code >= @first_char and code < @first_char + @char_count do
    (code - @first_char)
    |> Stream.iterate(&(&1 + @char_count))
    |> Enum.take_while(&(&1 < drives() * senses()))
    |> Enum.map(fn index ->
      {Enum.at(@drive_lines, div(index, senses())), Enum.at(@sense_lines, rem(index, senses()))}
    end)
  end

  def char_addresses(_char), do: []

  @spec sense_chip(integer()) :: String.t() | nil
  def sense_chip(sense) when sense >= 0 and sense < 32,
    do: Enum.at(~w(U6 U5 U4 U3), div(sense, 8))

  def sense_chip(_sense), do: nil

  @spec drive_chip(integer()) :: String.t() | nil
  def drive_chip(drive) when drive >= 0 and drive < 16, do: Enum.at(~w(U2 U1), div(drive, 8))
  def drive_chip(_drive), do: nil

  @spec lines_in_press_order([{integer(), integer(), boolean()}]) :: %{
          drives: [integer()],
          senses: [integer()]
        }
  def lines_in_press_order(events) do
    presses = for {drive, sense, true} <- events, do: {drive, sense}

    %{
      drives: presses |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
      senses: presses |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    }
  end

  @spec summarise([tuple()]) :: [map()]
  def summarise(events) do
    events
    |> Enum.map(&normalise_event/1)
    |> Enum.group_by(fn {_at, drive, sense, _pressed} -> {drive, sense} end)
    |> Enum.map(fn {{drive, sense}, group} ->
      stamps = group |> Enum.map(&elem(&1, 0)) |> Enum.reject(&is_nil/1)

      %{
        drive: drive,
        sense: sense,
        presses: Enum.count(group, &elem(&1, 3)),
        releases: Enum.count(group, &(not elem(&1, 3))),
        first_ms: Enum.min(stamps, fn -> nil end),
        last_ms: Enum.max(stamps, fn -> nil end)
      }
    end)
    |> Enum.sort_by(&{&1.drive, &1.sense})
  end

  defp normalise_event({at, drive, sense, pressed}), do: {at, drive, sense, pressed}
  defp normalise_event({drive, sense, pressed}), do: {nil, drive, sense, pressed}

  @spec event_grid([tuple()]) :: String.t()
  def event_grid(events) do
    counts =
      events
      |> summarise()
      |> Map.new(fn row -> {{row.drive, row.sense}, row.presses} end)

    [grid_header(), grid_rows(counts)]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp grid_header do
    tens = grid_join(0..31, fn s -> if s >= 10, do: "#{div(s, 10)}", else: " " end)
    units = grid_join(0..31, fn s -> "#{rem(s, 10)}" end)
    wired = grid_join(0..31, fn s -> if s in @sense_lines, do: "-", else: " " end)

    chips =
      0..31
      |> Enum.chunk_every(8)
      |> Enum.map_join(" ", fn [first | _] -> String.pad_trailing(sense_chip(first), 8) end)

    ["     " <> chips, "     " <> tens, "     " <> units, "     " <> wired]
  end

  defp grid_rows(counts) do
    Enum.map(0..15, fn drive ->
      mark = if drive in @drive_lines, do: "|", else: " "
      cells = grid_join(0..31, fn sense -> grid_cell(counts[{drive, sense}]) end)

      String.pad_leading("#{drive}", 3) <> " " <> mark <> cells
    end)
  end

  defp grid_join(range, fun) do
    range
    |> Enum.chunk_every(8)
    |> Enum.map_join(" ", fn chunk -> Enum.map_join(chunk, fun) end)
  end

  defp grid_cell(nil), do: "."
  defp grid_cell(0), do: "."
  defp grid_cell(n) when n > 9, do: "+"
  defp grid_cell(n), do: "#{n}"

  @spec describe_address(integer(), integer()) :: String.t()
  def describe_address(drive, sense) do
    case unwired(drive, sense) do
      [] ->
        "address (#{drive}, #{sense}) is on wired lines"

      bad ->
        "address (#{drive}, #{sense}) outside the matrix: " <>
          Enum.join(bad, " and ") <> " carries no wired line"
    end
  end

  defp unwired(drive, sense) do
    [
      {drive in @drive_lines, "drive #{drive} (#{chip_label(drive_chip(drive))})"},
      {sense in @sense_lines, "sense #{sense} (#{chip_label(sense_chip(sense))})"}
    ]
    |> Enum.reject(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp chip_label(nil), do: "no chip — off the scanned range, so a corrupt frame"
  defp chip_label(chip), do: chip

  @spec sense_pin(integer()) :: {String.t(), pos_integer()} | :error
  def sense_pin(sense) when sense >= 0 and sense < 32 do
    {sense_chip(sense), Enum.at([11, 12, 13, 14, 3, 4, 5, 6], rem(sense, 8))}
  end

  def sense_pin(_sense), do: :error

  @spec drive_pin(integer()) :: {String.t(), pos_integer()} | :error
  def drive_pin(drive) when drive >= 0 and drive < 16 do
    {drive_chip(drive), Enum.at([15, 1, 2, 3, 4, 5, 6, 7], rem(drive, 8))}
  end

  def drive_pin(_drive), do: :error

  @spec suspect_lines([{non_neg_integer(), non_neg_integer(), boolean()}]) :: %{
          senses: [{non_neg_integer(), String.t()}],
          drives: [{non_neg_integer(), String.t()}]
        }
  def suspect_lines(events) do
    %{
      senses: suspects(events, fn {d, s, _} -> {s, d} end, drives(), &sense_chip/1),
      drives: suspects(events, fn {d, s, _} -> {d, s} end, senses(), &drive_chip/1)
    }
  end

  defp suspects(events, split, partner_count, chip) do
    events
    |> Enum.map(split)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.filter(fn {_line, partners} -> Enum.count(Enum.uniq(partners)) >= partner_count end)
    |> Enum.map(fn {line, _} -> {line, chip.(line)} end)
    |> Enum.sort()
  end
end
