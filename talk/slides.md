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
duration: 20min
---

## From Pure Code to Physical Controls

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
- Two switchboards, 30 switches with 60 indicators (self-built)
- A fake floppy disk reader (NFC tag reader)
- A Bixolon XD5-43d sticker printer

Trivia : 
- Shift registers chains instead of IO expanders
- DIP ICs and passive components
- Hand wired on padboards to accomodate the short deadline

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
- **Simulate each component in Elixir**
- Keep the logic as pure as possible
- **Compose the system from components in a control panel**
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

```elixir
iex> PushButton.new(char: "a", shift: "A")
      |> PushButton.handle_event(:key_down, nil)

{:ok, %PushButton{pushed: true}, [{:key_down, %{char: "a", shift: "A", action: nil}}]}

# {:ok, new state, normalized events}
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

  @impl Hardware.Output # Impure, affects the world
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

## Event loop (1/2)

- An event enters from hardware 
- Its `PhysicalComponent` is resolved from a registry
- It enters through `handle_event/3` (or `feed_input/3` for high frequency events) 
- The pure `handle_event/3` is called -> `{:ok, state, emits}` (emits are normalized events)
- `PhysicalComponent` publishes : 
  - `{:component_changed, id, new_state}` for LiveView
  - and `{:component_event, id, event, payload}` for the core
- Impure effects (randomness, time) are injected by `RenderStateServer`
- `RenderState.apply` folds the event on the state
  - ```elixir
    {new_state, effects} = do_apply(state, event, layout)
    {new_state, Projections.propagate(state, new_state), effects}
    ```
  - Dependencies of the changes are resolved and become commands

---

## Event loop (2/2)

- `{render, commands, effects} = RenderState.apply/3`
- `RenderStateServer` dispatches commands (adjust your gauge...) to relevant `PhysicalComponent`s
- Components `handle_event/3` the commands and update in LiveView
- Output-enabled `PhysicalComponent` run `handle_transition/3` and impurely drive outputs
- Any cast effects on the world (printing) are run
- The actual rendering updates

---

A key press from the hardware :
```elixir
PhysicalComponent.handle_event(id, :key_down, nil)
```

A key press from liveview :
```elixir
PhysicalComponent.handle_event(id, :key_down, nil)
```

A key press from elsewhere :
```elixir
PhysicalComponent.handle_event(id, :key_down, nil)
```

---

RenderState : easy high-level view of the logic + dedicated pure logic modules
```elixir
def apply(state, event, layout) do
  {new_state, effects} = do_apply(state, event, layout)
  {new_state, Projections.propagate(state, new_state), effects}
end

defp do_apply(state, {id, :nudge, value}, _l), do: {Sizings.nudge(state, id, value), []}

defp do_apply(state, {_id, :nudge_quantity, chars}, _l),
  do: {TextSource.nudge_quantity(state, chars), []}

defp do_apply(state, {_id, :toggle_feature, tag}, _l),
  do: {Font.toggle_feature(state, tag), []}

defp do_apply(state, {_id, :set_feature, {tag, on?}}, _layout),
  do: {Font.set_feature(state, tag, on?), []}

defp do_apply(state, {_id, :select_font, font}, _layout),
  do: {Font.select(state, font), []}
```

---

```elixir
defmodule Bbparty.RenderState.TextSource do
  @sources %{
    source_user: :user,
    source_font_name: :font_name,
    source_alpha_upper: :alpha_upper,
    source_alpha_lower: :alpha_lower,
    source_numbers: :numbers
  }

  def effective_text(%RenderState{text_source: :font_name, selected_font: font}), do: font || ""
  def effective_text(%RenderState{text_source: :alpha_upper}), do: @alpha_upper
  def effective_text(%RenderState{text_source: :alpha_lower}), do: @alpha_lower
  def effective_text(%RenderState{text_source: :numbers}), do: @numbers
  def effective_text(%RenderState{text_quantity: n}) when is_integer(n) and n > 0, do: TextToWrite.take(n)
  def effective_text(%RenderState{text: text}), do: text
  
  def overridden?(%RenderState{text_source: source}) when source != :user, do: true
  def overridden?(%RenderState{text_quantity: n}), do: is_integer(n) and n > 0
  
  def clear_quantity(state), do: %{state | text_quantity: 0, text_source: :user}
  
  def nudge_quantity(state, chars),
    do: %{state | text_quantity: clamp(state.text_quantity + chars, 0, TextToWrite.count())}
```
---

## Build process

- Design on paper
- Implement the event + render pure loop
- Implement the first components and the control panel / render liveview
- Prepare the boards, generate the firmwares <small style="font-size: 0.5em">&larr; a few recurrent bugs despite the simplicity, blamed my soldering for firmware bugs</small>
- Correct the firmwares manually
- Let it run for days unattended at most points of the process
- AI helped with :
  - subsequent components and helpers <small style="font-size: 0.5em">&larr; muddied my design too much for my taste</small>
  - very niche parts of the effects <small style="font-size: 0.5em">&larr; efficient but bruteforce-y</small>
  - generate paper task-lists for soldering <small style="font-size: 0.5em">&larr; very helpful, no regrets</small>
  - pimping the digital twin UI/UX <small style="font-size: 0.5em">&larr; same</small>
- today : Refactor in progress of the post-human parts in progress for the next exhibitions

---

## What I would change

- Better distinction between event types (world event, internal command) and their handlers
- No distinction between outputs and effects : my initial reason to separate them did not materialize
- A connected Livebook instead of the codebase for all one-off commissioning scripts
<br/><br/>
### Benefits

- Very late resolution of handlers
- Live-reconfigurable installation
- No coupling between hardware and logic
- Other transports are easy to add
- Liveview isn't the app but a simple renderer
- **The simulator is the system**

---

## Beyond hardware

### Why manage state in a similar way for any<sup>*</sup> app
- Easily migrate to another framework
- Build liveview states in scripts and tests
- Expose pure function heads and docs via MCP, interpret lists of commands
- Universal UI + thin rendering layer

---
layout: media
media: mail_demo.png
fit: contain
---
### Alternative transports : I mean it 

---
layout: end
---

<a href="mailto:contact@turing-express.fr">contact@turing-express.fr</a>

20 minutes is short : code, more photos, french version : https://pushin.eu/lsifoni/codebeam26

Personal website -> <a href="https://lucassifoni.info">lucassifoni.info</a>  
My SaaS company -> <a href="https://alzo.fr">alzo.fr</a>  
My side-project -> <a href="https://chantepierre-optique.fr">chantepierre-optique.fr</a>
