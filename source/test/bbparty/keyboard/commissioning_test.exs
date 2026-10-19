defmodule Bbparty.Keyboard.CommissioningTest do
  use ExUnit.Case, async: false

  alias Bbparty.Bus.Module3Dispatcher
  alias Bbparty.Keyboard.Commissioning

  defp emit(drive, sense, pressed) do
    Phoenix.PubSub.broadcast(
      Bbparty.PubSub,
      Module3Dispatcher.topic(),
      {:module3, {:key_event, drive, sense, pressed}}
    )
  end

  setup do
    on_exit(&Module3Dispatcher.unsubscribe/0)
    :ok
  end

  test "reports one copy of an event however many stray subscriptions exist" do
    Enum.each(1..3, fn _ -> Module3Dispatcher.subscribe() end)

    task =
      Task.async(fn ->
        Enum.each(1..3, fn _ -> Module3Dispatcher.subscribe() end)
        Commissioning.capture(1)
      end)

    Process.sleep(50)
    emit(12, 8, true)
    emit(12, 8, false)

    assert Task.await(task, 5_000) == [{12, 8, true}, {12, 8, false}]
  end

  test "does not report events that arrived before the capture began" do
    task =
      Task.async(fn ->
        Module3Dispatcher.subscribe()
        Process.sleep(100)
        Commissioning.capture(1)
      end)

    Process.sleep(20)
    emit(12, 8, true)

    assert Task.await(task, 5_000) == []
  end

  test "leaves no subscription behind" do
    task =
      Task.async(fn ->
        Commissioning.capture(1)
        Process.sleep(150)

        receive do
          {:module3, _} -> :leaked
        after
          0 -> :clean
        end
      end)

    Process.sleep(1_100)
    emit(12, 8, true)

    assert Task.await(task, 5_000) == :clean
  end
end
