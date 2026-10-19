---
theme: ../theme
title: "From Pure Code to Physical Controls"
author: Lucas Sifoni
favicon: /favicon.png
lang: en
layout: cover
ribbon: Code BEAM
transition: fade
drawings:
  persist: false
duration: 35min
---

# From Pure Code to Physical Controls

Designing Hardware in Elixir

Lucas Sifoni / Turing-Express / Code BEAM Europe 2026

---
layout: media
media: bb_01.png
---

---
layout: media
media: bb_02.png
---

---
layout: media
media: bb_03.png
---

---
layout: media
media: ["Wmmorris3248.jpg", "morris1.png"]
---

---
layout: media
media: IMG_6232.jpeg
---

---
layout: media
media: IMG_5733.webp
fit: contain
---

---

# Project guidelines

- Intuitive & playful to use
- Build instead of subcontract
- Design controls intuitively
- Build along the design
- Old school look and feel, powered by Elixir

Used by ~500 people to create ~2000 printouts in 4 days

---

# Final hardware

- 196-key keyboard (self-built)
- Arcade trackball (adapted to run on 3v3)
- 3 joysticks & analog needle gauges
- A backlit keypad (self-built)
- Two switchboards, 32 switches with 64 indicators (self-built)
- A fake floppy disk reader (NFC tag reader)
- A Bixolon XD5-43d sticker printer

Trivia : 
- Shift registers chains instead of IO expanders
- DIP ICs and passive components
- Hand wired on padboards to accomodate the short delay

---
layout: media
media: layout.png
fit: contain
---
4 fully independent modules, 1 ESP32 each
---
layout: media
media: img_4636.webp # 2026-06-25 14:49
---

---
layout: media
media: [img_4665.webp, img_4705-2.webp]
---

---
layout: media
media: [img_4942.mp4, img_4949.mp4]
---

---
layout: media
media: [img_4951.mp4, img_4952.mp4] # 2026-07-20 14:29
---

---
layout: media
media: [img_4988.webp, img_4996.mp4]
---


---
layout: media
media: [img_5404.webp, img_5411.webp]
---

---
layout: media
media: [img_5416-2.webp, img_5417-2.webp, img_5418.webp]
---

---
layout: media
media: img_5519-2.mp4
---

---
layout: media
media: [img_5610.webp, img_5566.webp, img_5568.webp] 
---

---

## ⚠️ flashing slide

---
layout: media
media: stickers.webm
loop: false
---

---

## Where do we put complexity ?

- Hardware as simple as possible (provide inputs/outputs)
- Firmware as simple as possible (send events, get commands)
- All logic high-level in the Elixir host

<br/><br/><br/>
## How do we discover and refine our design ?
- Simulate each component in Elixir
- Keep the logic as pure as possible
- Move them around, experiment with different types of interactions and effects
- Advance the build, it helps refine the code
- Refine the code, it helps advance the build
---

## Firmware doesn't know its purpose

```cpp
void app_setup() {
  serial_link::begin(proto::kBaud, proto::kModuleId);
  key_spi.begin(kSck, kMiso, kMosi, -1);
  drive.begin();
  sense.begin();
  keys.set_settle(settle);
}

void app_loop() {
  serial_link::poll(apply_command);
  const unsigned long now = millis();
  if (now - last_scan_ms < kScanIntervalMs) {
    return;
  }
  last_scan_ms = now;
  keys.scan(on_key_event);
}
```
---

### Each control type implements `Component`

```elixir
defmodule Hardware.Component do
  
  @callback new(opts) # The data that represents me
  @callback events() :: list(atom()) # What I react to
  @callback effects() :: list(atom()) # What I do on the world
  @callback handle_event(state, event, payload) :: # How do I react to an event, what do I emit ?
              {:ok, new_state} | {:ok, new_state, [{atom(), term()}]} 
  @callback handle_effect(id, effect, payload, old_state, new_state) :: :ok
  @callback input_binding(state) :: term() | nil # How to map me to hardware ?

  @callback editable_fields() :: keyword(atom()) # How can I be configured ?
  @callback dimensions() :: {number(), number()} # How do I display ?
```

---

```elixir
defmodule Hardware.Components.PushButton do
  @behaviour Hardware.Component
  defstruct [:pushed, :char, :shift, :action, :red]

  def new(opts) do
    %__MODULE__{ pushed: false,
      char: Keyword.get(opts, :char, nil),
      shift: Keyword.get(opts, :shift, nil),
      action: Keyword.get(opts, :action, nil),
      red: Keyword.get(opts, :red) == true
    }
  end

  def editable_fields(), do: [char: :string, shift: :string, action: :string, red: :boolean]
  def events(), do: [:key_up, :key_down, :set_pushed]

  def handle_event(state, :key_down, _),
    do: {:ok, %{state | pushed: true}, [{:key_down, meaning(state)}]}
    
  def handle_event(state, :key_up, _),
    do: {:ok, %{state | pushed: false}, [{:key_up, meaning(state)}]}
end
```

---

### Some controls types implement `Output`

```elixir
defmodule Hardware.Output do
  @callback handle_transition(old :: struct(), next :: struct(), opts :: keyword()) :: :ok
end
```

```elixir
defmodule Hardware.Components.PushButtonWithLed do
  @behaviour Hardware.Component
  @behaviour Hardware.Output

  alias Bbparty.Bus.LedShadow
  alias Bbparty.Keyboard.Action

  defstruct pushed: false, lit: false, char: nil, shift: nil, action: nil, module: nil, led: nil
  def events(), do: [:key_up, :key_down, :set_pushed, :set_lit]

  @impl Hardware.Output # Impure, effect the world
  def handle_transition(%__MODULE__{} = _old, %__MODULE__{} = new, _opts) do
    LedShadow.put(new.module, new.led, new.lit)
    :ok
  end
end
```
---

### Every control type is capable of being rendered

```elixir
defmodule Hardware.Components.NeedleGauge do
  @behaviour Hardware.Component
  @behaviour Hardware.Output

  defstruct progress: 50, module: nil, gauge: nil, duty_min: 0, duty_max: 255
  ... 
```

```elixir
defmodule Hardware.Components.NeedleGauge.Display do
  use Phoenix.Component
  
  attr :data, :map
  def render(assigns) do
    ~H"""
    <div class="w-48 h-24 bg-blue-300 relative">
      <div
        class="needle w-[2px] bg-red-500 h-[80px] left-[50%] top-[10px] absolute origin-bottom"
        style={"transform: rotate(#{compute_rotation(@data.progress)}deg)"}
      >
      </div>
    </div>
    """
```

---
layout: media
media: components_rendered.png
---

---

### Behavior = type + instance, a `PhysicalComponent` GenServer

```
[info] Start switch_4_5 via {:via, Registry, {Bbparty.ComponentsRegistry, :PhysicalComponent_switch_4_5}}
[info] Start text_quantity via {:via, Registry, {Bbparty.ComponentsRegistry, :PhysicalComponent_text_quantity}}
[info] Start renderer_mirror via {:via, Registry, {Bbparty.ComponentsRegistry, :PhysicalComponent_renderer_mirror}}
[info] Start m4_trackball via {:via, Registry, {Bbparty.ComponentsRegistry, :PhysicalComponent_m4_trackball}}
[info] Start font_size_joystick via {:via, Registry, {Bbparty.ComponentsRegistry, :PhysicalComponent_font_size_joystick}}
[info] Start kerning_gauge via {:via, Registry, {Bbparty.ComponentsRegistry, :PhysicalComponent_kerning_gauge}}
[info] Start line_height_gauge via {:via, Registry, {Bbparty.ComponentsRegistry, :PhysicalComponent_line_height_gauge}}
```

``` elixir
defmodule Bbparty.Layout.ComponentInstance do
  use Ecto.Schema
  schema "component_instances" do
    field :component_id, :binary
    field :module, :binary
    field :attrs, :map
    field :position, :map
    field :group_id, :binary

    timestamps(type: :utc_datetime)
  end
```

---
layout: media
media: control_panel.png
fit: contain
---
Panel visit
---
layout: media
media: schematic_first_part.png
fit: contain
---
How events enter the system
---

## Build process

- Design on paper
- Implement the event + render pure loop
- Implement the first components and the control panel / render liveview
- Prepare the boards, generate the firmwares <small style="font-size: 0.5em">&larr; a few recurrent bugs despite the simplicity, lied about hardware faults despite firmware bugs</small>
- Correct the firmwares manually
- Let it run for days unattended
- AI helped with :
  - subsequent components and helpers <small style="font-size: 0.5em">&larr; muddied my design too much for my taste</small>
  - very niche parts of the effects <small style="font-size: 0.5em">&larr; efficient but bruteforce-y</small>
  - generate paper task-lists for soldering <small style="font-size: 0.5em">&larr; very helpful, no regrets</small>
  - pimping the digital twin UI/UX <small style="font-size: 0.5em">&larr; same</small>
- Refactor of the post-human parts in progress for the next exhibitions
---

## What I would change

- Less distinction between event types
- Less distinction between outputs and effects
- Livebook instead of the codebase for all one-off commissioning scripts
---
