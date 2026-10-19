defmodule BbpartyWeb.StickersLive do
  @moduledoc """
  Every archived printout, newest first, re-rendered from its stored state.

  Printouts do not keep their fitted type size, so each sticker is sized in the
  browser (`fit_locally`), which yields the size it was printed at as long as the
  fonts have not changed since.
  """
  use BbpartyWeb, :live_view

  alias Bbparty.Printouts
  alias Bbparty.Printouts.Printout
  alias Bbparty.RenderState
  alias Bbparty.RenderState.Restore
  alias BbpartyWeb.RenderCanvas

  @page_size 24

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Stickers")
     |> assign(:count, Printouts.count())
     |> assign(:last, nil)
     |> assign(:end_reached?, false)
     |> stream_configure(:stickers, dom_id: &"stickers-#{&1.id}")
     |> stream(:stickers, [])
     |> load_more()}
  end

  @impl true
  def handle_event("load_more", _params, socket), do: {:noreply, load_more(socket)}

  defp load_more(%{assigns: %{end_reached?: true}} = socket), do: socket

  defp load_more(socket) do
    printouts = Printouts.page(limit: @page_size, after: socket.assigns.last)

    socket
    |> stream(:stickers, Enum.map(printouts, &sticker/1))
    |> assign(:last, List.last(printouts) || socket.assigns.last)
    |> assign(:end_reached?, length(printouts) < @page_size)
  end

  @doc """
  What the page needs to draw one printout.
  """
  @spec sticker(Printout.t()) :: map()
  def sticker(%Printout{id: id, state: stored, printed_at: printed_at}) do
    state = Restore.from_stored(stored)

    %{
      id: id,
      state: state,
      fingerprint: RenderState.layout_fingerprint(state),
      printed_at: printed_at,
      font: state.selected_font
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="stickers-page" class="min-h-screen bg-neutral-950 text-neutral-100">
      <main class="mx-auto max-w-7xl px-4 py-8 sm:px-6">
        <ol
          id="stickers"
          phx-update="stream"
          phx-viewport-bottom={!@end_reached? && "load_more"}
          class="grid grid-cols-1 gap-x-6 gap-y-10 sm:grid-cols-2 lg:grid-cols-3"
        >
          <li :for={{dom_id, sticker} <- @streams.stickers} id={dom_id} class="group">
            <figure>
              <div class="overflow-hidden rounded-sm shadow-lg shadow-black/40 ring-1 ring-white/10 transition duration-200 group-hover:-translate-y-0.5 group-hover:shadow-xl group-hover:shadow-black/60">
                <RenderCanvas.sticker
                  id={"sticker-#{sticker.id}"}
                  state={sticker.state}
                  fingerprint={sticker.fingerprint}
                  palette={:print}
                  fit_locally
                />
              </div>
            </figure>
          </li>
        </ol>
      </main>
    </div>
    """
  end
end
