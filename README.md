# Fight to Escape the Backrooms

A Roblox horror shooter. You wake in Level 0 — an endless maze of stained yellow
corridors under failing fluorescents — with five lives, a pistol, and something
in the dark that hunts in packs. There is a way out. It is as far from where you
started as the level allows.

## Getting set up

Tools are pinned in `rokit.toml` and install themselves:

```bash
rokit install
```

## Working on it

```bash
rojo build default.project.json -o build.rbxl   # generate the place file
rojo serve                                      # live-sync into Studio
```

1. Run `rojo build` once, then open `build.rbxl` in Roblox Studio.
2. Run `rojo serve`, and in Studio use the Rojo plugin → Connect.
3. Every save to `src/` now syncs into the open place. Hit Play to test.

**Open `build.rbxl` itself, not a place made from a Roblox template.** Rojo syncs
into whatever place is open rather than replacing it, so a template's grey
baseplate and default spawn end up underneath the generated level. `WorkspaceCleaner`
strips both at startup and logs what it removed, but starting from the clean
build avoids the question.

Changing a *service* or a Workspace/Lighting property in `default.project.json`
needs the place reopened — Rojo cannot add a service to a place that is already
open. Plain script edits sync live and need no restart.

Checks:

```bash
stylua src/       # format
selene src/       # lint
```

Type-checking needs `luau-lsp` and a sourcemap:

```bash
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src/
```

That catches a category `selene` cannot — selene lints, it does not type-check.
Several real bugs in this project were found only by the type-checker.

> **selene is pinned to 0.26.1**, not latest. From 0.27.0 upstream builds its
> single macOS release asset on an Apple Silicon runner, so the published binary
> is arm64-only and will not run on an Intel Mac. 0.26.1 is the last release with
> an x86_64 macOS build. On Apple Silicon, bump it.

## Layout

| Path            | Becomes                                       |
| --------------- | --------------------------------------------- |
| `src/shared/`   | `ReplicatedStorage.Shared`                    |
| `src/server/`   | `ServerScriptService.Server` (a Script)       |
| `src/client/`   | `StarterPlayerScripts.Client` (a LocalScript) |
| `src/loading/`  | `ReplicatedFirst.Loading` (a LocalScript)     |
| `Packages/`     | Wally dependencies (optional, gitignored)     |

**`src/shared/Config.luau` holds every tuning value in the game** — level size,
light brightness, weapon feel, entity aggression, spawn counts. Start there.

## Controls

**Desktop** — the camera is locked to first person, so the mouse aims directly.

| Input            | Action                          |
| ---------------- | ------------------------------- |
| Mouse            | Aim                             |
| WASD             | Move                            |
| Shift            | Sprint (uses stamina)           |
| F                | Toggle flashlight               |
| Any mouse button | Fire                            |
| Right mouse      | Scope (sniper only — aims, does not fire) |
| R                | Reload                          |
| 1–4              | Equip from backpack             |

**Touch** — Roblox supplies the thumbstick, jump and drag-to-look; we add FIRE,
AIM, RELOAD, SPRINT and LIGHT. FIRE also respawns you from the death screen,
since a mobile player would otherwise have to find a bare patch of screen to tap.

Two decisions here follow mobile-shooter convention rather than being the obvious
implementation, and are worth not undoing:

- **FIRE and AIM are not buttons.** A `GuiButton` consumes the touch that starts
  on it, and Roblox drives the look camera from drags on the right of the screen
  — so a fire *button* there means you cannot aim while shooting, which every
  mobile shooter lets you do. They are non-interactive Frames with touches
  matched against their rectangle, so the touch is never consumed and the same
  thumb both fires and turns.
- **SPRINT and LIGHT sit on the left**, by the thumbstick. On the right they
  would crowd the area that has to stay clear for looking.

Everything is sized against viewport height rather than in fixed pixels (a
comfortable phone button is a postage stamp on a tablet), re-laid out when the
viewport changes, and the HUD, radar and controls use
`ScreenInsets.DeviceSafeInsets` to clear notches and home indicators. The scope
and loading screen deliberately use `None`, since they are full-bleed covers and
respecting the safe area would leave the game showing through at the corners.

Sensitivity lives in `Config.Camera`. Note that `Scope.Sensitivity` is a
*multiplier* on the base, so lowering the base slows the scope too.

## The level

A 49×49 grid of 9-stud cells — about 441 studs across — carved by randomised
depth-first search, with a few walls knocked through for loops and the odd wider
room. Roughly **50% wall coverage** and 2.4 open neighbours per tile: corridors
and dead ends, not open floor. Ceilings are 12 studs. A new seed every server
start; pin one with `Config.Level.Seed`.

### Lighting

Three separate things decide how bright this level looks, and tuning one in
isolation achieves very little:

1. `Lighting.Ambient` — applied at runtime by `LightingService`
2. The fixture **PointLights**
3. The **emissive colour of the Neon fixture panels** — a Neon part's apparent
   brightness *is* its colour, unaffected by any light setting

**`Config.Level.LightScale` multiplies all three.** Halve it and the whole level
halves. That is the dial to reach for.

Two things that are easy to get wrong here, both learned the hard way:

- **Light accumulates where pools overlap.** Fixtures sit every 3 cells (27
  studs). At a range of 30 an average of 3.2 lights reached every point, so a
  per-light brightness of 0.6 became an effective 2.0 — which clips a saturated
  surface toward white and renders as flat lemon with no shadow anywhere. The
  range is now 16, giving 0.7 lights per point.
- **Roblox has a hard budget for local lights**, and a much smaller one for
  shadow casters. Past it the engine *drops* lights rather than dimming, with no
  control over which — so the fixture above your head is as likely to go as one
  across the map. That is why a level full of lights can render pitch black.
  `LightStreaming` keeps only the nearest 64 enabled (about 62 live against 282
  built), nothing casts shadows, and 28% of fixtures are dead on arrival.

## What's in it

- **Three entity variants**, weighted by rarity, differing in silhouette rather
  than in stat block — a shape you can read down a corridor:

  | | Height | Health | Speed | Look |
  | --- | --- | --- | --- | --- |
  | Wanderer (×3) | 8.6 | 120 | 12 / 23 | Pale blank head, dark body |
  | Slender (×1) | 10.0 | 240 | 11 / 24 | Black suit, white head, tendrils |
  | Crawler (×2) | 4.4 | 70 | 15 / 26 | Two heads, tentacles for arms |

  All have gnashing fangs, glowing or black eyes chosen from the head's own
  luminance, a procedural walk cycle driven off the Motor6D joints (no animation
  assets), and a health bar overhead. They hunt as a pack — a sighting is
  broadcast to everything within 95 studs — and spawn in groups.

  Hitting you costs them 18 health and throws them backwards. You cannot retreat
  from something already touching you, so it has to be the one that moves.

- **Four weapons**, scattered 45 per type. Rolling over one equips it and fills
  it to a full magazine and reserve.

  | | Mode | Rate | Mag | Recoil | Kills |
  | --- | --- | --- | --- | --- | --- |
  | Pistol | Semi | 5/s | 20 | 0.2° | 5 body / 1 head |
  | Machine Gun | Burst of 10 | 11/s | 80 | 0.1° | 5 body / 1 head |
  | Shotgun | Semi, 9 pellets | 1.1/s | 6 | 0.45° | **outright**, ≤60 studs |
  | Sniper | Semi, scoped | 0.8/s | 10 | 0.5° | 5 body / 1 head |

  Lethality is a rule about **hits**, not damage numbers (`Config.Combat`): a
  headshot kills, five body shots kill, whatever you are holding and whichever
  variant you meet. Body damage derives from the target's own MaxHealth so it
  holds for any variant. Damage figures float up and fade on each hit.

- **Flashlight**, and it is the only thing that drives the entities off. Seven in
  the level, welded to the **left** arm rather than made a `Tool` — Roblox Tools
  equip to the right hand, and that would force a choice between light and a
  weapon. Anything caught in the beam turns blue and backs away at 55% speed,
  and keeps going 2.5s after the light leaves it. One minute of charge, with a
  pulsed warning for the last fifteen seconds.

- **Five lives**, capped at 8, with five extra lives in the level. Shown bottom
  right as your own avatar; spent ones dim rather than vanish. Out of lives shows
  GAME OVER, and the same click that would have respawned you starts a fresh run.

- **A way out.** The exit sits at the open cell furthest from spawn — about 280
  studs in a straight line and several times that through the corridors. Worth
  1000 score and $1000, repeatable: you are returned to the entrance and the exit
  stays put, so a second escape is the same crossing with fewer lives and a
  half-spent torch. Three things help you find it: a proximity radar that beeps
  faster as you close (on a squared curve, so the quickening lands in the final
  stretch), a large pulsing square on the map that is never culled, and ~90
  arrows raycast onto real walls pointing the way.

- **Radar**, top right. Entities, weapons, medkits, cash, torches, lives and the
  exit, rotated so up is where you face. Blips come from a fixed pool, so cost
  does not grow with what is out there — drawing the maze itself would have meant
  a frame per cell, 2401 of them.

- **Medkits** (14) restore full health. **Cash** ($50) drops from every kill.

- **Loading screen** that holds until the level is genuinely built, the character
  exists, and there are lit fixtures near you — then counts you in, 3-2-1-FIGHT.
  It shows the all-time top five while you wait.

## Performance notes

Things that turned out to matter, in case they are tempting to undo:

- **One proximity loop, not one per pickup.** Every weapon, medkit, torch, life,
  cash drop and the exit registers with `ProximityService`, which runs a single
  loop and buckets registrations by position so a player is tested against the
  handful of things near them. Seventy-nine coroutines each walking the player
  list several times a second became one — cost now scales with players rather
  than with how much loot is on the floor.
- **Nothing per-frame that does not need to be.** The heartbeat polls at 10Hz
  rather than on `RenderStepped`; the ammo string is cached and rebuilt only when
  it changes; HUD bars skip sub-percent writes; the minimap reuses its scratch
  tables; light streaming only re-sorts after the camera moves 6 studs.
- **Pools, not churn.** Tracers, impacts, the muzzle flash and damage numbers all
  come from fixed pools. Creating and destroying instances per shot is what made
  the machine gun stutter at eleven rounds a second.
- **Entities animate by distance** — 25Hz close, 8Hz mid, 2.5Hz far. Limb,
  tentacle and jaw transforms are several CFrame writes per tick per entity.

## Server-authoritative by design

The client sends the ray it was aiming down; the server re-casts it and decides
what was hit, enforcing fire rate, spread, ammo and damage. A client that lies
about its aim can still only hit what is genuinely in front of it.

The flashlight moved server-side for the same reason once the entities began
reacting to it: a client deciding when its own torch is lit would be a client
deciding when the monsters run away.

## High scores

All-time top five in an `OrderedDataStore`, shown on the loading screen. Only a
player's best is kept — `UpdateAsync` takes the max, so a bad run cannot
overwrite a good one. Banked when they escape, when they leave, on shutdown, and
every 90 seconds. Names live in a separate plain store, since an ordered store
holds only integers.

**Scores will not save in Studio until you enable it:** File → Experience
Settings → Security → **Enable Studio Access to API Services**. The place must be
published first. Studio then reads and writes the *same* datastore as the live
game, so test scores will appear on the real board once it is public.

## Audio

Ten sounds, all from **ProSoundEffects** and **APMOfficial** — Roblox's own
licensed libraries, free to use in any experience. Gunfire, creature growls, a
death scream, an ambient drone, a proximity heartbeat tied to the nearest
entity, an exit radar, pickup clicks and a fanfare.

**Every id was verified against Roblox's asset API before being used** —
confirmed to exist, confirmed to be type 3 (Audio), confirmed to belong to those
libraries. This matters more than it sounds: the previous set were
`rbxasset://sounds/...` paths assumed to ship with the client. They do not
resolve, each became a hanging HTTP request, and a burst weapon firing ten a
second took Studio down. `Config.Audio.Enabled` gates everything, and no `Sound`
is created at all unless its id is non-empty.

## Store art

`assets/branding/` holds the icon, three thumbnails and the generator that draws
them. See the README in that folder — note that Roblox icons and thumbnails are
*experience-level* assets and cannot ship inside the place file.

## Next up

- Level 1: a different generator behind the same exit
- An entity that only moves while unobserved
- Spending the cash on something
