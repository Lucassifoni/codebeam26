import Config

config :bbparty,
  ecto_repos: [Bbparty.Repo],
  generators: [timestamp_type: :utc_datetime]

config :bbparty, key_autoregister: false

config :bbparty, BbpartyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BbpartyWeb.ErrorHTML, json: BbpartyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Bbparty.PubSub,
  live_view: [signing_salt: "rIYdC4Ry"]

config :bbparty, Bbparty.Mailer, adapter: Swoosh.Adapters.Local

config :esbuild,
  version: "0.25.4",
  bbparty: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.1.12",
  bbparty: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :bbparty, :print_impls, [&Bbparty.Print.Sticker.print/1]

config :bbparty, :label, cooldown_ms: 10_000

import_config "#{config_env()}.exs"
