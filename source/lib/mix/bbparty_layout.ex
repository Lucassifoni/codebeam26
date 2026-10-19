defmodule Mix.Bbparty.Layout do
  def start_repo() do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Bbparty.Repo.start_link(pool_size: 2)
    :ok
  end
end
