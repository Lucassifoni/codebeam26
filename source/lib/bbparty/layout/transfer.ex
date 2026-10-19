defmodule Bbparty.Layout.Transfer do
  @format "bbparty.layout"
  @version 1

  @type row :: %{
          component_id: String.t(),
          module: String.t(),
          attrs: map(),
          position: map() | nil,
          group_id: String.t() | nil
        }

  @type problem :: %{
          index: non_neg_integer() | nil,
          component_id: String.t() | nil,
          field: atom(),
          error: atom(),
          value: term()
        }

  @type registry :: %{optional(String.t()) => keyword(atom())}

  def format(), do: @format

  def version(), do: @version

  @spec encode([map()]) :: map()
  def encode(rows) do
    components =
      rows
      |> Enum.map(&encode_row/1)
      |> Enum.sort_by(& &1["component_id"])

    %{"format" => @format, "version" => @version, "components" => components}
  end

  @spec to_json([map()]) :: String.t()
  def to_json(rows) do
    (rows |> encode() |> Jason.encode!(pretty: true)) <> "\n"
  end

  defp encode_row(row) do
    %{
      "component_id" => to_string(fetch(row, :component_id)),
      "module" => short_module(fetch(row, :module)),
      "attrs" => encode_attrs(fetch(row, :attrs)),
      "position" => encode_position(fetch(row, :position)),
      "group_id" => encode_group_id(fetch(row, :group_id))
    }
  end

  defp fetch(row, key) when is_map(row), do: Map.get(row, key, Map.get(row, to_string(key)))

  defp encode_attrs(nil), do: %{}

  defp encode_attrs(attrs) when is_map(attrs),
    do: Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

  defp encode_position(nil), do: nil

  defp encode_position(position) when is_map(position) do
    Map.new(position, fn {k, v} -> {to_string(k), v} end)
  end

  defp encode_group_id(nil), do: nil
  defp encode_group_id(group_id), do: to_string(group_id)

  @spec short_module(atom() | String.t()) :: String.t()
  def short_module(module) do
    case to_string(module) do
      "Elixir." <> rest -> rest
      other -> other
    end
  end

  @spec long_module(String.t()) :: String.t()
  def long_module("Elixir." <> _ = name), do: name
  def long_module(name), do: "Elixir." <> name

  @spec decode(String.t()) :: {:ok, map()} | {:error, [problem()]}
  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, envelope} ->
        {:ok, envelope}

      {:error, error} ->
        {:error, [problem(nil, nil, :file, :malformed_json, Exception.message(error))]}
    end
  end

  @spec validate(map(), registry()) :: {:ok, [row()]} | {:error, [problem()]}
  def validate(envelope, known_modules) when is_map(envelope) do
    registry = normalize_registry(known_modules)

    case envelope_problems(envelope) do
      [] -> validate_components(Map.fetch!(envelope, "components"), registry)
      problems -> {:error, problems}
    end
  end

  def validate(other, _known_modules) do
    {:error, [problem(nil, nil, :envelope, :not_an_object, other)]}
  end

  defp normalize_registry(known_modules) do
    Map.new(known_modules, fn {name, fields} -> {long_module(to_string(name)), fields} end)
  end

  defp envelope_problems(envelope) do
    [
      format_tag_problem(Map.get(envelope, "format")),
      version_problem(Map.get(envelope, "version")),
      components_problem(Map.get(envelope, "components"))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp format_tag_problem(@format), do: nil
  defp format_tag_problem(other), do: problem(nil, nil, :format, :unknown_format, other)

  defp version_problem(@version), do: nil
  defp version_problem(other), do: problem(nil, nil, :version, :unsupported_version, other)

  defp components_problem(components) when is_list(components), do: nil
  defp components_problem(other), do: problem(nil, nil, :components, :not_a_list, other)

  defp validate_components(components, registry) do
    problems =
      components
      |> Enum.with_index()
      |> Enum.flat_map(fn {component, index} -> row_problems(component, index, registry) end)
      |> Kernel.++(duplicate_problems(components))

    case problems do
      [] -> {:ok, Enum.map(components, &to_row/1)}
      _ -> {:error, problems}
    end
  end

  defp row_problems(component, index, _registry) when not is_map(component) do
    [problem(index, nil, :component, :not_an_object, component)]
  end

  defp row_problems(component, index, registry) do
    id = Map.get(component, "component_id")

    [
      component_id_problems(component, index),
      module_problems(component, index, id, registry),
      position_problems(component, index, id),
      group_id_problems(component, index, id),
      attrs_problems(component, index, id, registry)
    ]
    |> List.flatten()
  end

  defp component_id_problems(component, index) do
    case Map.get(component, "component_id") do
      id when is_binary(id) and id != "" -> []
      other -> [problem(index, nil, :component_id, :invalid_component_id, other)]
    end
  end

  defp module_problems(component, index, id, registry) do
    name = Map.get(component, "module")

    case name do
      name when is_binary(name) and name != "" ->
        unknown_module_problems(name, index, id, registry)

      other ->
        [problem(index, id, :module, :invalid_module, other)]
    end
  end

  defp unknown_module_problems(name, index, id, registry) do
    case Map.has_key?(registry, long_module(name)) do
      true -> []
      false -> [problem(index, id, :module, :unknown_module, name)]
    end
  end

  defp position_problems(component, index, id) do
    case Map.get(component, "position") do
      nil -> []
      %{"x" => x, "y" => y} when is_number(x) and is_number(y) -> []
      other -> [problem(index, id, :position, :malformed_position, other)]
    end
  end

  defp group_id_problems(component, index, id) do
    case Map.get(component, "group_id") do
      nil -> []
      group_id when is_binary(group_id) -> []
      other -> [problem(index, id, :group_id, :invalid_group_id, other)]
    end
  end

  defp attrs_problems(component, index, id, registry) do
    attrs = Map.get(component, "attrs")
    fields = Map.get(registry, long_module(to_string(Map.get(component, "module"))))

    case {attrs, fields} do
      {nil, _} -> []
      {attrs, nil} when is_map(attrs) -> []
      {attrs, fields} when is_map(attrs) -> unknown_attr_problems(attrs, fields, index, id)
      {other, _} -> [problem(index, id, :attrs, :not_an_object, other)]
    end
  end

  defp unknown_attr_problems(attrs, fields, index, id) do
    editable = fields |> Keyword.keys() |> Enum.map(&to_string/1) |> MapSet.new()

    attrs
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(editable, &1))
    |> Enum.sort()
    |> Enum.map(&problem(index, id, :attrs, :unknown_attr, &1))
  end

  defp duplicate_problems(components) do
    components
    |> Enum.filter(&is_map/1)
    |> Enum.map(&Map.get(&1, "component_id"))
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.frequencies()
    |> Enum.filter(fn {_id, count} -> count > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {id, _count} ->
      problem(nil, id, :component_id, :duplicate_component_id, id)
    end)
  end

  defp to_row(component) do
    %{
      component_id: Map.fetch!(component, "component_id"),
      module: long_module(Map.fetch!(component, "module")),
      attrs: Map.get(component, "attrs") || %{},
      position: Map.get(component, "position"),
      group_id: Map.get(component, "group_id")
    }
  end

  defp problem(index, component_id, field, error, value) do
    %{index: index, component_id: component_id, field: field, error: error, value: value}
  end

  @spec format_problems([problem()]) :: String.t()
  def format_problems(problems) do
    Enum.map_join(problems, "\n", &format_problem/1)
  end

  defp format_problem(%{index: index, component_id: id, field: field, error: error, value: value}) do
    "#{location(index, id)} #{field}: #{error} (#{inspect(value)})"
  end

  defp location(nil, nil), do: "file:"
  defp location(nil, id), do: "#{id}:"
  defp location(index, nil), do: "component ##{index}:"
  defp location(index, id), do: "component ##{index} (#{id}):"
end
