defmodule Bbparty.RenderState.Fit do
  defstruct fingerprint: nil, size: nil

  @type t :: %__MODULE__{fingerprint: String.t() | nil, size: number() | nil}

  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @spec from_params(term()) :: {:ok, t()} | :error
  def from_params(%{"fingerprint" => fingerprint, "size" => size})
      when is_binary(fingerprint) and is_number(size) and size > 0,
      do: {:ok, %__MODULE__{fingerprint: fingerprint, size: size}}

  def from_params(_params), do: :error

  @spec accept(t(), t(), String.t()) :: {:ok, t()} | :ignore
  def accept(held, %__MODULE__{fingerprint: current} = pushed, current)
      when pushed != held,
      do: {:ok, pushed}

  def accept(_held, _pushed, _current), do: :ignore

  @spec size_cqw(t(), number()) :: number()
  def size_cqw(%__MODULE__{size: nil}, floor), do: floor
  def size_cqw(%__MODULE__{size: size}, _floor), do: size
end
