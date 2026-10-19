defmodule Bbparty.Print.Chrome do
  @moduledoc """
  Finding a Chromium-based browser, and running one headless for captures that
  have no window to be taken from.
  """

  @candidates [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "google-chrome",
    "google-chrome-stable",
    "chromium",
    "chromium-browser",
    "brave-browser",
    "microsoft-edge"
  ]

  @blank "about:blank"
  @ready_attempts 50
  @ready_delay_ms 100

  @spec candidates() :: [String.t()]
  def candidates, do: @candidates

  @doc """
  The path of the browser to use: `given` when it names one, else the first
  candidate installed.
  """
  @spec find(String.t() | nil) :: {:ok, Path.t()} | :error
  def find(given \\ nil)
  def find(nil), do: Enum.find_value(@candidates, :error, &resolve/1)
  def find(given), do: resolve(given) || :error

  defp resolve("/" <> _ = path) do
    case File.exists?(path) do
      true -> {:ok, path}
      false -> nil
    end
  end

  defp resolve(name) do
    case System.find_executable(name) do
      nil -> nil
      path -> {:ok, path}
    end
  end

  @doc """
  The path a blank tab is listed under, for `Bbparty.Print.Cdp.open/1`.
  """
  @spec blank_path() :: String.t()
  def blank_path, do: URI.parse(@blank).path

  @doc """
  The flags of a headless browser showing one blank tab, `width` CSS pixels wide
  at a device pixel ratio of 1, with its debugging port on `port`.
  """
  @spec headless_args(pos_integer(), Path.t(), pos_integer()) :: [String.t()]
  def headless_args(port, profile, width) do
    [
      "--headless=new",
      "--remote-debugging-port=#{port}",
      "--user-data-dir=#{profile}",
      "--window-size=#{width},#{width}",
      "--force-device-scale-factor=1",
      "--hide-scrollbars",
      "--disable-backgrounding-occluded-windows",
      "--disable-renderer-backgrounding",
      "--disable-background-timer-throttling",
      "--no-first-run",
      "--no-default-browser-check",
      @blank
    ]
  end

  @doc """
  Starts a headless browser and waits for its debugging port to answer. Stop it
  with `stop/1`.
  """
  @spec start_headless(Path.t(), pos_integer(), Path.t(), pos_integer()) ::
          {:ok, port()} | {:error, term()}
  def start_headless(path, port, profile, width) do
    File.mkdir_p!(profile)

    browser =
      Port.open({:spawn_executable, path}, [
        :binary,
        :stderr_to_stdout,
        args: headless_args(port, profile, width)
      ])

    case await(port) do
      :ok ->
        {:ok, browser}

      {:error, reason} ->
        stop(browser)
        {:error, reason}
    end
  end

  defp await(port) do
    request =
      Req.get("http://localhost:#{port}/json/version",
        retry: :transient,
        retry_delay: @ready_delay_ms,
        max_retries: @ready_attempts,
        retry_log_level: false
      )

    case request do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, {:browser_listing_failed, status}}
      {:error, reason} -> {:error, {:browser_unreachable, reason}}
    end
  end

  @spec stop(port()) :: :ok
  def stop(browser) do
    case Port.info(browser, :os_pid) do
      {:os_pid, os_pid} -> System.cmd("kill", [Integer.to_string(os_pid)], stderr_to_stdout: true)
      nil -> :ok
    end

    :ok
  end
end
