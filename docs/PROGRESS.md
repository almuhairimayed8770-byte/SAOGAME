# Progress

Phase **0: Foundations and the vertical slice (the feel)**. Branch `phase-0`. Last update 2026-10-17.

This file is the one the spec asks for in section 1 ("phase, what shipped, what is stubbed, next three tasks") and
section 21 (the gate checklist, pasted with its results). Everything below was run from a clean clone with the pinned
toolchain (`aftman.toml`); nothing has run inside Roblox Studio yet, and every line that needs Studio says so.

## Shipped, by package

| Package | What is in the tree | Tests |
| --- | --- | --- |
| Foundation | Rojo project (`default.project.json`, `places/`), `aftman.toml` / `rokit.toml`, StyLua + Selene (online and offline configs), GitHub Actions CI, Lune test harness with a virtual DataModel (D-002), `tools/validate.luau` with 24 validators, the naming blocklist (D-014), the phase scope (D-015) | `tests/tools/validators.spec.luau`, `naming.spec.luau` |
| Shared data | 28 tables under `src/shared/data/` (combat, arts, weapons, armor, apex, enemies, bosses, floors, loot, origins, paths, tiers, ai, camera, choreo, fx, input, lighting, palette, playground, rigs, scope, sfx, assets, ui, weaponModels, world, dev), `types.luau`, `util/` (Signal, Spring, Easing, Verlet, Rng, Check) | `tests/data/*`, `tests/util/*` |
| Clips | 56 Choreo clips: 36 `player/OneHandedSword/*` (locomotion, guard, parry, dodges, flinches, Basic1-3, Horizontal, Vertical, RisingArc, SharpNail, DeathFreeze), 10 `enemy/Boar/*`, 10 `enemy/Kobold/*` | `tests/choreo/clips.spec.luau`, `ClipLibrary.spec.luau`, clips validator |
| Choreo (client) | `ClipSampler` (per-clip structure cache), `Pose`, `Mixer` (layers, pause, time scale, catch-up), `Choreo` (animator per rig, quality tiers, Roblox Animation fallback), `ClipLibrary`, `Locomotion` + `LocomotionState` | `tests/choreo/*` |
| Controllers, camera, net | Input, Character, Target, EntityTracker, Replication (drives every remote rig's locomotion), ActionLogic, WeaponInfo, Siblings; CameraController + CameraMath; `Net` / `Remotes` (D-008) | `tests/client/*`, `tests/net/*` |
| FX | Trails, Smear, Shatter (+ ShatterMath), Telegraphs (+ TelegraphShapes), OutlineManager (+ OutlineRanking), Digits, SwitchRing, Quality, FrameClock, Engine | `tests/client/*` |
| UI and audio | `El` component library (D-007), Hud (+ HudLogic), Nameplates, SystemLine; MusicDirector (+ MusicState), SfxPool | `tests/client/*` |
| Server | EntityService, CombatService (DamageMath, HitSweep D-010, the section 17 request checks including the quick-slot check), EnemyService with Brain / Charger / Brute AI, PlaygroundService, AntiCheatService (+ anticheat Rules), world builders (RigBuilder, WeaponBuilder, PlaygroundBuilder, PlaygroundLayout), `Main.server.luau` | `tests/server/*`, `tests/smoke/*.smoke.luau` (need Studio) |
| Tools and docs | `Capture.client.luau` (gate shot prompts), the ClipLab (`places/ClipLab.project.json`, `ClipLab.server.luau`, `ClipLab.client.luau`, `ReviewMarkers`), the PoseEditor Studio plugin (`tools/PoseEditor`) with `Serialize` / `Session`, `tools/pose-server.luau`, `tools/assets.luau`, `tools/smoke.sh`, `tools/animation-review.luau`, `tools/build-plugin.sh`, `data/dev.luau`, this docs set | `tests/tools/*` |

Suite at the time of writing: `lune run tests/run.luau` 741 passed, 0 failed, 65 spec files. `lune run tools/validate.luau`:
24 validators, 0 problems; the clips validator prints one warning for the 160 later-phase clips (66 Arts, 65 enemy
attacks, 29 boss attacks) that are not authored yet and are outside the Phase 0 scope (D-015).
`tools/animation-review.luau` flags no review-rule finding on the 56 clips (9 attacks); the hand-filled columns are
still empty (no Studio pass yet). `tools/lint.sh --offline` (StyLua, Selene, tests, validators, every Rojo build) passes.

## Stubbed or not started

- Everything in `docs/PLACEHOLDERS.md`: every mesh, texture, font and sound id is 0 (part-built rigs, blade-shaped
  weapon parts, flat telegraph parts, Trails without a texture, silent SFX, Gotham / Garamond fallback fonts).
- The IK layer (feet on stairs, hands on grips) and procedural cloth: `util/Verlet.luau` exists, no coat chain uses it.
- The Roblox `Animation` fallback path in Choreo is written but no clip uses an `rbxassetid://` id yet.
- Server: no saves (ProfileStore), party, Switch, Tempo / Guard Gauge break, loot drops in the world, quests, market,
  housing, weather, world clock, teleports, Floor Generator (`src/server/gen/` is empty). Phase 1 and later.
- Boss fights: `bosses.luau` holds the data; no BossService, no `Boss` attribute for the nameplates yet (Phase 3).
- Wally: zero packages by design (D-004); `wally.toml` lists the planned ones commented out.
- Mobile layout and touch controls: the data (`input.luau` touch buttons) exists; no layout pass has been made.
- Nothing has been published to Roblox; nothing has run inside Studio from this environment (no Studio here).

## Known review items for the Studio pass

- Kobold `Overhead` holds the raised axe for 1.3 s while the telegraph light goes out at the 1.0 s wind-up and the
  blade lands at 1.35 s (wind-up + strike, as the server times it). The clip is consistent with the server; judge at
  0.25x whether the swing should begin the moment the light goes out.
- Rising Arc smear planes (X on the rising diagonal, Y on the overhead flick) and the heels coming down at 0.9 s.
- Section 8 startups below 0.25 s for later weapon lines are kept verbatim (D-020); nothing in Phase 0 uses them.

## Phase 0 gate (section 20) and the section 21 checklist

Gate: *a 20-second clip of a player fighting a boar and a kobold where every attack shows the six beats, the parry
sparks, the kill shatters, and the server registered every hit; 60 fps in Studio; all tests green.*

| Line | State | Evidence / what is missing |
| --- | --- | --- |
| CI is green: StyLua, Selene, Lune tests, data validators, naming blocklist, `rojo build` | **Met** | GitHub Actions run [39006502106](https://github.com/almuhairimayed8770-byte/SAOGAME/actions/runs/39006502106) on `phase-0` (format, Selene with the real Roblox std, 741 tests, 24 validators, the review-report check, the game, both places and the plugin build). `tools/lint.sh --offline` reproduces every step except Selene's Roblox-only lints, which need the API dump; those run only in CI. `aftman.toml` pins the tool versions. |
| Every new clip is in `docs/ANIMATION_REVIEW.md` with the six beats marked present and the hit-stop tier noted | **Met** (generated), hand columns empty | All 56 clips are in the table; 9 attacks show the six beats and a tier. The three hand-filled columns need the ClipLab pass in Studio. |
| A recorded clip for every new Art, enemy and boss phase exists in `docs/clips/` and was watched at 0.25x | **Needs Studio** | `docs/clips/phase-0/README.md` lists the ten files the Capture panel prompts for. None recorded yet. |
| No T-pose, A-pose, frozen rig, popping limb or sliding foot appears in any clip | **Needs Studio** | Judged from the recordings. Remote rigs now walk (Replication drives their locomotion) and the root motor name matches the live R15 rig (D-016), the two defects a reviewer would have seen first. |
| Every enemy attack has a wind-up of at least 0.3 s with a colored telegraph that reads from behind | **Met in data, needs Studio to see** | `enemies.luau` wind-ups (boar 0.6 s, kobold 1.0 s) and the clips validator's Anticipation-covers-windUp check pass; Telegraphs FX exist. |
| The server rejects a scripted client that spams Arts, teleports, or reports its own hits | **Met in tests**, smoke pending | `CombatService` validates every request (section 17 list, including the quick slot), `AntiCheatService` + `anticheat/Rules` and the Net rate limits have Lune specs; clients never send hits (the server sweeps). The run-in-roblox smoke needs Studio. |
| Part count, draw calls, server heartbeat and memory are measured in the Playground and within section 16 | **Needs Studio** | Table below is empty until someone runs the MicroProfiler and Stats in the Playground. |
| `docs/PLACEHOLDERS.md` lists every stand-in asset with a replacement plan | **Met** | Written from `tools/assets.luau` plus the dev-scene stand-ins. |
| `docs/STUDIO_TASKS.md` lists every manual Studio step with exact menu paths | **Met** (paths marked "(verify)" where unsure) | |
| Every number introduced this phase lives in `src/shared/data/`, not in a script | **Met** | `numbers` validator green over every gameplay directory; dev tooling numbers live in `data/dev.luau`. |
| Every new name passed the blocklist and is in the section 4 table or an addendum | **Met** | `naming` validator green over the whole repo (D-014, D-030). |
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

1. Build `places/Playground.rbxl` and `places/ClipLab.rbxl`, open them in Studio, record the ten gate shots with the
   Capture panel (`P` starts the countdown) and watch every attack in the ClipLab at 0.25x; fill the hand columns of
   `docs/ANIMATION_REVIEW.md`. Anything that reads wrong at 0.25x is fixed with the PoseEditor, then the report is
   regenerated (`lune run tools/animation-review.luau`).
2. Run `tools/smoke.sh` on a machine with Studio; measure the section 16 numbers in the Playground and fill the table
   above.
3. Upload the first real assets or confirm the placeholders for the gate (every row in `PLACEHOLDERS.md` has a plan);
   merge `phase-0` into `main` and tag it once every gate line reads Met.

## Expected gate recordings

`data/dev.luau` `capture.shots`, saved by the reviewer to the path the panel shows:

| File | Length | Must show |
| --- | --- | --- |
| `docs/clips/phase-0/fight-boar-kobold.mp4` | 20 s | one boar and one kobold; every attack shows the six beats; a parry spark; a kill shatter; a digit per registered hit |
| `docs/clips/phase-0/art-horizontal.mp4` | 5 s | start pose, activation glow, anticipation, snap, smear, hold, settle, post-motion |
| `docs/clips/phase-0/art-vertical.mp4` | 5 s | the overhead cut; gauge-heavy hit; same six beats |
| `docs/clips/phase-0/art-sharp-nail.mp4` | 5 s | three hits, three hit-stops, the trail on only in the windows |
| `docs/clips/phase-0/art-rising-arc.mp4` | 5 s | the sunken start pose, the rise onto the toes, two hits with Normal then Final hit-stop, the trail on only in the windows |
| `docs/clips/phase-0/enemy-boar-charge.mp4` | 5 s | 0.6 s crouch with the red line, the launch, the skid, readable from behind |
| `docs/clips/phase-0/enemy-kobold-overhead.mp4` | 5 s | 1.0 s wind-up with the yellow edge, the chop, the recovery |
| `docs/clips/phase-0/parry-spark.mp4` | 5 s | guard tapped inside the window; spark and ring; the enemy staggers |
| `docs/clips/phase-0/kill-shatter.mp4` | 5 s | the 10-frame kill hit-stop, the 0.5 s freeze and silence, the shards rising |
| `docs/clips/phase-0/locomotion.mp4` | 10 s | walk, run, sprint drawn and sheathed, turn in place, skid stop, jump and land; no T-pose, no sliding foot |
