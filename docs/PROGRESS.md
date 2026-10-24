# Progress

Phase **0: Foundations and the vertical slice (the feel)**. Branch `phase-0`. Last update 2026-10-22 (6e0fd5e).

This file is the one the spec asks for in section 1 ("phase, what shipped, what is stubbed, next three tasks") and
section 21 (the gate checklist, pasted with its results). Everything below was run from a clean clone with the pinned
toolchain (`aftman.toml`). The Studio lines were run on the owner's PC over Remote Control (the run-in-roblox smokes and
an automated solo Play session); every line that still needs a person in Studio says so.

## Shipped, by package

| Package | What is in the tree | Tests |
| --- | --- | --- |
| Foundation | Rojo project (`default.project.json`, `places/`), `aftman.toml` / `rokit.toml`, StyLua + Selene (online and offline configs), GitHub Actions CI, Lune test harness with a virtual DataModel (D-002), `tools/validate.luau` with 28 validators, the naming blocklist (D-014), the phase scope (D-015) | `tests/tools/validators.spec.luau`, `naming.spec.luau` |
| Shared data | 31 tables under `src/shared/data/` (combat, arts, weapons, armor, apex, enemies, bosses, floors, loot, origins, paths, tiers, ai, camera, choreo, fx, input, lighting, palette, playground, rigs, scope, sfx, assets, ui, weaponModels, world, dev, and new: impact, accents, moments), `types.luau`, `util/` (Signal, Spring, Easing, Verlet, Rng, Check) | `tests/data/*`, `tests/util/*` |
| Clips | 64 Choreo clips: 44 `player/OneHandedSword/*` (locomotion in a sheathed and a drawn set, Draw and Sheathe, guard, parry, dodges, flinches, Basic1-3, Horizontal, Vertical, RisingArc, SharpNail, DeathFreeze), 10 `enemy/Boar/*`, 10 `enemy/Kobold/*` | `tests/choreo/clips.spec.luau`, `ClipLibrary.spec.luau`, clips validator |
| Choreo (client) | `ClipSampler` (per-clip structure cache), `Pose`, `Mixer` (layers, pause, time scale, catch-up), `Choreo` (animator per rig, quality tiers, Roblox Animation fallback), `ClipLibrary`, `Locomotion` + `LocomotionState` (gaits paced to the root on one phase, D-054; the lean held upright under the drawn left walk, D-058), the sheathed weapon (`WeaponMount`, `SheathState` with the remote rise filter, D-050, D-057) | `tests/choreo/*`, new `Stride.spec` (11) and `TurnClearance.spec` (1, 40 drawn turns); `GroundClearance.spec` 20 |
| Controllers, camera, net | Input, Character (the two-step stop carry, D-059), Target, EntityTracker, Replication (drives every remote rig's locomotion; builds each hit's `HitInfo` for the impact director, the death lead and the late-start replay, D-069 to D-102), ActionLogic, WeaponInfo, Siblings; CameraController (+ the FOV punch, D-072) + CameraMath; `Net` / `Remotes` (D-008), `TrailingSend` (D-056) | `tests/client/*` (new `CharacterController.spec` 3; `Replication.spec` 48), `tests/net/*` (new `TrailingSend.spec` 17) |
| FX | Trails (+ the swing direction, D-068), Smear, Shatter (+ ShatterMath, the shatter weight), Sparks, Telegraphs (+ TelegraphShapes), OutlineManager (+ OutlineRanking), Digits, SwitchRing, Quality, FrameClock, Engine; new: Impact (the director, D-069), ImpactFrames + ImpactSequence + FlashBudget (D-060 to D-066), Glint, SlashArc, SpeedLines + AccentStep (D-067) | `tests/client/*`: new `Impact.spec` 57, `ImpactFrames.spec` 38, `ImpactSequence.spec` 17, `FlashBudget.spec` 10, `Glint.spec` 11, `SlashArc.spec` 14, `SpeedLines.spec` 9, `Shatter.spec` 4; `tests/data/impact`, `accents`, `moments` specs 10, 17, 25 |
| UI and audio | `El` component library (D-007), Hud (+ HudLogic), Nameplates, SystemLine; MusicDirector (+ MusicState), SfxPool (layered cues, contours, `playEndingAt`, `playLate`, trims and fades, preload; D-075 to D-094), Ambience (D-095); 50 licensed library sounds on 54 slots (D-080) | `tests/client/*` (new `SfxPool.spec` 86, `Ambience.spec` 11), `tests/data/sfx.spec` 64 |
| Server | EntityService, CombatService (DamageMath, HitSweep with the per-sample blade overlap and the arc-following sweep D-010 / D-042 / D-044, the section 17 request checks including the quick-slot check), EnemyService with Brain / Charger / Brute AI, PlaygroundService, AntiCheatService (+ anticheat Rules), world builders (RigBuilder, WeaponBuilder, PlaygroundBuilder, PlaygroundLayout) and CharacterReady (D-046), `Main.server.luau` | `tests/server/*` (with the hit matrix, D-045), `tests/smoke/*.smoke.luau` (six, all pass on the owner's PC) |
| Tools and docs | `Capture.client.luau` (gate shot prompts), the ClipLab (`places/ClipLab.project.json`, `ClipLab.server.luau`, `ClipLab.client.luau`, `ReviewMarkers`), the PoseEditor Studio plugin (`tools/PoseEditor`) with `Serialize` / `Session`, `tools/pose-server.luau`, `tools/assets.luau`, `tools/smoke.sh`, `tools/animation-review.luau`, `tools/hit-matrix.luau`, `tools/build-plugin.sh`, `data/dev.luau`, this docs set | `tests/tools/*` |

Suite at the time of writing (6e0fd5e): `lune run tests/run.luau` 1559 passed, 0 failed, 94 spec files (about 145 s;
GroundClearance and Stride take most of it). `lune run tools/validate.luau`: 28 validators, 0 problems; the clips
validator warns about the 160 later-phase clips (66 Arts, 65 enemy attacks, 29 boss attacks) that are not authored
yet and are outside the Phase 0 scope (D-015), and about the boar's and kobold's long wind-ups, which are checked
against `enemies.luau` instead.
`tools/animation-review.luau` flags no review-rule finding on the 64 clips (9 attacks); the hand-filled columns are
still empty (they come from watching the recordings at 0.25x). `lune run tools/hit-matrix.luau --check`: every real-fight
placement registered on its strike at every frame phase. `tools/lint.sh --offline` (StyLua, Selene, tests, validators, every Rojo build) prints ALL GREEN.

## Stubbed or not started

- Everything in `docs/PLACEHOLDERS.md`: every mesh, texture and font id is 0 (part-built rigs, blade-shaped weapon
  parts, flat telegraph parts, Trails without a texture, Gotham / Garamond fallback fonts), and 92 of the 146 sound
  slots are silent placeholders (later floors, weapons, enemies, UI and the system voice). No music stems exist; the
  MusicDirector runs with silence.
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
  checks the handoff, the sword and scabbard against the body (D-055) and the pull along the sheath. The rigs and combat smokes check
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
  to 0.16 stud into the head box and into the hat brim. D-055 moved the mount: on the hit-matrix body the grip and guard
  now keep at least 0.013 stud from the head box in every checked pose (the real-avatar check is STUDIO_TASKS item 30).
- **Re-check on 6d6eb74 (same day, same avatar):** the limbs now move in Play: at idle the elbows, knees and neck
  breathe (up to 8 degrees), and the feet lift 0.6 to 0.9 stud at a guard walk and 1.6 to 1.8 at run and sprint (hip
  up to 90 degrees, knee up to 125). A 32 s sprint (766 studs, eight direction changes) logged no anti-cheat line.
  Lock-on drew the sword: Drawn turned true and the sword reached the hand 0.30 s later, 0.30 stud from the grip.
  Frame rate unchanged: 60.0 fps, p95 17.6 to 17.7 ms, render CPU 1.5 to 1.6 ms, GPU 0.6 to 0.7 ms.
- **Still open from the re-check:** the planted foot slides about 0.2 stud a second at a guard walk (clean) but 6 to 7
  at a run and 11 at a sprint, because the gaits still play at rate 1 whatever the body's speed (D-054 and D-059 now pace the
  gaits and carry the stop; not yet re-checked in Play, STUDIO_TASKS items 37 to 43). The sheathe about 6 s after lock-off was not seen: the enemies killed the character during the wait. A
  respawn logs "Something unexpectedly tried to set the parent of Animate to NULL": Choreo removes the engine's
  Animate script from inside the engine's own parenting; the removal is now deferred (D-103, STUDIO_TASKS item 82).

## After the Play-test (a556f8d, 8e88bf0, 3f9c671, 6e0fd5e)

Built and checked in Lune only; none of it has been seen in Studio yet (STUDIO_TASKS items 37 to 81).

- **Walk pacing (D-054, D-059):** the gait clips play on one shared phase, paced to the body's speed from ground
  speeds measured on the hit matrix's player (`tests/choreo/Stride.spec.luau`). A stop below the skid threshold
  carries the body through one more step to a planted stand. On the 240 Hz Lune body, the worst plant per stance went
  from before to now: Guard walk 3.95 to 0.13 stud; straight back at walk speeds 4.16 to 0.05; forward at 6 to 10 studs
  a second 2.46-4.56 to under 0.18; a stop from a Guard walk or a run, wherever in the stride the stick lets go, under
  0.24 (the old dead stop up to 3.95); a turn into a walk 6.2-9.2 to 0.1-2.3; a landing on the move 3.8-13.9 to under
  1.0. Still open, in the clips: the swing foot scrapes the field in the drawn walk and run (up to 1.84 studs a step in
  the Guard walk); the walk-to-run band at 3.75 to 4.75 studs a second slides up to 1.16; side and back moves at run
  speed slide until strafe and backpedal clips exist; and sheathed reversals slide 2.2 to 3.6, as before.
- **The back mount moved** (D-055): the grip sits behind the right shoulder blade, and the scabbard lies flat on the
  back, 0.2 stud off it. GroundClearance poses the sword and scabbard against every body part at 240 Hz (head 0.01,
  arms 0.03, legs 0.04, hips 0.01 stud: Breathe's reach rounded up). It covers the sheathed and drawn sets, every
  one-shot over every base of its set, the attacks, Guard, Parry, Draw and Sheathe, and the sword in the hand. On the
  old mount and clips it found 241 problems with the sword on the back (TurnRight's grip 0.327 stud into the head) and
  99 with it drawn (Vertical's scabbard 0.183 into the hips). Now there are none. The closest gaps are 0.013 stud (the
  hilt to the head) and 0.019 (the scabbard to the hips). Draw and Sheathe's grab, middle and reach keys were solved
  again; Draw settles with the point higher, so a draw during a sprint no longer sinks the tip about 1 stud into the
  field. The flinches no longer move the right shoulder (a hit during the pull pushed the blade 0.525 stud out through
  the scabbard). 17 other clips were re-keyed by a few degrees (D-055 lists them). The hit matrix stays green.
- **Small fixes (D-051, D-056, D-057):** TargetRequest and GuardRequest go through a trailing send, so the last lock
  state and the last guard raise or release always reach the server (simulated mashes lost 392 and 149 of 1400 before,
  0 after). The guard sender has a burst of 2, so a tap's raise and release go out together and a parry right after a
  tap is no longer refused. The lock-on clears with the character and is resent after a respawn. FullBody clips that
  cover more than half of the limbs silence the walk's footsteps, so nothing steps in the air (648 probe cases: 0
  missed, 18 doubled). A remote rig's Drawn rise waits 0.06 s, so an attack draw-cuts with no Draw flash.
- **Integration and fix rounds:** the dodge reads the stick, not the stop's carry, so a dodge pressed just after
  letting go steps back. A drawn reversal to the left showed the drawn left walk at high weight with the lean near its
  cap, putting the scabbard up to 0.172 stud into the left foot. The lean now stands up under that walk, and
  `tests/choreo/TurnClearance.spec.luau` keeps the scabbard at least 0.071 stud off the body over 40 drawn turns
  (D-058). Adversarial checks of the pacing, the mount and the small fixes found 8 + 9 + 2 confirmed problems; each
  was fixed with a spec that fails on the old code, or is listed as open.
- **Impact frames (D-060 to D-066):** an Art's final hit shows two frames of white figures on black, a kill a black
  beat, the figures and ink strokes (2 frames each), a perfect parry one inverted frame, all inside the hit-stop and
  only for the fighters in the hit. The sword is part of the figure. Every full-screen flash is costed per screen
  region by the WCAG general-flash rule and must fit a budget of 3 flashes in any second (`FlashBudget`); a refused
  one shows a soft dim. The local player's `SettingReduceFlashing` attribute swaps the frames for the dim, at most one
  a second. Every quality tier keeps the figures.
- **Reel accents and the director (D-067 to D-072, D-096, D-098):** a four-point glint, a slash crescent in the
  swing's plane and a slash line, made of flat frames and beams in palette colors; speed lines on the dodger's screen;
  a short FOV push on a final hit or kill. `moments.luau` says what each moment fires and who sees it, and
  `fx/Impact.luau` only reads it. One attacker's hits within 0.1 s are one sweep: one cue, one contour, one push, one
  tick, one picture.
- **Real sounds (D-073 to D-095, D-097 to D-102):** 54 sound slots now hold 50 picks from Roblox's licensed library,
  trimmed and faded (credits in `ASSETS.md`, the list and the weak picks in `PLACEHOLDERS.md`). Every hit is a layered
  cue (crack, flesh, body, ring; a final hit's sub after the hold; a kill's weight with the bass cut), with contours
  that cut and bring back the lows, a reverse riser that ends on the first damage frame, whooshes timed by each take's
  measured peak, and the guard's raise, block, break and parry. The death plays the enemy's scream at once and starts
  the 0.5 s silence after the kill's hit-stop; a player's (or an Elite's) death shatters heavier. The Plains bed and
  the rim wind play on the island. A remote clip that starts late replays the sounds and the Art light it jumped over.
  1559 tests pass in 94 spec files, 28 validators, ALL GREEN.

## Known review items for the Studio pass

- The sheathed sword at 0.25x in the ClipLab: Draw and Sheathe (the hand meets the hilt at 0.22 s and 0.42 s; the last
  2 studs of blade leave the sheath by swinging over the mouth between two frames at 1x, 0.284 to 0.295 s, an edge up to
  0.16 stud out through the wall for 7 ms, so judge whether that reads as a whip or a glitch), the hilt behind the head
  with a real avatar's hair, and the re-keyed one-shots (D-055: DodgeLeft leans 30 degrees, DodgeBack 18, TurnRight
  turns the torso 24 and the head 12 past it, FlinchFront brings the left leg forward, the flinches no longer move the
  right shoulder, and the dodge, Stagger and GuardBreak recoveries hold the head lower). The scabbard now keeps at
  least 0.019 stud from the hips box in every checked pose.
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
- Guard requests go through TrailingSend with a client burst of 2 (D-056): tapping guard never trips GuardRequest's
  rate limit, a tap's raise and release go out together, and the server always ends on the last state. Parry spam
  gains nothing past the 0.25 s re-arm (D-031). Tab is gated on the client at `SwitchCallRequest`'s rate (D-107), so
  mashing it no longer gets a player kicked.
- The walk-run blends are not posed by GroundClearance. Straight ahead at 8 to 10 studs a second, the sheathed blend
  brings the scabbard within 0.023 stud of the left forearm box (the arms margin is 0.03; no contact), and a drawn
  walk-run blend puts the held guard 0.009 stud into the right shin box for 10 frames. Watch Run from behind for the
  left forearm brushing the scabbard.
- WalkBack and WalkBackDrawn (re-keyed with 32 keys for the toe, D-054) stop and start every joint at every key: 283
  and 198 stop-go dips per cycle at 960 Hz, against 41 and 12 before. It shows at 0.25x and on a 240 Hz display; judge
  the backpedal in the recording.
- Feel calls kept as they are until Studio says otherwise: the basic whoosh lands about 54 to 69 ms after the snap
  (the take peaks too late, PLACEHOLDERS); the body holds still about 10 frames after the death tremor fades, before
  the shatter (D-073); an older kill's shatter plays quiet inside a newer kill's silence (D-073); a swing during a
  death's silence is ducked with everything else; the speed lines stay on with Reduce flashing (D-062); the bass cut
  still plays when the dim replaces the frames.

## Phase 0 gate (section 20) and the section 21 checklist

Gate: *a 20-second clip of a player fighting a boar and a kobold where every attack shows the six beats, the parry
sparks, the kill shatters, and the server registered every hit; 60 fps in Studio; all tests green.*

| Part of the gate sentence | State |
| --- | --- |
| The 20-second fight: six beats on every attack, the parry sparks, the kill shatters | Needs the owner's recording (`fight-boar-kobold.mp4`) |
| The server registered every hit | **Met** in the hit matrix (every window, both enemies, real fight distances, four frame phases; D-045) and in `combat.smoke` in Studio; the recording shows it again as a digit per hit |
| 60 fps in Studio | **Partly met**: 59.9 to 60.0 fps in Play with the window rendering on the owner's PC (2026-10-20, builds 927dbed and 6d6eb74, frame cap 60, p95 17.6 to 17.7 ms), standing and running with the enemies 66+ studs away; still to read during the recorded fight (**View > Stats**) |
| All tests green | **Met** in Lune on 6e0fd5e (1559 tests in 94 spec files, 28 validators, `tools/lint.sh --offline` ALL GREEN); the six Studio smokes and CI last passed on earlier builds (1051 tests) and still have to run on this one |

| Line | State | Evidence / what is missing |
| --- | --- | --- |
| CI is green: StyLua, Selene, Lune tests, data validators, naming blocklist, `rojo build` | **Met** | GitHub Actions run 39462350246 on `phase-0` (open it from the repository's Actions tab) (format, Selene with the real Roblox std, 1051 tests, 25 validators, the review-report check, the game, both places and the plugin build). `tools/lint.sh --offline` reproduces every step except Selene's Roblox-only lints, which need the API dump; those run only in CI. `aftman.toml` pins the tool versions. |
| Every new clip is in `docs/ANIMATION_REVIEW.md` with the six beats marked present and the hit-stop tier noted | **Met** (generated), hand columns empty | All 64 clips are in the table; 9 attacks show the six beats and a tier. The three hand-filled columns need the ClipLab pass in Studio. |
| A recorded clip for every new Art, enemy and boss phase exists in `docs/clips/` and was watched at 0.25x | **Needs the owner's recordings** | `docs/clips/phase-0/README.md` lists the ten files the Capture panel prompts for. None recorded yet; each is reviewed frame by frame once it is in the repository. |
| No T-pose, A-pose, frozen rig, popping limb or sliding foot appears in any clip | **Needs the owner's recordings** | Judged from the recordings. Before D-053 the local character stood frozen in Play with its feet sliding (the engine's Animator reset every pose); the re-check on 6d6eb74 shows the limbs moving and the feet lifting, with the planted foot still sliding at run and sprint on that build; D-054 now paces the gaits to the body's speed, D-059 carries the body through the stop, and D-058 keeps the scabbard off the left leg in drawn turns (STUDIO_TASKS items 34 and 37 to 43). Remote rigs now walk (Replication drives their locomotion) and the root motor name matches the live R15 rig (D-016), the two defects a reviewer would have seen first. |
| Every enemy attack has a wind-up of at least 0.3 s with a colored telegraph that reads from behind | **Met in data**, seen in the recordings | `enemies.luau` wind-ups (boar 0.6 s, kobold 1.0 s) and the clips validator's Anticipation-covers-windUp check pass; Telegraphs FX exist. |
| The server rejects a scripted client that spams Arts, teleports, or reports its own hits | **Met** | `CombatService` validates every request (section 17 list, including the quick slot), `AntiCheatService` + `anticheat/Rules` and the Net rate limits have Lune specs; clients never send hits (the server sweeps). In Studio on the owner's PC: `combat.smoke` refuses 20 Art repeats while locked (one hit lands) and a forged request with a target field, and no client remote is named for hits or damage; `playground.smoke` shadow-flags and then kicks a teleporting stand-in. The smokes drive the same request checks the remotes call, from the server. |
| Part count, draw calls, server heartbeat and memory are measured in the Playground and within section 16 | **Partly met** | Part count and server frame time measured and well inside the targets (table below). Client fps, draw calls and client memory need Play mode with the game window rendering, read by hand while recording. |
| `docs/PLACEHOLDERS.md` lists every stand-in asset with a replacement plan | **Met** | Written from `tools/assets.luau` plus the dev-scene stand-ins; the sounds from `sfx.luau`: the 50 licensed picks with their trims, the 4 reuses, the 5 real slots nothing plays yet, the 92 silent slots with the reason for each, and the picks to improve. |
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

## Play-test on the owner's PC (2026-10-23, f7b0722)

- Ran part of the round, sound audible (MasterVolume cannot be set from a script). Studio stopped drawing when the
  display slept part-way; the rest waits for the rerun.
- Pass: no "set the parent of Animate to NULL" warning after two resets and four deaths (item 82); 215 of 219 sounds
  load (the 4 that do not are the placeholder music stems, fixed by D-115); the kobold's kill on the player showed
  the impact frames in order (Black, Dark, Ink, 6 frames), the sword in the figure at rest size, the FOV punch 60 to
  55 and back with a 60.8 overshoot, every impact layer starting on the hit frame, nothing played twice; frame time
  p50 16.7 ms, p95 17.7, max 67.6 (not on a hit), about 60 fps against the 59.9 baseline.
- Fail: no player swing ever damaged an enemy (about 15 swings). The body faced 156 to 175 degrees away from the
  enemy: nothing turned it, lock-on only moved the camera, and the server sweeps around the body. The server path
  itself is sound for a real AJU player (probe and `tests/server/PlayerSwing.spec.luau`). Fixed by D-112 (the body
  faces the lock, each swing snaps up to 40 degrees, soft assist) and D-113 (the server sweeps along the validated
  facing).
- Measured: a regioned Sound fires Ended at the region end and will not start at or past it; a loop's first pass
  starts at TimePosition (D-091). The server keeps the sword motor on the right hand while the client shows it on the
  back; the server's Basic1 blade runs 2.9 to 6 studs in front of the root at about hip height.
- Console: four "Failed to load sound rbxassetid://0" and three ContentId errors (the music stems, D-115), two
  "Cloud instance must exist under Terrain node" (D-116), three "rbxassetid://203785492 Asset type does not match"
  (not in the repo; item 98).
- After the fixes: 1778 specs in 107 files, 30 validators, offline lint green, hit matrix unchanged, no new strict
  type messages in src or tools. Studio checks 97 to 106 cover the rest; the dev hooks (D-114) let a Studio session
  land swings and read why one missed even with the display asleep.

## Rerun with the display awake (2026-10-23, 3b51432)

- Pass: the lock turns the body to the target in 0.18 s; the basic chain landed 3 of 3 on a kobold (19 of 20 in the
  earlier run); guard and dodge reach the server. An Art's final hit drew the impact frames for 2 frames (the Final
  Dark look) with the sword in the figure at rest size, at most one picture a second over 8 Art hits; FOV 63.1 in the
  wind-up, 57.5 on the hit, back to 60 by 10 frames later; the riser ends 2 frames before the hit, five impact layers
  start on the hit frame and impact.Sub 7 frames later (the Final hold, by design); nothing played twice. Frame time
  p50 16.7 ms, p95 17.6, max 38.3 over 2225 frames (about 60 fps, same as the baseline). Reduce flashing on Art final
  hits: a soft 30 percent dim, no white, no figures. Items 88, 90, 93(a) and 100 pass; item 86 had no kick and no
  anticheat line (no Switch prompt sound was heard, so the prompt was not confirmed).
- Foot slide on real keys: running, the planted foot slides a median 0.07 (left) and 0.17 (right) studs a stance,
  worst 0.22; sprinting backward, 0.11 and 0.21, worst 0.69 and 0.77.
- Console: only "rbxassetid://203785492 Asset type does not match" (three times) remains. It loads only while the
  viewport renders and no instance property holds it (client, server, accessories), so it is likely Studio's own UI
  or a plugin; item 98 stays open.
- Not reached: a kill (the player kept dying to the kobold, enemies heal 1 percent a second 8 s after their last hit,
  and swings landed on a second boar), sheathing after lock-off (a boar's hit kept the sword out), the strafe feet
  (103), items 99, 101, 102, 85, 93(c) and the parry. These need a quiet, controlled fight.
- Seen: two kobolds' roars played over each other; with the display asleep the impact overlay stayed up and the lock
  survived a respawn (fixed below).

## Render stalls and the lock (2026-10-23, D-117 to D-119)

- ImpactFrames drops a picture whose first frame comes more than 3 frames after the hit, and a Heartbeat watchdog
  ends anything left showing and frees its figures (D-117). A picture ended between frames keeps its flash claim until
  the frame that shows it gone, so the 3-a-second budget and Reduce flashing hold through stalls (a stall hit storm
  drew 7 changes a second before this, 6 after).
- The camera steps by real time with stable springs and never replays a punch or shake after a stall (D-118).
- The lock ends with the local character on death, despawn and respawn (D-119).
- Checks: 1821 specs in 108 files, 30 validators, offline lint and the hit matrix pass; no new strict type messages.
- Open: Choreo still steps on RenderStepped (a stall freezes the clip, visual only); below 20 fps about half the Kill
  and Final pictures drop; the engine's first dt after a stall and ParticleEmitter bursts on wake are untested
  (item 107).

## Stall and lock check on the owner's PC (2026-10-23, 2cd153c)

- Pass, item 107(a): an Art's impact frames showed for 2 frames, then the overlay went off with its figures freed;
  through a 55 s display sleep the overlay stayed off with no figures, and nothing flashed in the 60 frames after
  waking.
- Pass, item 107(d): after a respawn the lock is gone, the next swing does not aim at the old boar, and F locks again
  0.58 s after the new character appears.
- Measured, item 107(c): the first RenderStepped dt after a stall is the whole gap (5.4 s, 54.1 s, 188.3 s); the camera
  and accent specs cover this case.
- Item 107(b): minimising Studio does not stop RenderStepped (60 a second throughout), so it is not a stall case; the
  window-drag hitch is left for the owner. Item 107(e): one hit landed while the display slept and nothing burst on
  waking; a kill shatter during a sleep is still unchecked. Item 107(f): one dim for one Art hit with Reduce flashing
  on; several hits with sleeps between them are still unchecked.
- Item 98: rbxassetid://203785492 is an audio asset ("Pop Close Sound" by another creator). Something asks for it as
  a non-audio type only while the viewport renders, and no instance in the place holds it, so it is most likely a
  Studio plugin or the engine's own UI. Left for the owner: Play with plugins turned off.

## A controlled fight and the idle phase (2026-10-23, D-120 to D-124)

- Studio dev hooks for a fight that cannot go wrong: DevCombat "hold" stops chosen enemies (they still take hits and
  never heal while held), "sethp" sets HP (never a kill, so the death still comes from a real swing), "heal" refills.
  The hold is also the cinematic hold for boss entrances and cutscenes (D-120, D-121). Item 108 is the recipe for the
  kill sequence, sheathing after lock-off, strafe feet, lock facing, the snap, the parry and the lock across death.
- Each impact picture now waits for its first drawn frame as long as its own hit-stop, so Kill and Final pictures play
  at 15 fps; the figures keep the frozen frame past the hit-stop (D-122).
- Enemy idles and walks start at a different point of their loop for each enemy, so a herd no longer sways and roars
  in unison (D-123). A same-sound gap between different enemies was left out on purpose (D-124).
- Checks: 1862 specs in 108 files, 30 validators, offline lint and the hit matrix pass; no new strict type messages.

## Controlled fight on the owner's PC (2026-10-24, ea7a8e8)

- Pass, item 108(a), the kill: one swing at a 1 HP boar gave Black 2 frames (figures hidden), Dark 2 (white figures),
  Ink 2 (strokes); FOV 60 to 55 and back by 13 frames with a 60.8 overshoot; Ring, Kill, the hit-stop tick, Crack,
  RingTail, Flesh and the death vocal all start on the hit frame; a quiet 0.68 s, then the shatter (65 shards, Crack,
  Slam, Chime, SubDrop); nothing played twice; the respawn comes back held.
- Pass: sheathing after lock-off (the sword sheathes 6 s after the last swing; the tip moved 2.7 studs in one frame
  just before the swap, smoothed by D-130); lock facing (item 99: turned in 0.27 s, at most 1.6 degrees off while
  strafing and backing off); lock and swing at once (101); the parry by timing (a guard 0.10 s before the kobold's
  hit parried 3 of 4 times and blocked once; 0.16 s before broke the guard every time); the lock across a natural
  death (107d); the idle phase (neighbours out of step, roars 0.3 s apart, never doubled); a kill at 15 fps (each
  look one rendered frame, figures frozen); Reduce flashing with sleeps between hits (no dim after any wake).
- Fail, fixed below: the strafe feet slid 0.4 to 0.9 studs a stance (103); the 35 degree snap jumped 23 degrees in
  one frame (102; the 12 degrees it stopped short is the soft assist picking the nearer boar); a white glint star
  showed about 1 s after waking from a kill during a display sleep, and the glints stayed on 3 s (107e).
- Seen: a 0.22 s render hitch about 2 s after each wake (likely the engine's own); Humanoid:MoveTo did not move the
  character in a slowed run; the item 98 console error is still there.

## Fixes from the controlled fight (2026-10-24, D-125 to D-131)

- Every accent and one-shot particle burst also ends on Heartbeat, so nothing from a hit during a display sleep shows
  on waking (D-125).
- The swing snap turns the body over 0.08 s (5 frames at 60 fps, eased out) while the request still carries the whole
  turn, so hits are unchanged (D-126).
- In Studio, the Capture time scale also slows the local body, so slowed captures keep the feet planted (D-127).
- The lock-on strafe clips are re-keyed as a quick guarded side-step (chassé) paced to walk speed, and the gait blend
  stops pushing Run's feet across a strafe: a square strafe at walk speed now slides under 0.1 studs (D-128, D-129).
  The Sheathe flip is retimed so the tip never jumps (D-130). A stride validator checks every walk can reach walk
  speed (D-131).
- Checks: 1905 specs in 110 files, 31 validators, offline lint, the hit matrix (unchanged) and the animation review
  pass; no new strict type messages.
- Open: Choreo replays a display sleep's gap in one step on waking (stale whoosh or footstep sounds, a small jump);
  light stick tilts on locked diagonals can tap the trailing foot; Draw still whips 3.4 studs in one frame (item 119).

## Controlled-fight fixes on the owner's PC (2026-10-24, 6437d91)

- Pass: no glint or particle burst after a wake from a kill during a display sleep (109); the swing snap at 1x turns
  over 5 rendered frames (largest step 15.6 degrees) and over 18 at 0.25x (largest 4.2) (110); the lock-on strafe at
  1x, drawn, slides 0.05 to 0.14 a stance at the median, worst 0.24 (115); Sheathe's largest tip step is 1.94 studs,
  down from 2.74 (116); reversals while locked plant within 0.05 to 0.25 (117); slowed capture moves the body at the
  slowed speed (4.00 run, 6.00 sprint).
- Fail, fixed below: stale sounds replayed on waking (the Art chime +0.17 s, a whoosh +0.32 s, footsteps) and the
  root moved 0.21 studs on the first frame (109); a locked forward walk, drawn, slid 1.75 to 1.83 a stance at 1x
  (117) and a slowed run slid up to 2.7 (112, 114).
- Seen: the snap settles about 5.6 degrees past the target's box centre (it aims at the target's root part); Draw's
  tip moves 3.34 studs in one frame at 0.57 s (119, needs eyes); an injected Q key arrives as already handled by the
  game and never starts an Art, so item 113 needs the owner's own key press.

## Wake replay and drawn feet (2026-10-24, D-132 to D-137)

- Waking from a display sleep now shows the present: a step longer than 0.5 s is a jump, the clips jump to where
  they would be, the root does not move, and the events the gap crossed only close what they opened (no stale sound,
  footstep, trail or kick). A swing or dodge started by the waking key press, or a remote's action just before the
  wake, still plays from its own start (D-132).
- The drawn forward walk, run and sprint now share the sheathed legs, and the forward walk is re-keyed with a brisker
  toe-off: a locked drawn walk at 1x slides 0.02 to 0.04 a stance (was 1.35), a 0.25x run 0.15 (was 2.59) (D-133 to
  D-135). The two-step stop takes an extra half step when the stance spot is reached too late (D-136). Slowed
  captures are measured with a scale-aware planted test (D-137, item 124).
- Checks: 1939 specs in 110 files, 32 validators, offline lint, the hit matrix and the animation review (64 clips)
  pass; no new strict type messages.
- Open: an Art held across a display sleep stays frozen at its start until release, then plays about 0.25 s late; the
  walk/Run blend between 4 and 6 studs/s (half stick) slides 0.33 to 0.57 a stance (item 128); a body deflected along
  a boar's flank slides about 1.1 (item 126); a locked walk straight through the target pivots one stance; any client
  hitch over 0.5 s drops that span's one-shots and root motion by design. The gait clip generator still lives outside
  the repo; commit it under tools/ once it is --!strict.

## Studio check of the wake fix (2026-10-24, bb316b4)

- Pass: waking after a 21 s screen sleep plays no stale chime, whoosh or footstep, the root moves 0.004 studs, the FOV
  stays at 60 and the trail is off (120); a released kobold's Art does not replay at the wake (121, a stand-in for a
  second player); a normal Art, dodge (7.97 studs) and kill keep every sound and the same timing as before (122); a
  swing pressed 0.27 s before the wake plays on with its whoosh and trail, one pressed 2.2 s before ends silently
  (123a); the first render dt after a wake equals the server-time gap every time (123c); a locked drawn walk with
  Guard held slides 0.15 at most (125).
- Fail or partly: a dodge pressed 0.2 s before the wake plays its landing thud at +0.07 s, before the body travels;
  an Art fired just before the sleep shows its trail on the first wake frame; slowed captures leave one foot per gait
  at about 0.20 a stance (the other is under 0.15); walking into a held boar keeps the legs walking in place (one
  stance slid 3.35 at 0.25x) and slides along its flank in bursts of 1.4 to 3.7 studs/s at 1x (126).
- Seen: the server anticheat kicked the test session for its own client teleports; a half-magnitude Player:Move
  walk at 8 studs/s keeps median slides near 0.01 with outliers up to 0.68 (128).

## Held Arts across stalls, root order and the gait generator (2026-10-24, D-138 to D-140)

- An Art held across a display sleep or a client hitch now waits at its hold pose with the blade lit, and its
  release launches on a normal hold's timing (D-138). It used to stay at its start or run past its stance, then
  launch about 0.25 s late. A hitch shorter than 0.5 s no longer freezes the hold mid-swing with its trail lit, and
  a hitch past the 1 s cancel time no longer chimes for a hold the cancel ends.
- The controller steps the local rig itself just before it reads the root motion, so a dodge or a lunge moves the
  body in the frame it is posed, with no one-frame lag. The other rigs, their rate tiers and ClipLab are unchanged
  (D-139).
- The gait clip generator is committed as strict tooling under tools/gaitgen, with a `--check` mode and a spec. 10 of
  the 12 gait clips are byte-checked; Run and Sprint keep their hand-keyed back-mount upper bodies (D-140). This
  closes two items left open in the section above (the held Art across a sleep, and the generator outside the repo).
- Checks: 1983 specs in 114 files, 32 validators, offline lint, the hit matrix, the animation review (64 clips) and
  gaitgen --check all pass. No new strict type messages in src.
- Open: the hold's chime and FOV kick play in the dark when the timer freezes it during a display sleep (item 130);
  an Art pressed in the wake frame of a 0.15 to 0.5 s hitch starts that far into its clip, and a release in that
  frame leaves the clip up to about 0.47 s behind, as before; Run's and Sprint's upper bodies are not byte-checked.

## The owner's first recordings (2026-10-24, bb316b4)

- Two free-play recordings (2 min 17 s and 1 min 52 s) reviewed frame by frame. The Capture panel was never started,
  so only the kill-and-shatter shot could be cut from them; the other nine shots need new recordings.
- Pass: kill impact frames Black 2, Dark 2, Ink 2 (one kill split 3/1/2); the half second of freeze and silence and
  the shatter at +0.68 s; the parry's inverted frame, spark and ring; the boar's red and the kobold's yellow
  telegraphs on time (0.55-0.60 s and 0.95-0.98 s); Art finals Dark 2; at most 3 full-screen flashes a second.
- Fail, to fix: most boar charges never rush but still deal damage; the kobold's damage sometimes lands 8-12 frames
  before its chop shows; hit flashes are 1 frame and boars never flash; the hit freeze starts after the blade has
  passed; an Art's activation flashes the whole body white; after an Art kill the player holds about 23 frames, then
  jumps; the camera sits high and the hat hides the kobold, with snap-ins on dodges and draws; enemy names float
  after the shatter and every enemy shows two names; the death silence also mutes the player's next hit.
- Not seen in this footage: legs walking in place against an enemy (fixed below anyway, from Studio item 126).

## Wake round and blocked feet (2026-10-24, D-141 to D-144)

- A dodge pressed while the display sleeps now plays whole from the wake, with its sounds at the travel (D-141).
- Trails go out during a render stall longer than a jump (D-142).
- The Studio-only DevCombat "place" moves a player without tripping the anticheat; a client teleport is still flagged
  (D-143).
- A body pushed off its stick by an enemy or a wall now stands, or steps the way it slides, instead of walking in
  place: deflected off a boar 1.29-1.74 a stance down to 0.11-0.34, pushed back 3.38 to 0.16 (D-144). Open-ground
  locomotion is frame-for-frame unchanged while the Humanoid's velocity follows its input within about 0.05 s.
- Item 124's one-foot 0.20 in Studio does not reproduce in Lune (0.07-0.10 a stance at 0.5x and 0.25x); the recipe
  split the R foot's stances on a small planted roll. Re-run with the blank R15 avatar and a Footstep log.
- Checks: 2029 specs in 115 files, 32 validators, offline lint, hit matrix, animation review and gaitgen --check pass;
  no new strict type messages.
- Open: a velocity that lags the stick by 0.07 s or more could latch an open-ground turn as blocked for 3-5 frames
  (item 137 measures it); a slow sideways creep near 0.4 studs/s shuffles; Idle has no re-plant step.

## Hit on contact, camera and names (2026-10-24, D-145 to D-164)

- **The hit:** the local fighter's hit now plays on the frame the blade touches. ContactPredictor sweeps the drawn blade, and the server still decides the hit and brings the number. A kill is predicted only when proven, and each hit gets one hold. The strike snaps read over 2 to 4 frames, and the hit-stop absorbs the authored hold, so a kill shows one still. Flashes and impact frames count drawn frames, and a boar flashes over its tint. An Art's activation flashes only the sword, and a cancelled Art's light fades out. The player's own sounds carry through the death silence, and the trail no longer streaks.
- **The camera:** it sits low over the right shoulder, and lock-on frames a two-shot. A back dodge keeps the camera at 0.93 of its distance or more (HEAD 0.69) and tilts the view at most 0.17° (HEAD 7.71°). Backing into a wall, the camera is past the wall face on 0 frames (HEAD 25). It looks past hats, weapons and characters.
- **Names and HUD:** each enemy shows one name, the plate goes with the shatter, and the HUD sits in the safe area.
- **Verification fixes:**
  - An earlier cut's late Kill confirm no longer stretches a later cut's hold (SharpNail at 30 fps: 7 still frames down to 3).
  - A 1 s hitch no longer replays a hit already played on contact.
  - A stall no longer plays a contact for a cut that was never drawn.
- **Checks:** 2215 specs in 126 files pass. Validators, stylua, offline lint, animation review and gaitgen are clean. In the hit matrix, every real-fight placement still registers on its strike, up to 1 frame later because of the snap ease.
- **Open:** Studio items 138 to 149, and the Shatter hook for Nameplates.hide.

## Enemy attacks on the server's beat (2026-10-24, D-165 to D-182)

- **Server (D-165 to D-170):**
  - Enemy bodies turn again.
  - A boar's rush hits each target once, on contact.
  - A rushing boar passes through players and other enemies.
  - A player's hit pauses an enemy's unlanded attack by its hit-stop, up to 0.25 s per attack.
  - Rushes are announced to the clients.
  - Spawns keep 12 studs apart.
- **Clients (D-171 to D-176):**
  - The rush is drawn on the server's clock.
  - Enemy attack clips and telegraphs keep the server's beat through hit-stops.
  - A flinch no longer dips the raised axe.
  - Swings carry a sequence number, so a quick second hit is never confused with the first.
  - An enemy's own strike stills once.
- **Follow-ups (D-177 to D-181):**
  - Plates leave on the shatter frame and survive a respawn.
  - Players carry no engine labels.
  - The dodge hop spreads over 2 to 3 frames.
  - A hit's camera nudge shows on the contact frame.
  - A sideways dodge no longer carries the player toward the screen's edge.
- **Verification fix (D-182):** strikes now resolve on the first AI tick at or after the beat the clients draw, no longer up to two ticks after it.
  - Kobold at ±2 ms frame jitter: 1.6 frames late on average and 3.4 at most, down from 3.4 and about 6.
  - Rush: the drawn tusks and the server's hit now agree to within the 20 Hz tick (−1 to +3 frames, down from up to +5.9).
- **Checks:** 2310 specs in 131 files pass. Validators, stylua, offline lint, the hit matrix, animation review and gaitgen are clean. luau-lsp shows no new kind of message.
- **Open:** Studio items 150 to 169, the Ceiling CastShadow place-file change (item 168), and the open issues listed with D-171 and D-181.

## Strikes on the frame, smooth turns and the ceiling shadow (2026-10-24, D-183 to D-192)

- **Server (D-183 to D-186):**
  - A boar that stood still before its rush no longer runs backward or jams. Each movement starts its own stuck clock, and a strike's own movement goes straight.
  - Enemy attack edges resolve on the first server frame at or after their beat: within one frame, never early.
  - Enemy bodies turn a little every server frame instead of in 8° steps per AI tick.
  - The Playground Ceiling casts no shadow.
- **Clients (D-187 to D-189):**
  - A dead enemy's plate leaves on the same frame as its body.
  - An enemy clip a little ahead of the server no longer ends its beat a frame early, so the boar's launch snap starts with its run.
  - The launch head step stays as a deliberate burst.
- **Verification fixes (D-190 to D-192):**
  - A jammed rush stops where it jammed. A stopped rush turns solid only after 0.5 s clear of everyone, longer than the clients' 0.3 s draw lag, so no player is carried or lifted onto a boar.
  - A render stall across the shatter's time no longer takes the plate a frame before the body.
  - Players are not meant to stand on enemies. A deliberate jump-on is a follow-up (item 180).
- **Checks:** 2378 specs in 133 files pass. Validators, stylua, offline lint, the hit matrix, animation review and gaitgen are clean. The Playground builds with the Ceiling's CastShadow false. luau-lsp shows no new messages in src or tools.
- **Open:**
  - Studio items 170 to 180; item 173 closes 138 and 168.
  - A path landing about 0.5 s late can still give a walking body one step back.
  - After a jam, hits keep resolving on the line's clock past the stopped body.
  - The plate trails the drawn body during a rush.
  - The frame pass costs about 22% more server time per step.

## Rush followers, jam line and late paths (2026-10-24, D-193 to D-198)

- **Clients (D-193, D-194):**
  - The plate, SWITCH, the lock camera, the lock range and break, the assist, the turn to the lock, and position-based sounds and effects follow a charging boar's drawn body instead of its lagging hidden root.
  - At 0.25 s and 0.5 s of lag the plate is exact, where it was 7 and 14 studs off.
- **Server (D-195, D-196):**
  - A jammed rush only hits what its body reaches, and nothing after the jam.
  - Paths that land late no longer turn a walking enemy back.
- **Verification fixes (D-197, D-198):**
  - A rush's line ends at the wall face the boar's root runs into. This fixes the Studio case where a player behind a wall at 8 was hit at 12.
  - Walking into an enemy meets one invisible upright blocker from the floor to 7 studs, instead of the floating root's edge, so there is no bob or slide. Rushes still pass through players.
- **Checks:**
  - 2416 specs in 136 files pass.
  - Validators, stylua, offline lint, the hit matrix, the animation review and gaitgen are clean.
  - luau-lsp shows no new messages in src or tools.
- **Open:**
  - Studio items 181 to 190. Item 177 is replaced by 181, and item 180 by 188.
  - When the camera steps before the rig, the lock camera lags by up to 0.9 studs.
  - A client still draws a jammed boar running past the wall until the jam report.
  - A remaining hit gap of up to 1.47 studs for stops the world cast does not see.

## The end of a charge (2026-10-24, D-199 to D-204)

- **Clients (D-199 to D-201):**
  - A charging boar is drawn stopping at the wall its root runs into, instead of overrunning by 4 to 16 studs and sliding back.
  - Its legs follow the drawn body.
  - Rigs step in a bound render step just before the camera, so the lock camera and the hit holds see this frame's pose in either engine order.
- **Server (D-202, D-203):**
  - A wall the cast sees ends the rush on that frame. Clients are told 0.12–0.13 s before the root arrives.
  - jamLagStuds stays 4 for stops the cast misses.
- **Verification fix (D-204):**
  - Ramp faces are ground, not walls. A charge runs up ramps of 5–20° on both sides, where the combined change had stopped the drawn boar partway up and ended a 20° rush at its foot.
  - The line still never resolves past a ramp's contact, so nobody behind a wall at the top is hit.
- **Checks:**
  - 2459 specs in 136 files pass.
  - Validators, stylua, offline lint, the hit matrix, the animation review and gaitgen are clean.
  - luau-lsp shows no new messages in src or tools.
- **Open:**
  - Studio items 191 to 198 (items 186(c), 186(d), 184 and 182(a) are superseded).
  - The snout still shows 3.1 studs through a wall.
  - Glancing walls and pillars stop a charge dead.
  - A drawn boar can still stop at a stair riser.
  - A wall hidden behind a ramp's contact still waits for the jam.

## Wall slams and frame order (2026-10-24, D-205 to D-218)

- **Wall contact (D-205 to D-210):**
  - A charging boar now stops with its snout on the wall's face, on the server and on screen. Before, it stopped 3.1 studs inside.
  - Shallow walls bend its path, barely-clipped corners are sidestepped, and stairs and ramps are run over.
  - A slam dazes the boar for 1.5 s.
- **Frame order (D-211 to D-216):** every pose reader runs in a fixed, data-driven order after the rigs move: rigs 199, character 301, camera 302, impact frames 303, trails 304. The camera, trail head and impact picture are off by 0 now, in both engine orders.
- **Verification (D-217, D-218):**
  - The slam plays dust, a stone thud (existing sounds only) and a near-only shake on the stop frame. It spends no flash budget.
  - A lost or late RushEnded no longer swallows the slam's cue or leaves the boar short of the wall.
- **Checks:**
  - 2562 specs in 139 files pass.
  - Validators, stylua, offline lint, the hit matrix, the animation review and gaitgen are clean.
  - luau-lsp shows no new error sites against HEAD.
- **Open:**
  - The slam point is 0.2–0.6 studs off the snout.
  - A wall only the server has can still be overrun at high lag.
  - Glance and clip cues are not wired.
  - Studio items 199–211.

## Draw, sheathe and lost rush messages (2026-10-25, D-219 to D-226)

- **Draw and Sheathe (D-219, D-220, D-225):**
  - Both read as a whip. On the client's own path the tip stays under 84 studs/s and the blade under 1080°/s, at every speed, frame rate, hitch and jitter tried (HEAD: Draw up to 233, Sheathe up to 111).
  - Draw is 0.875 s and Sheathe 0.815 s; the sword reaches the back at 0.535 s.
  - The drawn set stays on while the sword is in the hand. The drawn sprint pose gives way to the Sheathe in the same step, even across a long frame.
- **Rush messages (D-221, D-222, D-224):**
  - RushStarted, RushEnded and RushTurned are reliable, so a lost message can no longer run a jammed or staggered boar 16 studs past the server's stop.
  - A Telegraph heard after its own RushStarted is ignored, so no body steps back toward the crouch.
  - The torso step during a rush is rush speed × frame length; no change.
- **Impact frames (D-223, D-226):** a Kill heard after the overlay's step draws exactly 2/2/2 and a Final draws 2. A takeover keeps the picture on screen, the soft dim included, so the world never flashes between them.
- **Checks:**
  - 2572 specs in 140 files pass.
  - Validators, stylua, offline lint, the hit matrix, the animation review and gaitgen are clean.
  - luau-lsp shows no new messages in src against HEAD.
- **Open:**
  - A wind-up the server drops silently is drawn as a phantom rush.
  - A RushEnded resent after the drawn run is over still overruns at 0.25–0.5 s of lag.
  - The wind-up faces the late root.
  - Studio items 212–220.

## Next three tasks

1. Rerun the Play-test on the new build with the display kept awake: the fight with landed hits (items 99 to 102 and
   106 first), Reduce flashing, sheathing after lock-off, foot slide, then `docs/STUDIO_TASKS.md` items 37 to 96 in one
   sitting (a solo Play, then two players, then the ClipLab), with headphones for the items marked (listen). Report
   each result, the counts the items ask for, and the decisions they hand back (the heartbeat speed into D-083).
2. The owner records the ten gate shots in the Playground with the Capture panel (`docs/clips/phase-0/README.md`),
   with **View > Stats** open during the fight for the fps reading, and hands the files over (here in the project or in
   `docs/clips/phase-0/` on the PC). Each is then reviewed frame by frame at 0.25x, the hand columns of
   `docs/ANIMATION_REVIEW.md` are filled, and anything that reads wrong is fixed with the PoseEditor and recorded again.
3. Fill the section 16 numbers in the performance table: client fps during the recorded fight, draw calls
   (MicroProfiler), client memory (**View > Stats > Memory**), the 8 players + 30 enemies case and a 2020 phone. Then
   merge `phase-0` into `main` and tag it once every gate line reads Met.

### Open items (after the leftover fixes, not in the three above)

- **Code, other owners.** The server sends no `speed` on `ActionStarted` (every remote Art rises at speed 1) and no
  `isSwitch` on hits (the Switch moment, digit and partner flash never fire live); it should confirm
  `hitStop = "Final"` on a guard-breaking hit (the client lifts it today).
- **From the merge check (each has a Studio check, items 91 to 96).** A remote sprint into a dodge plays Skid's
  landing and the Dodge cue's (fix: skip Skid while a FullBody action holds the body). A remote opener from the sheath
  at 85 ms or more of catch-up measures its slash from the back mount, about 80 degrees off (fix: reset the tip ring
  when the weapon motor changes part). The stop carry treats `Humanoid.MoveDirection` as the stick and can keep
  walking with no active controller (fix: read the control module's move vector). The impact overlay and speed lines
  stop at the safe area on notched phones (fix: `ScreenInsets` None, `ClipToDeviceSafeArea` false). `OutlineManager.flash`
  enables Highlights past the 31 budget on a wide kill. Impact frames clone up to 48 parts per rig on the hit frame
  itself (fix: prewarm).
- **Not built yet.** The FX have no time-scale hook, so Capture's slow motion slows only the animation (D-111).
  `Trails.reset()` has no caller until a place change or teleport flow exists.
- **Checks.** The sfx coverage scan counts names inside comments. Not posed yet: a flinch over a FullBody one-shot,
  Draw with a flinch on top, the sheathed set with the sword still in the hand during `sheatheDelay`, the walk-run
  blends, gait weight pops.
- **Clean-up.** `SfxPool.hit`, `parry` and `hitStopTick` and Replication's `SOUNDS.impact`, `block`, `parry` and
  `switchLand` have no game caller: keep or delete. Two deaths in one frame start two ShatterBloom contours; the
  no-rig shatter fallback skips `SfxPool.shatter`'s merge; the merge remembers only the last shatter of each cue.
- **From the aim fix (D-112 to D-116).** A swing sent during the lock's acquisition turn sweeps along the facing the
  server accepts, up to about 49 degrees short of the client's body, so it may miss until the turn has replicated
  (about latency + 0.11 s). Server lag past `combat.lagAllowance` can still get a mid-turn swing refused "Facing".
  The lock turn runs on the render step (not while the display sleeps; DevAim "face" covers tests). Strafing at walk
  speed may slide the WalkLeft/WalkRight feet (item 103). CharacterController reaches TargetController through
  Siblings because `tests/net/TrailingSend.spec.luau` has no TargetController fake. `Assets.url` still returns the
  placeholder id (guarded by the content validator only). MusicDirector's Stop() rewinds a stem (item 104).
- **Design calls.** The settings menu (later phase) must write `SettingReduceFlashing` and `SettingQuality`, and every
  later full-screen flash must ask `FlashBudget`. A cue-level material slot for armor and construct hits. Stance Arts
  against the stop carry (MoveDirection stays non-zero up to 1.2 s) before Phase 1. Strafe and backpedal run clips,
  stance sync markers, foot lock, sheathed reversals and sheathed twins of the shared one-shots, skid only on a stick
  release, a stop carry for remote rigs, hip-height scaling, the hit matrix's wide head box, `ActionRejected` for rate
  drops. The trail snap at 20 fps (up to 42 degrees off on a thrust).
- **Clip re-keys.** The swing foot scraping in the drawn walk and run, Idle's feet below the field, WalkBack's stop-go
  dips, WalkLeftDrawn's left leg (then the lean rule can go, D-058), Breathe's arm keys during Draw and Sheathe (then
  `sheathSlide.breathe` drops to 0, D-050), Draw and Sheathe's elbow. If item 53 hears a double landing, delete the
  dodge clips' Footstep at 0.3 s (keep the Dodge cue's landing layer: it is also the remote dodge's landing).

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
