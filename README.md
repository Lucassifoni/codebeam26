# code-beam-26-talk-source

Source of the system I'm presenting at Code BEAM 26 : "From Pure Code to Physical Controls: Designing Hardware in Elixir "

### Slides :   
- English, technical audience : [slides pdf](Talk_English_Slides.pdf)  
- Français, audience non technique : [pdf slides](Talk_French_Slides.pdf)  

### Run it yourself and get a copy of the machine layout :

```
cd source
mix deps.get
mix bbparty.layout.import definitive_layout.json --mode replace_all
iex -S mix phx.server
```

### Stage notes for myself :

```
source .env (for the last demo)  
iex -S mix phx.server  
mix bbparty.display (don't forget it with stress)  
```
