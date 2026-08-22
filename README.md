# arlo-backrooms-game

A Roblox horror-exploration game. Level 0: an endlessly looping maze of yellow
rooms, buzzing fluorescents, and nothing else.

## Getting set up

Tools are pinned in `rokit.toml` and installed automatically:

```bash
rokit install
```

## Working on it

```bash
rojo build default.project.json -o build.rbxl   # generate the place file
rojo serve                                      # live-sync into Studio
```

1. Run `rojo build` once, then open `build.rbxl` in Roblox Studio.
2. Run `rojo serve`, and in Studio use the Rojo plugin -> Connect.
3. Every save to `src/` now syncs into the open place. Hit Play to test.

Formatting and linting:

```bash
stylua src/       # format
selene src/       # lint
```

## Layout

| Path                | Becomes                                  |
| ------------------- | ---------------------------------------- |
| `src/shared/`       | `ReplicatedStorage.Shared`               |
| `src/server/`       | `ServerScriptService.Server` (a Script)  |
| `src/client/`       | `StarterPlayerScripts.Client` (a LocalScript) |
| `Packages/`         | Wally dependencies (optional, gitignored) |

`src/shared/Config.luau` holds every tuning value — level size, walk speeds,
sanity drain rates. Start there when you want to change how the game feels.

## What's implemented

- **Procedural Level 0.** A randomised depth-first maze with extra loops and
  open halls carved in, wrapped in a sealed perimeter. New seed every server
  start (pin one via `Config.Level.Seed`).
- **Flickering fluorescents.** Client-side, so each player sees a different room.
- **Sprint** (hold Shift) with stamina.
- **Flashlight** (press F) with a draining battery.
- **Sanity.** Drains in the dark, regenerates in light. Zero is fatal. The client
  simulates it and the server owns the consequence.
- **HUD** with three bars and a vignette that closes in as sanity drops.

## Next up

- An entity that hunts by sound
- Exits / level transitions (Level 0 -> Level 1)
- Ambient audio: the hum, footsteps on carpet
- Saved progress via DataStores
- Multiplayer proximity voice
