import Config

config :bbparty, Bbparty.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "bbparty_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :bbparty, BbpartyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "xAwpF8s/exAcyfNz5a9oIZzmgwhDnLmwgRHN3HZhlPDqi7DKh1UxiRlOdpiogB4w",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:bbparty, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:bbparty, ~w(--watch)]}
  ]

config :bbparty, BbpartyWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*\.po$",
      ~r"lib/bbparty_web/router\.ex$",
      ~r"lib/hardware/.*.ex",
      ~r"lib/bbparty_web/(controllers|live|components)/.*\.(ex|heex)$"
    ]
  ]

config :bbparty, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false

config :bbparty, key_autoregister: true
