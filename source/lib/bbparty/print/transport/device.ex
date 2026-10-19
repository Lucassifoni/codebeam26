defmodule Bbparty.Print.Transport.Device do
  @behaviour Bbparty.Print.Transport

  @default_path "/dev/usb/lp0"

  @impl true
  def send(payload, opts) do
    path = Keyword.get(opts, :path, @default_path)

    case File.write(path, payload) do
      :ok -> :ok
      {:error, :eacces} -> {:error, {:printer_not_writable, path}}
      {:error, :enoent} -> {:error, {:printer_not_found, path}}
      {:error, reason} -> {:error, {:printer_write_failed, path, reason}}
    end
  end
end
