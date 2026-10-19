defmodule Bbparty.Bus.PortManager do
  use GenServer
  require Logger

  alias Bbparty.Bus.Link

  @vendor_ids [0x1A86, 0x0403]
  @poll_ms 2_000

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    if enabled?(), do: send(self(), :poll)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    reconcile()
    Process.send_after(self(), :poll, @poll_ms)
    {:noreply, state}
  end

  defp reconcile do
    present = MapSet.new(esp_ports())
    running = MapSet.new(link_ports())

    for port <- MapSet.difference(present, running) do
      Logger.info("PortManager: new board on #{port}")
      DynamicSupervisor.start_child(Bbparty.Bus.LinkSupervisor, {Link, port})
    end

    for port <- MapSet.difference(running, present) do
      Logger.info("PortManager: #{port} gone")
      terminate_link(port)
    end
  end

  defp esp_ports, do: esp_ports(Circuits.UART.enumerate())

  @spec esp_ports(map()) :: [String.t()]
  def esp_ports(enumeration) do
    enumeration
    |> Enum.filter(fn {_name, info} -> info[:vendor_id] in vendor_ids() end)
    |> Enum.map(fn {name, _info} -> name end)
    |> Enum.sort()
  end

  defp link_ports do
    Registry.select(Bbparty.Bus.LinkRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  defp terminate_link(port) do
    case Registry.lookup(Bbparty.Bus.LinkRegistry, port) do
      [{pid, _} | _] -> DynamicSupervisor.terminate_child(Bbparty.Bus.LinkSupervisor, pid)
      [] -> :ok
    end
  end

  defp enabled?, do: Application.get_env(:bbparty, :bus_autoconnect, true)

  defp vendor_ids, do: Application.get_env(:bbparty, :bus_vendor_ids, @vendor_ids)
end
