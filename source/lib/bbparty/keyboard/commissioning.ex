defmodule Bbparty.Keyboard.Commissioning do
  alias Bbparty.Bus.Module3Dispatcher
  alias Bbparty.Keyboard
  alias Bbparty.Keyboard.RowWalk
  alias Bbparty.Layout
  alias Hardware.PhysicalComponent

  @idle_ms 6_000

  @spec capture(pos_integer()) :: [{integer(), integer(), boolean()}]
  def capture(seconds \\ 30) do
    resubscribe()

    try do
      collect(System.monotonic_time(:millisecond) + seconds * 1_000, [])
    after
      Module3Dispatcher.unsubscribe()
    end
  end

  defp resubscribe do
    Module3Dispatcher.unsubscribe()
    drain()
    Module3Dispatcher.subscribe()
  end

  defp drain do
    receive do
      {:module3, _event} -> drain()
    after
      0 -> :ok
    end
  end

  defp collect(deadline, acc) do
    receive do
      {:module3, {:key_event, drive, sense, pressed}} ->
        collect(deadline, [{drive, sense, pressed} | acc])

      {:module3, _other} ->
        collect(deadline, acc)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> Enum.reverse(acc)
    end
  end

  @spec capture_timed(pos_integer()) :: [{non_neg_integer(), integer(), integer(), boolean()}]
  def capture_timed(seconds \\ 30) do
    resubscribe()
    start = System.monotonic_time(:millisecond)

    try do
      collect_timed(start + seconds * 1_000, start, [])
    after
      Module3Dispatcher.unsubscribe()
    end
  end

  defp collect_timed(deadline, start, acc) do
    receive do
      {:module3, {:key_event, drive, sense, pressed}} ->
        at = System.monotonic_time(:millisecond) - start
        collect_timed(deadline, start, [{at, drive, sense, pressed} | acc])

      {:module3, _other} ->
        collect_timed(deadline, start, acc)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> Enum.reverse(acc)
    end
  end

  @spec survey(pos_integer()) :: [{non_neg_integer(), integer(), integer(), boolean()}]
  def survey(seconds \\ 20) do
    events = capture_timed(seconds)

    IO.puts("\n" <> Keyboard.event_grid(events))

    IO.puts(
      "\n#{length(events)} events, #{length(Keyboard.summarise(events))} distinct crosspoints"
    )

    IO.puts("axis marks: - wired sense, | wired drive\n")

    events
  end

  @spec discover(pos_integer()) :: %{drives: [integer()], senses: [integer()]}
  def discover(seconds \\ 30) do
    seconds |> capture() |> Keyboard.lines_in_press_order()
  end

  @spec walk_keyboard(keyword()) :: map()
  def walk_keyboard(opts \\ []) do
    walk = RowWalk.new(opts)
    write? = Keyword.get(opts, :write, true)
    timeout = Keyword.get(opts, :timeout, @idle_ms)

    announce_row(walk, timeout)
    resubscribe()

    walk =
      try do
        fill_row(walk, timeout, write?)
      after
        Module3Dispatcher.unsubscribe()
      end

    release_stale(walk, write?)

    report = RowWalk.report(walk)
    print_row(report)

    Map.put(report, :meanings, assign(RowWalk.keys(walk), opts, write?))
  end

  @spec assign_row(non_neg_integer(), keyword(), keyword()) :: map()
  def assign_row(row, spec, opts \\ []) do
    keys = RowWalk.row_of(Layout.list_components(), Keyword.put_new(opts, :row, row))

    assign(keys, spec, Keyword.get(opts, :write, true))
  end

  @spec keyboard_report(keyword()) :: [map()]
  def keyboard_report(opts \\ []) do
    rows = RowWalk.rows(Layout.list_components(), opts)

    IO.puts("")

    width = rows |> Enum.map(&String.length(&1.group)) |> Enum.max(fn -> 0 end)

    for %{group: group, cells: cells} <- rows do
      IO.puts("  #{String.pad_trailing(group, width)}  #{Enum.map_join(cells, " ", &legend/1)}")
    end

    IO.puts(
      "\n  #{length(rows)} row(s), #{rows |> Enum.flat_map(& &1.cells) |> length()} key(s)\n"
    )

    rows
  end

  defp legend(%{char: nil, action: nil}), do: "·"
  defp legend(%{action: action}) when is_binary(action) and action != "", do: "[#{action}]"
  defp legend(%{char: char}), do: char

  defp fill_row(walk, timeout, write?) do
    case await_press(timeout) do
      {:ok, key} -> walk |> pressed(key, write?) |> fill_row(timeout, write?)
      :timeout -> walk
    end
  end

  defp pressed(walk, key, write?) do
    case RowWalk.press(walk, key) do
      {:ok, updated, cell} ->
        IO.puts("  col #{String.pad_leading("#{cell.col}", 2)} — #{key}")
        move(key, cell.position, walk.group, write?)
        updated

      {:error, {:already_in_row, key, col}} ->
        IO.puts("     #{key} is already column #{col} — ignored")
        walk
    end
  end

  defp move(_key, _position, _group, false), do: :ok

  defp move(key, position, group, true) do
    case Enum.any?(Layout.list_components(), &(&1.component_id == key)) do
      true ->
        Layout.move_components([{key, position}])
        if group, do: Layout.set_group([key], group)
        Phoenix.PubSub.broadcast(Bbparty.PubSub, "components", :layout_moved)

      false ->
        IO.puts("     #{key} is not in the layout — position not written")
    end
  end

  defp release_stale(%RowWalk{group: nil}, _write?), do: :ok
  defp release_stale(%RowWalk{col: col}, _write?) when col > 0, do: :ok
  defp release_stale(_walk, false), do: :ok

  defp release_stale(%RowWalk{group: group} = walk, true) do
    kept = MapSet.new(RowWalk.keys(walk))

    stale =
      Layout.list_components()
      |> Enum.filter(&(&1.group_id == group and not MapSet.member?(kept, &1.component_id)))
      |> Enum.map(& &1.component_id)

    case stale do
      [] ->
        :ok

      keys ->
        Layout.set_group(keys, nil)
        IO.puts("     released from #{group}: #{inspect(keys)}")
        Phoenix.PubSub.broadcast(Bbparty.PubSub, "components", :layout_moved)
    end
  end

  defp assign(keys, spec, write?) do
    case Keyword.take(spec, [:chars, :shift, :actions]) do
      [] -> %{assignments: [], untouched: keys, errors: [], overflow: 0}
      spec -> apply_meanings(RowWalk.meanings(keys, spec), write?)
    end
  end

  defp apply_meanings(result, write?) do
    if write? do
      for {key, attrs} <- result.assignments, do: write_meaning(key, attrs)
      Phoenix.PubSub.broadcast(Bbparty.PubSub, "components", :layout_moved)
    end

    print_meanings(result)
    result
  end

  defp write_meaning(key, attrs) do
    for {name, value} <- attrs, do: Layout.set_component_attr(key, name, value)

    if PhysicalComponent.running?(key) do
      PhysicalComponent.reconfigure(key, Layout.get_component(key))
      PhysicalComponent.query_state(key)
    end
  end

  defp await_press(timeout) do
    await_until(System.monotonic_time(:millisecond) + timeout)
  end

  defp await_until(deadline) do
    receive do
      {:module3, {:key_event, drive, sense, true}} ->
        press_id(drive, sense, deadline)

      {:module3, _other} ->
        await_until(deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> :timeout
    end
  end

  defp press_id(drive, sense, deadline) do
    case Keyboard.valid_address?(drive, sense) do
      true ->
        {:ok, String.to_atom(Keyboard.key_id(drive, sense))}

      false ->
        IO.puts("     " <> Keyboard.describe_address(drive, sense))
        await_until(deadline)
    end
  end

  defp announce_row(walk, timeout) do
    IO.puts("""

    Row #{walk.row}: press along it, left to right, starting at column #{walk.col}.
    Nothing lights. The row closes after #{Float.round(timeout / 1000, 1)}s of quiet.
    """)
  end

  defp print_row(%{row: row, group: group, cells: cells}) do
    IO.puts(
      "\n  row #{row}#{group && " (group #{group})"}: #{length(cells)} key(s) — " <>
        Enum.map_join(cells, " ", &"#{&1.key}")
    )
  end

  defp print_meanings(%{assignments: [], untouched: untouched}) do
    IO.puts("  no meanings given — #{length(untouched)} key(s) left as they were\n")
  end

  defp print_meanings(result) do
    IO.puts("  #{length(result.assignments)} key(s) assigned")

    for {key, reason} <- result.errors, do: IO.puts("     #{key}: #{explain(reason)}")

    case result.untouched do
      [] -> :ok
      keys -> IO.puts("     #{length(keys)} key(s) left as they were: #{inspect(keys)}")
    end

    case result.overflow do
      0 -> :ok
      n -> IO.puts("     #{n} spec entr(ies) had no key — the row is shorter than the legend")
    end

    IO.puts("")
  end

  defp explain({:unknown_action, value}),
    do: "#{inspect(value)} is not an action — one of #{inspect(Bbparty.Keyboard.Action.all())}"
end
