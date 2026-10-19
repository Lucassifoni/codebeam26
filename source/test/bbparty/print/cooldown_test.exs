defmodule Bbparty.Print.CooldownTest do
  use ExUnit.Case, async: false

  alias Bbparty.Print.Cooldown

  @key :cooldown_test

  setup do
    Cooldown.reset(@key)
    on_exit(fn -> Cooldown.reset(@key) end)
    :ok
  end

  defp configure(ms) do
    previous = Application.get_env(:bbparty, :label)
    Application.put_env(:bbparty, :label, Keyword.put(previous || [], :cooldown_ms, ms))

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:bbparty, :label)
        value -> Application.put_env(:bbparty, :label, value)
      end
    end)
  end

  describe "remaining/3" do
    test "nothing has fired yet" do
      assert Cooldown.remaining(nil, 1_000, 10_000) == 0
    end

    test "counts down" do
      assert Cooldown.remaining(0, 3_000, 10_000) == 7_000
    end

    test "exactly at the boundary is elapsed" do
      assert Cooldown.remaining(0, 10_000, 10_000) == 0
    end

    test "past the boundary stays elapsed rather than going negative" do
      assert Cooldown.remaining(0, 99_000, 10_000) == 0
    end

    test "a stamp from the future is simply not elapsed" do
      assert Cooldown.remaining(5_000, 0, 10_000) == 15_000
    end

    test "a zero interval never holds anything back" do
      assert Cooldown.remaining(0, 0, 0) == 0
    end
  end

  describe "claim/1" do
    test "the first claim succeeds" do
      configure(10_000)

      assert Cooldown.claim(@key) == :ok
    end

    test "a second claim inside the window is refused, with the time left" do
      configure(10_000)

      assert Cooldown.claim(@key) == :ok
      assert {:error, {:cooling_down, left}} = Cooldown.claim(@key)
      assert left > 0 and left <= 10_000
    end

    test "a claim after the window succeeds again" do
      configure(20)

      assert Cooldown.claim(@key) == :ok
      Process.sleep(30)
      assert Cooldown.claim(@key) == :ok
    end

    test "stamps the clock, so two callers cannot both be told yes" do
      configure(10_000)

      assert Cooldown.claim(@key) == :ok
      assert Cooldown.last_at(@key) != nil
      assert match?({:error, _}, Cooldown.claim(@key))
    end

    test "keys are independent" do
      configure(10_000)

      assert Cooldown.claim(@key) == :ok
      assert Cooldown.claim(:some_other_key) == :ok
      Cooldown.reset(:some_other_key)
    end

    test "reset lets the next claim through" do
      configure(10_000)

      assert Cooldown.claim(@key) == :ok
      Cooldown.reset(@key)
      assert Cooldown.claim(@key) == :ok
    end
  end

  describe "interval_ms/0" do
    test "ten seconds by default" do
      Application.delete_env(:bbparty, :label)

      assert Cooldown.interval_ms() == 10_000
    end

    test "configurable" do
      configure(2_500)

      assert Cooldown.interval_ms() == 2_500
    end
  end
end
