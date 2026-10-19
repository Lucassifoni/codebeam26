defmodule Hardware.Output do
  @callback handle_transition(old :: struct(), next :: struct(), opts :: keyword()) :: :ok
end
