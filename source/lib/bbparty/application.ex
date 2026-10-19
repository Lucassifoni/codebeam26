defmodule Bbparty.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      [
        BbpartyWeb.Telemetry,
        Bbparty.Repo,
        {DNSCluster, query: Application.get_env(:bbparty, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Bbparty.PubSub},
        Bbparty.TagProgrammer,
        {Registry, name: Bbparty.ComponentsRegistry, keys: :unique},
        {Registry, name: Bbparty.BindingsRegistry, keys: :unique},
        {Registry, name: Bbparty.ActionsRegistry, keys: :duplicate},
        Bbparty.RenderStateServer,
        {DynamicSupervisor, name: Bbparty.ComponentsSupervisor, strategy: :one_for_one},
        Bbparty.Print.Cooldown,
        Bbparty.Print.Preview,
        Bbparty.Bus.Supervisor
      ] ++
        mail_bridge(Application.get_env(:bbparty, :mail_bridge, :disabled)) ++
        [BbpartyWeb.Endpoint]

    opts = [strategy: :one_for_one, name: Bbparty.Supervisor]
    result = Supervisor.start_link(children, opts)

    for component <- Bbparty.Layout.list_components() do
      Hardware.PhysicalComponent.start(component.component_id, component)
    end

    Bbparty.RenderStateServer.sync()

    result
  end

  defp mail_bridge({:enabled, opts}), do: [{Bbparty.MailBridge.Supervisor, opts}]
  defp mail_bridge(:disabled), do: []

  defp mail_bridge({:incomplete, missing}) do
    Logger.warning("mail bridge not started: #{Enum.join(missing, ", ")} unset")
    []
  end

  @impl true
  def config_change(changed, _new, removed) do
    BbpartyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
