defmodule Bbparty.Keyboard.RowWalk do
  alias Bbparty.Keyboard
  alias Bbparty.Keyboard.Action

  defstruct row: 0, col: 0, group: nil, pitch: 120, origin: {0, 0}, keys: []

  @type key :: atom() | String.t()
  @type position :: %{String.t() => number()}
  @type cell :: %{
          key: key(),
          row: non_neg_integer(),
          col: non_neg_integer(),
          position: position()
        }
  @type t :: %__MODULE__{
          row: non_neg_integer(),
          col: non_neg_integer(),
          group: String.t() | nil,
          pitch: pos_integer(),
          origin: {number(), number()},
          keys: [key()]
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    row = Keyword.get(opts, :row, 0)

    %__MODULE__{
      row: row,
      col: Keyword.get(opts, :col, 0),
      group: Keyword.get(opts, :group, group_id(row)),
      pitch: Keyword.get(opts, :pitch, Keyboard.pitch()),
      origin: Keyword.get(opts, :origin, {0, 0})
    }
  end

  @spec group_id(non_neg_integer()) :: String.t()
  def group_id(row), do: "row_#{row}"

  @spec press(t(), key()) ::
          {:ok, t(), cell()} | {:error, {:already_in_row, key(), non_neg_integer()}}
  def press(%__MODULE__{keys: keys} = walk, key) do
    case Enum.find_index(keys, &(&1 == key)) do
      nil -> {:ok, %{walk | keys: keys ++ [key]}, cell(walk, key, length(keys))}
      index -> {:error, {:already_in_row, key, walk.col + index}}
    end
  end

  @spec keys(t()) :: [key()]
  def keys(%__MODULE__{keys: keys}), do: keys

  @spec cells(t()) :: [cell()]
  def cells(%__MODULE__{keys: keys} = walk),
    do: keys |> Enum.with_index() |> Enum.map(fn {key, index} -> cell(walk, key, index) end)

  @spec plan(t()) :: [{key(), position()}]
  def plan(%__MODULE__{} = walk), do: Enum.map(cells(walk), &{&1.key, &1.position})

  @spec report(t()) :: %{
          row: non_neg_integer(),
          group: String.t() | nil,
          cells: [cell()],
          plan: [{key(), position()}]
        }
  def report(%__MODULE__{} = walk),
    do: %{row: walk.row, group: walk.group, cells: cells(walk), plan: plan(walk)}

  defp cell(%__MODULE__{} = walk, key, index) do
    {x, y} = walk.origin
    col = walk.col + index

    %{
      key: key,
      row: walk.row,
      col: col,
      position: %{"x" => x + col * walk.pitch, "y" => y + walk.row * walk.pitch}
    }
  end

  @spec meanings([key()], keyword()) :: %{
          assignments: [{key(), map()}],
          untouched: [key()],
          overflow: non_neg_integer(),
          errors: [{key(), term()}]
        }
  def meanings(keys, spec) do
    chars = entries(spec, :chars)
    shifts = entries(spec, :shift)
    actions = entries(spec, :actions)
    width = Enum.max([length(chars), length(shifts), length(actions)])

    results =
      keys
      |> Enum.with_index()
      |> Enum.map(fn {key, index} -> {key, attrs_at(chars, shifts, actions, index)} end)

    %{
      assignments: for({key, {:ok, attrs}} <- results, attrs != %{}, do: {key, attrs}),
      untouched: for({key, {:ok, attrs}} <- results, attrs == %{}, do: key),
      errors: for({key, {:error, reason}} <- results, do: {key, reason}),
      overflow: max(width - length(keys), 0)
    }
  end

  defp entries(spec, key) do
    case Keyword.get(spec, key) do
      nil -> []
      value when is_binary(value) -> String.graphemes(value)
      value when is_list(value) -> value
    end
  end

  defp attrs_at(chars, shifts, actions, index) do
    case action_at(Enum.at(actions, index)) do
      {:ok, action} ->
        {:ok,
         %{}
         |> put_attr(:char, Enum.at(chars, index))
         |> put_attr(:shift, Enum.at(shifts, index))
         |> put_attr(:action, action)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp action_at(nil), do: {:ok, nil}
  defp action_at(""), do: {:ok, nil}

  defp action_at(value) do
    case Action.parse(value) do
      {:ok, action} -> {:ok, Atom.to_string(action)}
      :error -> {:error, {:unknown_action, value}}
    end
  end

  defp put_attr(attrs, _key, nil), do: attrs
  defp put_attr(attrs, _key, ""), do: attrs
  defp put_attr(attrs, key, value), do: Map.put(attrs, key, value)

  @spec rows([map()], keyword()) :: [%{group: String.t(), cells: [map()]}]
  def rows(components, opts \\ []) do
    components
    |> key_cells(opts)
    |> Enum.group_by(&label/1)
    |> Enum.sort_by(fn {_label, cells} -> cells |> Enum.map(&{&1.row, &1.x}) |> Enum.min() end)
    |> Enum.map(fn {label, cells} -> %{group: label, cells: renumber(cells)} end)
  end

  @spec row_of([map()], keyword()) :: [key()]
  def row_of(components, opts \\ []) do
    wanted = Keyword.get_lazy(opts, :group, fn -> group_id(Keyword.get(opts, :row, 0)) end)

    components
    |> rows(opts)
    |> Enum.find(%{cells: []}, &(&1.group == wanted))
    |> Map.fetch!(:cells)
    |> Enum.map(& &1.key)
  end

  defp label(%{group: group}) when is_binary(group) and group != "", do: group
  defp label(%{row: row}), do: group_id(row)

  defp key_cells(components, opts) do
    pitch = Keyword.get(opts, :pitch, Keyboard.pitch())
    {origin_x, origin_y} = Keyword.get(opts, :origin, {0, 0})

    components
    |> Enum.filter(&(Keyboard.address(&1.component_id) != :error))
    |> Enum.map(fn component ->
      position = component.position || %{}

      %{
        key: component.component_id,
        group: Map.get(component, :group_id),
        row: round((Map.get(position, "y", 0) - origin_y) / pitch),
        x: Map.get(position, "x", 0) - origin_x,
        char: component.attrs[:char],
        shift: component.attrs[:shift],
        action: component.attrs[:action]
      }
    end)
  end

  defp renumber(cells) do
    cells
    |> Enum.sort_by(& &1.x)
    |> Enum.with_index()
    |> Enum.map(fn {cell, col} -> Map.put(cell, :col, col) end)
  end
end
