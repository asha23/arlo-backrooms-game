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

> **Note on selene's version.** It's pinned to `0.26.1` rather than latest.
> From `0.27.0` onward upstream builds its single macOS release asset on an
> Apple Silicon runner, so the published binary is arm64-only and won't run on
> an Intel Mac. `0.26.1` is the last release with an x86_64 macOS build. If this
> project is only ever worked on from Apple Silicon, bump it back to latest.

## Layout

| Path                | Becomes                                  |
| ------------------- | ---------------------------------------- |
| `src/shared/`       | `ReplicatedStorage.Shared`               |
| `src/server/`       | `ServerScriptService.Server` (a Script)  |
| `src/client/`       | `StarterPlayerScripts.Client` (a LocalScript) |
| `Packages/`         | Wally dependencies (optional, gitignored) |

`src/shared/Config.luau` holds every tuning value — level size, walk speeds,
sanity drain rates. Start there when you want to change how the game feels.

## Controls

**Desktop** — the camera is locked to first person, so the mouse aims directly
and the crosshair always points where you're looking.

| Input     | Action                |
| --------- | --------------------- |
| Mouse            | Aim                   |
| WASD             | Move                  |
| Shift            | Sprint (uses stamina) |
| F                | Toggle flashlight     |
| Any mouse button | Fire                  |
| R                | Reload                |
| 1/2/3            | Equip from backpack   |

You spawn with the pistol already equipped. The Roblox chat window is hidden by
default — it steals keyboard focus, which matters when movement is on WASD.

**Touch** — Roblox supplies the movement thumbstick, the jump button and
drag-to-look; we add FIRE (hold to keep firing), RELOAD, SPRINT (a toggle) and
LIGHT. The HUD moves to the top of the screen so it clears the thumbstick and
the fire button. All four drive the same methods the keyboard bindings do, so
touch is never a second implementation of the game's rules.

Set `Config.Camera.FirstPerson = false` for Roblox's third-person orbit camera,
and `Config.Camera.Sensitivity` to taste — trackpads generally want a higher
value than a mouse.

## What's implemented

- **Procedural Level 0.** A randomised depth-first maze with extra loops and
  open halls carved in, wrapped in a sealed perimeter. New seed every server
  start (pin one via `Config.Level.Seed`).
- **Flickering fluorescents.** Client-side, so each player sees a different room.
- **Sprint** (hold Shift) with stamina.
- **Flashlight** (press F) with a draining battery.
- **Sanity.** Drains in the dark, regenerates in light. Zero is fatal. The client
  simulates it and the server owns the consequence.
- **Weapons.** Pistol, Machine Gun and Sniper Rifle, scattered as pickups
  through the maze and rebuilt from primitives (no binary model assets). Stats
  live in `src/shared/WeaponConfig.luau`. Everyone spawns with a pistol.
- **Hostiles.** Faceless wanderers that patrol the maze, chase on sight via
  `PathfindingService`, search your last known position when they lose you, and
  take damage — including headshots.
- **HUD** with three bars, a crosshair, hitmarker, ammo readout, and a vignette
  that closes in as sanity drops.

## Audio

There are no uploaded audio assets. Everything uses `rbxasset://` paths, which
are the sound files that ship with the Roblox client, pitched well down and
run through reverb. That means audio works the moment you clone the repo, with
no uploads and no moderation wait — but they are stock effects doing a job they
weren't written for, and should be replaced with real audio eventually.

Roblox ships no *music*, so the score is synthesised: several copies of one low
tone at different pitches, each drifting on its own slow volume cycle. The
periods don't divide into each other, so the bed keeps shifting rather than
looping audibly. Set `Config.Ambience.MusicId` to an `rbxassetid://` of your own
track and that plays instead.

## Shooting is server-authoritative

The client sends the ray it was aiming down; the server re-casts that ray
itself and decides what was hit. Fire rate, spread, ammo and damage are all
enforced server-side. A client that lies about its aim can still only hit
things genuinely in front of it, and can never out-fire its own weapon.

## Next up

- Exits / level transitions (Level 0 -> Level 1)
- Ambient audio: the hum, gunfire, footsteps on carpet
- Entity variants — one that hunts by sound, one that only moves unobserved
- Saved progress via DataStores
