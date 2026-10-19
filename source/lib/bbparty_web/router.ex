defmodule BbpartyWeb.Router do
  use BbpartyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BbpartyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BbpartyWeb do
    pipe_through :browser

    live "/", ControlPanelLive
    live "/render", RenderLive
    live "/print_render", PrintRenderLive
    live "/tags", TagProgrammerLive
    live "/stickers", StickersLive
    live "/stickers/:id", StickerLive
  end

  if Application.compile_env(:bbparty, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BbpartyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
