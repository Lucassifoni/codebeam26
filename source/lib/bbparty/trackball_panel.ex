defmodule Bbparty.TrackballPanel do
  alias Bbparty.Keyboard

  @buttons 2

  @pitch 120

  @spec buttons() :: pos_integer()
  def buttons, do: @buttons

  @spec pitch() :: pos_integer()
  def pitch, do: @pitch

  @spec valid_button?(term()) :: boolean()
  def valid_button?(index) when is_integer(index), do: index >= 0 and index < @buttons
  def valid_button?(_index), do: false

  @spec button_id(non_neg_integer()) :: String.t()
  def button_id(index), do: "m4_button_#{index}"

  @spec trackball_id() :: String.t()
  def trackball_id, do: "m4_trackball"

  @spec button_default_position(non_neg_integer()) :: %{String.t() => integer()}
  def button_default_position(index), do: %{"x" => index * @pitch, "y" => below_keyboard()}

  @spec trackball_default_position() :: %{String.t() => integer()}
  def trackball_default_position, do: %{"x" => @buttons * @pitch, "y" => below_keyboard()}

  defp below_keyboard, do: (Keyboard.drives() + 1) * Keyboard.pitch()

  @spec transitions(0..255, 0..255) :: [{non_neg_integer(), boolean()}]
  def transitions(previous, current) when is_integer(previous) and is_integer(current) do
    changed = Bitwise.bxor(previous, current)

    for index <- 0..(@buttons - 1), Bitwise.band(changed, Bitwise.bsl(1, index)) != 0 do
      {index, Bitwise.band(current, Bitwise.bsl(1, index)) != 0}
    end
  end
end
