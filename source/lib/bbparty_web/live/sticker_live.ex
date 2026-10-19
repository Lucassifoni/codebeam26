defmodule BbpartyWeb.StickerLive do
  @moduledoc """
  One archived printout, alone on the page and as wide as the window, as it was
  printed. This is the page `mix bbparty.printouts.export` captures.

  Like `BbpartyWeb.StickersLive`, the sticker is sized in the browser.
  """
  use BbpartyWeb, :live_view

  alias Bbparty.Printouts
  alias BbpartyWeb.RenderCanvas
  alias BbpartyWeb.StickersLive

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    sticker = id |> Printouts.get!() |> StickersLive.sticker()

    {:ok,
     socket
     |> assign(:page_title, "Sticker #{sticker.id}")
     |> assign(:sticker, sticker)}
  end

  @doc """
  The DOM id of the element holding printout `id`'s sticker.
  """
  @spec root_id(integer()) :: String.t()
  def root_id(id), do: "sticker-#{id}-root"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="sticker-page" class="min-h-screen bg-white">
      <RenderCanvas.sticker
        id={"sticker-#{@sticker.id}"}
        state={@sticker.state}
        fingerprint={@sticker.fingerprint}
        palette={:print}
        fit_locally
      />
    </div>
    """
  end
end
