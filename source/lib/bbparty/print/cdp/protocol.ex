defmodule Bbparty.Print.Cdp.Protocol do
  @fit_wait_ms 2_000
  @local_fit_wait_ms 8_000
  @settled_checks 3

  @spec list_url(String.t(), pos_integer()) :: String.t()
  def list_url(host, port), do: "http://#{host}:#{port}/json/list"

  @spec select_target([map()], String.t()) :: {:ok, String.t()} | {:error, :no_such_page}
  def select_target(targets, path) do
    targets
    |> Enum.filter(&(&1["type"] == "page" and page_path(&1["url"]) == path))
    |> Enum.find_value(:error, & &1["webSocketDebuggerUrl"])
    |> case do
      :error -> {:error, :no_such_page}
      nil -> {:error, :no_such_page}
      url -> {:ok, url}
    end
  end

  @spec navigate_command(pos_integer(), String.t()) :: map()
  def navigate_command(id, url) do
    %{id: id, method: "Page.navigate", params: %{url: url}}
  end

  @spec navigated(map()) :: :ok | {:error, {:navigation_failed, String.t()}}
  def navigated(%{"errorText" => reason}), do: {:error, {:navigation_failed, reason}}
  def navigated(_result), do: :ok

  @doc """
  Measures the sticker at `selector` once it is ready to be captured. `:server`
  waits for the fit the server accepted; `:local` for a sticker that sizes itself
  in the browser (`fit_locally`), which may not be on the page yet.
  """
  @spec rect_command(pos_integer(), String.t(), :server | :local) :: map()
  def rect_command(id, selector, fit \\ :server) do
    %{
      id: id,
      method: "Runtime.evaluate",
      params: %{
        expression: rect_expression(selector, fit),
        awaitPromise: true,
        returnByValue: true
      }
    }
  end

  def rect_expression(selector, fit \\ :server)

  def rect_expression(selector, :local) do
    """
    (async () => {
      const deadline = Date.now() + #{@local_fit_wait_ms};
      const pause = () => new Promise((resolve) => setTimeout(resolve, 20));
      const size = () => {
        const el = document.querySelector(#{inspect(selector)});
        const text = el && el.querySelector("[data-render-text]");
        const shown = text && text.style.visibility === "visible";
        return shown && document.fonts.status === "loaded" ? text.style.fontSize : null;
      };
      let seen = null;
      let settled = 0;
      while (settled < #{@settled_checks}) {
        if (Date.now() > deadline) {
          return document.querySelector(#{inspect(selector)}) ? {unfitted: true} : null;
        }
        await pause();
        const now = size();
        settled = now && now === seen ? settled + 1 : 0;
        seen = now;
      }
      const r = document.querySelector(#{inspect(selector)}).getBoundingClientRect();
      return {
        x: r.left + window.scrollX,
        y: r.top + window.scrollY,
        width: r.width,
        height: r.height,
        dpr: window.devicePixelRatio
      };
    })()
    """
  end

  def rect_expression(selector, :server) do
    """
    (async () => {
      await document.fonts.ready;
      const el = document.querySelector(#{inspect(selector)});
      if (!el) return null;
      const fitted = () => el.dataset.fittedFor && el.dataset.fittedFor === el.dataset.fingerprint;
      const deadline = Date.now() + #{@fit_wait_ms};
      while (!fitted()) {
        if (Date.now() > deadline) return {unfitted: true};
        await new Promise((resolve) => setTimeout(resolve, 20));
      }
      await document.fonts.ready;
      const r = el.getBoundingClientRect();
      return {
        x: r.left + window.scrollX,
        y: r.top + window.scrollY,
        width: r.width,
        height: r.height,
        dpr: window.devicePixelRatio
      };
    })()
    """
  end

  @spec screenshot_command(pos_integer(), map(), float()) :: map()
  def screenshot_command(id, rect, scale) do
    %{
      id: id,
      method: "Page.captureScreenshot",
      params: %{
        format: "png",
        captureBeyondViewport: true,
        clip: %{
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
          scale: scale
        }
      }
    }
  end

  @spec classify(map()) ::
          {:result, pos_integer(), map()} | {:error, pos_integer(), String.t()} | :event
  def classify(%{"id" => id, "error" => %{"message" => message}}), do: {:error, id, message}
  def classify(%{"id" => id, "result" => result}), do: {:result, id, result}
  def classify(%{"id" => id}), do: {:result, id, %{}}
  def classify(_frame), do: :event

  @spec rect(map()) :: {:ok, map()} | {:error, :no_element | :not_fitted | :unexpected_result}
  def rect(%{"result" => %{"value" => nil}}), do: {:error, :no_element}
  def rect(%{"result" => %{"value" => %{"unfitted" => true}}}), do: {:error, :not_fitted}

  def rect(%{
        "result" => %{"value" => %{"x" => x, "y" => y, "width" => w, "height" => h} = value}
      }) do
    {:ok, %{x: x, y: y, width: w, height: h, dpr: Map.get(value, "dpr", 1.0)}}
  end

  def rect(_result), do: {:error, :unexpected_result}

  @spec png(map()) :: {:ok, binary()} | {:error, :unexpected_result}
  def png(%{"data" => base64}) do
    case Base.decode64(base64) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :unexpected_result}
    end
  end

  def png(_result), do: {:error, :unexpected_result}

  defp page_path(nil), do: nil
  defp page_path(url), do: URI.parse(url).path
end
