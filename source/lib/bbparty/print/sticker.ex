defmodule Bbparty.Print.Sticker do
  require Logger

  alias Bbparty.Print.{Cdp, Cooldown, Label, Preview, Transport, Zpl}
  alias Bbparty.Printouts

  @spec print(Bbparty.RenderState.t() | nil) :: :ok | {:error, term()}
  def print(render_state \\ nil) do
    case Cooldown.claim() do
      :ok -> do_print(render_state)
      {:error, {:cooling_down, left}} -> refuse(left)
    end
  end

  defp refuse(left) do
    Logger.info("PRINT ignored, #{div(left, 1000) + 1}s of cooldown left")
    {:error, {:cooling_down, left}}
  end

  defp do_print(render_state) do
    with {:ok, png} <- capture(),
         {:ok, pixels, width, height, channels} <- decode(png) do
      result = deliver(pixels, width, height, channels)
      Preview.put(png, width: width, height: height, printed?: result == :ok)
      archive(result, render_state)
      report(result, width, height)
    else
      {:error, {:capture_failed, :not_fitted}} = error ->
        Logger.error(
          "sticker not printed: the current text has not been sized — is /render open?"
        )

        error

      {:error, reason} = error ->
        Logger.error("sticker not captured: #{inspect(reason)}")
        error
    end
  end

  defp archive(_, %Bbparty.RenderState{} = render_state) do
    case Printouts.record(render_state) do
      {:ok, _printout} -> :ok
      {:error, reason} -> Logger.error("printout not recorded: #{inspect(reason)}")
    end
  rescue
    error -> Logger.error("printout not recorded: #{Exception.message(error)}")
  end

  defp archive(_result, _render_state), do: :ok

  defp report(:ok, width, height) do
    Logger.info("printed a #{width}x#{height} sticker")
    :ok
  end

  defp report({:error, reason} = error, _width, _height) do
    Logger.error("sticker captured but not printed: #{inspect(reason)}")
    error
  end

  @spec capture_preview() :: :ok | {:error, term()}
  def capture_preview do
    with {:ok, png} <- capture(),
         {:ok, _pixels, width, height, _channels} <- decode(png) do
      Preview.put(png, width: width, height: height, printed?: false)
      Logger.info("previewed a #{width}x#{height} sticker (not printed)")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("sticker not previewed: #{inspect(reason)}")
        error
    end
  end

  defp capture do
    case Cdp.capture() do
      {:ok, png} -> {:ok, png}
      {:error, reason} -> {:error, {:capture_failed, reason}}
    end
  end

  defp decode(png) do
    with {:ok, image} <- Image.from_binary(png),
         {:ok, pixels} <- Vix.Vips.Image.write_to_binary(image) do
      {width, height, channels} = Image.shape(image)
      {:ok, pixels, width, height, channels}
    else
      {:error, reason} -> {:error, {:decode_failed, reason}}
      other -> {:error, {:decode_failed, other}}
    end
  end

  defp deliver(pixels, width, height, channels) do
    warn_on_size_mismatch(width, height)
    zpl = Zpl.from_pixels(pixels, width, height, channels: channels, cutoff: cutoff())

    case Transport.send(zpl) do
      :ok -> :ok
      {:error, reason} -> {:error, {:transport_failed, reason}}
    end
  end

  @size_tolerance 2

  defp warn_on_size_mismatch(width, height) do
    {expected_width, expected_height} = Label.dots()

    off_by = max(abs(width - expected_width), abs(height - expected_height))

    if off_by > @size_tolerance do
      Logger.warning(
        "captured #{width}x#{height} but the label is #{expected_width}x#{expected_height} dots — " <>
          "#render-root is not holding the stock's #{Label.aspect_ratio()} aspect ratio"
      )
    end

    :ok
  end

  @spec cutoff() :: 0..255
  def cutoff do
    :bbparty
    |> Application.get_env(:label)
    |> Kernel.||([])
    |> Keyword.get(:cutoff, 128)
  end

  @spec print_test_pattern(pos_integer() | nil, pos_integer() | nil) :: :ok | {:error, term()}
  def print_test_pattern(width \\ nil, height \\ nil) do
    case Transport.send(Bbparty.Print.TestPattern.label(width, height)) do
      :ok ->
        Logger.info("sent the test pattern")
        :ok

      {:error, reason} = error ->
        Logger.error("test pattern not printed: #{inspect(reason)}")
        error
    end
  end

  @spec capture_to_file(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def capture_to_file(path) do
    with {:ok, png} <- capture(),
         :ok <- File.write(path, png) do
      {:ok, path}
    end
  end
end
