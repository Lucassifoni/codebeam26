defmodule Hardware.Component do
  @callback new(opts :: keyword()) :: struct()
  @callback events() :: list(atom())
  @callback effects() :: list(atom())
  @callback handle_event(state :: struct(), event :: term(), payload :: term()) ::
              {:ok, struct()} | {:ok, struct(), [{atom(), term()}]} | {:error, term()}
  @callback handle_effect(
              id :: term(),
              effect :: term(),
              payload :: term(),
              old_state :: term(),
              new_state :: term()
            ) :: :ok
  @callback editable_fields() :: keyword(atom())
  @callback dimensions() :: {number(), number()}
  @callback input_binding(state :: struct()) :: term() | nil
  @optional_callbacks handle_effect: 5,
                      effects: 0,
                      editable_fields: 0,
                      dimensions: 0,
                      input_binding: 1

  @ppi 96
  @mm_per_inch 25.4
  @default_dimensions {10, 10}

  def dimensions(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :dimensions, 0) do
      module.dimensions()
    else
      @default_dimensions
    end
  end

  def mm_to_px(mm), do: mm * @ppi / @mm_per_inch
end
