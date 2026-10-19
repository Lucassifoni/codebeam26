defmodule Bbparty.Bus.Supervisor do
  use Supervisor

  def start_link(_opts \\ []), do: Supervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    children = [
      {Registry, keys: :unique, name: Bbparty.Bus.LinkRegistry},
      {Registry, keys: :unique, name: Bbparty.Bus.ModuleRegistry},
      {DynamicSupervisor, name: Bbparty.Bus.LinkSupervisor, strategy: :one_for_one},
      Bbparty.Bus.LedShadow,
      Bbparty.Bus.Module2Dispatcher,
      Bbparty.Bus.Module3Dispatcher,
      Bbparty.Bus.Module4Dispatcher,
      Bbparty.Bus.Module7Dispatcher,
      Bbparty.Bus.PortManager
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
