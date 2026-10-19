defmodule Bbparty.Print.Transport.MacUsb do
  @behaviour Bbparty.Print.Transport

  @backend "/usr/libexec/cups/backend/usb"

  @impl true
  def send(payload, opts) do
    with {:ok, uri} <- device_uri(opts) do
      path =
        Path.join(System.tmp_dir!(), "bbparty-label-#{System.unique_integer([:positive])}.zpl")

      try do
        with :ok <- File.write(path, payload) do
          run(uri, path, opts)
        end
      after
        File.rm(path)
      end
    end
  end

  @spec discover(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def discover(opts \\ []) do
    case Bbparty.Print.Transport.run(@backend, [], opts) do
      {:ok, output} -> {:ok, parse_devices(output)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec parse_devices(String.t()) :: [String.t()]
  def parse_devices(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, " ", parts: 3) do
        [_class, "usb://" <> _ = uri | _] -> [uri]
        _ -> []
      end
    end)
  end

  defp device_uri(opts) do
    case Keyword.get(opts, :device_uri) do
      nil -> first_discovered(opts)
      uri -> {:ok, uri}
    end
  end

  defp first_discovered(opts) do
    case discover(opts) do
      {:ok, [uri]} -> {:ok, uri}
      {:ok, []} -> {:error, :no_usb_printer}
      {:ok, uris} -> {:error, {:ambiguous_usb_printer, uris}}
      {:error, _reason} = error -> error
    end
  end

  defp run(uri, path, opts) do
    args = ["1", user(), "bbparty", "1", "", path]

    case Bbparty.Print.Transport.run(
           @backend,
           args,
           Keyword.put(opts, :env, [{"DEVICE_URI", uri}])
         ) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp user, do: System.get_env("USER") || "bbparty"
end
