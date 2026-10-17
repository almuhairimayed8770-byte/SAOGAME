# Progress

Phase **0: Foundations and the vertical slice (the feel)**. Branch `phase-0`. Last update 2026-10-17.

This file is the one the spec asks for in section 1 ("phase, what shipped, what is stubbed, next three tasks") and
section 21 (the gate checklist, pasted with its results). Packages were written in parallel by separate agents on the
same branch; a line marked *(integrator: confirm)* was read from the tree, not run end to end by the package that
wrote this file.

## Shipped, by package

| Package | What is in the tree | Tests |
| --- | --- | --- |
| Foundation | Rojo project (`default.project.json`, `places/`), `aftman.toml` / `rokit.toml`, StyLua + Selene (online and offline configs), GitHub Actions CI, Lune test harness with a virtual DataModel (D-002), `tools/validate.luau` with 23 validators, the naming blocklist (D-014) | `tests/tools/validators.spec.luau`, `naming.spec.luau` |
| Shared data | 25 tables under `src/shared/data/` (combat, arts, weapons, armor, apex, enemies, bosses, floors, loot, origins, paths, tiers, ai, camera, choreo, fx, input, lighting, palette, playground, rigs, sfx, assets, ui, weaponModels, world, dev), `types.luau`, `util/` (Signal, Spring, Easing, Verlet, Rng, Check) | `tests/data/*`, `tests/util/*` |
| Clips | 55 Choreo clips: 35 `player/OneHandedSword/*` (locomotion, guard, parry, dodges, flinches, Basic1-3, Horizontal, Vertical, SharpNail, DeathFreeze), 10 `enemy/Boar/*`, 10 `enemy/Kobold/*` | `tests/choreo/clips.spec.luau`, clips validator |
| Choreo (client) | `ClipSampler`, `Pose`, `Mixer` (layers, pause, time scale, catch-up), `Choreo` (animator per rig, quality tiers, Roblox Animation fallback), `ClipLibrary`, `Locomotion` + `LocomotionState` | `tests/choreo/*` |
| Controllers, camera, net | Input, Character, Target, EntityTracker, Replication, ActionLogic, WeaponInfo, Siblings; CameraController + CameraMath; `Net` / `Remotes` (D-008) | `tests/client/*`, `tests/net/*` |
| FX | Trails, Smear, Shatter (+ ShatterMath), Telegraphs (+ TelegraphShapes), OutlineManager (+ OutlineRanking), Digits, SwitchRing, Quality, FrameClock, Engine | `tests/client/*` |
| UI and audio | `El` component library (D-007), Hud (+ HudLogic), Nameplates, SystemLine; MusicDirector (+ MusicState), SfxPool | `tests/client/*` |
| Server | EntityService, CombatService (DamageMath, HitSweep D-010), EnemyService with Brain / Charger / Brute AI, PlaygroundService, AntiCheatService (+ anticheat Rules), world builders (RigBuilder, WeaponBuilder, PlaygroundBuilder, PlaygroundLayout), `Main.server.luau` *(integrator: confirm the anticheat and playground smoke are complete)* | `tests/server/*`, `tests/smoke/*.smoke.luau` |
| Tools and docs (this package) | `Capture.client.luau` (gate shot prompts), the ClipLab (`places/ClipLab.project.json`, `ClipLab.server.luau`, `ClipLab.client.luau`, `ReviewMarkers`), the PoseEditor Studio plugin (`tools/PoseEditor`) with `Serialize` / `Session`, `tools/pose-server.luau`, `tools/assets.luau`, `tools/smoke.sh`, `tools/animation-review.luau`, `tools/build-plugin.sh`, `data/dev.luau`, this docs set | `tests/tools/Serialize.spec.luau`, `PoseSession.spec.luau`, `ReviewMarkers.spec.luau` |

Suite at the time of writing: `lune run tests/run.luau` 706 passed, 0 failed, 64 spec files. `lune run tools/validate.luau`:
22 of 23 validators green; the clips validator reports 132 problems, every one a *missing clip file* for an Art or an
enemy that belongs to a later phase (floors 2 to 10, the other weapon categories). No Phase 0 clip has a validator
problem. `tools/animation-review.luau` flags no review-rule finding on the 55 clips (8 attacks); the hand-filled
columns are still empty (no Studio pass yet).

## Stubbed or not started

- Everything in `docs/PLACEHOLDERS.md`: every mesh, texture, font and sound id is 0 (part-built rigs, blade-shaped
  weapon parts, flat telegraph parts, Trails without a texture, silent SFX, Gotham / Garamond fallback fonts).
- The IK layer (feet on stairs, hands on grips) and procedural cloth: `util/Verlet.luau` exists, no coat chain uses it.
- The Roblox `Animation` fallback path in Choreo is written but no clip uses an `rbxassetid://` id yet.
- Server: no saves (ProfileStore), party, Switch, Tempo / Guard Gauge break, loot drops in the world, quests, market,
  housing, weather, world clock, teleports, Floor Generator (`src/server/gen/` is empty). Phase 1 and later.
- Wally: zero packages by design (D-004); `wally.toml` lists the planned ones commented out.
- Mobile layout and touch controls: the data (`input.luau` touch buttons) exists; no layout pass has been made.
- Nothing has been published to Roblox; nothing has run inside Studio from this environment (no Studio here).

## Phase 0 gate (section 20) and the section 21 checklist

Gate: *a 20-second clip of a player fighting a boar and a kobold where every attack shows the six beats, the parry
sparks, the kill shatters, and the server registered every hit; 60 fps in Studio; all tests green.*

| Line | State | Evidence / what is missing |
| --- | --- | --- |
| CI is green: StyLua, Selene, Lune tests, data validators, naming blocklist, `rojo build` | **Not met** | Selene (offline), Lune tests, naming and `rojo build` (game, both places, the plugin) pass locally. `stylua --check` still fails on two sibling files (`src/shared/data/rigs.luau`, `src/shared/choreo/ClipSampler.luau`; one `stylua` run fixes them). `tools/validate.luau` exits 1 because the clips validator lists the later-phase clips as missing *(integrator: confirm whether CI scopes that validator to Phase 0 content or the gate accepts the known list)*. |
| Every new clip is in `docs/ANIMATION_REVIEW.md` with the six beats marked present and the hit-stop tier noted | **Met** (generated), hand columns empty | All 55 clips are in the table; 8 attacks show the six beats and a tier. The three hand-filled columns need the ClipLab pass in Studio. |
| A recorded clip for every new Art, enemy and boss phase exists in `docs/clips/` and was watched at 0.25x | **Needs Studio** | `docs/clips/phase-0/README.md` lists the nine files the Capture panel prompts for. None recorded yet. |
| No T-pose, A-pose, frozen rig, popping limb or sliding foot appears in any clip | **Needs Studio** | Judged from the recordings. |
| Every enemy attack has a wind-up of at least 0.3 s with a colored telegraph that reads from behind | **Met in data, needs Studio to see** | `enemies.luau` wind-ups (boar 0.6 s, kobold 1.0 s) and the clips validator's Anticipation-covers-windUp check pass; Telegraphs FX exist. |
| The server rejects a scripted client that spams Arts, teleports, or reports its own hits | **Met in tests** *(integrator: confirm)* | `AntiCheatService` + `anticheat/Rules` and the Net rate limits have Lune specs; the run-in-roblox smoke needs Studio. |
| Part count, draw calls, server heartbeat and memory are measured in the Playground and within section 16 | **Needs Studio** | Table below is empty until someone runs the MicroProfiler and Stats in the Playground. |
| `docs/PLACEHOLDERS.md` lists every stand-in asset with a replacement plan | **Met** | Written from `tools/assets.luau` plus the dev-scene stand-ins. |
| `docs/STUDIO_TASKS.md` lists every manual Studio step with exact menu paths | **Met** (paths marked "(verify)" where unsure) | |
| Every number introduced this phase lives in `src/shared/data/`, not in a script | **Met** | `numbers` validator green; the dev tooling numbers live in `data/dev.luau`. |
| Every new name passed the blocklist and is in the section 4 table or an addendum | **Met** | `naming` validator green over the whole repo. |
| The phase's story and quest text was read aloud and no line took over four seconds | **Not applicable** | Phase 0 has no story text. |

### Performance (section 16 targets; fill in from the Playground place)

| Measure | Target | Measured | Where / how |
| --- | --- | --- | --- |
| Frame rate, mid-range PC, 8 players + 30 enemies on screen | 60 fps | | Studio play test, View > Stats > Summary (verify) |
| Frame rate, 2020 phone | 30 fps | | device test |
| Parts loaded | under 60,000 | | View > Stats > Render: instance / part count (verify) |
| Draw calls | under 1,500 | | MicroProfiler (Ctrl+F6) render thread (verify) |
| Server heartbeat with 8 players and 60 enemies | under 12 ms | | Developer Console (F9) > Server > ServerJobs Heartbeat (verify) |
| Memory, PC | under 1.2 GB | | View > Stats > Memory |
| Memory, mobile | under 600 MB | | device test |

## Next three tasks

1. Build `places/Playground.rbxl` and `places/ClipLab.rbxl`, open them in Studio, record the nine gate shots with the
   Capture panel (`P` starts the countdown) and watch every attack in the ClipLab at 0.25x; fill the hand columns of
   `docs/ANIMATION_REVIEW.md`. Anything that reads wrong at 0.25x is fixed with the PoseEditor, then the report is
   regenerated (`lune run tools/animation-review.luau`).
2. Run `tools/smoke.sh` on a machine with Studio; measure the section 16 numbers in the Playground and fill the table
   above. Decide (and record in `DECISIONS.md`) how CI treats the clips validator's later-phase "missing clip" list.
3. Upload the first real assets or confirm the placeholders for the gate (every row in `PLACEHOLDERS.md` has a plan);
   tag `phase-0` once every gate line reads Met.

## Expected gate recordings

`data/dev.luau` `capture.shots`, saved by the reviewer to the path the panel shows:

| File | Length | Must show |
| --- | --- | --- |
| `docs/clips/phase-0/fight-boar-kobold.mp4` | 20 s | one boar and one kobold; every attack shows the six beats; a parry spark; a kill shatter; a digit per registered hit |
| `docs/clips/phase-0/art-horizontal.mp4` | 5 s | start pose, activation glow, anticipation, snap, smear, hold, settle, post-motion |
| `docs/clips/phase-0/art-vertical.mp4` | 5 s | the overhead cut; gauge-heavy hit; same six beats |
| `docs/clips/phase-0/art-sharp-nail.mp4` | 5 s | three hits, three hit-stops, the trail on only in the windows |
| `docs/clips/phase-0/enemy-boar-charge.mp4` | 5 s | 0.6 s crouch with the red line, the launch, the skid, readable from behind |
| `docs/clips/phase-0/enemy-kobold-overhead.mp4` | 5 s | 1.0 s wind-up with the yellow edge, the chop, the recovery |
| `docs/clips/phase-0/parry-spark.mp4` | 5 s | guard tapped inside the window; spark and ring; the enemy staggers |
| `docs/clips/phase-0/kill-shatter.mp4` | 5 s | the 10-frame kill hit-stop, the 0.5 s freeze and silence, the shards rising |
| `docs/clips/phase-0/locomotion.mp4` | 10 s | walk, run, sprint drawn and sheathed, turn in place, skid stop, jump and land; no T-pose, no sliding foot |
