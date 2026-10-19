defmodule Bbparty.RenderState.FitTest do
  use ExUnit.Case, async: true

  alias Bbparty.RenderState.Fit

  defp fit(fingerprint, size), do: %Fit{fingerprint: fingerprint, size: size}

  describe "from_params/1" do
    test "a fingerprint and a positive size" do
      assert Fit.from_params(%{"fingerprint" => "123", "size" => 4.2}) == {:ok, fit("123", 4.2)}
    end

    test "anything else is refused" do
      for params <- [
            %{"fingerprint" => 123, "size" => 4.2},
            %{"fingerprint" => "123", "size" => "4.2"},
            %{"fingerprint" => "123", "size" => 0},
            %{"fingerprint" => "123", "size" => -1},
            %{"size" => 4.2},
            nil
          ] do
        assert Fit.from_params(params) == :error, "accepted #{inspect(params)}"
      end
    end
  end

  describe "accept/3" do
    test "a push for the current fingerprint replaces what is held" do
      assert Fit.accept(fit("a", 3), fit("b", 5), "b") == {:ok, fit("b", 5)}
    end

    test "the first push is accepted" do
      assert Fit.accept(Fit.empty(), fit("b", 5), "b") == {:ok, fit("b", 5)}
    end

    test "a push for superseded typography is dropped" do
      assert Fit.accept(fit("a", 3), fit("a", 4), "b") == :ignore
    end

    test "a new size for the same fingerprint wins" do
      assert Fit.accept(fit("b", 5), fit("b", 6), "b") == {:ok, fit("b", 6)}
    end

    test "an identical push is not news" do
      assert Fit.accept(fit("b", 5), fit("b", 5), "b") == :ignore
    end
  end

  describe "size_cqw/2" do
    test "the floor before anything was measured" do
      assert Fit.size_cqw(Fit.empty(), 3.0) == 3.0
    end

    test "the last accepted size, whatever it was measured for" do
      assert Fit.size_cqw(fit("old", 12.0), 3.0) == 12.0
    end
  end
end
