defmodule Mix.Tasks.Bbparty.Layout.Export do
  @shortdoc "Export the component list to a portable JSON file"

  use Mix.Task

  alias Bbparty.Layout.TransferStore

  @impl Mix.Task
  def run(args) do
    path = parse_args(args)
    Mix.Bbparty.Layout.start_repo()

    rows = TransferStore.export()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Bbparty.Layout.Transfer.to_json(rows))

    Mix.shell().info("Exported #{length(rows)} components to #{path}")
  end

  defp parse_args([path]), do: path

  defp parse_args(_args) do
    Mix.raise("usage: mix bbparty.layout.export PATH")
  end
end
