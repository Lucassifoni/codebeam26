import Config

if System.get_env("PHX_SERVER") do
  config :bbparty, BbpartyWeb.Endpoint, server: true
end

config :bbparty, BbpartyWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() != :test do
  config :bbparty,
         :mail_bridge,
         Bbparty.MailBridge.Config.from_env(System.get_env())
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :bbparty, Bbparty.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT", "4000"))

  config :bbparty, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  origins = Enum.uniq(["//localhost", "//127.0.0.1", "//#{host}"])

  config :bbparty, BbpartyWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    check_origin: origins,
    secret_key_base: secret_key_base
end
