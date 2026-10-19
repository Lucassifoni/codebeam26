defmodule Bbparty.Print.Preview do
  use GenServer

  @table :bbparty_print_preview
  @topic "print:preview"
  @key :sticker

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  def topic, do: @topic
  def subscribe, do: Phoenix.PubSub.subscribe(Bbparty.PubSub, @topic)

  @spec put(binary(), keyword()) :: :ok
  def put(png, opts \\ []) when is_binary(png) do
    entry = %{
      png: png,
      width: Keyword.get(opts, :width),
      height: Keyword.get(opts, :height),
      printed?: Keyword.get(opts, :printed?, false),
      at: DateTime.utc_now()
    }

    :ets.insert(@table, {@key, entry})
    Phoenix.PubSub.broadcast(Bbparty.PubSub, @topic, {:sticker_preview, entry})
    :ok
  end

  @spec last() :: map() | nil
  def last do
    case :ets.lookup(@table, @key) do
      [{@key, entry}] -> entry
      [] -> nil
    end
  end

  @spec last_data_uri() :: String.t() | nil
  def last_data_uri do
    case last() do
      nil -> nil
      %{png: png} -> "data:image/png;base64," <> Base.encode64(png)
    end
  end

  @spec clear() :: :ok
  def clear do
    :ets.delete(@table, @key)
    Phoenix.PubSub.broadcast(Bbparty.PubSub, @topic, {:sticker_preview, nil})
    :ok
  end

  @spec print(Bbparty.RenderState.t() | nil) :: :ok | {:error, term()}
  def print(_render_state \\ nil) do
    Bbparty.Print.Sticker.capture_preview()
  end
end
