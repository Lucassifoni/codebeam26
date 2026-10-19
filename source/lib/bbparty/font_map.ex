defmodule Bbparty.FontMap do
  @manifests [
    Path.expand("../../priv/fonts.json", __DIR__),
    Path.expand("../../priv/fonts.system.json", __DIR__)
  ]

  for manifest <- @manifests, do: @external_resource(manifest)

  @all_features ~w(
    liga dlig smcp smcp+c2sc case zero
    tnum onum ss19 ss20 titl swsh
    ss01 ss02 ss03 ss04 ss05 ss06
    ss07 ss08 ss09 ss10 ss11 ss12
    ss13 ss14 ss15 ss16 ss17 ss18
  )

  @feature_tags @all_features
                |> Enum.flat_map(&String.split(&1, "+", trim: true))
                |> Enum.uniq()

  @entries Enum.flat_map(@manifests, fn manifest ->
             manifest |> File.read!() |> Jason.decode!() |> Map.fetch!("fonts")
           end)

  for {id, count} <- Enum.frequencies_by(@entries, &Map.fetch!(&1, "id")), count > 1 do
    raise CompileError, description: "font id #{inspect(id)} is defined #{count} times"
  end

  @fonts Map.new(@entries, fn entry ->
           id = Map.fetch!(entry, "id")
           offered = Map.get(entry, "features", [])

           {id,
            %{
              family: Map.get(entry, "family") || id,
              features:
                Enum.filter(@all_features, fn switch ->
                  switch
                  |> String.split("+", trim: true)
                  |> Enum.all?(&(&1 in offered))
                end)
            }}
         end)

  @ids @fonts |> Map.keys() |> Enum.sort()

  @spec all_features() :: [String.t()]
  def all_features, do: @all_features

  @spec feature_tags() :: [String.t()]
  def feature_tags, do: @feature_tags

  @spec latching?(term()) :: boolean()
  def latching?(<<"ss", tens, units>>) when tens in ?0..?9 and units in ?0..?9, do: false
  def latching?(_switch), do: true

  @spec tags_for_switch(term()) :: [String.t()]
  def tags_for_switch(switch) when is_binary(switch),
    do: String.split(switch, "+", trim: true)

  def tags_for_switch(_switch), do: []

  @spec feature_settings([term()]) :: String.t()
  def feature_settings(active) do
    on = active |> Enum.flat_map(&tags_for_switch/1) |> MapSet.new()

    Enum.map_join(@feature_tags, ", ", &setting(&1, MapSet.member?(on, &1)))
  end

  defp setting(tag, true), do: ~s("#{tag}" 1)
  defp setting(tag, false), do: ~s("#{tag}" 0)

  @spec fonts() :: %{optional(String.t()) => %{family: String.t(), features: [String.t()]}}
  def fonts, do: @fonts

  @spec ids() :: [String.t()]
  def ids, do: @ids

  @spec known?(term()) :: boolean()
  def known?(id) when is_binary(id), do: Map.has_key?(@fonts, id)
  def known?(_id), do: false

  @spec features_for_font(term()) :: [String.t()]
  def features_for_font(id) do
    case Map.fetch(@fonts, id) do
      {:ok, font} -> font.features
      :error -> []
    end
  end

  @spec family_for_font(term()) :: String.t() | nil
  def family_for_font(id) do
    case Map.fetch(@fonts, id) do
      {:ok, font} -> font.family
      :error -> nil
    end
  end
end
