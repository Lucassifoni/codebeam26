defmodule Bbparty.RenderState.Projections do
  alias Bbparty.FontMap
  alias Bbparty.RenderState
  alias Bbparty.RenderState.Sizings
  alias Bbparty.RenderState.TextSource

  @type command :: {term(), {atom(), term()}}

  @gauges %{
    zoom: :font_size_gauge,
    kerning: :kerning_gauge,
    leading: :line_height_gauge
  }

  @spec propagate(RenderState.t(), RenderState.t()) :: [command()]
  def propagate(old, new),
    do: project(new, fn field -> Map.get(old, field) != Map.get(new, field) end)

  @spec sync(RenderState.t()) :: [command()]
  def sync(state), do: project(state, fn _field -> true end)

  @spec projections() :: %{atom() => (term() -> [command()])}
  def projections do
    bounds = Sizings.bounds()

    %{
      zoom: gauge(@gauges.zoom, bounds.zoom),
      kerning: gauge(@gauges.kerning, bounds.kerning),
      leading: gauge(@gauges.leading, bounds.leading),
      text_quantity: &quantity_commands/1,
      alignment: &alignment_lamps/1,
      transform_toupper: &uppercase_lamp/1,
      text_source: &source_lamps/1,
      cumulative_features: &feature_active_commands/1,
      selected_font: &font_commands/1
    }
  end

  @spec referenced_ids() :: [String.t()]
  def referenced_ids, do: @gauges |> Map.values() |> Enum.map(&to_string/1)

  @spec percentile(number(), {number(), number()}) :: float()
  def percentile(value, {min, max}), do: (value - min) / (max - min) * 100

  defp project(state, include?) do
    for {field, projector} <- projections(), include?.(field) do
      projector.(Map.get(state, field))
    end
    |> List.flatten()
  end

  defp gauge(id, bounds) do
    fn value -> [{id, {:set_progress, percentile(value, bounds)}}] end
  end

  defp quantity_commands(quantity), do: [{{:field, :text_quantity}, {:set_quantity, quantity}}]

  defp alignment_lamps(alignment) do
    [
      {{:action, :align_left}, {:set_lit, alignment == :left}},
      {{:action, :align_center}, {:set_lit, alignment == :center}}
    ]
  end

  defp uppercase_lamp(on?), do: [{{:action, :uppercase}, {:set_lit, on? == true}}]

  defp source_lamps(source) do
    for {action, value} <- TextSource.sources(),
        do: {{:action, action}, {:set_lit, source == value}}
  end

  defp font_commands(font),
    do: [{{:field, :selected_font}, {:set_font, font}} | feature_availability_commands(font)]

  defp feature_availability_commands(font) do
    available = FontMap.features_for_font(font)

    for feature <- FontMap.all_features() do
      {{:feature, feature}, {:set_available, feature in available}}
    end
  end

  defp feature_active_commands(active) do
    for feature <- FontMap.all_features() do
      {{:feature, feature}, {:set_active, feature in active}}
    end
  end
end
