defmodule Bbparty.Layout.ComponentInstance do
  use Ecto.Schema
  import Ecto.Changeset

  schema "component_instances" do
    field :component_id, :binary
    field :module, :binary
    field :attrs, :map
    field :position, :map
    field :group_id, :binary

    timestamps(type: :utc_datetime)
  end

  def changeset(component_instance, attrs) do
    component_instance
    |> cast(attrs, [:component_id, :module, :attrs, :position, :group_id])
    |> validate_required([:component_id, :module])
    |> unique_constraint(:component_id, name: :unique_component_ids_index)
  end

  def hydrate(%__MODULE__{} = instance) do
    module = String.to_existing_atom(instance.module)

    %{
      instance
      | component_id: String.to_atom(instance.component_id),
        module: module,
        position: instance.position || %{"x" => 0, "y" => 0},
        attrs: hydrate_attrs(instance.attrs, module)
    }
  end

  def hydrate_attrs(attrs, module) do
    attrs = attrs || %{}

    fields =
      if Code.ensure_loaded?(module) and function_exported?(module, :editable_fields, 0),
        do: module.editable_fields(),
        else: []

    for {key, type} <- fields, into: %{} do
      {key, cast(attrs[to_string(key)], type)}
    end
  end

  def cast(nil, _type), do: nil
  def cast(value, :integer) when is_integer(value), do: value
  def cast(value, :integer) when is_float(value), do: trunc(value)

  def cast(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  def cast(value, :float) when is_number(value), do: value / 1

  def cast(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {f, _} -> f
      :error -> nil
    end
  end

  def cast(value, :boolean) when is_boolean(value), do: value

  def cast(value, :boolean) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      truthy when truthy in ~w(true 1 yes on) -> true
      falsy when falsy in ~w(false 0 no off) -> false
      _ -> nil
    end
  end

  def cast(value, :string), do: to_string(value)
  def cast(value, _type), do: value
end
