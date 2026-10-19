defmodule BbpartyWeb.RenderLive do
  use BbpartyWeb, :live_view

  alias Bbparty.RenderState
  alias Bbparty.RenderState.Fit
  alias Bbparty.RenderState.TextLayout
  alias BbpartyWeb.RenderCanvas

  def mount(params, _, socket) do
    Phoenix.PubSub.subscribe(Bbparty.PubSub, "render")

    {:ok,
     socket
     |> assign(:measure, measure?(params))
     |> assign(:fit, Bbparty.RenderStateServer.get_fit())
     |> assign_state(Bbparty.RenderStateServer.get_state())}
  end

  def handle_info({:new_state, state}, socket), do: {:noreply, assign_state(socket, state)}
  def handle_info({:fit, fit}, socket), do: {:noreply, assign(socket, :fit, fit)}

  def handle_event("text_layout", params, socket) do
    Bbparty.RenderStateServer.put_layout(TextLayout.from_params(params))
    {:noreply, socket}
  end

  def handle_event("fit", params, socket) do
    case Fit.from_params(params) do
      {:ok, fit} -> Bbparty.RenderStateServer.put_fit(fit)
      :error -> :ok
    end

    {:noreply, socket}
  end

  @doc """
  Whether this page is the one renderer that measures and pushes layout.
  `?mirror` gives a read-only copy, as embedded by the panel editor.
  """
  @spec measure?(map() | atom()) :: boolean()
  def measure?(%{"mirror" => _}), do: false
  def measure?(_params), do: true

  defp assign_state(socket, state) do
    socket
    |> assign(:state, state)
    |> assign(:fingerprint, RenderState.layout_fingerprint(state))
  end

  def render(assigns) do
    ~H"""
    <RenderCanvas.canvas
      state={@state}
      fingerprint={@fingerprint}
      fit={@fit}
      measure={@measure}
      palette={:screen}
    />
    <div :if={@state.caps_lock} id="render-caps-lock" style={caps_lock_style()}>caps lock on</div>
    """
  end

  defp caps_lock_style do
    """
    position: fixed;
    top: 0.8vw;
    left: 0.8vw;
    font-family: "Brut Grotesque Medium", sans-serif;
    font-size: clamp(14px, 1.4vw, 48px);
    line-height: 1;
    color: #fff;
    mix-blend-mode: difference;
    pointer-events: none;
    """
  end
end
