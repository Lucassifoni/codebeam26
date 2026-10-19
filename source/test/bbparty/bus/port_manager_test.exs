defmodule Bbparty.Bus.PortManagerTest do
  use ExUnit.Case, async: true

  alias Bbparty.Bus.PortManager

  @enumeration %{
    "/dev/cu.Bluetooth-Incoming-Port" => %{},
    "/dev/cu.debug-console" => %{},
    "/dev/cu.usbserial-A50285BI" => %{
      manufacturer: "FTDI",
      serial_number: "A50285BI",
      vendor_id: 0x0403,
      product_id: 24577
    },
    "/dev/cu.wchusbserial1420" => %{vendor_id: 0x1A86, product_id: 29987}
  }

  describe "esp_ports/1" do
    test "accepts both USB-serial bridges the boards ship with" do
      assert PortManager.esp_ports(@enumeration) == [
               "/dev/cu.usbserial-A50285BI",
               "/dev/cu.wchusbserial1420"
             ]
    end

    test "ignores ports with no vendor id" do
      assert PortManager.esp_ports(%{"/dev/cu.Bluetooth-Incoming-Port" => %{}}) == []
    end

    test "ignores an unrelated USB-serial device" do
      assert PortManager.esp_ports(%{"/dev/cu.usbmodem1" => %{vendor_id: 0x2341}}) == []
    end
  end
end
