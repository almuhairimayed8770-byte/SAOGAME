# Progress

Phase **0: Foundations and the vertical slice (the feel)**. Branch `phase-0`. Last update 2026-10-18.

This file is the one the spec asks for in section 1 ("phase, what shipped, what is stubbed, next three tasks") and
section 21 (the gate checklist, pasted with its results). Everything below was run from a clean clone with the pinned
toolchain (`aftman.toml`). The Studio lines were run on the owner's PC over Remote Control (the run-in-roblox smokes and
an automated solo Play session); every line that still needs a person in Studio says so.

## Shipped, by package

| Package | What is in the tree | Tests |
| --- | --- | --- |
| Foundation | Rojo project (`default.project.json`, `places/`), `aftman.toml` / `rokit.toml`, StyLua + Selene (online and offline configs), GitHub Actions CI, Lune test harness with a virtual DataModel (D-002), `tools/validate.luau` with 25 validators, the naming blocklist (D-014), the phase scope (D-015) | `tests/tools/validators.spec.luau`, `naming.spec.luau` |
| Shared data | 28 tables under `src/shared/data/` (combat, arts, weapons, armor, apex, enemies, bosses, floors, loot, origins, paths, tiers, ai, camera, choreo, fx, input, lighting, palette, playground, rigs, scope, sfx, assets, ui, weaponModels, world, dev), `types.luau`, `util/` (Signal, Spring, Easing, Verlet, Rng, Check) | `tests/data/*`, `tests/util/*` |
| Clips | 64 Choreo clips: 44 `player/OneHandedSword/*` (locomotion in a sheathed and a drawn set, Draw and Sheathe, guard, parry, dodges, flinches, Basic1-3, Horizontal, Vertical, RisingArc, SharpNail, DeathFreeze), 10 `enemy/Boar/*`, 10 `enemy/Kobold/*` | `tests/choreo/clips.spec.luau`, `ClipLibrary.spec.luau`, clips validator |
| Choreo (client) | `ClipSampler` (per-clip structure cache), `Pose`, `Mixer` (layers, pause, time scale, catch-up), `Choreo` (animator per rig, quality tiers, Roblox Animation fallback), `ClipLibrary`, `Locomotion` + `LocomotionState`, the sheathed weapon (`WeaponMount`, `SheathState`, D-050) | `tests/choreo/*` |
| Controllers, camera, net | Input, Character, Target, EntityTracker, Replication (drives every remote rig's locomotion), ActionLogic, WeaponInfo, Siblings; CameraController + CameraMath; `Net` / `Remotes` (D-008) | `tests/client/*`, `tests/net/*` |
| FX | Trails, Smear, Shatter (+ ShatterMath), Sparks, Telegraphs (+ TelegraphShapes), OutlineManager (+ OutlineRanking), Digits, SwitchRing, Quality, FrameClock, Engine | `tests/client/*` |
| UI and audio | `El` component library (D-007), Hud (+ HudLogic), Nameplates, SystemLine; MusicDirector (+ MusicState), SfxPool | `tests/client/*` |
| Server | EntityService, CombatService (DamageMath, HitSweep with the per-sample blade overlap and the arc-following sweep D-010 / D-042 / D-044, the section 17 request checks including the quick-slot check), EnemyService with Brain / Charger / Brute AI, PlaygroundService, AntiCheatService (+ anticheat Rules), world builders (RigBuilder, WeaponBuilder, PlaygroundBuilder, PlaygroundLayout) and CharacterReady (D-046), `Main.server.luau` | `tests/server/*` (with the hit matrix, D-045), `tests/smoke/*.smoke.luau` (six, all pass on the owner's PC) |
| Tools and docs | `Capture.client.luau` (gate shot prompts), the ClipLab (`places/ClipLab.project.json`, `ClipLab.server.luau`, `ClipLab.client.luau`, `ReviewMarkers`), the PoseEditor Studio plugin (`tools/PoseEditor`) with `Serialize` / `Session`, `tools/pose-server.luau`, `tools/assets.luau`, `tools/smoke.sh`, `tools/animation-review.luau`, `tools/hit-matrix.luau`, `tools/build-plugin.sh`, `data/dev.luau`, this docs set | `tests/tools/*` |

Suite at the time of writing: `lune run tests/run.luau` 1051 passed, 0 failed, 77 spec files. `lune run tools/validate.luau`:
25 validators, 0 problems; the clips validator prints one warning for the 160 later-phase clips (66 Arts, 65 enemy
attacks, 29 boss attacks) that are not authored yet and are outside the Phase 0 scope (D-015).
`tools/animation-review.luau` flags no review-rule finding on the 64 clips (9 attacks); the hand-filled columns are
still empty (they come from watching the recordings at 0.25x). `lune run tools/hit-matrix.luau --check`: every real-fight
placement registered on its strike at every frame phase. `tools/lint.sh --offline` (StyLua, Selene, tests, validators, every Rojo build) passes.

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
- Nothing has been published to Roblox. Studio runs on the owner's PC only (the cloud environment has no Studio).

## Review pass (2026-10-17)

Two adversarial review rounds over the whole tree, each finding checked by two independent reviewers
before it was fixed. The fixes that matter most for the gate:

- **Server-to-client remotes work.** `Net.fire` and `fireAll` threw on every call, so no hit,
  telegraph, death or rejection would have reached a client in Studio. `tests/net/Net.spec.luau`
  now covers the send path.
- **The parry sparks** (`fx/Sparks.luau`), enemy directional flinches on every non-lethal hit, the
  death freeze with all sound ducked and the system line after the shatter (D-035).
- **No linear limb blends.** Crossfades are eased and blend-space weights keep summing to 1, so a
  stop no longer dips the pose toward rest (D-032, D-033).
- **Server authority.** The guard cone is judged from the server's root, not the client's facing;
  the 150 ms lag allowance is a bounded time rewind of the hit sweep (D-010); the anti-cheat spends
  its lag budget once instead of per sample (D-034); basic-attack mashing can no longer trip the
  rate limit (D-037).
- **Spec fidelity.** Boar charges are Unblockable red lines (section 9), so the parry beat in the
  gate clip is against the kobold's overhead. Clip sound events name real `sfx.luau` entries and
  are validated (D-036). The repository's GitHub name is kept out of every file (D-001).

## Studio pass on the owner's PC (2026-10-18)

Run over Remote Control: `tools/smoke.sh` (all six smokes) and a solo Play session started from a script through
`StudioTestService`, which reads the player's own character from the client. What it found and what changed:

- **Player rigs have no body Motor6Ds.** Current Studio builds give an R15 character 15 `AnimationConstraint` joints
  (Avatar Joint Upgrade); every rig reader accepts both classes now (D-041).
- **A cast never reports a part it starts inside**, so the first hit of a close strike was lost; the sweep also
  overlap-tests the whole blade at every sample (D-042).
- **Hit windows opened after most of the snap had passed**; every window now opens on its snap's first frame (D-043),
  and the sweep follows the blade's arc between server frames instead of a straight chord (D-044).
- **The gate's "server registered every hit" is a test** now: the hit matrix swings every window against both enemies
  at real fight distances and four frame phases (D-045). It caught the Rising Arc's second hit passing clear and the
  Vertical falling short; both were re-authored.
- **The player's own character never joined the fight**: the server prepared it before the engine had parented and
  dressed it, so it was never registered and its sword fell off. Fixed (D-046); the rerun shows it registered with
  the anime proportions and the sword.
- The combat smoke now also refuses 20 Art repeats while the fighter is locked and a forged request carrying a target
  field; the perf smoke has the eight stand-ins swinging Arts the whole sample.
- **The sword went into the ground** in 19 player clips (a new 240 Hz spec, D-047): Idle, the four walks, both turns,
  Run, Sprint, Skid, Jump, Land, both forward and right dodges, Guard Break, Basic 3, Sharp Nail, Vertical and Rising
  Arc. Only joint rotations changed (no times, easings, events or windows), and the hit matrix stays green; the one
  new miss, Rising Arc hit 1 at the boar facing 11.5 studs away, is outside the real-fight range.
- A second adversarial pass over the sweep fixed one bug (a window closing inside a frame solved its last sample from
  where the body went on to) and corrected the cost and margin claims in D-044.
- **Sweep hardening** after that pass: a root that jumps (a teleport, a snap back) is no longer swept across (D-048);
  teammates, the attacker and dead enemies no longer use up the target cap (D-049); joints are read once per fighter
  per frame, which pays for raising the arc sub-sample cap from 4 to 12 (D-044). Studio perf rerun with cap 12 on the
  owner's PC: server work p95 2.01 ms (2.72 before), so the cap stays at 12.
  Known and older: a server hitch of 0.25 s that lands a basic swing past its 0.35 s Art state loses that window (34 of
  14,400 hitch swings in a Lune study).

- **The sword is sheathed on the back out of combat** (D-050): a placeholder scabbard across the back, a server-owned
  `Drawn` attribute from the combat tag (the server's sword never leaves the hand, so hits are unchanged), Draw and
  Sheathe clips that only move the sword where the hand is, draw-cuts for attacks, guard and parry, and a sheathed
  locomotion set (empty hands; the anime run with both arms pumping) next to the drawn set (renamed `…Drawn`). Walked
  end to end in Lune (spawn, Art draw-cut, tag expiry, lock-on, a remote copy, a hit taken, respawn, the ClipLab).
  Three adversarial passes fixed: the sword jumping 2.75 studs when a turn, jump or stagger hid the Draw's arm; a
  stopped Draw's late event moving the sword; per-frame part and attribute lookups; footsteps from every walk at weight
  0 (332 events in 10 s standing still, now 0; D-051); the hilt up to 0.28 stud into the head and the left hand into
  the scabbard in the sheathed set; the blade cutting through the scabbard wall on the pull. GroundClearance now also
  checks the handoff, the sheathed set against the body and the pull along the sheath. The rigs and combat smokes check
  the scabbard and `Drawn`.

## Play-test on the owner's PC (2026-10-20)

A real Play session on build 927dbed, driven through Studio's own assistant connection over Remote Control, with the
game window rendering. What it found and what changed:

- **The character never moved its limbs in Play.** Every joint read at rest on RenderStepped and Heartbeat, so the feet
  stayed flat and slid at the body's speed (walk 7.5, run 16, sprint 24 studs a second, no lift). The character's
  engine `Animator` puts every joint back to rest after RenderStepped, even with no track playing; a Transform written
  on PreSimulation holds, and with the Animator removed Choreo's own pose showed. Choreo now writes the pose again on
  PreSimulation for any rig with an Animator (D-053). The Lune runs and the ClipLab never saw it: neither has one.
- **An honest sprint was kicked.** After 15 s at exactly the cap the anti-cheat had 12 flags such as 6.5 studs against
  6.4 allowed and kicked. The speed check now allows the cap times 1.1 (D-052).
- **Frame rate:** 59.9 fps standing and running (the frame cap is 60; p95 17.6 ms, max 18.7 ms), render CPU 1.7 to
  1.8 ms, GPU 0.5 to 0.6 ms, with the enemies 66+ studs away. Memory read 2.7 GB, the whole Studio process.
- **The sheath** sits where it should and turns rigidly with the body, but on this avatar the grip and guard reach up
  to 0.16 stud into the head box and into the hat brim; the mount move under way fixes that.
- Still to check in Play once both fixes are in: the legs pose and the feet lift, a long sprint is not flagged, and the
  draw on lock-on (STUDIO_TASKS items 34 to 36).

## Known review items for the Studio pass

- The sheathed sword at 0.25x in the ClipLab: Draw and Sheathe (the hand meets the hilt at 0.22 s and 0.42 s; the last
  2 studs of blade leave the sheath by swinging over the top in about 2 frames at 1x, so judge whether that reads as a
  whip or a glitch), the hilt behind the head with a real avatar's hair, and whether the scabbard's lower end visibly
  enters the hips on drawn-set waist twists (up to 0.18 stud on the test body's boxes).
- The shared one-shots (turns, jump, fall, land, skid, dodges, stagger) key a sword grip, so while sheathed they show a
  gripping empty hand; sheathed twins are later work.

- At 0.25x: no blade in the grass anywhere (D-047 checks the blank avatar on a flat field); the hilt should not read as
  entering the thigh in Basic 3 at 0.15 s and Sharp Nail at 0.58 s (on the blank avatar's boxes the grip sits as deep
  as the hand already does); the Rising Arc's sword arm should read clear of the torso in its crossed start pose.
- Kobold `Overhead` holds the raised axe for 1.3 s while the telegraph light goes out at the 1.0 s wind-up and the
  blade lands at 1.35 s (wind-up + strike, as the server times it). The clip is consistent with the server; judge at
  0.25x whether the swing should begin the moment the light goes out.
- Rising Arc smear planes (X on the rising diagonal, Y on the overhead flick) and the heels coming down at 0.9 s.
- Section 8 startups below 0.25 s for later weapon lines are kept verbatim (D-020); nothing in Phase 0 uses them.
- A Basic swing's trail goes out about two frames before the clip's `TrailOff`, because its hit window closing
  turns the Basic trail kind off; judge at 0.25x whether the tail reads short.
- Each guard tap sends two `GuardRequest`s, so tapping guard faster than six times a second for a few seconds
  would trip that remote's rate limit. Parry spam gains nothing past the 0.25 s re-arm (D-031); raise
  `remoteRates.GuardRequest` in `world.luau` if play-testing shows honest players reaching it.

## Phase 0 gate (section 20) and the section 21 checklist

Gate: *a 20-second clip of a player fighting a boar and a kobold where every attack shows the six beats, the parry
sparks, the kill shatters, and the server registered every hit; 60 fps in Studio; all tests green.*

| Part of the gate sentence | State |
| --- | --- |
| The 20-second fight: six beats on every attack, the parry sparks, the kill shatters | Needs the owner's recording (`fight-boar-kobold.mp4`) |
| The server registered every hit | **Met** in the hit matrix (every window, both enemies, real fight distances, four frame phases; D-045) and in `combat.smoke` in Studio; the recording shows it again as a digit per hit |
| 60 fps in Studio | **Partly met**: 59.9 fps in Play with the window rendering on the owner's PC (2026-10-20, frame cap 60, p95 17.6 ms), standing and running with the enemies 66+ studs away; still to read during the recorded fight (**View > Stats**) |
| All tests green | **Met** (1051 tests, 25 validators, six smokes in Studio, CI) |

| Line | State | Evidence / what is missing |
| --- | --- | --- |
| CI is green: StyLua, Selene, Lune tests, data validators, naming blocklist, `rojo build` | **Met** | GitHub Actions run 39462350246 on `phase-0` (open it from the repository's Actions tab) (format, Selene with the real Roblox std, 1051 tests, 25 validators, the review-report check, the game, both places and the plugin build). `tools/lint.sh --offline` reproduces every step except Selene's Roblox-only lints, which need the API dump; those run only in CI. `aftman.toml` pins the tool versions. |
| Every new clip is in `docs/ANIMATION_REVIEW.md` with the six beats marked present and the hit-stop tier noted | **Met** (generated), hand columns empty | All 64 clips are in the table; 9 attacks show the six beats and a tier. The three hand-filled columns need the ClipLab pass in Studio. |
| A recorded clip for every new Art, enemy and boss phase exists in `docs/clips/` and was watched at 0.25x | **Needs the owner's recordings** | `docs/clips/phase-0/README.md` lists the ten files the Capture panel prompts for. None recorded yet; each is reviewed frame by frame once it is in the repository. |
| No T-pose, A-pose, frozen rig, popping limb or sliding foot appears in any clip | **Needs the owner's recordings** | Judged from the recordings. Before D-053 the local character stood frozen in Play with its feet sliding (the engine's Animator reset every pose); the Play re-check is STUDIO_TASKS item 34. Remote rigs now walk (Replication drives their locomotion) and the root motor name matches the live R15 rig (D-016), the two defects a reviewer would have seen first. |
| Every enemy attack has a wind-up of at least 0.3 s with a colored telegraph that reads from behind | **Met in data**, seen in the recordings | `enemies.luau` wind-ups (boar 0.6 s, kobold 1.0 s) and the clips validator's Anticipation-covers-windUp check pass; Telegraphs FX exist. |
| The server rejects a scripted client that spams Arts, teleports, or reports its own hits | **Met** | `CombatService` validates every request (section 17 list, including the quick slot), `AntiCheatService` + `anticheat/Rules` and the Net rate limits have Lune specs; clients never send hits (the server sweeps). In Studio on the owner's PC: `combat.smoke` refuses 20 Art repeats while locked (one hit lands) and a forged request with a target field, and no client remote is named for hits or damage; `playground.smoke` shadow-flags and then kicks a teleporting stand-in. The smokes drive the same request checks the remotes call, from the server. |
| Part count, draw calls, server heartbeat and memory are measured in the Playground and within section 16 | **Partly met** | Part count and server frame time measured and well inside the targets (table below). Client fps, draw calls and client memory need Play mode with the game window rendering, read by hand while recording. |
| `docs/PLACEHOLDERS.md` lists every stand-in asset with a replacement plan | **Met** | Written from `tools/assets.luau` plus the dev-scene stand-ins. |
| `docs/STUDIO_TASKS.md` lists every manual Studio step with exact menu paths | **Met** (paths marked "(verify)" where unsure) | |
| Every number introduced this phase lives in `src/shared/data/`, not in a script | **Met** | `numbers` validator green over every gameplay directory; dev tooling numbers live in `data/dev.luau`. |
| Every new name passed the blocklist and is in the section 4 table or an addendum | **Met** | `naming` validator green over the whole repo (D-014, D-030). |
| The phase's story and quest text was read aloud and no line took over four seconds | **Not applicable** | Phase 0 has no story text. |

### Performance (section 16 targets; fill in from the Playground place)

| Measure | Target | Measured | Where / how |
| --- | --- | --- | --- |
| Frame rate, mid-range PC, 8 players + 30 enemies on screen | 60 fps | 59.9 fps with one player and the five Playground enemies 66+ studs away (p95 17.6 ms, max 18.7 ms; the frame cap is 60), 2026-10-20; the 8 + 30 case is still to measure | Play on the owner's PC with the window rendering, client frame times read every RenderStepped; then View > Stats > Summary (verify) in a full test |
| Frame rate, 2020 phone | 30 fps | | device test |
| Parts loaded | under 60,000 | 1,158 BaseParts in workspace (Stats.PrimitivesCount max 1,173) | `tools/smoke.sh perf` on the owner's PC, 2026-10-18: 8 stand-ins with swords, 60 enemies, server only |
| Draw calls | under 1,500 | not exposed to scripts; render CPU 1.67 to 1.80 ms, GPU 0.51 to 0.57 ms per frame in the same Play test | MicroProfiler (Ctrl+F6) render thread (verify) |
| Server heartbeat with 8 players and 60 enemies | under 12 ms | p95 2.72 ms, mean 1.68 ms, max 8.27 ms (timed server work per frame over 1,198 frames, 59.9 steps/s); Stats.HeartbeatTime p95 0.62 ms. With the stand-ins idle: p95 1.77 ms. Rerun after the sub-sample cap rose to 12 (D-044): p95 2.01 ms | `tools/smoke.sh perf` on the owner's PC, 2026-10-18: 8 registered stand-ins swinging Arts back to back (142 Arts, 565 hits on enemies; the arc sweep of D-044 included), 60 enemies winding up and striking (94 hits on the stand-ins), server only. Recheck with real players in a test server (F9 > Server > ServerJobs) |
| Memory, PC | under 1.2 GB | not yet: 1,909 MB (Run) and 2,709 to 2,751 MB (Play, 2026-10-20) are the whole Studio process, server and client together | read a client in Play mode (View > Stats > Memory) or a live server |
| Memory, mobile | under 600 MB | | device test |

## Next three tasks

1. The owner records the ten gate shots in the Playground with the Capture panel (`docs/clips/phase-0/README.md`), with
   **View > Stats** open during the fight for the fps reading, and hands the files over (here in the project or in
   `docs/clips/phase-0/` on the PC).
2. Review every recording frame by frame at 0.25x, fill the hand columns of `docs/ANIMATION_REVIEW.md`, and fix with the
   PoseEditor anything that reads wrong (that shot is then recorded again).
3. Fill the client rows of the performance table, then merge `phase-0` into `main` and tag it once every gate line reads
   Met.

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
| `docs/clips/phase-0/parry-spark.mp4` | 5 s | guard tapped inside the window against the kobold's overhead (the boar's charge is unblockable); spark and ring; the enemy staggers |
| `docs/clips/phase-0/kill-shatter.mp4` | 5 s | the 10-frame kill hit-stop, the 0.5 s freeze and silence, the shards rising |
| `docs/clips/phase-0/locomotion.mp4` | 14 s | sheathed: walk, run, sprint with the sword on the back; lock on to draw; drawn: walk, run, sprint with the blade low and back; turn in place, skid stop, jump and land; no T-pose, no sliding foot |
