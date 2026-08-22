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
- **Lighting that is dim, never black.** A fixture every three cells means every
  open cell in the level is within 26 studs of a light — verified by simulating
  the generator, not by eye. Flickering fixtures *dim* rather than switch off,
  and about 28% are dead on arrival: bright enough to make out the walls, too
  dim to count as safety. Around 40% of the level drains sanity while 0% of it
  is genuinely unlit.
- **Flickering fluorescents.** Client-side, so each player sees a different room.
- **Sprint** (hold Shift) with stamina.
- **Flashlight** (press F) with a draining battery.
- **A way out.** An exit sits at the open cell furthest from spawn — around 280
  studs away in a straight line, and several times that through the maze. It is
  the only green light in a yellow level, so it reads from the far end of a
  corridor without needing a HUD marker. Reaching it pays 2500 score and $750,
  shows a banner, and returns you to the entrance for another run.
- **Radar**, top right. Entities, weapons, medkits, cash and the exit, rotated
  so up is where you are facing. Blips come from a fixed pool that is created
  once and reused, so the cost does not grow with how much is out there —
  drawing the maze itself would have meant a frame per cell, 2401 of them.
- **Scoring.** Kills and headshots, tracked server-side and exposed both to the
  HUD and as `leaderstats`, so the player list doubles as a scoreboard. A kill's
  value is read off the rig, so a new variant scores correctly without touching
  the weapon code. Headshots pay double on a kill, plus a bonus when they don't.
- **Weapons.** Pistol, Machine Gun and Sniper Rifle, scattered as pickups
  through the maze and rebuilt from primitives (no binary model assets). Stats
  live in `src/shared/WeaponConfig.luau`. Everyone spawns with a pistol.
- **Health.** Medkits scattered through the maze restore you to full on contact.
  Weapons and medkits draw from one shuffled position pool, so two pickups can
  never share a tile.
- **Hostiles**, in two variants defined in `Config.Entity.Variants`:
  - *Wanderer* — nine studs of nothing much, pale blank head, dark body.
  - *Slender* — rarer, eleven studs, black suit, bright featureless head, arms
    past the knees, and four tendrils off the back. Twice the health, slower to
    start, faster once it has you.

  Both patrol via `PathfindingService`, chase on sight, search your last known
  position when they lose you, sway constantly so they never read as props, and
  take damage — including headshots. They scream when they die.
- **HUD** with score, health/battery/stamina bars, crosshair, hitmarker, ammo
  readout, headshot callout, and a vignette that closes in as health drops.

## Weapons

| | Mode | Rate | Magazine | Reserve | Recoil |
| --- | --- | --- | --- | --- | --- |
| Pistol | Semi — one shot per click | 5/s | 20 | 120 | 1.3° |
| Machine Gun | Burst of 10, then a forced pause | 11/s | 80 | 320 | 0.55° |
| Sniper Rifle | Semi | 0.8/s | 10 | 40 | 3.2° |

A burst runs to completion whether or not you keep holding the trigger — that
is what makes it read as a burst rather than a short spell of automatic fire.

Rolling over a weapon equips it and refills it to a full magazine and full
reserve, whether or not you already own it. The pickup is only consumed if
something actually changed, so walking over one fully loaded and already armed
leaves it for someone else.

Recoil is applied at `RenderPriority.Camera + 1`, after Roblox's camera scripts
have positioned the camera — anything earlier is simply overwritten.

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
