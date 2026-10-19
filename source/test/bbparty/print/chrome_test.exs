defmodule Bbparty.Print.ChromeTest do
  use ExUnit.Case, async: true

  alias Bbparty.Print.Chrome

  describe "find/1" do
    test "a given path that exists is used as is" do
      assert Chrome.find(__ENV__.file) == {:ok, __ENV__.file}
    end

    test "a given path that does not exist is an error, not a fallback" do
      assert Chrome.find("/no/such/browser") == :error
    end

    test "a given name is looked up on the PATH" do
      assert {:ok, "/" <> _} = Chrome.find("sh")
    end
  end

  describe "headless_args/3" do
    setup do
      %{args: Chrome.headless_args(9333, "/tmp/profile", 1181)}
    end

    test "opens the debugging port on its own profile", %{args: args} do
      assert "--headless=new" in args
      assert "--remote-debugging-port=9333" in args
      assert "--user-data-dir=/tmp/profile" in args
    end

    test "one CSS pixel is one device pixel, at the width asked for", %{args: args} do
      assert "--force-device-scale-factor=1" in args
      assert "--window-size=1181,1181" in args
    end

    test "keeps animation frames coming, which the sticker waits on to size itself",
         %{args: args} do
      assert "--disable-renderer-backgrounding" in args
      assert "--disable-backgrounding-occluded-windows" in args
      assert "--disable-background-timer-throttling" in args
    end

    test "ends on the blank tab that blank_path/0 finds again", %{args: args} do
      assert List.last(args) == "about:blank"
      assert Chrome.blank_path() == "blank"
    end
  end
end
