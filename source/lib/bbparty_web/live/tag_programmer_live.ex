defmodule BbpartyWeb.TagProgrammerLive do
  use BbpartyWeb, :live_view

  alias Bbparty.Bus.{Link, Module2Dispatcher}
  alias Bbparty.TagProgrammer
  alias Bbparty.TagProgrammer.State

  @max_bytes 46

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      TagProgrammer.subscribe()
      Module2Dispatcher.subscribe_tags()
    end

    %{machine: machine, log: log} = TagProgrammer.snapshot()

    {:ok,
     socket
     |> assign(:mode, :program)
     |> assign(:programmer, machine_or_nil(machine))
     |> assign(:log, log)
     |> assign(:reads, [])
     |> assign(:lines_text, "")
     |> assign(:errors, [])
     |> assign(:max_bytes, @max_bytes)}
  end

  @impl true
  def handle_event("load", %{"lines" => text}, socket) do
    case parse_lines(text) do
      {:ok, lines} ->
        {:ok, state} = TagProgrammer.load(lines)

        {:noreply,
         socket
         |> assign(:programmer, state)
         |> assign(:lines_text, text)
         |> assign(:errors, [])}

      {:error, errors} ->
        {:noreply, socket |> assign(:errors, errors) |> assign(:lines_text, text)}
    end
  end

  def handle_event("retry", _params, socket) do
    {:ok, state} = TagProgrammer.retry()
    {:noreply, assign(socket, :programmer, state)}
  end

  def handle_event("skip", _params, socket) do
    {:ok, state} = TagProgrammer.skip()
    {:noreply, assign(socket, :programmer, state)}
  end

  def handle_event("reset", _params, socket) do
    TagProgrammer.reset()
    {:noreply, assign(socket, :programmer, nil)}
  end

  def handle_event("clear_log", _params, socket) do
    TagProgrammer.clear_log()
    {:noreply, socket}
  end

  def handle_event("set_mode", %{"mode" => "read"}, socket) do
    TagProgrammer.reset()
    {:noreply, socket |> assign(:mode, :read) |> assign(:programmer, nil)}
  end

  def handle_event("set_mode", %{"mode" => "program"}, socket) do
    {:noreply, assign(socket, :mode, :program)}
  end

  @impl true
  def handle_info({:tag_programmer, %{machine: machine, log: log}}, socket) do
    {:noreply, socket |> assign(:programmer, machine_or_nil(machine)) |> assign(:log, log)}
  end

  def handle_info({:module2, {:tag_read, %{uid: uid, text: text}}}, socket) do
    read = %{uid: Base.encode16(uid), text: text, at: now_hms()}
    {:noreply, assign(socket, :reads, Enum.take([read | socket.assigns.reads], 50))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp machine_or_nil(%State{items: []}), do: nil
  defp machine_or_nil(%State{} = machine), do: machine

  @impl true
  def render(assigns) do
    assigns =
      case assigns.programmer do
        nil ->
          assigns |> assign(:summary, nil) |> assign(:current, nil)

        state ->
          assigns
          |> assign(:summary, State.summary(state))
          |> assign(:current, State.current(state))
      end

    assigns = assign(assigns, :last_read, List.first(assigns.reads))
    assigns = assign(assigns, :connected, Link.module_connected?(2))

    ~H"""
    <div class="max-w-3xl mx-auto p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-semibold">NFC tags</h1>
        <div class="flex gap-1">
          <button
            type="button"
            phx-click="set_mode"
            phx-value-mode="program"
            class={"px-3 py-1 rounded text-sm " <>
              if(@mode == :program, do: "bg-blue-600 text-white", else: "border")}
          >
            Program
          </button>
          <button
            type="button"
            phx-click="set_mode"
            phx-value-mode="read"
            class={"px-3 py-1 rounded text-sm " <>
              if(@mode == :read, do: "bg-blue-600 text-white", else: "border")}
          >
            Read
          </button>
        </div>
      </div>

      <p class="text-sm">
        <span :if={@connected} class="text-green-700">● board 2 connected</span>
        <span :if={not @connected} class="text-gray-500">○ waiting for board 2…</span>
      </p>

      <section :if={@mode == :read} class="space-y-4">
        <div class="border rounded-lg p-6 text-center">
          <p :if={@reads == []} class="text-gray-500">Place a tag on the reader to read it…</p>
          <div :if={@last_read}>
            <p class="text-sm text-gray-500">last read · {@last_read.at}</p>
            <p class="text-2xl font-mono mt-2 break-all">{read_display(@last_read.text)}</p>
            <p class="text-xs text-gray-400 mt-1">UID {@last_read.uid}</p>
          </div>
        </div>
        <div :if={@reads != []} class="border rounded-lg p-4">
          <div class="flex items-center justify-between mb-2">
            <h2 class="font-medium">Recent reads</h2>
            <span class="text-sm text-gray-500">{length(@reads)}</span>
          </div>
          <ol class="max-h-72 overflow-y-auto font-mono text-xs leading-5">
            <li :for={r <- @reads}>
              <span class="text-gray-400">{r.at}</span>
              <span class="text-gray-400">{r.uid}</span> — {read_display(r.text)}
            </li>
          </ol>
        </div>
      </section>

      <section
        :if={@mode == :program and @errors != []}
        class="border border-red-300 bg-red-50 rounded-lg p-4"
      >
        <ul class="list-disc list-inside text-sm text-red-800">
          <li :for={e <- @errors}>{e}</li>
        </ul>
      </section>

      <section :if={@mode == :program and is_nil(@programmer)} class="border rounded-lg p-4 space-y-3">
        <h2 class="font-medium">2. Paste one target string per line (max {@max_bytes} bytes each)</h2>
        <form phx-submit="load" class="space-y-3">
          <textarea
            name="lines"
            rows="12"
            class="w-full border rounded p-2 font-mono text-sm"
            placeholder="TAG-001\nTAG-002\n..."
          >{@lines_text}</textarea>
          <button
            type="submit"
            disabled={not @connected}
            class="px-4 py-2 rounded bg-blue-600 text-white disabled:opacity-40"
          >
            Load &amp; start
          </button>
          <span :if={not @connected} class="text-sm text-gray-500 ml-2">
            waiting for board 2…
          </span>
        </form>
      </section>

      <section :if={@mode == :program and @programmer} class="space-y-4">
        <div class="border rounded-lg p-4 space-y-3">
          <div class="flex items-center justify-between">
            <h2 class="font-medium">Programming</h2>
            <button type="button" phx-click="reset" class="text-sm underline">start over</button>
          </div>

          <p class="text-sm">
            {@summary.done}/{@summary.total} done · {@summary.failed} failed
          </p>

          <div class={"rounded p-3 text-sm " <> phase_banner_class(@programmer.phase)}>
            {phase_instruction(@programmer)}
          </div>

          <div :if={@programmer.phase == :failed} class="flex gap-2">
            <button type="button" phx-click="retry" class="px-3 py-1 rounded bg-amber-600 text-white">
              Retry
            </button>
            <button type="button" phx-click="skip" class="px-3 py-1 rounded border">Skip</button>
          </div>

          <ol class="max-h-96 overflow-y-auto divide-y text-sm font-mono">
            <li
              :for={item <- @programmer.items}
              class={"flex items-center justify-between px-2 py-1 " <>
                if(@current && item.index == @current.index, do: "bg-blue-50", else: "")}
            >
              <span class="truncate">{item.index + 1}. {item.text}</span>
              <span class={"ml-2 shrink-0 px-2 rounded text-xs " <> status_class(item.status)}>
                {status_label(item.status)}
              </span>
            </li>
          </ol>
        </div>
      </section>

      <section :if={@mode == :program and @log != []} class="border rounded-lg p-4">
        <div class="flex items-center justify-between mb-2">
          <h2 class="font-medium">Event log</h2>
          <button type="button" phx-click="clear_log" class="text-sm underline">clear</button>
        </div>
        <ol class="max-h-72 overflow-y-auto font-mono text-xs leading-5">
          <li :for={e <- @log} class={log_class(e.level)}>
            <span class="text-gray-400">{e.at}</span> {e.text}
          </li>
        </ol>
      </section>
    </div>
    """
  end

  defp log_class(:ok), do: "text-green-700"
  defp log_class(:error), do: "text-red-700"
  defp log_class(:warn), do: "text-amber-700"
  defp log_class(_), do: "text-gray-700"

  defp read_display(nil), do: "(unreadable / no NDEF text)"
  defp read_display(""), do: "(empty)"
  defp read_display(text), do: text

  defp now_hms, do: Time.utc_now() |> Time.truncate(:second) |> Time.to_string()

  defp phase_instruction(%State{phase: :awaiting_tag} = s) do
    "Place a blank tag on the reader to write line #{s.cursor + 1}: #{inspect(State.current(s).text)}"
  end

  defp phase_instruction(%State{phase: :awaiting_removal}),
    do: "✓ Verified. Remove the tag to continue to the next line."

  defp phase_instruction(%State{phase: :failed} = s),
    do: "Line #{s.cursor + 1} failed: #{s.error}"

  defp phase_instruction(%State{phase: :complete}), do: "All lines processed."
  defp phase_instruction(%State{}), do: ""

  defp phase_banner_class(:awaiting_removal), do: "bg-green-50 text-green-800"
  defp phase_banner_class(:failed), do: "bg-red-50 text-red-800"
  defp phase_banner_class(:complete), do: "bg-green-100 text-green-900"
  defp phase_banner_class(_), do: "bg-blue-50 text-blue-800"

  defp status_class(:done), do: "bg-green-100 text-green-800"
  defp status_class(:failed), do: "bg-red-100 text-red-800"
  defp status_class(:writing), do: "bg-blue-100 text-blue-800"
  defp status_class(:skipped), do: "bg-gray-200 text-gray-700"
  defp status_class(_), do: "bg-gray-100 text-gray-500"

  defp status_label(:done), do: "done"
  defp status_label(:failed), do: "failed"
  defp status_label(:writing), do: "writing"
  defp status_label(:skipped), do: "skipped"
  defp status_label(_), do: "pending"

  defp parse_lines(text) do
    lines =
      text
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case {lines, validate_lines(lines)} do
      {[], _} -> {:error, ["No non-empty lines to program."]}
      {_, []} -> {:ok, lines}
      {_, errors} -> {:error, errors}
    end
  end

  defp validate_lines(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, i} ->
      case byte_size(line) do
        n when n > @max_bytes ->
          ["Line #{i}: #{n} bytes exceeds the #{@max_bytes}-byte limit (#{inspect(line)})"]

        _ ->
          []
      end
    end)
  end
end
