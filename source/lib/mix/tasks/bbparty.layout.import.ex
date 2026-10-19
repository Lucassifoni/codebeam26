defmodule Mix.Tasks.Bbparty.Layout.Import do
  @shortdoc "Import a component list from a portable JSON file"

  use Mix.Task

  alias Bbparty.Layout.Transfer
  alias Bbparty.Layout.TransferStore

  @modes ~w(replace_all merge)

  @impl Mix.Task
  def run(args) do
    {path, mode} = parse_args(args)
    Mix.Bbparty.Layout.start_repo()

    path
    |> read!()
    |> TransferStore.import_json(mode)
    |> report(path, mode)
  end

  defp parse_args(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: [mode: :string])

    case {positional, Keyword.get(opts, :mode), invalid} do
      {[path], "replace_all", []} -> {path, :replace_all}
      {[path], "merge", []} -> {path, :merge}
      _ -> Mix.raise(usage())
    end
  end

  defp usage() do
    "usage: mix bbparty.layout.import PATH --mode #{Enum.join(@modes, "|")}"
  end

  defp read!(path) do
    case File.read(path) do
      {:ok, json} -> json
      {:error, reason} -> Mix.raise("cannot read #{path}: #{:file.format_error(reason)}")
    end
  end

  defp report({:error, problems}, path, _mode) do
    Mix.raise("#{path} is invalid, nothing was written:\n" <> Transfer.format_problems(problems))
  end

  defp report({:ok, result}, path, mode) do
    Mix.shell().info("""
    Imported #{path} (mode: #{mode})
      inserted:  #{summarize(result.inserted)}
      updated:   #{summarize(result.updated)}
      unchanged: #{length(result.unchanged)}
      deleted:   #{summarize(result.deleted)}
    """)

    restart_notice(result.changed)
  end

  defp restart_notice([]), do: Mix.shell().info("Nothing changed; no component needs restarting.")

  defp restart_notice(changed) do
    Mix.shell().info(
      "Restart the app (or call Bbparty.Layout.TransferStore.restart_components/1 in it) " <>
        "for these #{length(changed)} components: #{Enum.join(changed, ", ")}"
    )
  end

  defp summarize([]), do: "0"
  defp summarize(ids), do: "#{length(ids)} (#{Enum.join(ids, ", ")})"
end
