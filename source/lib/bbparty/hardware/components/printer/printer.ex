defmodule Hardware.Components.Printer do
  @behaviour Hardware.Component
  defstruct [:status, :data]

  @impl true
  def new(_) do
    %__MODULE__{
      status: :idle,
      data: nil
    }
  end

  @impl true
  def handle_event(state, _event, _), do: {:ok, state}

  @impl true
  def events(), do: []

  @impl true
  def dimensions(), do: {70, 45}

  @impl true
  def effects(), do: [:print]

  @spec print_impls() :: [(Bbparty.RenderState.t() -> any())]
  def print_impls, do: Application.get_env(:bbparty, :print_impls, [])

  @impl true
  def handle_effect(_id, :print, _payload, _old_render, render) do
    Enum.each(print_impls(), fn impl ->
      try do
        impl.(render)
      rescue
        error ->
          require Logger
          Logger.error("print implementation failed: #{Exception.message(error)}")
      end
    end)

    :ok
  end
end
