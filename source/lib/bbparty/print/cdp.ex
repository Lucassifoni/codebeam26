defmodule Bbparty.Print.Cdp do
  alias Bbparty.Print.Cdp.Protocol

  @default_host "localhost"
  @default_port 9222
  @default_path "/print_render"
  @default_selector "#render-root"
  @timeout 10_000

  @type session :: map()

  @spec capture(keyword()) :: {:ok, binary()} | {:error, term()}
  def capture(opts \\ []) do
    selector = Keyword.get(opts, :selector, @default_selector)

    with {:ok, session} <- open(opts) do
      try do
        with {:ok, png, _session} <- capture_element(session, selector, opts) do
          {:ok, png}
        end
      after
        close(session)
      end
    end
  end

  @doc """
  Attach to the browser tab showing `:path`. The session is bound to the calling
  process, which receives the socket's messages, and must be passed on from one
  call to the next.
  """
  @spec open(keyword()) :: {:ok, session()} | {:error, term()}
  def open(opts \\ []) do
    host = Keyword.get(opts, :host, @default_host)
    port = Keyword.get(opts, :port, @default_port)
    path = Keyword.get(opts, :path, @default_path)

    with {:ok, ws_url} <- find_page(host, port, path) do
      connect(ws_url)
    end
  end

  @doc """
  Point the tab at `url`. Returns once the browser has committed to the new
  document, not once it has rendered: `capture_element/3` does the waiting.
  """
  @spec navigate(session(), String.t()) :: {:ok, session()} | {:error, term()}
  def navigate(session, url) do
    with {:ok, session, result} <- call(session, &Protocol.navigate_command(&1, url)),
         :ok <- Protocol.navigated(result) do
      {:ok, session}
    end
  end

  @doc """
  A PNG of the sticker at `selector`, at the label's resolution unless `:scale`
  says otherwise. `:fit` is `:server` for a sticker sized by the server and
  `:local` for one sized in the browser, and decides what is waited for.
  """
  @spec capture_element(session(), String.t(), keyword()) ::
          {:ok, binary(), session()} | {:error, term()}
  def capture_element(session, selector, opts \\ []) do
    fit = Keyword.get(opts, :fit, :server)
    scale = Keyword.get(opts, :scale)

    with {:ok, session, rect} <- fetch_rect(session, selector, fit),
         {:ok, session, png} <- fetch_png(session, rect, clip_scale(scale, rect)) do
      {:ok, png, session}
    end
  end

  @spec close(session()) :: :ok
  def close(session) do
    Mint.HTTP.close(session.conn)
    :ok
  rescue
    _ -> :ok
  end

  defp find_page(host, port, path) do
    case Req.get(Protocol.list_url(host, port), receive_timeout: @timeout) do
      {:ok, %{status: 200, body: targets}} when is_list(targets) ->
        Protocol.select_target(targets, path)

      {:ok, %{status: status}} ->
        {:error, {:browser_listing_failed, status}}

      {:error, reason} ->
        {:error, {:browser_unreachable, reason}}
    end
  end

  defp fetch_rect(session, selector, fit) do
    with {:ok, session, result} <- call(session, &Protocol.rect_command(&1, selector, fit)),
         {:ok, rect} <- Protocol.rect(result) do
      {:ok, session, rect}
    end
  end

  defp clip_scale(nil, rect), do: Bbparty.Print.Label.capture_scale(rect.width, rect.dpr)
  defp clip_scale(scale, rect), do: scale / rect.dpr

  defp fetch_png(session, rect, scale) do
    with {:ok, session, result} <- call(session, &Protocol.screenshot_command(&1, rect, scale)),
         {:ok, png} <- Protocol.png(result) do
      {:ok, session, png}
    end
  end

  defp connect(ws_url) do
    uri = URI.parse(ws_url)

    with {:ok, conn} <- Mint.HTTP.connect(:http, uri.host, uri.port),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(:ws, conn, uri.path, []),
         {:ok, conn, status, headers} <- await_upgrade(conn, ref),
         {:ok, conn, websocket} <- Mint.WebSocket.new(conn, ref, status, headers) do
      {:ok, %{conn: conn, websocket: websocket, ref: ref, buffer: []}}
    else
      {:error, reason} -> {:error, {:websocket_connect_failed, reason}}
      {:error, _conn, reason} -> {:error, {:websocket_connect_failed, reason}}
    end
  end

  defp await_upgrade(conn, ref, status \\ nil, headers \\ nil) do
    receive do
      message ->
        case Mint.WebSocket.stream(conn, message) do
          {:ok, conn, responses} ->
            case upgrade_parts(responses, ref, status, headers) do
              {:done, status, headers} -> {:ok, conn, status, headers}
              {:more, status, headers} -> await_upgrade(conn, ref, status, headers)
            end

          {:error, _conn, reason, _responses} ->
            {:error, reason}

          :unknown ->
            await_upgrade(conn, ref, status, headers)
        end
    after
      @timeout -> {:error, :upgrade_timeout}
    end
  end

  defp upgrade_parts(responses, ref, status, headers) do
    Enum.reduce(responses, {:more, status, headers}, fn
      {:status, ^ref, code}, {_, _, h} -> {:more, code, h}
      {:headers, ^ref, hs}, {_, s, _} -> {:more, s, hs}
      {:done, ^ref}, {_, s, h} -> {:done, s, h}
      _other, acc -> acc
    end)
  end

  defp call(session, build) do
    id = System.unique_integer([:positive, :monotonic])
    payload = build.(id) |> Jason.encode!()

    with {:ok, session} <- send_text(session, payload) do
      await_result(session, id)
    end
  end

  defp send_text(session, payload) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(session.websocket, {:text, payload}),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(session.conn, session.ref, data) do
      {:ok, %{session | websocket: websocket, conn: conn}}
    else
      {:error, _websocket_or_conn, reason} -> {:error, {:websocket_send_failed, reason}}
    end
  end

  defp await_result(session, id) do
    case take_buffered(session, id) do
      {:ok, session, result} ->
        {:ok, session, result}

      {:error, reason} ->
        {:error, reason}

      {:empty, session} ->
        with {:ok, session} <- receive_frames(session) do
          await_result(session, id)
        end
    end
  end

  defp take_buffered(session, id) do
    Enum.reduce_while(session.buffer, {:empty, session}, fn frame, _acc ->
      case Protocol.classify(frame) do
        {:result, ^id, result} -> {:halt, {:ok, drop(session, frame), result}}
        {:error, ^id, message} -> {:halt, {:error, {:cdp_error, message}}}
        _other -> {:cont, {:empty, drop(session, frame)}}
      end
    end)
  end

  defp drop(session, frame), do: %{session | buffer: List.delete(session.buffer, frame)}

  defp receive_frames(session) do
    receive do
      message ->
        case Mint.WebSocket.stream(session.conn, message) do
          {:ok, conn, responses} ->
            decode_data(%{session | conn: conn}, responses)

          {:error, _conn, reason, _responses} ->
            {:error, {:websocket_stream_failed, reason}}

          :unknown ->
            receive_frames(session)
        end
    after
      @timeout -> {:error, :capture_timeout}
    end
  end

  defp decode_data(session, responses) do
    Enum.reduce_while(responses, {:ok, session}, fn
      {:data, ref, data}, {:ok, session} when ref == session.ref ->
        case Mint.WebSocket.decode(session.websocket, data) do
          {:ok, websocket, frames} ->
            {:cont,
             {:ok, %{session | websocket: websocket, buffer: session.buffer ++ texts(frames)}}}

          {:error, _websocket, reason} ->
            {:halt, {:error, {:websocket_decode_failed, reason}}}
        end

      _other, acc ->
        {:cont, acc}
    end)
  end

  defp texts(frames) do
    for {:text, json} <- frames, {:ok, decoded} = Jason.decode(json), do: decoded
  end
end
