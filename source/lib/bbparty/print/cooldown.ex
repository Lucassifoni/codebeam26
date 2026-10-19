defmodule Bbparty.Print.Cooldown do
  use GenServer

  @table :bbparty_print_cooldown
  @default_ms 10_000

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @spec claim(atom()) :: :ok | {:error, {:cooling_down, non_neg_integer()}}
  def claim(key \\ :sticker) do
    now = now_ms()

    case remaining(last_at(key), now, interval_ms()) do
      0 ->
        :ets.insert(@table, {key, now})
        :ok

      left ->
        {:error, {:cooling_down, left}}
    end
  end

  @spec remaining(integer() | nil, integer(), non_neg_integer()) :: non_neg_integer()
  def remaining(nil, _now, _interval), do: 0

  def remaining(last, now, interval) do
    case interval - (now - last) do
      left when left > 0 -> left
      _elapsed -> 0
    end
  end

  @spec last_at(atom()) :: integer() | nil
  def last_at(key \\ :sticker) do
    case :ets.lookup(@table, key) do
      [{^key, at}] -> at
      [] -> nil
    end
  end

  @spec reset(atom()) :: :ok
  def reset(key \\ :sticker) do
    :ets.delete(@table, key)
    :ok
  end

  @spec interval_ms() :: non_neg_integer()
  def interval_ms do
    :bbparty
    |> Application.get_env(:label)
    |> Kernel.||([])
    |> Keyword.get(:cooldown_ms, @default_ms)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
