# Skyspire

A 100-floor floating-tower action RPG for Roblox: strict-typed Luau, a Rojo project in git, online co-op for 2 to 8
players, a brutal climb, and a code-driven animation system (Choreo) so every swing is authored as data, reviewed frame
by frame, and never depends on an upload. `docs/GAME_SPEC.md` is the single source of truth; `docs/README.md` indexes
the rest.

The GitHub repository is named `SAOGAME` because that is what its owner called it (`docs/DECISIONS.md` D-001). The
game, every file, every name inside and the store page use Skyspire names only; nothing in the code references the
repo name.

## Quick start

```sh
git clone https://github.com/almuhairimayed8770-byte/SAOGAME.git skyspire
cd skyspire
aftman install                          # or: rokit install  (rojo, wally, selene, stylua, lune, run-in-roblox)
tools/lint.sh                           # what CI runs: format check, lint, Lune tests, validators, rojo build
lune run tests/run.luau                 # the unit suite alone
lune run tools/validate.luau            # data validators + naming blocklist
tools/build-places.sh                   # places/Playground.rbxl, places/ClipLab.rbxl
rojo serve places/Playground.project.json   # then Studio > Plugins > Rojo > Connect
```

`tools/lint.sh --offline` lints `src/` against `tools/lint/roblox-lite.yml` when Selene cannot download the Roblox API
dump. Studio-side steps (plugins, HTTP permission, recording, publishing) are in `docs/STUDIO_TASKS.md`.

## Layout

```
default.project.json   Rojo: src/shared -> ReplicatedStorage.Shared, src/server -> ServerScriptService.Server,
                       src/client -> StarterPlayerScripts.Client
places/                Playground (400-stud field) and ClipLab (clip review scene) projects; .rbxl built, gitignored
src/shared/data/       every number in the game (combat, arts, weapons, enemies, clips budgets, palette, dev tooling...)
src/shared/clips/      Choreo clips: player/<WeaponCategory>/<Clip>.luau, enemy/<Rig>/<Clip>.luau
src/shared/            types.luau, choreo/ (ClipSampler, Pose), net/, util/
src/client/            choreo/, controllers/, camera/, fx/, ui/, audio/, dev/ (Capture, ClipLab, ReviewMarkers)
src/server/            services/, combat/, ai/, world/, anticheat/, dev/ (ClipLab stage)
tools/                 validate.luau + validators/, naming blocklist, PoseEditor plugin, pose-server, assets report,
                       animation-review, smoke.sh, build scripts, lint configs
tests/                 Lune specs (*.spec.luau) and run-in-roblox smoke scripts (tests/smoke)
docs/                  spec, architecture, decisions, progress, placeholders, assets, Studio tasks, review report
```

## Tools

| Command | Does |
| --- | --- |
| `tools/lint.sh [--offline]` | the CI pipeline locally |
| `lune run tests/run.luau [filter]` | Lune unit tests |
| `lune run tools/validate.luau` | data validators and the naming blocklist |
| `tools/build-places.sh` | builds the dev places |
| `tools/build-plugin.sh [--install]` | builds (and installs) the PoseEditor Studio plugin |
| `lune run tools/pose-server.luau [--port N]` | the local server the PoseEditor saves clips through |
| `lune run tools/animation-review.luau [--check]` | regenerates `docs/ANIMATION_REVIEW.md` |
| `lune run tools/assets.luau [--markdown]` | placeholder / missing asset report |
| `tools/smoke.sh [--list] [filter]` | run-in-roblox smoke scripts against the Playground (needs Studio) |

## Branching

`main` is always publishable. One branch per phase, merged after the phase gate (`docs/GAME_SPEC.md` section 20) is met
and tagged with the phase name (`phase-0`, `phase-1`, ...). `docs/PROGRESS.md` holds the current gate checklist.
