defmodule BbpartyWeb.PrintRenderLive do
  use BbpartyWeb, :live_view

  alias Bbparty.RenderState
  alias BbpartyWeb.RenderCanvas

  def mount(_, _, socket) do
    Phoenix.PubSub.subscribe(Bbparty.PubSub, "render")

    {:ok,
     socket
     |> assign(:fit, Bbparty.RenderStateServer.get_fit())
     |> assign_state(Bbparty.RenderStateServer.get_state())}
  end

  def handle_info({:new_state, state}, socket), do: {:noreply, assign_state(socket, state)}
  def handle_info({:fit, fit}, socket), do: {:noreply, assign(socket, :fit, fit)}

  defp assign_state(socket, state) do
    socket
    |> assign(:state, state)
    |> assign(:fingerprint, RenderState.layout_fingerprint(state))
  end

  def render(assigns) do
    ~H"""
    <RenderCanvas.canvas state={@state} fingerprint={@fingerprint} fit={@fit} palette={:print} />
    """
  end
end
