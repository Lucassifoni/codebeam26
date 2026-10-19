defmodule Bbparty.Keyboard.Action do
  @actions ~w(
    up down left right backspace enter space shift capslock reset print dead
    align_left align_center uppercase
    source_user source_font_name source_alpha_upper source_alpha_lower source_numbers
  )a

  @selectors ~w(
    align_left align_center uppercase
    source_user source_font_name source_alpha_upper source_alpha_lower source_numbers
  )a

  @spec all() :: [atom()]
  def all, do: @actions

  @spec selectors() :: [atom()]
  def selectors, do: @selectors

  @spec parse(String.t() | atom() | nil) :: {:ok, atom()} | :error
  def parse(nil), do: :error
  def parse(action) when is_atom(action), do: parse(Atom.to_string(action))

  def parse(action) when is_binary(action) do
    normalised = action |> String.trim() |> String.downcase()

    case Enum.find(@actions, &(Atom.to_string(&1) == normalised)) do
      nil -> :error
      found -> {:ok, found}
    end
  end

  def parse(_action), do: :error

  @spec layout_dependent?(atom()) :: boolean()
  def layout_dependent?(action), do: action in [:up, :down]

  @spec editing?(atom()) :: boolean()
  def editing?(action), do: action not in [:reset, :print] and action not in @selectors

  @spec dead?(atom()) :: boolean()
  def dead?(action), do: action == :dead
end
