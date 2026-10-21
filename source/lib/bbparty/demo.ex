defmodule Bbparty.Demo do
  alias Hardware.PhysicalComponent
  @pause_ms 50
  @joystick_sample_ms 20
  @joystick_pushed 300
  @joystick_center 2100

  def hello do
    PhysicalComponent.handle_event(:font_selector, :select_font, "Boogy Brut Bold Italic")
    pause()

    PhysicalComponent.handle_event(:button_0, :key_down, nil)
    pause()
    PhysicalComponent.handle_event(:button_0, :key_up, nil)
    pause()

    PhysicalComponent.handle_event(:key_11_13, :key_down, nil)
    pause()
    PhysicalComponent.handle_event(:key_11_13, :key_up, nil)
    pause()

    PhysicalComponent.handle_event(:key_12_9, :key_down, nil)
    pause()
    PhysicalComponent.handle_event(:key_12_9, :key_up, nil)
    pause()

    PhysicalComponent.handle_event(:key_11_3, :key_down, nil)
    pause()
    PhysicalComponent.handle_event(:key_11_3, :key_up, nil)
    pause()

    PhysicalComponent.handle_event(:key_11_3, :key_down, nil)
    pause()
    PhysicalComponent.handle_event(:key_11_3, :key_up, nil)
    pause()

    PhysicalComponent.handle_event(:key_12_3, :key_down, nil)
    pause()
    PhysicalComponent.handle_event(:key_12_3, :key_up, nil)
    pause()

    Enum.each(1..25, fn _ -> joystick_sample(@joystick_pushed) end)
    Enum.each(1..15, fn _ -> joystick_sample(@joystick_center) end)

    :ok
  end

  defp joystick_sample(raw) do
    PhysicalComponent.handle_event(:font_size_joystick, :axis, raw)
    Process.sleep(@joystick_sample_ms)
  end

  defp pause, do: Process.sleep(@pause_ms)
end
