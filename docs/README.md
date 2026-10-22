# Skyspire docs

Skyspire is a 100-floor floating-tower action RPG for Roblox: strict-typed Luau, a Rojo project in git, online co-op
for 2 to 8 players, and a code-driven animation system so every swing is authored as data and reviewed frame by frame.
`GAME_SPEC.md` is the single source of truth; everything else here derives from it.

| File | What it is |
| --- | --- |
| [`GAME_SPEC.md`](GAME_SPEC.md) | the spec; read it in full before any work (section 0 says how) |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | module map, entity attributes, clip ids, combat flow, the data tables |
| [`DECISIONS.md`](DECISIONS.md) | every choice made where the spec is silent (D-001 ...) |
| [`PROGRESS.md`](PROGRESS.md) | phase, what shipped per package, stubs, the section 21 gate checklist, perf table, next three tasks |
| [`ANIMATION_REVIEW.md`](ANIMATION_REVIEW.md) | generated: one line per clip (beats, hit-stop, trail timing, problems) plus hand-filled review columns |
| [`PLACEHOLDERS.md`](PLACEHOLDERS.md) | every stand-in asset with its replacement plan |
| [`ASSETS.md`](ASSETS.md) | the asset pipeline and license ledger |
| [`STUDIO_TASKS.md`](STUDIO_TASKS.md) | numbered checklist of everything that needs Roblox Studio by hand |
| [`clips/phase-0/README.md`](clips/phase-0/README.md) | the gate recordings expected for Phase 0 |

## Working on the repo

**Clone and install the tools.** The repository on GitHub keeps the owner's own name for it (D-001); the game,
every file and every name inside is Skyspire. Install [Aftman](https://github.com/LPGhatguy/aftman) or Rokit,
then:

```sh
git clone <repository URL> skyspire
cd skyspire
aftman install        # or: rokit install
```

This installs the pinned `rojo`, `wally`, `selene`, `stylua`, `lune` and `run-in-roblox` (`aftman.toml`). Phase 0
has no Wally packages (D-004), so there is nothing to `wally install`.

**Lint, test, validate, build (what CI runs).**

```sh
tools/lint.sh             # stylua --check, selene, lune tests, validators, rojo build, places
tools/lint.sh --offline   # same, with selene using tools/lint/roblox-lite.yml when the API dump cannot be downloaded
lune run tests/run.luau [filter]      # the Lune unit suite; filter is a path substring (e.g. tests/tools)
lune run tools/validate.luau          # the 28 validators (the naming blocklist among them)
rojo build default.project.json -o build/Skyspire.rbxl
tools/build-places.sh                 # places/Playground.rbxl and places/ClipLab.rbxl (gitignored)
tools/build-plugin.sh                 # build/SkyspirePoseEditor.rbxm, the Studio plugin
```

Formatting is StyLua with the repo `stylua.toml` (tabs, 120 columns); `stylua src tests tools` before a commit.

**Sync with Studio.** `rojo serve places/Playground.project.json` (or `places/ClipLab.project.json`), then in Studio
**Plugins > Rojo > Connect**. `STUDIO_TASKS.md` section B has the full steps.

**Review loop tools** (section 10): the Capture panel in the Playground (`src/client/dev/Capture.client.luau`, on when
the Workspace has the `DevCapture` attribute) prompts the gate shots; the ClipLab (`places/ClipLab.project.json`)
loops any clip at 0.25x / 0.5x / 1x with a frame counter and the six-beat timeline; the PoseEditor plugin
(`tools/PoseEditor`) edits a clip and saves through `lune run tools/pose-server.luau`;
`lune run tools/animation-review.luau` regenerates `ANIMATION_REVIEW.md`; `lune run tools/assets.luau` reports the
placeholders; `tools/smoke.sh` runs the run-in-roblox smoke scripts on a machine with Studio. Every number these tools
use lives in `src/shared/data/dev.luau`.

**Rules that every change follows** (section 19 and `ARCHITECTURE.md`): `--!strict` in every file; every tunable in
`src/shared/data/`; the server owns HP, hits, loot and rolls; no `wait()`; no `Instance.new` in hot loops; no linear
tweens on limbs; one-line doc comments on public functions; no names from the source franchise anywhere (the naming
validator scans the whole repository, docs included).

**Branching.** `main` is always publishable. One branch per phase (`phase-0`, `phase-1`, ...), merged after its gate
is met and the gate tagged with the same name. A gate is met only when every line of the section 21 checklist in
`PROGRESS.md` is true in a recorded clip or a passing test; never drop a checklist line to pass a gate.

**Adding a CI step for the plugin and the review report** (for the integrator): after the "Rojo build (places)" step
in `.github/workflows/ci.yml` add

```yaml
      - name: Rojo build (PoseEditor plugin) and review report check
        run: |
          tools/build-plugin.sh
          lune run tools/animation-review.luau --check
```

`tools/build-plugin.sh` lints the plugin with the offline Roblox globals list; the `--check` fails when
`ANIMATION_REVIEW.md` is stale against the clips.
