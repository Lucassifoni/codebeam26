defmodule Bbparty.TagProgrammer do
  use GenServer

  alias Bbparty.Bus.{Link, Module2, Module2Dispatcher}
  alias Bbparty.TagProgrammer.State

  @topic "tag_programmer"
  @max_log 400

  @tag_events [:tag_read, :tag_gone, :write_result]

  defstruct machine: nil, log: []

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def topic, do: @topic
  def subscribe, do: Phoenix.PubSub.subscribe(Bbparty.PubSub, @topic)

  def load(texts) when is_list(texts), do: GenServer.call(__MODULE__, {:load, texts})

  def retry, do: GenServer.call(__MODULE__, :retry)

  def skip, do: GenServer.call(__MODULE__, :skip)

  def reset, do: GenServer.call(__MODULE__, :reset)

  def clear_log, do: GenServer.call(__MODULE__, :clear_log)

  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  @impl true
  def init(_opts) do
    Module2Dispatcher.subscribe()
    {:ok, %__MODULE__{machine: State.new([]), log: []}}
  end

  @impl true
  def handle_call({:load, texts}, _from, server) do
    {machine, effects} = texts |> State.new() |> State.start()
    entries = [entry(:info, "loaded #{length(texts)} line(s)") | effect_entries(effects)]
    server = commit(server, machine, effects, entries)
    {:reply, {:ok, machine}, server}
  end

  def handle_call(:retry, _from, server) do
    {machine, effects} = State.retry(server.machine)
    entries = [entry(:info, "retry line #{line_no(machine)}") | effect_entries(effects)]
    {:reply, {:ok, machine}, commit(server, machine, effects, entries)}
  end

  def handle_call(:skip, _from, server) do
    skipped = line_no(server.machine)
    {machine, effects} = State.skip(server.machine)
    entries = [entry(:warn, "skipped line #{skipped}") | effect_entries(effects)]
    {:reply, {:ok, machine}, commit(server, machine, effects, entries)}
  end

  def handle_call(:reset, _from, server) do
    {:reply, :ok, commit(server, State.new([]), [], [entry(:info, "reset")])}
  end

  def handle_call(:clear_log, _from, server) do
    server = %{server | log: []}
    Phoenix.PubSub.broadcast(Bbparty.PubSub, @topic, {:tag_programmer, snapshot_of(server)})
    {:reply, :ok, server}
  end

  def handle_call(:snapshot, _from, server), do: {:reply, snapshot_of(server), server}

  @impl true
  def handle_info({:module2, event}, server) when elem(event, 0) in @tag_events do
    {machine, effects} = State.handle_event(server.machine, event)

    entries =
      event_entries(event) ++
        transition_entries(server.machine, machine) ++ effect_entries(effects)

    {:noreply, commit(server, machine, effects, entries)}
  end

  def handle_info(_msg, server), do: {:noreply, server}

  defp commit(server, machine, effects, entries) do
    Enum.each(effects, &perform/1)
    server = %{server | machine: machine, log: prepend(server.log, entries)}
    Phoenix.PubSub.broadcast(Bbparty.PubSub, @topic, {:tag_programmer, snapshot_of(server)})
    server
  end

  defp perform({:write_tag, text}),
    do: Link.send_command(Module2.module_id(), Module2.write_tag(text))

  defp snapshot_of(%__MODULE__{machine: machine, log: log}), do: %{machine: machine, log: log}

  defp prepend(log, entries), do: Enum.take(Enum.reverse(entries) ++ log, @max_log)

  defp line_no(%State{cursor: cursor}), do: cursor + 1

  defp event_entries({:tag_read, %{text: text, uid: uid}}),
    do: [entry(:info, "read-back #{format_uid(uid)}: #{inspect(text)}")]

  defp event_entries({:write_result, %{ok: true}}), do: [entry(:ok, "device: write OK")]
  defp event_entries({:write_result, %{ok: false}}), do: [entry(:error, "device: write FAILED")]
  defp event_entries({:tag_gone}), do: [entry(:info, "tag removed")]
  defp event_entries(_), do: []

  defp transition_entries(%State{phase: :awaiting_tag}, %State{phase: :awaiting_removal} = new),
    do: [entry(:ok, "line #{line_no(new)} verified ✓")]

  defp transition_entries(%State{phase: old}, %State{phase: :failed} = new) when old != :failed,
    do: [entry(:error, "line #{line_no(new)} failed — #{new.error}")]

  defp transition_entries(%State{phase: old}, %State{phase: :complete}) when old != :complete,
    do: [entry(:ok, "all lines complete")]

  defp transition_entries(_old, _new), do: []

  defp effect_entries(effects) do
    Enum.map(effects, fn {:write_tag, text} -> entry(:info, "→ WriteTag #{inspect(text)}") end)
  end

  defp entry(level, text), do: %{at: timestamp(), level: level, text: text}

  defp timestamp do
    Time.utc_now() |> Time.truncate(:millisecond) |> Time.to_string()
  end

  defp format_uid(uid) when is_binary(uid) and byte_size(uid) > 0, do: "[#{Base.encode16(uid)}]"
  defp format_uid(_), do: ""
end
