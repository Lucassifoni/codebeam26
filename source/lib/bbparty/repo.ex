defmodule Bbparty.Repo do
  use Ecto.Repo,
    otp_app: :bbparty,
    adapter: Ecto.Adapters.Postgres
end
