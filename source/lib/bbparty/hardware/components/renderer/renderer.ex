defmodule Hardware.Components.Renderer do
  @moduledoc """
  The display screen as a panel component. It has no inputs or effects; its
  Display embeds the `/render` page in mirror mode, so it shows what the
  screen shows without measuring or pushing layout back to the server.
  """
  @behaviour Hardware.Component

  defstruct []

  @impl true
  def new(_opts), do: %__MODULE__{}

  @impl true
  def events(), do: []

  @impl true
  def dimensions(), do: {160, 90}

  @impl true
  def handle_event(state, _event, _payload), do: {:ok, state}
end
