defmodule Mix.Tasks.Bbparty.Display do
  @shortdoc "Open the installation's two browser windows, with the flags the capture needs"

  use Mix.Task

  alias Bbparty.Print.Chrome

  @default_url "http://localhost:4000"
  @default_port 9222

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} =
      OptionParser.parse!(argv,
        strict: [url: :string, port: :integer, browser: :string, print_only: :boolean]
      )

    url = Keyword.get(opts, :url, @default_url)
    port = Keyword.get(opts, :port, @default_port)

    case browser(opts) do
      {:ok, path} -> launch(path, url, port, opts)
      :error -> Mix.raise(not_found())
    end
  end

  defp launch(path, url, port, opts) do
    profile = Path.join(System.tmp_dir!(), "bbparty-display-profile")
    File.mkdir_p!(profile)

    unless opts[:print_only] do
      open(path, profile, port, "#{url}/render")
    end

    open(path, profile, port, "#{url}/print_render")

    Mix.shell().info("""
    #{Path.basename(path)} launched with the debugging port on #{port}.

      profile: #{profile}
      capture: Bbparty.Print.Sticker.capture_to_file("/tmp/label.png")
      targets: curl -s http://localhost:#{port}/json/list | grep '"url"'

    The second window is /print_render — leave it open. It is what a sticker is
    captured from; the room's window is /render.
    """)
  end

  defp open(path, profile, port, url) do
    args = [
      "--remote-debugging-port=#{port}",
      "--user-data-dir=#{profile}",
      "--disable-backgrounding-occluded-windows",
      "--disable-renderer-backgrounding",
      "--disable-background-timer-throttling",
      "--no-first-run",
      "--no-default-browser-check",
      "--app=#{url}"
    ]

    spawn(fn -> System.cmd(path, args, stderr_to_stdout: true) end)
    Process.sleep(400)
  end

  defp browser(opts) do
    case Chrome.find(Keyword.get(opts, :browser)) do
      {:ok, path} -> {:ok, path}
      :error -> missing(Keyword.get(opts, :browser))
    end
  end

  defp missing(nil), do: :error
  defp missing(given), do: Mix.raise("no browser at #{given}")

  defp not_found do
    """
    No Chromium-based browser found. Looked for:

    #{Enum.map_join(Chrome.candidates(), "\n", &"  #{&1}")}

    Point at one with --browser. It cannot be Firefox: the capture speaks the
    Chrome DevTools Protocol, and Firefox dropped CDP for WebDriver BiDi.
    """
  end
end
