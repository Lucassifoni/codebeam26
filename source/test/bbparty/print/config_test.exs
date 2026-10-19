defmodule Bbparty.Print.ConfigTest do
  use ExUnit.Case, async: true

  @config_root Path.expand("../../../config", __DIR__)

  describe "print_impls across environments" do
    test "prod prints" do
      assert [impl] = print_impls(:prod)
      assert impl == (&Bbparty.Print.Sticker.print/1)
    end

    test "dev prints" do
      assert [_ | _] = print_impls(:dev)
    end

    test "test does not print, so no test waits out a capture timeout" do
      assert print_impls(:test) == []
    end
  end

  test "the configured implementations are callable as printers" do
    for env <- [:prod, :dev], impl <- print_impls(env) do
      assert is_function(impl, 1), "#{env} configured a print impl that is not 1-arity"
    end
  end

  defp print_impls(env) do
    @config_root
    |> Path.join("config.exs")
    |> Config.Reader.read!(env: env, target: :host)
    |> get_in([:bbparty, :print_impls])
    |> Kernel.||([])
  end
end
