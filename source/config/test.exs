import Config

config :bbparty, bus_autoconnect: false

config :bbparty, Bbparty.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "bbparty_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :bbparty, BbpartyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "uOaM9dwRKS/j7WC5EGcTCz7nvTybYMSo2rWN9JfjQDBXU1J+JWXSFEjORg6Pd8JX",
  server: false

config :bbparty, Bbparty.Mailer, adapter: Swoosh.Adapters.Test

config :swoosh, :api_client, false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true

config :bbparty, key_autoregister: true

config :bbparty, :print_impls, []
