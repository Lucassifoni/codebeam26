defmodule Bbparty.Print.Label do
  @default_mm {100, 50}
  @default_dpi 300

  @mm_per_inch 25.4

  @spec mm() :: {number(), number()}
  def mm, do: config(:mm, @default_mm)

  @spec dpi() :: pos_integer()
  def dpi, do: config(:dpi, @default_dpi)

  @spec aspect_ratio() :: String.t()
  def aspect_ratio do
    {w, h} = mm()
    "#{w} / #{h}"
  end

  @spec dots() :: {pos_integer(), pos_integer()}
  def dots do
    {w, h} = mm()
    {to_dots(w, dpi()), to_dots(h, dpi())}
  end

  @spec to_dots(number(), pos_integer()) :: pos_integer()
  def to_dots(mm, dpi), do: round(mm / @mm_per_inch * dpi)

  @points_per_inch 72

  @spec points_across() :: float()
  def points_across do
    {w, _} = mm()
    w / @mm_per_inch * @points_per_inch
  end

  @spec points_to_cqw(number(), number()) :: float()
  def points_to_cqw(points, padding_fraction) when padding_fraction < 0.5 do
    points / points_across() * 100 / (1 - 2 * padding_fraction)
  end

  @spec content_aspect(number()) :: float()
  def content_aspect(padding_fraction) when padding_fraction < 0.5 do
    {w, h} = mm()
    (h / w - 2 * padding_fraction) / (1 - 2 * padding_fraction)
  end

  @spec capture_scale(number(), number()) :: float()
  def capture_scale(css_width, device_pixel_ratio \\ 1)

  def capture_scale(css_width, device_pixel_ratio)
      when css_width > 0 and device_pixel_ratio > 0 do
    {dots_wide, _} = dots()
    dots_wide / css_width / device_pixel_ratio
  end

  defp config(key, default) do
    :bbparty
    |> Application.get_env(:label)
    |> Kernel.||([])
    |> Keyword.get(key, default)
  end
end
