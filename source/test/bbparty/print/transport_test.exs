defmodule Bbparty.Print.TransportTest do
  use ExUnit.Case, async: false

  alias Bbparty.Print.Transport

  defp configure(value) do
    previous = Application.get_env(:bbparty, :print_transport)
    Application.put_env(:bbparty, :print_transport, value)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:bbparty, :print_transport)
        set -> Application.put_env(:bbparty, :print_transport, set)
      end
    end)
  end

  describe "configured/0" do
    test "with nothing configured, picks by platform" do
      Application.delete_env(:bbparty, :print_transport)

      expected =
        case :os.type() do
          {:unix, :darwin} -> Bbparty.Print.Transport.MacUsb
          _ -> Bbparty.Print.Transport.Device
        end

      assert {^expected, []} = Transport.configured()
    end

    test "a bare module means no options" do
      configure(Bbparty.Print.Transport.Device)

      assert Transport.configured() == {Bbparty.Print.Transport.Device, []}
    end

    test "a module with options" do
      configure({Bbparty.Print.Transport.Cups, queue: "Bixolon_XD5"})

      assert Transport.configured() == {Bbparty.Print.Transport.Cups, [queue: "Bixolon_XD5"]}
    end

    test "options without a module keep the platform's choice" do
      configure(queue: "Bixolon_XD5", path: "/dev/usb/lp0")

      assert {module, opts} = Transport.configured()
      assert module == Transport.platform_default()
      assert opts == [queue: "Bixolon_XD5", path: "/dev/usb/lp0"]
    end
  end

  describe "platform_default/1" do
    test "macOS calls the CUPS USB backend directly, having no raw queue" do
      assert Transport.platform_default({:unix, :darwin}) == Bbparty.Print.Transport.MacUsb
    end

    test "Linux writes the character device, skipping the driver stack" do
      assert Transport.platform_default({:unix, :linux}) == Bbparty.Print.Transport.Device
    end

    test "anything else falls back to the device path" do
      assert Transport.platform_default({:win32, :nt}) == Bbparty.Print.Transport.Device
    end

    test "this machine's answer matches its OS" do
      assert Transport.platform_default() == Transport.platform_default(:os.type())
    end
  end

  describe "the device transport" do
    test "writes the payload verbatim" do
      path =
        Path.join(System.tmp_dir!(), "bbparty-transport-#{System.unique_integer([:positive])}")

      on_exit(fn -> File.rm(path) end)

      assert :ok = Bbparty.Print.Transport.Device.send(["^XA", "^XZ"], path: path)
      assert File.read!(path) == "^XA^XZ"
    end

    test "a missing device is named" do
      assert {:error, {:printer_not_found, "/nope/usb/lp0"}} =
               Bbparty.Print.Transport.Device.send("^XA", path: "/nope/usb/lp0")
    end
  end

  describe "the macOS USB backend transport" do
    alias Bbparty.Print.Transport.MacUsb

    @listing """
    direct usb://BIXOLON/XD5-43d?serial=BEGWWRKA24020051 "BIXOLON XD5-43d" "BIXOLON XD5-43d" "SERN:BEGWWRKA24020051;MFG:BIXOLON ;CMD:BXL_2;MODEL:XD5-43d;CLASS:PRINTER;" ""
    network ipps
    network socket
    direct usb://Brother/HL-L2350DW?serial=X0000 "Brother" "Brother" "" ""
    """

    test "picks the device URIs out of a discovery listing" do
      assert MacUsb.parse_devices(@listing) == [
               "usb://BIXOLON/XD5-43d?serial=BEGWWRKA24020051",
               "usb://Brother/HL-L2350DW?serial=X0000"
             ]
    end

    test "ignores everything that is not a USB device" do
      refute Enum.any?(MacUsb.parse_devices(@listing), &String.contains?(&1, "ipp"))
    end

    test "an empty listing" do
      assert MacUsb.parse_devices("") == []
    end
  end

  describe "the timeout" do
    test "a command that outlives its budget is killed and named" do
      assert {:error, {:command_timed_out, "sleep", 50}} =
               Transport.run("sleep", ["5"], timeout: 50)
    end

    test "a command that finishes in time returns its output" do
      assert {:ok, output} = Transport.run("echo", ["hello"], timeout: 5_000)
      assert String.trim(output) == "hello"
    end

    test "a missing executable is named rather than raised" do
      assert {:error, {:command_not_found, "bbparty-no-such-binary"}} =
               Transport.run("bbparty-no-such-binary", [])
    end
  end

  describe "the CUPS transport's queue" do
    test "an unnamed queue is refused rather than sent to the system default" do
      assert Bbparty.Print.Transport.Cups.send("^XA^XZ", []) == {:error, :no_queue_configured}
    end

    test "and through the dispatcher too" do
      configure({Bbparty.Print.Transport.Cups, []})

      assert Transport.send("^XA^XZ") == {:error, :no_queue_configured}
    end
  end

  describe "the CUPS transport" do
    test "reports what lp said when it fails" do
      result = Bbparty.Print.Transport.Cups.send("^XA^XZ", queue: "bbparty-no-such-queue")

      assert match?({:error, {:command_failed, _status, _output}}, result) or
               match?({:error, {:command_not_found, _}}, result),
             "expected a named failure, got: #{inspect(result)}"
    end

    test "leaves no temporary file behind" do
      before = tmp_labels()

      Bbparty.Print.Transport.Cups.send("^XA^XZ", queue: "bbparty-no-such-queue")

      assert tmp_labels() == before
    end
  end

  defp tmp_labels do
    System.tmp_dir!()
    |> File.ls!()
    |> Enum.filter(&String.starts_with?(&1, "bbparty-label-"))
    |> Enum.sort()
  end
end
