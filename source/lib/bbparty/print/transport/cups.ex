defmodule Bbparty.Print.Transport.Cups do
  @behaviour Bbparty.Print.Transport

  @impl true
  def send(payload, opts) do
    case Keyword.get(opts, :queue) do
      nil ->
        {:error, :no_queue_configured}

      queue ->
        path =
          Path.join(System.tmp_dir!(), "bbparty-label-#{System.unique_integer([:positive])}.zpl")

        try do
          with :ok <- File.write(path, payload) do
            lp(path, queue, opts)
          end
        after
          File.rm(path)
        end
    end
  end

  defp lp(path, queue, opts) do
    case Bbparty.Print.Transport.run("lp", ["-o", "raw", "-d", queue, path], opts) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
