defmodule Mix.Tasks.Bbparty.Fonts do
  @shortdoc "Import a bureaubrut font export: manifest, @font-face CSS and files"

  use Mix.Task

  alias Bbparty.FontBundle
  alias Bbparty.FontMap

  @manifest "priv/fonts.json"
  @css "assets/css/fonts.css"
  @static_dir "priv/static/fonts"
  @system_manifest "priv/fonts.system.json"

  @impl Mix.Task
  def run(args) do
    {dir, opts} = parse_args(args)
    Mix.Task.run("compile")

    export = read_export!(dir)
    fonts = valid_fonts!(export)
    refuse_system_clashes!(fonts)
    refuse_missing_pin_sources!(fonts)
    print_export_problems(export)

    run_mode(mode(opts), dir, fonts, opts)
  end

  defp parse_args(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args, strict: [check: :boolean, report: :boolean, names: :string])

    case {positional, invalid} do
      {[dir], []} -> {dir, opts}
      _ -> Mix.raise("usage: mix bbparty.fonts EXPORT_DIR [--check | --report | --names FILE]")
    end
  end

  defp mode(opts) do
    opts
    |> Keyword.take([:check, :report, :names])
    |> Enum.reject(fn {_mode, value} -> value in [false, nil] end)
    |> Keyword.keys()
    |> Enum.uniq()
  end

  defp run_mode([], dir, fonts, _opts), do: import!(dir, fonts)
  defp run_mode([:check], dir, fonts, _opts), do: check!(dir, fonts)
  defp run_mode([:report], _dir, fonts, _opts), do: print_report(fonts)
  defp run_mode([:names], _dir, fonts, opts), do: names!(fonts, Keyword.fetch!(opts, :names))

  defp run_mode(_modes, _dir, _fonts, _opts),
    do: Mix.raise("--check, --report and --names are exclusive")

  defp read_export!(dir), do: dir |> Path.join("fonts.json") |> read_json!()

  defp read_json!(path) do
    with {:ok, json} <- File.read(path),
         {:ok, export} <- Jason.decode(json) do
      export
    else
      {:error, %Jason.DecodeError{} = error} -> Mix.raise("#{path}: #{Exception.message(error)}")
      {:error, reason} -> Mix.raise("cannot read #{path}: #{:file.format_error(reason)}")
    end
  end

  defp valid_fonts!(export) do
    case FontBundle.fonts(export) do
      {:ok, fonts} ->
        fonts

      {:error, problems} ->
        Mix.raise(
          "the export is invalid, nothing was written:\n" <> FontBundle.format_problems(problems)
        )
    end
  end

  defp refuse_system_clashes!(fonts) do
    system_ids =
      @system_manifest
      |> read_json!()
      |> Map.fetch!("fonts")
      |> MapSet.new(&Map.fetch!(&1, "id"))

    case Enum.filter(fonts, &(&1.id in system_ids)) do
      [] ->
        :ok

      clashes ->
        Mix.raise(
          "these fonts are also hand-kept in #{@system_manifest}, nothing was written:\n" <>
            Enum.map_join(clashes, "\n", &"  #{inspect(&1.id)}")
        )
    end
  end

  defp refuse_missing_pin_sources!(fonts) do
    case FontBundle.missing_pin_sources(fonts) do
      [] ->
        :ok

      missing ->
        Mix.raise(
          "the export is missing #{Enum.map_join(missing, ", ", &inspect/1)}, which " <>
            "#{Bbparty.FontBundle.pins() |> length()} pinned codepoint ranges are served " <>
            "from; nothing was written"
        )
    end
  end

  defp print_export_problems(export) do
    case FontBundle.export_problems(export) do
      [] ->
        :ok

      problems ->
        Mix.shell().info(
          "The export reports #{length(problems)} problems:\n" <>
            Enum.map_join(problems, "\n", &"  #{inspect(&1)}")
        )
    end
  end

  defp import!(dir, fonts) do
    missing = Enum.reject(fonts, &File.regular?(Path.join(dir, &1.source)))

    case missing do
      [] ->
        :ok

      _ ->
        Mix.raise(
          "files missing from the export, nothing was written:\n" <>
            Enum.map_join(missing, "\n", &"  #{&1.source}")
        )
    end

    File.mkdir_p!(@static_dir)
    removed = remove_stale_files(fonts)
    Enum.each(fonts, &File.cp!(Path.join(dir, &1.source), Path.join(@static_dir, &1.file)))

    File.write!(@manifest, FontBundle.manifest_json(fonts))
    File.write!(@css, FontBundle.font_faces_css(fonts))

    Mix.shell().info("""
    Imported #{length(fonts)} fonts from #{dir}
      #{@manifest}
      #{@css}
      #{@static_dir}/ (#{length(fonts)} files, #{length(removed)} stale removed)
    """)
  end

  defp remove_stale_files(fonts) do
    shipped = MapSet.new(fonts, & &1.file)

    @static_dir
    |> Path.join("*.woff2")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) in shipped))
    |> Enum.map(fn path ->
      File.rm!(path)
      path
    end)
  end

  defp check!(dir, fonts) do
    drift =
      [
        drift_in(@manifest, FontBundle.manifest_json(fonts)),
        drift_in(@css, FontBundle.font_faces_css(fonts))
        | Enum.map(fonts, &file_drift(dir, &1))
      ]
      |> List.flatten()

    case drift do
      [] ->
        Mix.shell().info("The shipped bundle matches #{dir} (#{length(fonts)} fonts).")

      _ ->
        Mix.raise(
          "The shipped bundle differs from #{dir}; run `mix bbparty.fonts #{dir}`:\n" <>
            Enum.map_join(drift, "\n", &"  #{&1}")
        )
    end
  end

  defp drift_in(path, expected) do
    case File.read(path) do
      {:ok, ^expected} -> []
      {:ok, _other} -> ["#{path} differs"]
      {:error, _} -> ["#{path} is missing"]
    end
  end

  defp file_drift(dir, font) do
    shipped = Path.join(@static_dir, font.file)

    case {File.read(shipped), File.read(Path.join(dir, font.source))} do
      {{:ok, same}, {:ok, same}} -> []
      {{:error, _}, _} -> ["#{shipped} is missing"]
      _ -> ["#{shipped} differs from the export"]
    end
  end

  defp print_report(fonts) do
    report = FontBundle.report(fonts, FontMap.feature_tags())
    panel = MapSet.new(FontMap.feature_tags())

    rows =
      Enum.map_join(report.frequencies, "\n", fn {tag, count} ->
        "  #{String.pad_trailing(tag, 6)} #{String.pad_leading(Integer.to_string(count), 4)}/#{report.fonts}  #{panel_marker(tag in panel)}"
      end)

    absent =
      Enum.reject(FontMap.feature_tags(), fn tag ->
        Enum.any?(report.frequencies, &(elem(&1, 0) == tag))
      end)

    Mix.shell().info("""
    #{report.fonts} fonts, #{length(report.frequencies)} distinct tags (most frequent first):
    #{rows}

    On the panel but offered by no font: #{Enum.join(absent, ", ")}
    """)
  end

  defp panel_marker(true), do: "panel"
  defp panel_marker(false), do: ""

  defp names!(fonts, path) do
    burnt =
      case File.read(path) do
        {:ok, text} -> String.split(text, ~r/\r?\n/)
        {:error, reason} -> Mix.raise("cannot read #{path}: #{:file.format_error(reason)}")
      end

    comparison = FontBundle.compare_names(fonts, burnt)

    Mix.shell().info("""
    Fonts no tag selects (#{length(comparison.fonts_without_tag)}):
    #{Enum.map_join(comparison.fonts_without_tag, "\n", &"  #{&1}")}
    """)

    case comparison.burnt_without_font do
      [] ->
        Mix.shell().info("Every burnt tag selects a font.")

      dead ->
        Mix.raise(
          "Tags that select no font (#{length(dead)}):\n" <>
            Enum.map_join(dead, "\n", &"  #{inspect(&1)}")
        )
    end
  end
end
