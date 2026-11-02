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
| The server registered every hit | **Met** in the hit matrix (every window, both enemies, real fight distances, four frame phases; D-045) and in `combat.smoke` in Studio; the recording shows it again as a digit per hit. The first takes (2026-10-25) showed one point-blank Horizontal hit the server did not register; the matrix now also swings at four point-blank placements at 30, 60 and 144 fps (D-234) |
| 60 fps in Studio | **Partly met**: 59.9 to 60.0 fps in Play with the window rendering on the owner's PC (2026-10-20, builds 927dbed and 6d6eb74, frame cap 60, p95 17.6 to 17.7 ms), standing and running with the enemies 66+ studs away; still to read during the recorded fight (**View > Stats**) |
| All tests green | **Met** in Lune on the build with the section AH fixes (2026-11-01: 3879 tests in 233 spec files, 41 validators, `tools/lint.sh --offline` ALL GREEN); CI runs on every push to `phase-0`; the six Studio smokes last passed on earlier builds and still have to run on this one |

| Line | State | Evidence / what is missing |
| --- | --- | --- |
| CI is green: StyLua, Selene, Lune tests, data validators, naming blocklist, `rojo build` | **Met** | GitHub Actions runs on every push to `phase-0` (open the latest run from the repository's Actions tab): format, Selene with the real Roblox std, the whole Lune suite, the validators, the review-report check, the game, both places and the plugin build. `tools/lint.sh --offline` reproduces every step except Selene's Roblox-only lints, which need the API dump; those run only in CI. `aftman.toml` pins the tool versions. |
| Every new clip is in `docs/ANIMATION_REVIEW.md` with the six beats marked present and the hit-stop tier noted | **Met** (generated), hand columns partly filled | All 66 clips are in the table; 9 attacks show the six beats and a tier, and the body audit (D-363) adds its findings per clip. The three hand-filled columns need the ClipLab pass in Studio. |
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

## Gate shot fixes (2026-10-25, D-227 to D-270)

- **Hits (D-227 to D-235, D-267):**
  - A hit's freeze starts on its strike key, from the client's contact (HEAD: 824 of 844 early; now 0 of 845) and from the server's word (0 of 80 early at 0–100 ms of lag).
  - Holds are exactly 3, 6 and 10 frames at 60 fps under jitter. The smear shows only while the blade moves, and Sharp Nail's trail goes out between cuts.
  - The client draws exactly the hits the server counts, over the whole hit matrix at 30, 60 and 144 fps.
  - An Art whose first cut would start inside the enemy steps back up to 1.5 studs during its wind-up.
  - An Art the server takes away shows no tell. No body spin after Sharp Nail. No small-enemy launch in Phase 0.
- **Camera and capture (D-236 to D-251, D-268):**
  - Toe-to-toe fights are framed three-quarter at head height. The lock camera turns at most 150°/s and never looks down onto the hat, and it holds still through the death freeze.
  - Walking into a boar or kobold stops at its body on every side.
  - Each gate shot stages itself in Studio: the player is walked into a ring (never teleported), then the enemies, heal, camera, prompts, auto-stop and optional auto-perform. J gives the field back only once the server agrees.
- **Enemies (D-252 to D-260):**
  - The kobold's tell stays lit to the snap, with a white glint over the parry window. Cones lie on the ground.
  - A parry shows no freeze and eases into the deflect and the stagger.
  - An enemy blow flinches the player on the frame it lands; HP still waits for the server.
  - A dropped wind-up draws no phantom rush, the crouch faces the blow, a jam is read from a root at rest, and a late ActionStarted no longer replays the Charge.
  - Enemies keep room between their bodies.
- **Trails, glow, sound and HUD (D-261 to D-266, D-269, D-270):**
  - The trail is a thick ribbon that follows the arc, and the activation glow reads in daylight.
  - The FinalHit bass cut holds from the hit frame, the heartbeat ducks under the player's own hits, and the shatter glass sits over the bass.
  - Bigger system lines and hotbar labels, plates that lift apart and keep their order, inked speed lines, and a wall-slam shake that fires and reads.
  - A Draw or Sheathe that is cut back stays under the tip-speed cap.
- **Checks:**
  - 2845 specs pass in 156 files (HEAD: 2572 in 140); tools/lint.sh --offline is ALL GREEN. The staging first teleported the player through the anti-cheat's server-move path from its remote, which D-143's caller test refused; it now walks the player into a ring instead (D-244), and that test is unchanged.
  - Stylua, selene, the 32 validators (0 problems), the rojo builds, the hit matrix, the animation review and gaitgen are clean.
  - luau-lsp shows no new messages against HEAD.
- **Open:**
  - Lock-relative movement is not wired (D-238). Kill words are not held (D-267). Holds run 8–17% short at 120 Hz and above.
  - The parry glint is wholly inside the press window only up to 50 ms of one-way latency.
  - A jam still overruns 9–14 studs at 0.25–0.5 s of lag. The trail's first segment can show one frame of wind-up. The slam shake has no falloff.
  - Studio items 221–262, then the gate shots recorded again.

## Gate shot fixes, second round (2026-10-25, D-271 to D-296)

- **Hits (D-271 to D-277):**
  - Holds end on the frame nearest their length at any refresh rate. They are still exactly 3/6/10 frames at 60 Hz, and 120/144/240 Hz now hold about 50/100/167 ms (HEAD 41.7 ms for a Normal hit).
  - A kill's word and its death wait for the strike key. No kill freezes before the key at 30/60/144 fps and 0–100 ms (HEAD: up to 30 of 30).
  - The trail starts at the window's open on the blade's own path (within 0.03 studs; HEAD up to 5.8). Boar/Charge's smear is on its moving frames.
  - A free swing turns onto an enemy within 40° of the look. A fighter outside that cone is cut only by the drawn blade, so the server no longer counts blades a stud short of a fighter to the side.
  - The Art stand-off never steps into a wall or a pillar. A blade meeting the kobold's axe is a clash, never a wound.
- **Enemies (D-278 to D-283, D-295):**
  - A slam rests exactly where RushEnded says, at the wall: 0 studs in during the rush and at most 0.10 after the daze (HEAD 0.5 and up to 3.1).
  - A walk or turn never puts the snout into a wall, and an enemy by a wall still finds its way round and attacks.
  - A blocked rush is told Jammed in 0.033–0.067 s (HEAD 0.10–0.134), which cuts the drawn overrun by about 2 studs at low latency.
  - Blockers collide between enemies, and a stopped rush turns solid only once its blocker is clear.
  - RushEnded is typed, and the validators carry the camera, capture and shatter-balance rules.
- **Camera and capture (D-284 to D-290, D-296):**
  - Walking under a lock reads the lock's frame: walking at a flank walks in (1.80 studs) instead of orbiting.
  - The kill shot holds still through the shard rise (1.30 s).
  - The lock takes the open shoulder by a wall.
  - A boar rushing past is off screen for at most 12 frames (HEAD 24), at most 7.7° a frame.
  - The wall-slam shake falls off from 26 to 32 studs on the real path.
  - The parry glint leads by the client's latency: a press on the glint parries up to 150 ms one way (HEAD 50).
  - Auto-perform's F acts on the staged target only, and stopping a take never launches a held Art.
- **Animation (D-291 to D-294):**
  - The Draw keeps under the tip cap over every gait (worst 74.6 studs/s at 240 Hz over 12 cycle points, about 1.32 studs a frame in Studio).
  - Run and Sprint are generated with a foot peel. Drawn run and sprint plants slide 0.035–0.044 median (HEAD 0.086–0.153), and a held walk plays the walks alone.
  - A hit out of a stance shows the flinch on the strike frame, and the taken-away stance no longer runs its clock into its sound, trail and smear.
- **Checks (final tree, after the id renumbering):**
  - 2955 specs pass in 160 files, 0 failed (HEAD: 2845 in 156), in about 6.5 minutes.
  - tools/lint.sh --offline is ALL GREEN: stylua, selene with 0 errors, the suite, the 32 validators with 0 problems, and the rojo builds of the game, ClipLab and Playground.
  - The hit matrix exits 0: every required placement registers at every frame phase, and the client draws exactly what the server counts.
  - The animation review is current (64 clips). gaitgen matches all 12 gait clips.
  - luau-lsp (old solver) shows 812 messages in src on both HEAD and the tree, none new. The tests have 19 new type messages in five new or changed specs (open).
  - The verifiers found and fixed two breaks: enemies stalled facing walls after the snout guard (D-295), and the slam falloff was never called (D-296).
  - Verified with no change needed: wall stop and jam under 30/45/60 fps jitter; the RushEnded wire; kill words in both wire orders; lock walk, death and rush camera, wall side, glint, Capture lock; trail first segment; drawn gait slide; stance flinch.
- **Open:**
  - Holds at 30 fps: under jitter a Normal hold holds 1 frame in about half the hits (HEAD always 2). It needs a once-per-hold frame count with ties going to the longer hold.
  - Beside rule:
    - The server sweeps from the live root, which lags the drawn body. At 90° mid-snap it still counts a Basic drawn 0.2 studs off the boar at 0.11 s of lag.
    - Client and server can disagree near the ±40° edge.
    - A 45° enemy now needs a lock (owner to confirm).
  - Death and remote rigs:
    - TargetController keys off State "Dead", which arrives before the held EntityDied.
    - A remote player's Art keeps playing on observers after the server staggers it.
    - CharacterController still lights and chimes an Art whose strike was already shown.
  - Enemies:
    - A boar's rear can swing 0.77 studs into a wall on a Recover turn.
    - Corpse blockers stay solid for 4 s and blockerClear skips them.
    - A steep slope ends Jammed with no Wall told.
    - Overrun at 0.5 s of lag is still 11–15 studs (message latency).
  - Camera: shoulder swaps past alternating pillars have no dwell time. Look input waits about 1.47 s after a kill under lock. A boss's longer shatter rise would outlast riseHoldSeconds. There is no glint lead before the first telegraph heard.
  - Sprint Draw at 240 Hz passes the 0.92 moving cap in 3 of 288 cases when sampled at 48 cycle points (the spec samples 12). Drawn slide at 12 studs/s is 0.147–0.189.
  - Missing:
    - Validator rules for the new combat, camera, fx and choreo keys.
    - A clash spark or sound when a blade meets a held weapon.
    - The FlinchFront review row stays open (re-record).
  - Studio items 263–283, then the ten gate shots recorded again.

## Gate shot fixes, third round (2026-10-25, D-297 to D-341)

- **Why:** two Studio runs on the owner's PC. One on 2727b4c, before rounds B and C; its "glint" timing was the clash-star billboard, as its correction says. One on c2f76c1 (round B). Round C (D-297 to D-322) and round D (D-323 to D-341) answer what they found. Every fix has a spec that failed before it.
- **Capture and staged shots (D-297 to D-311, D-319, D-320, D-328, D-337, D-338):**
  - A take ends with its staged enemies held, and the next shot clears them first. Leftover hits per take went from 4/3/3/3 to 0.
  - Art shots press at 0.5 s and launch on release at 1.0 s (was +1.39 to +1.42 s).
  - ThreeQuarter sits 75° off the line at 14 studs on the weapon side: the kobold is in frame 98.4% and 95.8% of its takes (was about 70%), its axe 85.7% and 100% (was 0%). The boar charges from 12 studs and lands one counted hit (Meets). The Open view holds the locomotion take under the lock.
  - The auto-walk sprints in and skids: worst rest 2.25 studs and 8.7° → 0.20 and 0.5°, the same at 0.5x and 0.25x. It walks the last leg again up to 2 times and is never staged outside the ring. A movement key hands over in any phase (auto moves after a key 113 → 0). J needs no change.
  - Auto-perform has `at`, `onClip` reactions with chains, and `every` standing rules, plus a stick, releaseAfter and staged HP on release. A capture Guard comes the latency lead early, and a reaction ends at `to`.
  - Shot 1 is the gate fight: at 60 fps, 12 server hits (5 basics, 7 Art), 6 parries with 6 sparks, 0 hits taken, the boar killed at 10.80–10.93 s with one shatter, 300/300 HP, and the digits equal the server's count. 144 fps is the same; at 17–100 ms of lag, 11 hits.
  - Shot 10 walks, runs, sprints and turns in place by itself: walk at 8.0 studs/s, Fall 1.78 s, Land 2.02 s, skids at 4.85, 8.83 and 13.23 s, turns with 0 studs moved.
  - The panel counts rendered frames ("r N") and flips a 12 px frame-tick square every frame. Sprint is held per source, so a player's Shift let-go no longer ends the panel's sprint (6.08 studs off the path → 0).
  - The F key's staged-only rule (D-328) is in TargetController but inert until Capture.client calls stageTarget.
- **Hits and freezes (D-312 to D-314, D-321, D-326, D-327, D-341):**
  - A hold waits for its word, up to 0.2 s from the contact, so under 0.1 s of lag the number shows inside the freeze (Normal 4 frames). A Kill upgrades the running hold in place, as one unbroken 10-frame freeze with no blade jump.
  - A freeze holds the whole body still: the Mixer holds the procedural channels, and every Art and basic plans a keep-out, so no colliding part goes deeper into a blocker than the swing found it (worst +0.0139). Rising Arc's Normal drift of 0.08–0.2 studs a frame is gone.
  - The hit matrix swings from the keep-out too.
  - An Art that a shown blow dooms never lights: 16 of 16 lit before, 0 of 24 now.
  - Holds are counted in frames from the rig's pace: 30 fps holds 2/3/5 frames in 100% of jittered runs (was 1 frame in 44–52%). 60 Hz stays 3/6/10 and 144 Hz holds 7/14/24. At 45 fps on 60 Hz, Final 5 and Kill 8 frames.
- **Blockers and enemies (D-315, D-318, D-322, D-329, D-332, D-333, D-339):**
  - An enemy's blocker is faces over its rest and idle hull, plus one per held part. The kobold's idle column went 1.03 → −0.025, and its stops front/right/back/left 1.37/2.62/1.37/2.62 → 1.86/3.43/1.69/3.08.
  - The faces are not the body: bodyExtents and the client's rush profile skip them (the drawn boar stopped up to 0.12 short of the server's wall stop; now 0). Every face blocks between enemies.
  - Corpse faces go off at the shatter (about 0.67 s after the death, was 4 s).
  - Spacing is face to face. Closest gaps: heap line −0.346 → 1.849, stack −0.328 → 1.063, three chasing −0.048 → 0.720.
  - DevCombat gains "enemy", "walk", "charge", "part" and "clearparts" (Studio only, no remote, no anti-cheat call), so items 269–272 and 277 can be set up exactly.
  - A dropped attack is cut at the drop's own time, so a charge right after a hold keeps its tell and crouch.
- **Camera (D-323 to D-325):**
  - The death's still shot keys off the kill this client shows and is a still frame: 0.28–0.42 studs a frame → 0.000.
  - A look of 4° or more ends it within 3 frames.
  - A wall-forced shoulder swap dwells 2 s: changes in 5 s past pillars 7/8/6/5/3 → 2/2/2/2/1.
- **Telegraphs (D-316, D-317):** the parry glint is three white frames, one frame early plus the latency lead. Presses on every glint frame parry at 0, 17, 50 and 100 ms on Studio's link and a live one (768 of 768). Unblockable blows never glint.
- **Animation and FX (D-330, D-334 to D-336, D-340):**
  - The Draw is 0.97 s: at most 74.6 studs/s at 240 Hz over 48 points of any gait.
  - The gait phase follows the root's real travel: a flat foot moved up to 0.258 studs between frames, now ≤ 0.037 a frame and ≤ 0.048 net per plant.
  - The trail ribbon reads as an arc: lifetime 0.13 s, full width only at the head, and it ends at the blade's turn-back (217/157/139 px over the cut, 9 frames, 0.32 above the floor). The kill trail lights on its first frame.
  - A stance the server takes away comes down over 0.5 s: tip 110–142 → 55–58 studs/s.
- **Validators (D-331):** new contact, telegraph and wallSlam validators, and rules for the round-B combat, camera.lock, choreo and stride keys (35 validators).
- **PC run on 2727b4c (before rounds B and C), Studio items 221–262:**

| Item | Result | Numbers | Answered by |
|---|---|---|---|
| 221 | Pass | 10/10 Horizontals counted at 2.14 studs, 71° right; every flash had its number | — |
| 222 | (a) fail by numbers, (b) pass | real touch 2.33–2.42 studs, never 1.8; ease-back 0.04–0.10, not about 0.5; largest step 0.33 a frame | The item text was wrong: D-314; item 286 |
| 223 | Pass | no step at the 2.76 touch; root ≥ 0.69 off the wall | — |
| 224(b) | Partial | Finals 6 (Horizontal, Vertical), 5–6 (Rising Arc, Sharp Nail); Sharp Nail Normal 3; Rising Arc Normal drifts 0.08–0.2 a frame | D-271 (round B), D-314; item 288 |
| 225 | Pass | 3/3: no flash or number, glow out in about 0.2 s | — |
| 226 | Pass | at most 0.84° of turn after the Final | — |
| 228, shots 1–9 | Fail in places | shot 1's perform empty, player killed about 5 s after; shot 4 stopped 3.13 from the spot (radius 3); shot 6's charge missed, a second hit for 16 after the take; shot 7's kobold hidden; shots 7–9 hit during the walk | D-306, D-310 (shot 1); D-302, D-303; D-300; D-299; D-297 |
| 230, shot 10 | Fail | perform only pressed F, player never moved; A then D moved about 15 studs each way; camera behind or in front | D-307, D-311, D-301 |
| 231 | Fail | Arts at +1.39 to +1.42 s against the prompt's 1.0 | D-298 |
| 236 | Partial | boar flanks 1.9, front 6.2, back 3.9; kobold front and back 1.35; its right arm and axe inside the player at its right flank | D-315, D-318; item 284 |
| 238 | Partial | wedge lit to +1.27 s; no white seen | D-316; item 291 |
| 240 | Pass | tell out on the Idle frame, no RushStarted | — |
| 242 | (a) pass, (b) inconclusive | flash 0.12–0.13 s before the HP drop at 0.1 s of lag, 0.27 s at 0.25 s | — |
| 255 | Fail | freezes 1–3 frames; number 2 frames (0.05 s) or 5 frames (0.1 s) after the freeze starts | D-271 (round B), D-312; item 298 |
| 256 | Fail | 2-frame freeze, a 1.07-stud blade jump, about 4 frames held 0.1 s later | D-272 (round B), D-313; item 299 |
| 257 | Void | timed the clash-star billboard. The real glint on c2f76c1 (item 278): first-frame press 2/10 at 0 lag, 10/10 at 0.1 s | D-316, D-319; item 292 |
| 259(a), 260 | 259(a) fail, 260 pass | shot 4 rested 3.13 studs out; shot 10's walk round the ledge took 6 s | D-302, D-303; item 316 |
| 262 | Fail | W tap: about 7 more studs, then staged; J: about 3.5 studs of slide | D-304, D-305; item 317 |
| Not run | — | 227, 237, 239, 241, 243–254, 258 (video, 120/144 Hz, a second client, listening, enemy placement) | D-333 hooks place and move enemies |

- **PC run on c2f76c1 (round B), items 264–282:**

| Item | Result | Numbers | Answered by |
|---|---|---|---|
| 264 | Pass | 15 point-blank kills at 0/0.05/0.1 s, 10-frame freezes after the snap | D-312, D-313 make the word land inside |
| 266 | Fail against the text | on the right, 60/75/90° hit with clear −0.15 | The item text was wrong: D-275 corrected; item 290 |
| 267 | Mixed | flush wall and 0.3 off pass; pillar behind sank about 0.07; pillar beside stepped 0.05, not 0.5 | D-314 (the text assumed a 1.8 touch); item 287 |
| 268 | (a) pass, (b) not achieved | hits unchanged when the blade crossed the axe | — |
| 269 | Head-on only | snout at the wall face (0.00–0.25); the client drew no rush and the boar jumped 9.4 studs after a DevCombat place | Not reproduced in Lune; D-339, D-333; items 306, 307 |
| 273 | Mixed | right flank 2.95 (not 1.8); left flank 1.07, inside the body | D-315; item 289 |
| 274 | Fail | camera 0.45–0.76 studs a frame for the first 6 frames of a locked kill freeze | D-323, D-324; items 300, 293 |
| 275 | Pass | left shoulder at 11 studs, at most 0.25 a frame | D-325 adds the dwell; item 294 |
| 276 | Pass | never off screen; under 3.2° a frame | — |
| 278 | (a) pass, (b) fail | 0.1 s: 10/10; 0 lag: 2/10 (white +1.13 to +1.23 s, parries +1.17 to +1.30 s) | D-316, D-319; items 292, 301 |
| 279 | Pass | — | — |
| 280 | (a) pass, (b) note | the stance faded in 0.19 s, the blade sweeping from +3.6 to −4.4 in front | D-340; item 295 |
| 281 | Pass, plus a new fault | Draw tip ≤ 1.27 studs a frame (1.76 at the skid); a guard pressed sheathed snaps 6.2 studs | D-330; the guard is open (guard-draw.patch) |
| 255, 236, 222 re-run | Improved / unchanged / unchanged | 255: full-length freezes, the number still about 5 frames late at 0.1 s; 236: 1.32–1.35 front and back, head in head; 222: touch 2.34–2.43 | D-312; D-315, D-318; D-314 |

- **Checks (final tree, after the id renumbering):**
  - 3170 specs pass in 173 files, 0 failed (HEAD c2f76c1: 2955 in 160), in 568 s.
  - stylua is clean. tools/lint.sh --offline is ALL GREEN in 560 s: stylua, selene with 0 errors, the suite, 35 validators with 0 problems (HEAD 32), and the rojo builds of the game, ClipLab and Playground.
  - The hit matrix exits 0 in 52 s: every required placement registers at every frame phase, and the client draws exactly the hits the server counts, keep-out included.
  - The animation review is current (64 clips, Draw regenerated at 0.97 s). gaitgen matches all 12 gait clips. The CI UDim2 grep prints nothing.
  - luau-lsp (old solver): src has 814 messages against HEAD's 813. The one new is InputController.luau:106 ('true' expected, 'true?' given). rigs.luau's 12 are the old message, with the blocker type now in its text. New specs add 5 real type messages (DevCombat.spec ×3, DevEnemyHooks.spec ×2); the rest are the harness globals every spec has.
  - The code comments' round C and D placeholder ids are now D-297 to D-341 (68 files, comments and spec names only).
- **Open:**
  - GAME_SPEC section 10 says the trail lifetime is 0.18 s; D-335 uses 0.13. Update the spec line or revert the value.
  - Unapplied patches:
    - guard-draw.patch: a guard pressed sheathed draws first; c2f76c1 item 281 snapped 6.2 studs. It needs an id and its Studio check.
    - frameclock-pace.patch: the impact picture reads the pace as the holds do; item 305(b) waits on it.
    - walk-fix.patch no longer applies on this tree: shot 10's walk from shot 9's spot still fails.
  - Capture.client does not call TargetController.stageTarget yet, so D-328 is inert.
  - Freeze and impact frames land on the strike key (touch +2, Rising Arc and Sharp Nail +3), not the contact frame. The fix amends D-227, D-267 and D-272 and changes Replication.
  - Validator rules still missing: camera.lock.lookBreakDegrees and wallSwapDwellSeconds, impact.hold, fx.trail, and stride travelSlipSeconds, flatBand and frameBar. 18 of 133 report sites have no spec case.
  - Holds:
    - At 30 fps with the word at 100–117 ms a Kill upgrade holds 6 frames, not 5; with 8% jitter 11 of 257 Final holds at 30 and 144 fps are a frame off.
    - At 250 ms a Kill can freeze twice, past the 0.2 s cap.
    - A Dead with no kill word now waits 0.25 s before the lock lets go.
  - The travel slip has no leak. In Lune, looping the PC's step pattern for 18 s puts it on its clamp after about 5.5 s, and a sprinting foot then moves 0.152 studs a frame (bar 0.04). Not seen in the engine yet; item 296(b) checks it.
  - Enemies:
    - Four kobolds chasing still end 0.22 inside each other's faces.
    - Attack poses still reach in (kobold Overhead 1.13, boar Charge 1.12).
    - wallGapStuds strict < would need a data change.
    - A parry from sheathed still snaps the blade 7.78 studs, by design (an instant draw-cut).
  - Capture:
    - Shot 6 is off screen for about 68 of 300 frames.
    - The 30 fps fight has a first-guard break.
    - A player leaving during DevStage leaves the field held.
    - InputController's other held actions still use a single flag.
  - Code:
    - TargetController requires the dev CaptureLogic.
    - WeaponMount.spec depends on spec order.
    - A remote fighter's struck stance still fades over 0.2 s (Replication.playReaction and stopReaction).
    - CharacterController reads a shown blow from the local Flinch; a Replication.strikeShown query would be exact.
  - The commit must add the untracked files: the 13 new specs and tools/validators/contact, telegraph and wallSlam.
  - Studio items 284–328, then the ten gate shots recorded again.

## Gate shot fixes, fourth round (2026-10-30, D-342 to D-468)

- Why: the owner's PC run of section AE on 1cf87aa failed 285, 287, 288(b), 290, 295(b), 298(a), 299(a), 300(a), 302(a), 306(c), 307, 308(a), 311(a), 312, 316, 317(a), 319(a), 320(a), 322, 323(d), 325, 327(a) and the held shove in 284, and the frame logs showed every hit cue one frame ahead of the pose it belongs to (M1–M9). The cause was the frame order: a rig's pose is drawn one frame after its step.
- Hit moment: cues wait for the first frame that draws the contact pose (blade moving 1.4–4.7 studs under the flash → 0); a wait for a word is one freeze (3+6 and 3+4 splits → one run); a late kill plays no picture over a moving blade (26 frames late → none); a word holds its bodies over its picture (1–4 of 6 frames moving at 60 fps, 13 of 15 at 144 → 0); held means drawn held (heldShown); holds count whole rig steps (30 fps kills 6 frames in 30 of 70 cases → 0); the pace is the mean of 32 frames (Final 3/1–2 frames → 2, Kill 3/3/3 or 1/1/1 → 2/2/2); an enemy blow freezes both bodies (0 → 4 frames at 60 fps); a 1-HP kill shows "1" (was 5 or 2).
- Camera and FX: the follow stands while a hit is drawn held (0.142–0.160 studs a frame → 0.000), a proven locked kill does not shake (0.37–0.73 → 0.000), every shake starts at one phase (peaks 0.310–0.625 → 0.423 at 22 studs, 0.313 at 28); a trail's arc goes with its window (tails 8/9/10 frames → 2/2/2), an edge-on cut draws a streak (147 px → ≤ 29 px), ribbons name their rig, the smear sits on the 2 snap frames, a cut clip closes its trail at once (90+ frames → 1).
- Clips: a body audit of 66 clips in every game context with a scoped pending list; the player attacks, one-shots and enemy clips re-keyed; the run hands off per joint (Run@ pops 22–31° → none but Basic2 Run@0.5); cancels snap over 3 frames (41–61° pops → none); the blade eases out of a freeze (1.48 → ≤ 0.25 a frame); Rising Arc rises (+0.057 → +0.265); standing turns plant the feet (slide 0.31 → 0.011, drift 1.06 → 0.042); the drawn idle no longer sinks (0.16 → 0); the kobold walk no longer dips (0.28 → 0.007); the travel slip no longer leaks (0.158 → 0.037).
- Bodies and enemies: the reach rule stops each cut at the body's surface (0.32–0.44 deep → ≤ 0.20); the keep-out moves at most 12 studs/s and not inside a strike's hold (0.501 a frame → ≤ 0.200); the stick walk is held by a body shell (hands 0.30–1.08 inside → ≤ 0.03); held enemies are anchored; rushes never teleport (steps 0.747/0.927 → 0.467), end at the line end (0.196 → 0), forgive climbs (Jammed at 15.55 → Done at 22.00), and judge the slam on the drawn Charge pose (0.220 → 0); walks stay out of walls (2.397 → 0.032, 30 s → 2.55 s); the drawn rush shoulders past the player and throws skid dust; a guard holds through a block (dropped 4 of 4 → held 4 of 4) and draws first from the back (1665 → 71.3 studs/s).
- Staging and capture: Behind is a fixed view and Rear is new (camera 0.467 a frame → 0); the stage reads a settled root (charge at +4.1 s → on time); the walk corrects at a walk, waits 0.5 s at rest before asking, faces the shot (18.5° → 1.0°), lets go when blocked (15 s → 1.0 s) and never times out a walk by hand; field enemies land past the ramp (9 of 216 → 0); shot 1 lands 10–13 basics (was 7) and parries on a measured lead (TAKEN → PARRY); shots 7 and 8 stage one attack; f holds on frames drawn held (2 wrong frames a hold → 0); new dev hooks pack, place onWindUp, DevAim draw and a Studio frame cap (30 fps at 33.40 ms); the time-scale key is T.
- Checks: the full suite passes 3666 specs in 219 files; 39 validators, 0 problems; the hit matrix passes; ANIMATION_REVIEW.md is current (66 clips).
- Still open: the follow-through depth on 7 clips (up to 0.53 studs for up to 24 frames); Basic3's reach step (1.25 studs for 0.158); the activation light, chime, FOV kick, TrailOn and footsteps still one frame early; the rush's first drawn move (0.70 at 60 fps, 1.87 at 30); Studio's 240 Hz substep mispredict (about ±0.23); Basic2's mashed pull, enemy Break, Stagger and Walk strides, the RunDrawn leg crossing; the kobold's hipHeight; the owner's avatar feet; the trail lifetime against GAME_SPEC; every PC item in section AF.

## Code leftovers after the fourth round (2026-11-01, D-469 to D-493)

- Why: the fourth round's "Still open" list and its code owners' open issues left code that Lune can fix without the PC: no clip speed on the wire, no Switch from the server, a guard break confirmed at Normal, a Skid under a remote dodge, a sheath-drawn opener's ribbon streak, a stop carry that read its own Move, full-screen effects inside the safe area, flashes past the Highlight budget, clones on the hit frame, stacked shatters, clip cues one frame early, the rush's first drawn move, enemy Break, Stagger and Walk feet, the drawn run's legs crossing, the kobold's hipHeight, the follow-through depth, Basic3's reach step and Basic2's mashed pull. Five owners fixed them side by side; one merge joined them and re-measured each claim.
- Fights: a run's clip speed (0.6 to 1.4) goes on ActionStarted and the server sweeps on it; a remote clip matches the server within 1e-6 at lag 0 and 0.05 s (30/60/144 Hz; speeds 0.6, 1.15, 1.4) (D-469). The server judges Switches and sends isSwitch and switchPartner, so the Switch moment plays in fights (D-470). A guard break is confirmed at Final: 3 → 6 frames, with the Final shake and tick (D-471).
- Remote rigs and input: no Skid under a dodge (LandSoft 1 → 0) (D-472); a sheath-drawn opener caught up 85–250 ms slashes on its line (53–71° → 0.0°) (D-473); the stop carry reads the control module, so with controls off the body stands at frame 72 after 9.47 studs, where it walked 79.8 and never stood (D-474).
- Screen and budgets: the impact overlay and speed lines go edge to edge and the HUD stays safe (D-475); enabled Highlights in a wide kill 41 → 31, re-measured at most 31 with 48 rigs, 18 staggered flashes and 4 tints, every flash shown (D-476); hit-frame clones 52 → 0 (D-477); simultaneous kills make one crack and one bloom (3 blooms → 1) (D-478).
- Cue frames: every clip cue shows on the first frame that draws its pose, on local and remote rigs (1 frame early → 0 at 30/60/144). Re-measured on the merged tree at 30/60/144 Hz: 0 of 1140 events off on the re-keyed player clips (local and remote), 0 of 217 on the re-keyed enemy clips, and 0 of 1026 on remote Arts at speeds 0.6, 1.15 and 1.4, with late starts at lag 0.05 and 0.25 s on their frames. The ribbon head is within 0.001 studs of the drawn tip (was up to 8.99 ahead at 30) (D-479). A boar rush's first drawn step is no larger than the steady step, 0.933/0.467/0.194 at 30/60/144 (was up to 1.867), re-measured in all 54 cases of rate, lag, order and message arrival (D-480).
- Clips: RunDrawn's legs pass (0.238 → 0.038 deep) (D-481); enemy Break and Stagger have 0 audit findings (were Pop 55–62°) and the walks hold their feet over a cycle (drift 5.13 → 0.070 boar, 2.86 → 0.043 kobold) (D-482); the kobold's rest pose stands on the floor (0.200 below → 0.000) under a new rigs validator (D-483); a follow-through rule and re-keys take the worst blade left in the kobold 6 frames past a hold from 0.48 to 0.08 studs and Horizontal's hand in the torso from 0.36 to 0.10 (D-484, D-486 to D-491); Basic3's reach step 1.25 → 1.00 (D-485); Basic2's mashed pull 70% → 47% of the snap and its Run@0.5 off-hand pop 20.24° → 19.6° (D-492).
- Merge fixes: the kobold standing 0.2 higher (D-483) failed 3 FollowThrough specs on the merged tree, so Basic2's 0.067 wind-up key rolls the sword wrist 3.5° less (the leg at 4.8: 0.341 → 0.170 deep), the PENDING list is restated (Basic2 Approach 0.21 → 0.08, Rising Arc's Exit gone), and the held-at-key self-test plays Basic3; each fix was shown failing first (D-493). ANIMATION_REVIEW's Basic2 row was regenerated after the merge. Raising catchUpMaxJump so a fast remote clip can catch up at lag 0.25 was tried and dropped, because it loosens a bound and would start an Art inside its first window (0.333–0.35).
- Mutations: 18 of the 25 rows were broken on purpose (all but D-481, D-484, D-486, D-487 and D-489 to D-491), and each break failed its specs except in three places no spec covers yet: the second light-serial check in Trails (Replication's check already stops the call), CharacterController's stance and dodge reads of MoveInput, and the HUD's insets in HudInstances.
- Checks: ALL GREEN (full): 3792 specs passed in 226 spec files; 41 validators, 0 problems; the hit matrix passes; ANIMATION_REVIEW.md is current (66 clips).
- Still open: a faster clip under 0.25 s lag runs up to 0.100 clip-s behind at 1.4 (catchUpMaxJump); the Weapon motor's Part0 change may show a frame before the hand's pose; Basic2's cock 0.153 into the kobold at 3.5 and 0.170 at 4.8, its mash speed 47% and run hidden 67%; Sheathed Run, Sprint and SprintDrawn legs still cross 0.20/0.25/0.32; the walks' Lab cut-in; the rule for distant Heartbeat-stepped rigs; the Phase 1 Switch payoff; every PC item in section AG (372 to 396).

## Section AF fixes (2026-11-01, D-494 to D-507)

- Why: the owner's PC ran section AF on 48a846f. Part 1 (items 329 to 352): 12 pass, 17 fail. Part 2 (353 to 371 and the rehearsal): every staged boar charge (shots 1, 6 and 11) ended "Jammed" 9 frames into the rush, because a Humanoid anchored on its first physics step goes FallingDown and MoveTo does nothing there for about 3 s; a free S("charge") on the same boar ran Done at 22. So 3 of the 11 rehearsals failed and nothing was recorded. The logs also showed AF's frame names one frame off: the logger reads isPaused at Input+1, before the local character step. Four owners fixed what the code controls, side by side from 48a846f, and one merge put their work on top of round F.
- Boar jam (D-494, D-495): enemies keep out of FallingDown and Ragdoll from the frame they are made and stand up on release. Shot 6's first charge: Jammed 0.15 s after the launch with 0 studs → Done 22.000 and one hit at 1.10 s; a staged kobold's first overhead 3.55 → 0.75 s after go; shot 1 in the loopback probe: 9 hits, 5 parries and a jammed boar → 12 hits, 6 parries, the dodge at 9.3 s, the kill at 10.8 s, 0 hits taken. Up a 40° slope the drawn rush keeps the flat clock: a 3D step of 0.609 is by design, and item 349's 0.5 was below it.
- Held frames, camera and ribbons (D-496 to D-498): the local root holds with its pose on held frames (Lune 0.200/0.100/0.042 → 0.000 at 30/60/144; PC 0.181 at 60), moving a step at a time and ending in the same place; a kill's still shot keeps the shake's last offset (hand-over 0.020–0.211 → 0.000; PC 0.016–0.026); ribbon hosts carry TrailLit, so Studio can time the close's fade (2/1/5 frames at 60/30/144).
- Bodies and staging (D-499 to D-503): hands and arms are kept out of an enemy's body on every sample, with no clip keys changed (deepest at the walk-in rests 0.412 kobold and 0.635 boar → 0.007 and 0.009 at 30–240 Hz; PC 0.69–0.71); the stand-off no longer pushes the root into a wall flush behind (0.13–0.69 → −0.017; PC 0.48); packs dropped at one point stay ≥ 12 studs apart (closest 8.83 → 12.05); a hold or an enemy move ends a waiting charge, so "hold, then charge" runs; the ledge is never built round a body the server still reads late.
- Sheath, lock turn and feet (D-504 to D-507): a sheathed guard under a cover no longer snaps the sword (7.41 → 0.290 per 240 Hz frame; PC 5.7–6.6); the lock turn lands on PreSimulation, so planted feet hold (slide 0.079–0.094 → ≤ 0.010 a frame, drift 0.102 → 0.015); the turn plant counts the pose's own twist (chest 57.5 → 45.4, head 55 → 45.1); the foot IK and a new standHeight channel stand the owner-sized body on the Humanoid's floor (sole +0.681 or −0.20 → within 0.004), and the landing pop drops from 34.8° to 12.0°.
- Studio: section AH (items 397 to 419) moves the logger to Last+2 and names every frame as the logger logs it (the contact pose on F, heldShown from F+1). Its table answers 84 AF lines: 28 fixed, 25 corrected pass lines where the test asked for the wrong thing, 5 not bugs, 18 that need a Studio log before any fix, and 8 still open. Item 398 (the boar jam) runs first; item 419 is the rehearsal and the recording.
- Merge fix: tests/choreo/FollowThrough.spec.luau's self-test "fails a hand pushed into the body after the cut" pushed the hand 2 studs nearer the kobold after the cut. With D-501 the keep-out holds hands and arms out too, so a 2-stud push is taken back whole (no Limb finding; 3 studs leaves 0.24). The self-test now pushes 4 studs (Limb 1.02) and also requires the excess to be over 0.5. No bound moved. Other changed expectations, each in its row: two CharacterController.spec numbers one 60 Hz step later (0.400 → 0.375, 0.315 → 0.3067; D-496) and validators.spec's maxPackSize needles (2 to 25 → 2 to 6; D-499).
- Checks: ALL GREEN (full): 3830 specs passed in 231 spec files, 0 failed; 41 validators, 0 problems; the hit matrix passes; gaitgen matches 12 gait clips; ANIMATION_REVIEW.md is current (66 clips).
- Still open: the rush root's prediction in Studio's frame order (a replicated velocity leading the drawn root would explain 347's snout past the face and its back-snaps; item 401(c) measures it) and the server body resting 0.05–0.28 short of a slam's told stop; the late root's first drawn move (≤ 0.98 at 60); the enemy blow's white a frame after the axe's strike pose (D-355); the torso twisting into a wall behind (0.44 and 0.63) and D-315's aside against 337's slide line; hands at a kobold placed 1.75 away (Sharp Nail Final 0.61, Basic2 0.39); the Humanoid's overshoot past the shell rest (3.14 against 3.27); a cover arriving after the Draw's grab pulls the held sword 0.7–1.66 per 240 Hz frame; attacks out of a sprint (arms 20.4–21.9°, no Sprint@ audit); Skid 22.4–24.0° a 60 Hz frame; the kobold's Idle 0.032 and Walk 0.053 below the field and its 0.055 start drop; C("face")'s one-frame lead; the lines not reproduced in Lune (361's shot 8, 365(b)'s guard, 366(a)'s 6.6-stud jump, 366(c)'s head, 335's sword and axe on frozen frames, 338(b) and (c), 350(b), 345(b)'s Draw jumps, 363(a)); every PC item in sections AG and AH.

## Section AH fixes (2026-11-01, D-508 to D-522)

- Why: the owner's PC ran sections AH and AG on 0582a04. The boar jam is fixed: 24 staged charges ended Done at 22, none Jammed, with the server Humanoid Running on every row. What failed: the client copy of each held enemy read FallingDown (398(a)); shot 6's telegraph came 0.38–0.42 s after the take's start (398(c), 399(f)); shot 1 never killed the boar at lag 0 and pressed no dodge at 0.1 s (400); the drawn rush stepped 0.75–0.82 a row and its snout went up to 0.34 past a wall face (399(a), 401); the tip on held rows and the camera under lag (404, 405); hands 0.4–1.0 inside the kobold and its axe at the 3.5 staging (409); the root box 0.48 into a wall and 1.74 past a pillar (410(b)); a held guard broke on only 1 of 5 Overheads and never came back (413(a)); a sheathed guard's tip at 321 studs/s (415); lock-turn and landing feet (416, 417); and in AG 373(a), 379(b), 389, 390(c) and (d), and 396. Nothing was recorded, because item 419 needs every AH line to pass. Five owners fixed what the code controls, side by side, and one merge joined them.
- Enemies and shot 6 (D-508, D-509): enemy Humanoids keep out of the fall states on each client too (Lune: FallingDown on 196 of 196 held rows → 0; nothing on the client reads an enemy's state, so nothing drawn changes); the alert ends on its fifth AI tick (staged shot 6, go → Telegraph 0.366–0.399 s → 0.316–0.349 s on slightly short frames, and up to 0.401 → 0.351 s jittered; the hit stays 0.800 s after it).
- Shot 1 and the rush (D-512 to D-514): the capture's perform holds its run as a scripted stick the controller reads (lag 0: the boar never killed and its second charge hitting the player → killed at 10.75 s, 0 hits taken); a remote clip's start is heard even when the catch-up starts it past its events (0.1 s: no dodge and a hit at 9.73–9.87 s → the dodge and the kill at 10.70–11.15 s at every lag tried up to 0.25 s, 12 hits, 6 parries); a drawn rush is drawn again after physics against the root physics moved (at the PC's velocity error: the snout past the wall 0.34 → 0.000, drawn steps 0.86 → 0.467 at 60 fps, with no first-move exception).
- Camera (D-515): a still shot or a freeze moves with the body from its first frame (0.1295 studs apart → 0.0000).
- Bodies and the guard (D-516 to D-518): a held guard comes back up after each 1.2 s stagger with no parry window (GuardBreak on 1 of 5 Overheads → 5 of 5); the stand-off's room counts the torsos and the head (the step into a touching wall: Basic1 0.125 → 0, Sharp Nail 0.442 → 0); the gate shots' kobold is staged 4.2 studs out, turned 10.35° to the walk-in's bearing (the deepest hand in its axe across the five shots 0.430 → −0.001, every cut still landing).
- Sword, feet and clips (D-519 to D-522): WeaponMount looks again for a late category or torso and writes WeaponMount and WeaponMountWhy for the logger (the PC's sword most likely never went to the back; the cause is not proven); a body held at spawn stands on the floor (root 3.45 → 3.40, lowest leg +0.050 → 0.000); a landing on the move hands the legs to the stride over 0.15 s (24.3–38.8° → 19.3–20.3° against the stride's own 19.6–22.8); a new ClipAudit rule keeps every settle slower than its snap (Basic1 727 → 154 studs/s against 303, Basic3 395 → 229 against 391; Basic1 per 30 fps row 4.48 → 3.11, where the PC saw 3.99 and 4.94).
- Lines corrected, with no code change (D-510, D-511 and the table in section AI): the 30 cap's frame time is os.clock read first at Last+2 (the cap's releases are ≥ 33.333 ms apart; dt varies 31.5–35.1 ms in Lune); the rush is judged by the root's 28 studs/s, not MoveDirection, which reads 0 for a MoveTo walk; shot 6's 0.35 s is the server's go → Telegraph. The logger at Last+2 reads the tip one row ahead of the picture (Lune's drawn tip is 0.0000 on every held row), so 404's lines judge the tip logged a row before. Also corrected: 399(a)'s "14 rows later", 402(c), 406(c), 407(e), (g) and (h), 412(a), 416(a) and (c), 417(b) and (d), 418(e), and AG 373(a), 389 and 396. AG 379(b)'s 6 of 10 is the 6-target cap (D-010, D-049). Two owner calls drop: the late root's big first drawn step (D-514 draws that row within 28 × dt) and the enemy blow's white with the strike pose (407(g): they already share E).
- Studio: section AI (items 420 to 438). Item 420 adds what every AI line reads: os.clock beside dt, the drawn body at Input+1 for rushes, the root at PreSimulation and PostSimulation, the server root at land, landingUntil and landed, WeaponMount, the clip time and world tip, and the tip one row back. Its table answers 61 AH and AG lines: 17 fixed, 21 corrected pass lines, 4 not bugs, 16 that need a log and 3 still open; it also lists the AG items the PC did not run. Item 421 (shot 1) is the first re-test; item 438 is the rehearsal and the recording.
- Merge: the five patches went on in order (the client upright and alert fix, the camera, the rush and shot 1, the clips and feet with the settle follow-up, the bodies and the guard with the staging follow-up) with no conflicts; the files two owners both changed (CharacterController.spec; dev.luau and the dev validator) merged cleanly with every owner's cases kept. The merged tree before the last patch ran the full check green (3867 specs in 233 files). The merge changed no spec, bound or data value. Changed expectations, each in its row: StandOff.spec's step measured from the backmost colliding part (D-517), DevStage and DevStageKobold's turned look (D-518), and ClipAudit.spec's PC list with the Settle kind (D-522); everywhere else cases were only added.
- Checks: ALL GREEN (full): 3879 specs passed in 233 spec files, 0 failed; 41 validators, 0 problems; the hit matrix passes; gaitgen matches 12 gait clips; ANIMATION_REVIEW.md is current (66 clips).
- Still open: the server body's rest against the told stop (0.126 past after a slam at 60 fps, about 0.58 short of an open run's line end; land again for what is left, once item 420's server log shows which); 399(a)'s white one row after the closest snout, and the 1.903 and 7.77 jumps (not reproduced); D-514 assumes the frame is drawn after PostSimulation (item 420 shows it); the same tick boundary in Recover (the boar's 1.2 s) and the interrupt resume; a client stand-up if an enemy's first client row reads FallingDown; lag 0.1 s adding 8–10 rows over lag 0; the logs AI asks for (404(b)'s 0.29 and 0.37 at 144 Hz, 405(c)'s 0.455 and 1.72 camera jumps, 408(b)'s 0.066 s guard, the 9.2-stud and 4.4 rows at 144 Hz, 409(b)'s missing number, the engine steps of 409(c) and 410); the PC's cause for the sheathed sword (415); the owner's avatar may reach farther than Lune's at 4.2 (the fallback is 4.85); the clips' own lean past the drawn idle at a flush wall (Basic1 0.21 to Rising Arc 0.52); the sheathed player Idle 0.061–0.068 below the floor and the kobold Idle's 0.032 sink; Sprint@ arms at 21.2°; Basic3's recovery start (59 → 229 studs/s in one 240 Hz sample at 0.325, under the rule; a SineInOut there put the blade 0.18 into the kobold's head); FollowThrough reads 60 Hz rows only (Basic1's old lift passed 0.47 deep between rows); the capture's walk-in still Moves in world space without MoveInput.script; a spawn made inside EnemyService.step would lose its lift before physics (no such path found); TrailRibbon's "holds its ages on the frames the rig's animator draws held" fails when the client/Trail filter group runs alone, though it passes alone and in the full suite (order-dependent); every PC item in section AI and the AG items not run.

## Section AI fixes, first part (2026-11-01, D-523 to D-526)

- Why: the owner's PC ran section AI on 4b18b5c, items 420 to 429 (with 432(c)) first, then 430 to 437. Shot 1 passed at lags 0, 0.05 and 0.1 s (421). What failed in 420 to 429: the client copy of every staged enemy read GetStateEnabled(FallingDown) true on rows 0–9 of all 6 takes and FallingDown on every held row (520 at lag 0, 531 at 0.1 s, and 1–2 more after the release at 0.1 s), while the server read Running on all 1063–1086 rows (425(a), (b)); the server boar ran on at 28 studs/s through a slam's told stop and rested 0.126 past it (6.295 against 6.169), WalkSpeed 28 throughout (423(c)), and rested 0.533 short of an open run's line end (21.467 against 22), which the client showed as a 0.58 slide back over about 30 rows (422(d)); the boar's Torso stepped 0.74–0.85 on 2–5 rows a rush (422(a)); and the snout was drawn 0.05–0.37 past the wall face on 3–7 rows a take at lags 0 to 0.1 s, and 1.607 once at 0.25 s (423(b)). In 435(h) a kobold's client copy read FallingDown on 331 of 440 Idle rows. Owners took them side by side from 4b18b5c; this first part merges the enemy and server-rest fixes.
- Enemies upright on each client (D-523, D-524, amending D-508): D-508 asked once, on first sight, and never read the answer, so a copy whose turn-off did not take, or whose Humanoid or EntityKind came later, was never asked again. Now the client reads the copy first and the states back, asks again before every physics step (PreSimulation) and on an EntityKind change until they read off (at most 240 tries), and stands a copy already down up to Running. Lune through the real tracker and Replication, 196 held rows: every late arrival order 196 → 0 FallingDown rows; an EntityKind a frame late 196 → 1 (row 0, then stood up); an engine that drops the first turn-off (the PC's pattern) 196 → 0; pack kobolds held later 196 → 0 in all 6 late orders (0 in one batch); players never asked. Enemy models carry client-only UprightClient, UprightClientWhy and UprightClientTries, which item 442 reads to name the PC's cause (not proven).
- The server boar's rest (D-525, D-526): the landing onto a slam's contact or a run's line end is landed again every server frame for what is left (paced over at least 2 frames, stopped within 0.02, never past, at most 0.25 s), and the mover issues no MoveTo to a goal it has landed on. Lune, with a studio Humanoid fitted to the PC's rows: a slam +0.125 → −0.013 and an open run −0.534 → −0.017 at 60 fps; worst across 60 and 144 Hz with frame jitter 0.534 off and 0.351 past → 0.020 off, never past, no back step; the client's slide back after an open run about 0.58 → under 0.02. Done stays on the run's timer and the root reaches the line end 0.083 s after it (≤ 0.25 s), inside Recover; RushEnded "Interrupted" tells the stop (6.169), not the overshoot (6.295). Three new ai.movement values with validator rules: landFrames 2, landSlackStuds 0.02, landMaxSeconds 0.25.
- The render check (measured on the PC at 4b18b5c, 60 fps, rows at Last+2): a joint Transform written on PostSimulation never shows on screen (the boar's Root lifted 3 studs: not visible; the avatar's RightShoulder +80°: not visible); written in the render step at Camera−1 it shows, steadily; written on PreSimulation it shows on the boar, while on the avatar's arm the game's own PreSimulation write replaces it. On every test the screen matched BasePart.CFrame, and BasePart.CFrame at Last+2 equals the previous row's joint-chain read (300 of 301 rows). So the screen shows the pose as physics solved it, and D-514's PostSimulation redraw has no visible effect: 422(a), 423(b) and 424 stay open, keep their AI lines and are being re-worked.
- Studio: section AJ, first part (items 439 to 443). Item 439 replaces item 420 column 4's marks (land, the landing rows, landingUntil as a bound, landed); 440 is the slam's server rest (423(c)); 441 the open run's rest and the client's slide back (423(c)'s open run, 422(d)); 442 enemies upright on the client, with the new attributes (425(a), (b), (h)); 443 the kobolds' client copies (435(h)). Section AI marks each line they replace "Superseded by item …". The fails in 430 to 437 are being fixed separately; a second part of section AJ follows with their re-tests.
- Merge: the two patches went on 4b18b5c 3-way with no conflicts. Both changed ai.luau, the ai validator, data/ai.spec and validators.spec; every block of both is intact, and their specs pass together (ai.spec 13, validators.spec 220, EnemyUprightClient 15, BoarHooks 10). The merge changed no spec, bound or data value. Changed expectations, each in its row: validators.spec's D-494 fixture carries upright.client (D-523); BoarHooks' frames() are time-based, with no number changed (D-525); everywhere else cases were only added.
- Checks: ALL GREEN (full): 3898 specs passed in 233 spec files, 0 failed; 41 validators, 0 problems; the hit matrix passes; gaitgen matches 12 gait clips; ANIMATION_REVIEW.md is current (66 clips).
- Still open: the PC's cause for 425 (a dropped first turn-off, the connection order, or watch never running; item 442(c) names it); the studio Humanoid's arrival braking is a fit to the PC's 60 fps rows (at 144 Hz it predicted −0.219 on 4b18b5c where round G measured 0.015–0.03 past), so items 440 and 441 decide; a hitch longer than twice the last frame can carry a landing past its stop; D-514's redraw does not show, so 422(a), 423(b) and 424 are being re-worked; the fails in 430 to 437; and every line of section AJ.

## Section AI fixes, second part (2026-11-01, D-527 to D-529)

- Why: the PC's section AI run on 4b18b5c (items 433 to 436) found the drawn guard raise still turning the arms 24–34° a row on its 4th row (436(c)), the dodges turning the arms 30.9–60.3° a row before State read Dodge (436(d)), and a set of feet and tip lines that Lune either matched or could not reproduce (433(b)(d), 434(a), 435(a)(c)(d), 436(a)).
- The guard raise is a snap (D-527): raised drawn with nothing to cut, it comes in as the cancel's hand-over (0.05 s, ExpoOut, D-408). Largest upper-body turn on the 4th row after the press: standing 24.1° → 0.1°, walking 33.5° → 0.8°; done in 2 rows. A guard raised sheathed keeps D-420's Draw over it.
- A dodge takes the body without a pop (D-528): a dodge that cuts nothing takes each joint over its own blend (arms 0.18 s, legs, spine, neck and root 0.12 s), with the gait's phase, pace and weights held under it. Worst turn a row from any stance, walk or run: arms 58.6° → 19.6° (the dodge's own recovery row), legs 40.2° → 18.9°.
- Pass-line fixes with no code change (D-529): 435(a) exempts the drawn stance's heel-up rear foot (D-417), 435(c)'s planted share band is 55–65% (Lune 59–61%, the PC 58–61%), 435(d) and 436(a) judge against the sprint's own foot turn at 24 (31.3), and 433(b) judges only presses made sheathed.
- Needs Studio: 433(b) and (d) (the PC's tip peaks of 301 and 171 against Lune's 61–75) and 434(a) (the PC's pivot slide 0.097 against Lune's 0.005) are not reproduced in Lune; the likeliest cause, an assumption, is frames that get 0 or 2 physics substeps. Items 444 to 446 count the substeps on each row.
- Studio: section AK (items 444 to 452), run after section AJ. Section AI marks each line they replace "Superseded by item …".
- Merge: F2's patch went on 9063a60 with no conflicts. Its specs pass with the first part's; no existing spec, bound or data value changed.

## Section AJ on the PC (2026-11-01, 9063a60)

- Passed: the slam's told stop and its Interrupted stop (440(a), (c), (d), (f), (g); 6.169), the open run's Done timing (441(a)), and every rest at 144 fps (−0.017 to −0.020). The kobolds' feet now sit in the Idle sink (−0.032 to −0.006, 443).
- Failed at 60 fps: the landing's WalkSpeed does not halve each frame (28, 25.22, 8.21, 8.26, 7.63, then slowly to about 2.3), so the root rests short of its stop (the slam −0.060 to −0.090, 440(e); the open run −0.114 to −0.144, 441(b)), lands 0.267–0.285 s after it starts (bar 0.25), and the client's Torso slides back 0.23–0.34 after an open run (0.14–0.22 at 144; 441(d)). A probe on the PC then measured the server Humanoid's MoveTo arrival tolerance at about 0.93 studs: a goal nearer than that never moves the body, and every farther goal stops about 0.93 short, so a landing paced over 2 frames never closes. Being fixed.
- Failed: every enemy copy that arrives while the player's client is present is FallingDown on every held row on the client (442, 443; first row UprightClient StoodUp, tries 2), while the server reads Running. The Humanoid appears on the same frame as the tag but after the tag's handler, the anchored copy falls on its first step, and once down neither turning the state off nor ChangeState gets it up while anchored. A probe on the PC found three ways that hold: turning the fall states off in a DescendantAdded handler the moment the Humanoid appears, setting EvaluateStateMachine false there, or, for a copy already down, EvaluateStateMachine false then ChangeState(Running). The drawn body is the same with or without FallingDown (the root is anchored and Choreo owns the joints). Being fixed.

## Section AI fixes, third part (2026-11-01, D-530 to D-533)

- Why: the render check proved D-514's redraw after physics never reaches the screen, and the PC's x423 wall runs on 4b18b5c showed the boar's snout 0.372 / 0.367 / 1.607 / 0.027 past the wall face on the BasePart read (60 fps lag 0, 0.05, 0.25; 144 lag 0): the screen draws the pose from before physics on the root where physics left it, and the replicated root's move is not what its velocity foretold (0 on most moving rows, 0 → 1.697 in one row).
- The rush's body is drawn off the root's physics move (D-531): while the rush is away from its root, this client turns the boar's root joint off, anchors the Torso and writes it where the step drew it, and puts it back on its joint when the rush hands back. Lune replays all four PC runs row by row through the real path: snout 0.381 / 0.406 / 1.628 / 0.036 → 0.000 past the face; drawn steps up to 1.248 → ≤ 28·dt. The server is untouched; detachBody = false undoes it.
- D-514's redraw is removed (D-532), and its specs now judge the screen.
- The Torso's launch step is the Charge clip's own strike snap on top of the drawn root (D-530): 0.737–0.853 on the screen at 60 fps, as the PC's 0.74–0.85; every other row ≤ 0.484.
- The nameplate and the SWITCH prompt ride the drawn Torso during a charge (D-533): 0.491 / 0.487 / 0.487 / 0.216 off the body → 0.000.
- Studio: section AL (items 453 to 458), run after section AK; 453 checks the engine behaviour D-531 assumes (the client-local joint and anchor writes stick and never replicate). Section AI marks each line they replace "Superseded by item …".
- Merge: E2's patches went on 4e60f11 with no conflicts; its specs pass with every earlier part's; no existing bound or data value changed (RushDrawOrder's existing cases now read the screen with the same numbers).

## Section AK on the PC (2026-11-01, 4e60f11)

- Passed: the drawn idle's feet (447), the landing at walk speed 24 (449), the drawn sprint into an attack (450; arms 18–21°), the drawn guard raise (451), and 15 of 17 dodges (452).
- Failed: the sheathed guard's and the Draw's tip speed at 240 fps (444(a), 445(a)): every row over 84 studs/s is a 2.4–3.9 ms frame right after a 4.5–6.2 ms one, a frame with no physics in between reads 0, and over the pair the tip reads 49–86.5. The lock turn's pivot foot moves 0.012–0.094 (446(a), ≤ 0.01 asked). The locked drawn walk's feet are planted 34% of rows at 60 fps (27% at 144) with a p90 step of 0.065 on the screen against 0.019 on the joint chain (448). Two dodges turn the legs 21.6° and 20.2° on the press row (452(a)), and parts still move until 0.30–0.32 s. Being fixed.

## Section AL on the PC (2026-11-02, f446653)

- 453(a) passed: the client's joint and anchor writes hold for the whole detached stretch and never reach the server, so D-531 stands.
- 453(b) and 456 failed: on the row the Torso goes back on its joint it shows 0.63–0.64 off its joint, about 0.15–0.19 low and 0.6 ahead along the run, and lands back the next row, on every take at 60 and 144 fps; both rows step 0.60–0.70 against 0.48–0.56 at 60 fps and 0.65–0.67 against 0.22–0.28 at 144 (30 fps passes, 0.75–0.81 under 0.98, and so does one uphill take). The PC's probes found the hand-over has to happen at PreSimulation. Being fixed.
- 453(c): the Head and Snout follow the drawn Torso on the same row.
- Passed: the snout stays 0.061–0.073 short of the wall face on every detached row (454(a), 12 of 12), the steps off the launch rows (455(a), 0.48–0.58 at 60 fps, 0.29–0.32 at 144), the launch rows against the drawn root (455(b)), the wall runs' run, skid, slam and crouch rows (455(c)), the uphill run's stop at 22.00 (458(b), 3 of 3), a second charge apart from its re-attach rows (458(a)), the first launch row on 14 of 18 charges (458(c)), and the back charge (458(d), as 424(b)). The nameplate is adorned to the drawn Torso on every detached row (457(a)); after the re-attach it is adorned to the model, which the logger read as no Adornee.
- Failed: the Charge clip's snap row and the two rows after it step 0.79–0.86, 0.60–0.67 and 0.53–0.57 at 60 fps against 0.51–0.53 (454(b), the uphill run in 458(b), and the row after 458(c)'s first); after the stop the body steps back 0.072–0.080 and then 0.040–0.046 at 60 fps on 5 of 6 takes, 0.022–0.038 at 144 (454(b)); shot 6's run rows lead the drawn root by 0.12–0.18 at the turn into the skid on 5 of 6 takes (455(c)); the nameplate misses the drawn body by 0.46–0.52 on stagger rows at 60 fps, and by 0.45 for the rest of a run after a late RushStarted moves the drawn body 0.45 back at lag 0.25 (457(b)); on the uphill run the Torso moves 0.08–0.20 on the slope over 5–9 rows after the stop (458(b)); and after a placement the client detached the Torso for 18–19 Idle rows on 3 takes. No SWITCH prompt showed in solo play, so 457(c) was not read. Being fixed.

## Section AI fixes, fourth part (2026-11-02, D-534 to D-537)

- At a wall or pillar flush behind, the stand-off no longer steps back into room a later lean needs (D-534): the code's step back on touching rows 0.125 (Basic1) / 0.149 (Sharp Nail) → 0.000 at 30, 60 and 144; rows over 12·dt 1 → 0. Left: the clip's own lean, which the engine pushes out (about 0.32 over Basic1).
- The keep-out also keeps the hands out of the kobold as the screen draws them, one frame behind the root (D-535): Horizontal's drawn hand at the walk-in rests 0.065–0.103 inside → ≤ 0.006 (the PC read 0.090) at 30, 60, 144 and 240 Hz, with every cut landing; the body stands up to 0.20 further back at Rising Arc's first key.
- A sword on the back no longer zeroes the keep-out (D-537): that was the PC probe's Basic3 0 at 3.2–3.75 and Basic1 0 at 3.5.
- 430(c) and (d) were logger reads, not code fails: every hit shows its number (the 30 fps 3rd number reused the 1st's freed anchor; now the oldest-freed digit is taken, D-536), and every row over 12·dt is the clip's own forward lunge.
- Studio: section AM (items 459 to 464), run after section AL. Section AI marks each line they replace "Superseded by item …".
- Merge: F1's patches went on f446653; its specs pass with every earlier part's; the hit-matrix tool now runs 73 s (was 55).

## Ribbon fixes (2026-11-02, D-538 and D-539)

- A watcher now draws a late remote basic's ribbon (D-538): at a catch-up of 0.11–0.134 s it drew nothing; now the rest of the stroke, 0.06–3.6 studs at 30, 60 and 144, from the clip's own blade with no streak from the back. When none of the stroke is left (a catch-up of 0.15 or more, or the 0.25 cap) nothing is drawn.
- The ribbon ends on the frame that shows the stroke's end pose, on local and remote rigs, at 30, 60 and 144, with or without a hit (D-539): 51 of 66 Lune cases drew segments after it → 0.
- 374(b) needed no code: the catch-up is right above speed 1, and the PC's 0.106 s came from the message's 0.284 s lateness (0.092 expected, within a frame); the line is corrected.
- 376(b), the sword in the idle hand for one frame when it leaves the back, is real on screen; the fix (WeaponMount's swap on the step that writes the grab pose) is chosen and comes with the next guard and Draw round.
- Studio: section AN (items 465 to 469), run after section AM. Section AG marks each line they replace "Superseded by item …".

## Section AM on the PC (2026-11-02, 006f057)

- Passed: every hit's number shows, counted both ways, at 30, 60 and 144 fps and at lag 0.05 (459); the code's step back or aside stays under 12·dt at 30 and 60 (460(a)) and the engine adds nothing on Art rows (460(c)); Basic3's step back matches the in-game plan at 0.10 (463(a), 3 of 3) and its net move by 0.15 (463(b)); the sheathed plan is no longer zero (463(c)); the head stays 2.84–2.96 from the axe tip (463(f)).
- Failed: Basic3's right arm and hand go 0.14–0.20 into the kobold's Torso at the walk-in rests at 30, 60 and 144, Horizontal's 0.053 at 144 and Rising Arc's 0.090 at 30 (461(a), (c)), with the joint chain reading the same, so the plan lets them in; placed at 2.0, the idle left hand is 0.30–0.45 inside the kobold's arm (461(e)). Basic1's blade is 0.43–0.57 deep at its key and still 0.19–0.40 in at clip 0.283 and at the clip's end (464): the plan keeps only 0.30–0.45 back where Lune kept 1.05, and the PC found it follows the kobold's idling axe. At a wall or pillar flush behind, the root box ends 0.24–0.50 inside the wall, the torso and head about 0.5 inside, and the body slides 3.4–5.9 studs along it over a take (462). One 144 fps row of Sharp Nail steps back 0.082 against 0.078 (460(a)). Being fixed.

## Enemy clip, upright, landing, ribbon and measure fixes (2026-11-02, D-540 to D-550)

- AG 392(b): an enemy's walk now crossfades by the player's gait rule (D-541). A boar wheeling at half speed walks on its hooves: lowest corner −0.092 → −0.002, slide 0.198 → 0.087–0.113 a frame. The kobold is unchanged.
- AG 391(e): the Kobold Break's axe rests on the dirt instead of 1.75 under the floor and turns at most 2.6° a frame instead of flipping 67° (D-542). The Kobold Walk's axe no longer dips 0.34 under every step.
- AG 391(c): the pass line is corrected. The boar rears its front hooves about 1.0 high, as the clip authors it, not 0.12 (D-540).
- New specs: EnemyWalkStart (8 cases, 4 pending on their slide) and EnemyWeaponGround (11 cases; 3 clips pending, each over its bar by 0.29 studs or 1.9–2.6°).
- Client upright, third pass (D-543, D-544): on 9063a60 every enemy copy that came while the client was in read FallingDown on every held row (442; 443 #38 on 456 of 456), because the Humanoid comes after the tag and an anchored copy that has fallen cannot be pulled out. The client now turns the fall states off inside the Humanoid's own arrival handler (the PC's P1 probe: Running on 2260 and 2080 of as many rows; Lune 196 → 0), and a copy still found down stands up with its state machine off (P1: 862 of 862; Lune 196 → 1). Item 474 confirms it from the game's own LocalScript.
- Section AK's fails, re-read (D-545 to D-547, no code): the tip speeds of 444 and 445 were measured over the wrong frame time (the pose's own speed is 64.7–75.5 and 65.1–71.7, under 84); 446's chain read is built into the read (Lune 0.0785 = the PC's 0.076–0.078) and its screen slide is not reproduced, so item 476 splits physics yaw from the drawing; 448's 144 fps slide is real and reproduced (Lune 0.0503, the PC 0.0514), from D-334's take-up running a frame late on the screen; 452's two fails are the run's own stride on the press row.
- The boar's landing at 60 fps (D-548, AI 440 and 441): the landing's MoveTo aimed at its stop, inside Studio's MoveTo arrival tolerance of about 0.93 (the PC's P2 probe), so the body stalled after one frame and rested 0.06–0.14 short. It now aims 4 studs past the stop and the service halts within 0.02: Lune slam −0.120 → −0.013, open run −0.131 → −0.017, landing 0.267 → 0.100 / 0.083 s; 144 stays within 0.02. 441(d)'s slide back is read on the drawn root (0.016); the Torso's other 0.2 is the Charge clip's own Recovery (D-549).
- A late remote basic now draws its whole slash (D-550): 5.36–5.40 studs at every catch-up from 0.10 to 0.149, against 0.06–3.6 under D-538, from the clip's own blade, and nothing on a frozen frame.
- Studio: section AO (items 470 to 481), run after section AN. Section AG marks each line they replace "Superseded by item …".

## Section AN on the PC (2026-11-02, 006f057)

- Passed: a late remote basic at lag 0.25 draws no ribbon (465(c), 8 of 8), and at lag 0.1 every ribbon that is drawn meets its bars (465(b)); on the swinger's own screen no ribbon segment comes after the end pose at 30, 60 and 144 fps (467(a), 27 of 27), and the light, flash and ribbon head read as 382 asks (467(b) on 26 of 27 takes, 468(b) on 12 of 12); on the watcher no segment comes after the end pose at lag 0.1 at every rate, or at lag 0 at 30 fps (468(a)); one of the two 1.3-speed takes is late by the predicted amount (469(b), +0.0628 against +0.0627).
- Failed: on the watcher at lag 0, at 60 and 144 fps, the hit-stop freezes the remote rig at clip 0.383–0.391, before the stroke's end (0.401–0.404 on the swinger's screen); its blade still drifts 0.02–0.07 a row over the 13–14 frozen rows and lays a segment on 2–4 of them, and after the release the stroke finishes and lays 4 + 3 + 1 more (468(a), 4 of 4). At lag 0.1, the 4 takes whose first row showed clip 0.160–0.164 drew no ribbon (465(b), on D-538's rule, which D-550 since replaced). At lag 0 the ribbon lit 4 rows after P, not 5 (465(a)). One air take kept the light one row past the ribbon's first segment (382(c), 26 of 27). The other 1.3-speed take was 0.020 off, outside its 0.017 tolerance (469(b)). At 30 fps the remote ribbon's head reads 0.14–0.28 from the tip, and at lag 0.1 the light shows while the remote wind-up still moves 0.95–3.2 a row (468(b)). Being fixed.
- 466 (measurement): the tip jumps 6.13–6.22 studs on row P while the hand moves 0.000–0.009, and the hand moves on row P+1, on every take, remote and local; fixed below (D-555).

## Boar rush hand-over and sword-to-hand fixes (2026-11-02, D-551 to D-555)

- The boar's Torso goes back on its joint at PreSimulation, in the order the PC's P4 probe found (D-551): on the hand-back's last row it showed 0.63–0.64 off its chain and stepped 0.64–0.70 at 60 fps (AL 453(b), 456); Lune now reads 0.000 on that row and steps ≤ 0.034 at 60 fps, ≤ 0.011 at 144 and ≤ 0.052 at 30.
- The nameplate, the lock camera and the target keys follow the body where it is drawn, not the root part moved by the offset (D-552): the plate sat 0.46–0.52 off on stagger rows at 60 fps (AL 457(b)); Lune ≤ 0.001.
- A boar placed during its charge is drawn on its new place from the next row (D-553); AL saw its Torso held off its joint for 18–19 Idle rows. A placement under 4 studs still slides back over the hand-back's 0.2 s.
- Section AL's launch, back-step and slope fails are re-read on their own bars (D-554, no code): the Torso's launch rows carry the Charge clip's own snap off the haunches, the back steps after a slam are the daze clip's recoil on a drawn root that stands still, and the slope's late rows are hand-back rows.
- AG 376(b): the sword lands in the hand on the row that draws the grab (D-555), local and remote. The hand's move on row P at 60 fps goes from 0.0016 to 0.038–0.106 remote and 0.089 local. Every row now draws the step's pose a frame late with the sword's place included; the swap row was off by 5.99 studs for an opener, 0.50–0.66 for a Draw and 0.52–0.53 for a Sheathe. A remote sheathed opener's ribbon, read in the hand in the game's frame order, was 15.6° off at 85 ms and is now 0.02° (D-473).
- New specs: SwordToHand (4 tests), WeaponMount (+6), CharacterController (+1), RushDrawOrder (the re-attach and the placement), and DrawnBody, RushDraw and validators cases.
- Studio: section AP (items 482 to 490), run after section AO. Sections AL, AN and AH mark each line they replace "Superseded by item …".

## Section AO on the PC (2026-11-02, 209875b)

- Passed: the Kobold Break's axe stays on the floor and turns ≤ 4.72° a row, in the ClipLab and in game at 60 and 144 fps (471), and the Kobold Walk's axe ≥ +0.008 over the field (472); the boar Stagger's front hooves rear and come down (470(a), (b)); enemies stay upright on the client from the game's own script, Running on every held and released row with the state machine on (474(a) to (d)); the guard and Draw tip speed on the screen ≤ 70.7 studs/s (475); the locked drawn walk plants 59–61% of rows at 60 and 144 fps (477(a)); the dodge's press rows (478, 20 of 20); the slam's and the open run's rests within 0.02 (479(a), (c) to (e), 480(b), (c)); a late remote basic draws its whole slash (481).
- Failed: the boar Stagger rolls onto its left side, its right hooves up to 0.0965 at clip 0.45–0.72 (470(c)), and the boar's only attack is unblockable, so its parry stagger cannot be reached in game; the walk start slides 0.168 for the boar turned 90° and 0.098–0.140 for the kobold at 144 fps (473(a), (e)); a rescued copy reads FloorMaterial Air on all 536 rows of its walk (474(e)); the lock turn's pivot foot moves 0.030–0.086 a row on 5 of 6 turns (476(a)); the dodge out of the drawn run at 16 swings the right arm 20–32° after the press (478(a), 4 of 20); at 144 fps the boar's landing keeps WalkSpeed 28 for 2–3 rows (479(b), 480(a)); one open-run take slid back 0.101 (480(d), 1 of 12). Seen outside the judged clips: the Sheathe at a sprint's Skid stop moves the tip at up to 241 studs/s. Fixed stepping does not make the drawn walk's physics steps regular (477(c)). Being fixed.

## Section AP on the PC (2026-11-02, 318f0a3)

- Passed: the boar's Torso goes back on its joint on the hand-back's last row at 0.000 off its chain and steps ≤ 0.033 at 60 fps, ≤ 0.013 at 144 and ≤ 0.050 at 30 (482, every take); the nameplate rides the drawn body at 0.000 and never steps on the stagger rows (483, 484); shot 6's wall runs keep the Torso within +0.077 of the drawn root (486); a boar placed during its charge is drawn on its new place on the next row (488(a), (b)); the sword lands in the hand on the row that draws the grab on 48 of 48 takes at 30, 60 and 144 fps, local and remote at lags 0 to 0.25 (490(b), (f)).
- Failed or wrongly asked: on the uphill run the drawn root's 3D steps read 0.58–0.635 against a flat bar of about 0.52, and 4–5 run rows a take are over the slope bar by up to 0.107 (485(a), 487(a)); just after the launch snap the Torso steps over its 28 × dt + 0.05 bar on 1 row a take at 60 fps (0.50–0.57) and 2–3 rows at 144 (0.25–0.39) (485(b)); at 30 fps the drawn root steps back 0.018–0.032 after the stop against 0.02 (485(c)); a fresh boar's plate is adorned to the Model, which draws at its bounding box's centre, 1.3 studs off the root (489); 488(c) cannot launch as written, since a placement drops the wind-up (the next charge launched from where it stood); 490(a)'s idle bar (0.003) fails on 12 of 48 takes on idle motion, mostly at lag 0.25, and 490(c) on 2 mid-stroke rows at 30 fps where the blade turns round the wrist. Being fixed or corrected.

## Watcher hit-stop, blade light, rescued upright and wall stand-off fixes (2026-11-02, D-556 to D-564)

- A watcher's copy of another player now freezes on the stroke's end pose, as the swinger's own screen does (D-557): Lune at lag 0 freezes at clip 0.4267 / 0.410 / 0.4003 at 30 / 60 / 144 fps, against 0.3933 / 0.3933 / 0.3864 before (the PC on 006f057 0.383–0.391), with the hit's cues and the last ribbon segment on the row that draws the key.
- A frame drawn held lays no ribbon, however the watcher's copy drifts with its replicated root (D-556): Lune 0 samples on held frames, against 3 / 6 / 7 under a 4 studs/s drift before (the PC saw 1 on 2–4 frozen rows).
- The blade light goes out on the ribbon's first segment, never a frame before it (D-558): Lune 0 of 8 crossing phases off, against 6 of 8 (the PC's one air take of 27).
- A kobold rescued with its state machine off gets it back when let go (D-559), so its floor reads the field and its footsteps play the grass set: Lune walking rows 0 → 299 of 299, against the PC's Air on 536 of 536.
- The stand-off no longer steps a root box the engine pressed into a pillar further in (D-560): Lune's Studio-like body 0.106 / 0.100 a frame on 11 rows at 30 / 60 fps before, 0.000 after. Item 462's setup was squeezed (the face 1.165 from the kobold's Blocker against the drawn idle's 1.558), so its takes now stand where a kobold at its own stop distance leaves the body (D-561), and Lune passes every line there; (b) and (d) read less the clip's own root motion (D-562).
- Corrected without code: 465(a)'s row count (4 rows at 60 fps on 209875b, 3 on this build), 481(b)'s slash is whole on its first row at every rate, and 469(b) uses each take's own arrival (its second take now 0.0001 off).
- Item 490's sword grab passed its headline lines on all 48 takes; its other lines asked for the wrong thing and are corrected without code (D-563, D-564): row P−1 is judged in the root's frame against the sheathed idle's real size (up to 0.40 studs/s for the hand), the 30 fps mid-stroke fails are Basic1's own settle roll about the wrist, 1 row local and 2 remote are the right counts, and the grip bar is the joint's 0.30 offset ± 0.01. Row P's blade turn (θP) and six whole-body rows on B at lag 0.25 go to Studio.
- New specs: WatcherFreeze (3 tests), CueFrames (+1), EnemyUprightClient (+7), StandOffWall (+4, a Studio-like body at a wall and a pillar), and ai and validators cases.
- Studio: section AQ (items 491 to 497), run after section AP. Sections AM, AN, AO and AP mark each line they replace "Superseded by item …".

## Moving-target keep-out, nameplate, enemy walk start and sheath-arm fixes (2026-11-02, D-565 to D-581)

- The keep-out plan now knows how the kobold moves on through a swing: its idle, on from its clock, and each cut's flinch (D-565). Lune with the kobold played as the game plays it, at the 3.15 rest: the hands and arms are ≤ 0.006 inside at 30–240 Hz, posed and as drawn, against 0.035 / 0.040 / 0.095 / 0.115 at 30 / 60 / 144 / 240 before (the PC on 006f057: Basic3 0.14–0.20, Horizontal 0.053 at 144, Rising Arc 0.090 at 30).
- At a target that moves on, the blade's own part is held out between the cuts from 0.1 s after each strike's hold (D-566), and a basic's plan holds on to its clip's end instead of ending with its state at clip 0.33 (D-568): Basic1 at 3.5 leaves the kobold after the cut (Lune −0.022, against 0.192 in before; the PC 0.19–0.40).
- Nothing keeps an idle body out of an enemy (D-567): the idle hands touch the kobold only nearer than 2.70 root to root, every walk-in the PC logged rested at 3.08–3.41, and 2.01–2.13 comes only from a dev placement or a forward dodge (an owner call below). 460(a)'s bar is 12 × the longer of the row's and the row before's frame time (D-496: the PC's 0.082 at 144 came after a 6.83 ms row), and 464(b) reads the trail's line, which the plan caps, with the Weapon part reported beside it.
- The boar's landing at 144 fps is not a fault (D-569): the server lands it on every frame at min(28, left / (2 × dt)), which holds 28 until the body is within 0.39 of its stop, and the PC's log read each write a row late. Lune reproduces the PC's column: 28 on 4 rows, then 0.576, 0.400, 0.700 and 0.400 of the row before (the PC 0.57, 0.35, 0.65 …). Items 479 and 480 now read WalkSpeed at the server's PreSimulation.
- The open run's one 0.101 slide (480(d)) was the old HumanoidRootPart × offset read (D-570): with the root 0.2 s late it reads 0.094–0.232 past at 60 fps in Lune, while the screen and DrawnBody.position read 0.000 past and slide 0.017. The Torso's 0.62–0.71 on 209875b was the stale hand-back row D-551 fixed (Lune 0.217 on this build).
- Every enemy plate sits on its rig's HumanoidRootPart from the first frame the rig has one, re-pointed each Heartbeat (D-571): a boar tagged before its PrimaryPart arrived kept its plate on the Model, which draws at the bounding box's centre (0.68 up and 1.16 toward the snout on the PC, AP 489), so the hand-back jumped the plate there. Lune: on the root within 1e-4 at the hand-back.
- Section AP's rush fails are read on their own bars (D-572, no code): uphill, the drawn root's 3D step is slope travel (Lune 0.608–0.610 against 28 × dt / cos 40° = 0.609 at 60 fps; the PC 0.58–0.635); the launch snap's rows are counted by its 0.05 s, 4 rows at 60 and 9 at 144, and the PC's over-rows all lie inside it; the 30 fps back step is the hand-back's 0.31 first-row share of a root resting 0.06–0.10 short. 488(c) cannot launch by design, since a placement drops the wind-up (D-254, D-333); its line now reads the AI's next charge, which launches from its own crouch. 487(a)'s 4–5 uphill rows over (up to 0.107) are not reproduced in Lune; a report line splits them into the ground probe, the hover and the Torso in the body's space.
- The enemy walk start no longer slides the planted feet at the PC's rates (D-574 to D-576): the gait is paced by the root's own travel, not by the replicated velocity that under-reads it; the chase's 7 → 14 pace step eases over 0.23 s; and the walks are keyed four times a 60 fps frame. Lune in the PC's view: the boar at 90° 0.190 → 0.091 at 60 fps and 0.090 → 0.041 at 144 (the PC on 209875b 0.168 / 0.086); the kobold at 0°, 60° and 90° 0.116 → 0.001–0.059 at 60 and 0.059–0.063 → 0.009–0.029 at 144 (the PC up to 0.140 / 0.098). The boar at 135° and 180° passes too; the kobold's crab-walk there stays open. A planted foot is now a corner within 0.02 of the field on both rows (D-578), since the 0.05 band counted the boar's swing rows (its sole clears only 0.042).
- The boar Stagger's sway onto its left legs is authored, as its header says (D-573): 470 now reads the right hooves rising to about 0.1 and back by 0.74 (Lune 0.0966 at 0.583; the PC 0.0965 at 0.58). The clip cannot play in game, because every boar attack is unparryable (D-577), so 470 is a ClipLab line.
- A Sheathe or Draw caught by a sprint's Skid stop keeps the arm and the sword's joint, and its clock stands through the Skid's brake (D-579): Lune before, the Sheathe's tip up to 419.1 studs/s at 240 Hz and the Draw's 271.8 (the PC on 209875b 241); now ≤ 77.0 and ≤ 82.8, under the 84 cap.
- A dodge pressed over a live Draw or Sheathe leaves that clip the arm until the dodge has gone (D-580). This is what 478(a)'s drawn-run takes hit, since DevAim "draw" plays a Draw and then a Sheathe: Lune before up to 87.7° a row over a Draw and 264.2 over a Sheathe; now ≤ 19.6 on all 68 cases (the PC 20.1–31.63).
- Corrected without code (D-581): 476(b)(2)'s read is the lock write's rigid turn (Lune 0.000–0.27, the PC 0.001–0.44), so item 513 splits the root's drift from which row's Transforms the engine draws, and 478(c)'s 2° match is per joint, not part to root. 476(a) is not reproduced in Lune (≤ 0.005 on the PC's stated facts, against the PC's up to 0.086). For 477(b) and 448, Lune reproduces the PC's screen p90 (0.0236 / 0.0506 against 0.026 / 0.051); a step predictor would give 0.0202 / 0.0338, but Stride.spec's engine-steps block fails its bar on the screen order, so the take-up waits on an owner call.
- New specs: HandsOut (+8, a kobold that idles and flinches on), StandOff (+2), CharacterController (+2), BoarHooks (+1, the landing's pace at 60 and 144 Hz), RushDrawOrder (+10: the open run's end, the slope, the launch snap and the hand-back), HudInstances (+2), DrawnBody (+1), DevEnemyHooks (+1), BoarStaggerHooves (8), EnemyGaitTravel (8), SheathSkid (2), DodgeSheath (2), EnemyWalkStart (the PC's views at 60 and 144 Hz and the pace easing; the boar's 135° and 180° off PENDING), and ai and validators cases; Locomotion.spec's stale-event case is now covered by a Stagger. docs/ANIMATION_REVIEW.md is regenerated for the re-keyed walks.
- Studio: section AR (items 498 to 515), run after section AQ. Sections AH, AM, AO and AP mark each line they replace "Superseded by item …".

## Section AQ on the PC (2026-11-02, 82b82d4)

- 491: passed (b) to (d) on 18 of 18 takes, heldShown from N+1 and the boar's flash on N at lag 0, and no hit picture on the watcher. Failed (a) on 1 of 6: at 30 fps N drew clip 0.4349 against 0.43, which is 0.40 plus a 0.0349 s row. Corrected line: D-584, item 516(a).
- 492: passed (c) on 45 of 45 takes and (d) on 27 of 27 on A and 18 of 18 on B; the light lit on the first row drawing 0.15 on 6 of 6 B takes. Failed on A at 60 fps: the light came a row late on 3 of 27 takes, after a row printing 0.1500 (D-585, item 516(b)). The lit row's own step read 0.783, 0.046 and 0.283 on B (D-585, item 516(c)). The root drifted 0.051 … 0.027 a row on boar1, fixed by D-604 and D-605 (item 516(e)). The newest Core end read 0.237–0.242 on one row of 4 takes, a row drawing 0.350 with no ribbon shown yet (D-586, item 516(h)). B at 144 lag 0.1 read 0.241 on one row, now report only (item 516(i)).
- 493: passed (a)'s formula on 24 of 24, the sheathed first points (6.96–7.53, against 5 and 7), the whole slash on T and T+1, and (c). Failed: the table's counts were one row short of the formula, and the ribbon read 5.43–6.58 rather than about 5.4 (D-587, item 517(a) to (c)). At 60 fps lag 0.1 the longest segment read 0.565–0.611 against 0.52, and the late first points sat 0.29–0.44 from lag 0's against 0.05 (D-588, item 517(d) and (e)). At 144 fps every catch-up was 0.110–0.121, so the slash built over rows (item 517(g)).
- 494: passed, on 4 of 4 lag 0.25 takes within 0.0002 and at lag 0.1 within 0.0012 of the offset.
- 495: passed (a), (b), (c), (e) and (g) (EvaluateStateMachine true and Grass on 565 of 565 rows from R+1). Failed (d) on row R alone: GetState FallingDown in both rescue takes. A state machine turned on while held went off again with one write (i). Fixed by D-589 (item 518(d), (i) and (j)). (f) read 0.346 against 0.435 on chase takes whose AI timing differs, so item 518 replaces them with a scripted 20-stud walk.
- 496: passed (a), (d) and the slide (0.57–0.66, under 1).
  - Failed the pre-check on 5 of 6 takes on the owner's non-colliding Head (0.142–0.212 in), and (c) and (f) by up to 0.016 with the colliding parts at 0.050–0.066 (D-593).
  - Failed (b): steps along the face read up to 0.016 (D-594).
  - Failed (e) only on blend rows: 0.106–0.166 (D-595).
  - First-to-First steps were over 12 × dt after long rows, 0.081 against 0.044 (D-596).
  - (g) was squeezed, as expected. All in item 519.
- 497: passed (c), (d) and (f) on 48 of 48 takes.
  - Failed (a) on 1 of 48, by 0.00003 (D-591, item 520(a)).
  - Failed (b) on the 4 takes at 144 fps lag 0.25, ratio 1.5–2.9: the engine stepping A's replicated root at velocity 0.000 (D-591, item 520(b)).
  - (e) read θP 0.0–1.29° on every take against the key's 4–27°: the blade placed from the back mount's rest, fixed by D-590 (item 520(e)).
  - (g) found no speed over 0.25 studs/s while A stood, so no deadband (D-592).

## Section AR on the PC (2026-11-02, c78acd1)

- Logger correction: the owner's avatar joints are AnimationConstraints, not Motor6Ds, so the logger's joint-chain read of the player fell back to the BasePart. The chain column beside 498 was therefore not an independent read; the BasePart judgements stand. The logger now reads every joint's Transform, and 513 was re-run with it. Item 514(a)'s chain read is not valid either.
- 498: passed (a) at 60 and 144 (Horizontal's LeftHand 0.024–0.029 in), (d) and (f). No hand came near the axe (c). Failed (b) at 30 fps on Horizontal: the LeftHand was in the kobold's Torso on 7 held rows at clip 0.167, by 0.116–0.139. Fixed by D-606 (item 522).
- 499: passed (d) on 12 of 12 takes, and (a) at 60 on 6 of 6.
  - Failed (a) at 144 (0.073 and 0.037 in, LeftArm) and at 30 (0.041 in). Lune does not reproduce this; item 523(a) logs the avatar's scales and the flinch clock.
  - Failed (b): 0.528–0.586 at 60 and 0.280–0.325 at 144 on the row nearest 0.15, which draws the step before the contact (D-607, item 523(b)).
  - (c)'s keep(0.15) read under keep(0.10) because the read left out Basic1's own root motion (item 523(c)); keep(0.15) is still open.
- 500: every touching row sits on 12 × the longer frame; 18 rows were over by ≤ 0.0009, the render step's dt against the logger's. Corrected line: D-608, item 524.
- 501: passed (c), (e) and (f). Failed (a) and (b) on one row in each of the 9 slams, landed − 1, where paced read 28 or the row before's value. That row is the service's halt, not a fault (D-597, item 525).
- 502: passed (a) and (c) to (f). Failed (b) on the same halt row in all 12 takes (D-597, item 526).
- 503 to 505 and 507 to 509: passed. The drawn body never went past 22.000 and slid back 0.011–0.018. The plates rode the Torso or the root, 0.000 off. The uphill Torso steps were under their bar. A placement drops the wind-up. The fresh boar's plate was on its root from the first row.
- 506: passed (a) and (b) on 19 takes.
  - Failed (c) at 30 fps: the drawn root stepped back 0.038 / 0.064 / 0.024 after the stop, against 0.009–0.010. Fixed by D-602 (item 527(b)).
  - At 144 one Torso step read 0.059 against 0.05: the daze recoil on a long row (D-603, item 527(c)).
- 510: passed (a) to (d) at 60 and 144, 1x and 0.25x.
- 511 failed:
  - (a) the boar at 90° slid 0.116 at 60 and up to 0.0566 at 144 (bar 0.042);
  - (b) the WalkSpeed rises just missed 30 × dt (0.509–0.545 against 0.48);
  - (c) hooves went to −0.072;
  - (e) the kobold at 0°, 60° and 90° slid 0.160 / 0.221 / 0.101 at 60.
  
  D-598 answers the kobold's 135° and 180° (0.298 / 0.380), and D-599 to D-601 its first rows and the boar idle's hoof. The rest is fixed in the enemy walk's next part, re-tested in a later section.
- 512: passed (c), and (a) and (b) at 60 on 10 of 10 takes. Failed at 240:
  - two Sheathe takes with no Skid read 84.6–88.3 and 85.3–87.3 studs/s (D-611, D-612);
  - the Skid played on only 3 of 10 takes (D-612).
  
  Both are in item 528. (d) was not logged.
- 513 (re-run with joint Transforms): passed at −90° and −179°. Failed four turns: the pivot foot moved 0.011–0.047 a row with no root drift, and the engine drew the previous row's Transforms (0.0001–0.0004). Fixed by D-615 (item 529).
- 514, report: p90 0.036 at 60 and 0.065 at 144, and the predictor missed 521 of 603 and 101 of 1318 rows. The cause is the PC's os.clock dt running about 1.5% short of the steps, not the code. Item 530 logs the step clocks for the take-up call.
- 515: passed (a) on 18 of 20 and (d) on 19 of 20, and the Draw take of (c).
  - Failed (a): drawn walk F LeftLowerLeg 20.40 and drawn run F RightFoot 22.26.
  - Failed (b) on 8 takes: row 1 of the run's B and R takes at 20.48–24.41, which was the body's AutoRotate yaw; rows 16–17 at 20.3–22.5; and a turn in place at 33.60.
  - Failed (c): over the Sheathe the sword was still in the hand at the dodge's end.
  - Failed (d): sheathed run F RightHand 20.72 at row 31.
  
  Answered by D-609, D-610 and D-613 (fixes) and D-614 (the root frame, 60 Hz scaling and a whole-stride bar), in item 531. Item 531(c) now asks for the sword on the back by the row the Sheathe has gone.

## Art tell and stance, sword grab, enemy walk start, rush hand-back, lock-turn and dodge fixes (2026-11-02, D-582 to D-617)

- The rush's ground probe numbers are data (D-582: ai.luau rushWorld probeBoxStuds 0.1, riserBeforeStuds 0.25 and riserPastStuds 0.5, with a validator rule); every rush spec passes unchanged, and a sweep of the code changed since 209875b found no other tunable literal. The SWITCH prompt goes onto its rig's root part on the first Heartbeat the rig has one, as the nameplates do (D-583): a window opened before the PrimaryPart replicated kept it on the Model for the whole 0.8 s, and a rush's hand-back put it back on the Model. Lune: on the root part at the lift within 1e-4, and on the drawn Torso mid-rush.
- Section AQ's watcher lines (491 to 493, the PC on 82b82d4) were traced through the real path, with no code change (D-584 to D-588). A watcher's copy freezes on the first frame at or past the key, at 0.40 plus up to one row of clip: the PC's 0.4349 is a 0.0349 s row, and that pose is the key's within 0.0012. The light came a row late on 3 of 27 takes at 60 fps because those clocks summed a hair short of 0.15 (nine exact 1/60 steps sum to 0.14999999999999999). 492(e)'s 0.237–0.242 come from a row with no ribbon shown yet. 493(a)'s formula holds (24 of 24 on the PC); only its table had dropped a row. A late basic's slash starts on the clip's own blade, 0.032 from an on-time copy's, and at 144 fps catch-ups under 0.142 build over the rows to the snap's landing.
- The Art's tell now holds still (D-604, D-605): the stand-off's blade step starts at the activation hold's end (0.25 on every Art) and lands by the window's open at no more than 12 studs/s, and a frame that still draws the hold keeps its root move back a frame, so the step shows with the pose that leaves the hold. Vertical's 0.30 step at 60 fps stepped 0.048 … 0.023 on the 7 rows of the tell (the PC's boar1 on 82b82d4 0.051 … 0.027); it now stands at 0.000 there and lands on the 6 rows to the open (0.092 … 0.008). The reach's 0.65 at the kobold went from 0.104 … 0.050 in the hold to 0.000. A step over 0.60 (0.50 on Rising Arc and Sharp Nail) starts as late as 12 studs/s allows, and maxStuds 1.5 keeps the release's timing (15.6–17.1 studs/s, an owner call below). The contact validator now requires every player Art's hold to end before its first window opens. Where the tell meets the held stance (D-606), the hold reads a frame-summed clock within 1e-4 of its end (D-616: a 144 fps clock summing to 0.25000000000000006 let 0.040 through on the last hold row) and the stance's own steps show on their frames (D-617: its last step had landed on the first frozen row, 0.107 at 30 fps); both now read 0.000 on every hold row.
- A rescued kobold let go reads one FallingDown row, then Running and Grass with its state machine on (495 on 82b82d4). That row is the engine's turn-on step and shows nothing (Lune: the same feet with any floor read, and no footstep on it), but D-559's read-back could take it for a lay-down and keep the state machine off for good. It now waits out the turn-on's fall for up to 12 PreSimulations, and a held copy found down stands up again and waits for its release (D-589). Lune: a turn-on while held, then a walk, 0 → 299 of 299 walking rows on the field; a 144 Hz client on a 60 Hz server, 0 → 297 of 300. Item 518 re-tests 495 on a scripted 20-stud walk.
- The sword's step-asked move between the back and the hand lands at the next PreSimulation (FrameClock.atStepPoseSolve), not at First (D-590), so physics solves the blade on the stroke's key: AQ 497(e) read θP 0.0–1.29° on 82b82d4 against the key's 4–27°, the blade placed from the back mount's rest. In Lune's measured model θP is now the key within 0.01° (14.7–26.9° at 30, 4.2–10.3° at 60, 1.0–3.65° at 144), the 60 fps P+1 tip goes from 0.65–1.22 to 0.51–0.88, and a Sheathe no longer draws on the back at the hand's 77° for a row; row P is unchanged. 497(a)'s bar is hand 1.0 × and tip 2.0 × the frame time in the root's frame, and 497(b) is judged in the root's frame off the idle's glance and weight shifts (D-591): the 144 fps lag 0.25 ratios were the engine stepping A's replicated root at velocity 0.000, and no remote speed deadband is needed (D-592).
- Item 496 found no stand-off step into a wall or pillar: along the face's normal the code's step is 0.0000 at 30, 60 and 144 under the PC's conditions. Its lines are corrected (D-593 to D-596): the pre-check, (c) and (f) on colliding parts at ≤ 0.07, the engine's resting contact (the PC's fails on 82b82d4 were the owner's non-colliding Head, 0.142–0.212 in); (b) along the face's normal (the PC's 0.016 were steps along the face); (e) on rows alone at full weight (the PC's 0.106–0.166 were the blends); (d) and (f) on the long-row bar (the PC's 0.081 on a 3.7 ms row is 12 × 6.75 ms).
- AR 501 and 502's one failing row per take is the service's halt, not a fault (D-597): within landSlackStuds 0.02 the body is stopped dead and no pace is written, and the PC's log, which reads velocity before the service, marks landed a row later. Lune through the real path finds the halt on that row in all 32 takes (left 0.009–0.019; the PC on c78acd1 0.007–0.014), and land to landed read the PC's way matches the PC (0.099–0.118 s at 60, 0.055–0.062 s at 144). Items 525 and 526 judge the pace to landed − 2 and add a halt-row line.
- The Brute wheels (D-598): more than 20° off its target it walks along its facing at half pace while it turns, so the kobold no longer crab-walks from behind: planted feet 0.161 / 0.280 → 0.052 / 0.051 a 60 Hz row at 135° / 180° (0.070 / 0.123 → 0.024 / 0.022 at 144). An enemy's walk steps off from a set point of its cycle (D-599, the kobold's left mid-stance), which takes the start's Idle-to-Walk pull from 0.28–0.37 a 60 Hz row to 0.057–0.176. The walk start is now judged from row 1 as well (D-600), with what is left pinned in EnemyWalkStart. enemy/Boar/Idle's weight shift is re-keyed so no hoof dips into the field (D-601: −0.067 → −0.0134 or higher over the loop, and −0.013 under the Charge's crouch and out of the Stagger).
- The drawn rush's hand-back waits for a late root the server is still landing under the body (D-602): AR 506(c)'s 30 fps back steps (0.024–0.064 on c78acd1) were the slide drawing the body back toward a root that a long row put at the stop while the server still landed it. Lune with the root 0.3–0.4 s late: back 0.052 / 0.041 / 0.031 at 30 / 60 / 144, then forward again → 0.0053 / 0.0027 / 0.0011 and never forward. The 144 fps Torso back-step bar scales with the row's length (D-603): the PC's 0.059 is the daze recoil on a long row.
- An Art's held start pose plans its own keep-out at the press (D-606): at a lock the body steps back as the stance forms (done by clip 0.133) and then stands still through the hold. AR 498(b)'s 30 fps Horizontal LeftHand 0.116–0.139 in the kobold (Lune 0.251 at a 3.08 rest) is now ≤ 0.009 at every rate, with a step back of up to 0.248. 499(b) and 500(a) are read on the right row and clock (D-607, D-608): 499(b)'s 0.53–0.59 is the row before the contact (Lune 0.472 / 0.476 there and 0.198–0.200 on it), and 500(a)'s 18 rows over by ≤ 0.0009 are the render step's dt against the logger's. 499(a) is not reproduced (Lune out at every rate), so item 523 logs the avatar's scales and the flinch clock.
- Dodges out of the run no longer pop (D-609, D-610, D-613): the blend-out picks the stride up at a fixed phase (resumePhase 0.21; the lower legs 21.9 / 25.2 → 13.6 / 15.4 from the drawn / sheathed run), the legs hand off over 0.13 s (row +4 20.7–21.3 → ≤ 19.6), and a dodge cut into a turn in place blends from the turn instead of snapping (up to 67.3 sheathed and 24.7 drawn → ≤ 19.6; the PC on c78acd1 33.60). The Skid's trigger is a fall rate, the same at 60 and 240 fps (D-612: a 0.03 s stop skidded at 60 and not at 240; the PC 3 of 10 at 240), and a stop with no Skid holds a live Draw or Sheathe as a Skid's brake does (D-611: the Sheathe's tip 94.5 → ≤ 79.7 studs/s, against 84). Item 515's turns are read in the root's frame, scaled to a 60 Hz frame (D-614): the PC's row-1 fails were the body's AutoRotate yaw (24.41 in the world, ≤ 20.4 in the root's frame).
- The lock turn's pivot foot holds from any point of the drawn idle (D-615): the Mixer turns the root joint's layered position with the plant's lag, so the idle's weight shift (up to 0.1 stud off the root's axis) turns with the hips. Lune: 0.028–0.031 a 60 Hz row on 38–40 of 48 idle phases → 0.003–0.005 (0 of 48); the PC on c78acd1 read 0.011–0.047 on four of six turns. AR 514's predictor misses (521 of 603 rows at 60) come from the PC's os.clock dt summing about 1.5% short of the physics steps, and 514(a)'s worse p90 is the clocks, not the code: no take-up change landed, and item 530 logs the step clocks for the owner's call.
- New specs: RushWorld (+1), HudInstances (SWITCH's adornee), StandOffHold and StandOff (the hold's step), EnemyUprightClient (the turn-on's fall, a held copy, a copy that stays down), SwordToHand (both placement models), FrameClock, WeaponMount and CharacterController (new cases), StandOffWall (+1, the PC's conditions), BoarHooks (+1, the halt row), EnemyWalkStart (the start rows) and BoarIdleHooves, RushDraw and RushDrawOrder (the late root), HandsOut (the held stance), DodgeRun, DodgeTurn, SkidRate and SheathStop, LockTurnShown and Mixer (the root's yaw), and validator cases for every new data key. Changed expectations, none loosened: StandOff's Art step now starts at stepStart's time; EnemyUprightClient's turn-on case rides the fall out (D-589); EnemyWalkStart's Kobold PENDING is empty (D-598); RigBuilder's boar Blocker narrows to X −1.4007..1.300 (D-601); CharacterController's world casts go 1 → 2 (the stance plan); SheathSkid runs 64 cases a clip, was 32.
- Studio: section AS (items 516 to 531), run after section AR. Sections AQ and AR mark each line they replace "Superseded by item …".

## Next three tasks

1. Run section AS (items 516 to 531) of `docs/STUDIO_TASKS.md` on the owner's PC with the build that has these fixes,
   every item with item 397's frame names, at the frame rates and lags each names, judged on the BasePart read. Report
   every pass line with its numbers. Earlier sections' lines not superseded stand as written.
2. Fix what section AS finds. Queued for the next round: the owner's Head kept out of a wall the fighter backs onto,
   and a Brute's stop distance that grows when the fighter's back is to the world (item 519); a sheathed lock turn's
   pivot foot on item 529's 0.01 bar; 448's take-up, once item 530 has read the PC's step clocks; the keep-out's
   sideways step-aside inside an Art's hold; and the enemy walk's second part (an enemy's stop on its feet, the boar's
   turning hooves and its breath), with AR 510 and 511's re-test. Their re-tests follow as later Studio sections. The
   owner's calls (below, and in AI) go to the owner.
3. The rehearsal and the recording (item 438), once every line passes: rehearse the 11 shots in dev.luau order with the
   frame-tick square on and log any take that fails its own pass lines; if all pass, record each with Game Bar at 60
   fps, High quality, with **View > Stats** open during the fight for the fps reading, and hand the files over (here in
   the project or in `docs/clips/phase-0/` on the PC). Each is then reviewed frame by frame at 0.25x, the hand columns
   of `docs/ANIMATION_REVIEW.md` are filled (with AG item 391(f)'s enemy cells), and anything that reads wrong is fixed
   with the PoseEditor and recorded again. The section 16 numbers and the merge into `main` follow (Open items).

### Open items (after the Art tell and stance, sword grab, enemy walk start, rush hand-back, lock-turn and dodge fixes, not in the three above)

- **Owner calls from the Art tell and stance, sword grab, enemy walk start, rush hand-back, lock-turn and dodge fixes
  (the default is chosen; say if not).**
  - A clip event whose summed clock lands a hair short of its time fires a row late: the ActivationHold light on 3 of
    27 A takes at 60 fps on 82b82d4, and a TrailOn that falls on a frame. Firing every event within
    combat.contact.keyEpsilon (1e-4 s) ahead of the clock would take that row out, at the cost of the same tolerance in
    every reader of event times (Trails, Replication's catch-up checks, CharacterController's hold) and of the Lune
    specs that step exact 1/60 frames moving by a row. The default leaves it open for a later round; item 516(b)
    reports the takes it touches.
  - The Art stand-off keeps maxStuds 1.5 (D-604): the hit matrix's point-blank shoulder placements ask for 1.35 and
    1.45, which only the release's timing fits, at 15.6–17.6 studs/s on those rare steps. Dropping maxStuds to what 12
    studs/s allows from the release (about 1.0–1.1) would give those placements no step, so their first cut would start
    inside the body. A step that cannot start at the hold's end within 12 studs/s starts as late before it as that cap
    allows. The default keeps both.
  - An Art held at a lock steps back up to 0.25 studs as its stance forms at the nearest walk-in rests (D-606), a
    planted stance a hand's width off the foe. Re-keying the free hand's reach in the Horizontal and Sharp Nail start
    poses, so the stance stays clear on its own, is the other way; the default keeps the step back. An unlocked Art
    takes no stance step, since the soft assist picks its target at the release; picking it at the press is the other
    way, and the default leaves unlocked Arts as they are.
  - Item 520(a)'s idle bar carries Lune's blank rig × 2.5, the largest factor the PC's avatar has shown, rather than
    waiting for a Lune rig with the owner's proportions; 520(b)'s floors and 5× ratio are Pass only off the idle's
    glance and weight shifts, and (d), (e) and (f) decide that the grab is drawn on row P. The default adopts both.
  - The owner's Head does not collide, so it shows 0.14–0.21 inside a face the fighter backs onto (up to 0.40 through
    the swings): off screen for the owner in the lock two-shot, in view for a watcher behind. The default keeps the
    Head out of walls, queued for the next round; the ways are a walk shell sized to the Head's box (every fighter then
    stands about 0.16–0.21 off a wall behind) or a colliding Head.
  - A Brute that walks a fighter back to a wall stops 3.0–3.5 root to root, which leaves 2.2–2.7 studs to its Blocker
    against Sharp Nail's lean of 2.71, and the engine pushes the leaning body out (in Lune 0.42–0.51 at the tightest).
    The default is a stop distance that grows when the fighter's back is to the world, queued for the next round; the
    engine's push (today) and a lean-off pose are the other ways. This replaces the earlier wall-pin call's default.
  - G2c's three calls are decided with the defaults closest to the anime feel and built in the enemy walk start's
    second part, whose re-test comes as a later section: an enemy's chase pace eases up from standing (every enemy sets off on its feet and
    winds up about 0.15 s later); an enemy walking-turn plant takes the boar's planted hooves round its turn at 144
    fps; and a breathing boar keeps its hooves within stride.contact (0.02) of the field.
  - The Skid fires on a fall of more than 360 studs/s each second, the old 60 Hz rule, now the same at every rate
    (D-612); a stop with no Skid holds a live Draw or Sheathe while the gait falls faster than 1 step a second (D-611,
    stopBrakeRate 1; 2 leaves 84.0 on a run eased over 0.5 s); and every completed dodge hands the legs back at the
    stride's resumePhase 0.21 (D-609), so the next right Footstep at the run comes about 0.17 s after the hand-back.
    Item 531 keeps the unlocked run's S, A and D takes as a report-only group. The default accepts all four.
  - The take-up for 448 and item 530: run item 530's PreSimulation logging first. If PreSimulation's deltaTime × 240
    matches each row's physics steps, the take-up moves to PreSimulation, where it is exact (Lune p90 0.019 at both
    rates) and Stride.spec's engine-steps block can move to the screen order with its bars as they are; if not, a
    fitted-drift accumulator in the render step (Lune 0.022–0.032 at 60, 0.020 at 144) with a screen-order spec judged
    on the walk's step p90. Keeping D-334 (0.024–0.034 / 0.065) is the third way. This replaces the earlier call on 448
    and 477(b).
  - A sheathed lock turn's pivot foot gets the same 0.01 a row from any point of the sheathed idle: from its
    weight-shift phase (4.25–7.75 s) the blend into TurnLeft or TurnRight still slides 0.0475 / 0.0445 on 16–18 of 48
    phases. It is a blend fix in the turn clips' entry, queued for the next round.
- **From the Art tell, watcher and SWITCH fixes.** Steps that even the release's timing leaves over 12 studs/s keep it
  (maxStuds 1.5: 15.6–17.6 studs/s, above). A body that starts inside the target's blocker still steps out during the
  hold at up to 12 × dt (D-314), since waiting would leave a hand or the torso in the body through the tell. The reach
  at 144 fps moves ≤ 0.002 on the hold's last two rows, the speed cap's lead (item 516(e) allows 0.003 there). The tell
  is not checked on the owner's avatar, which is larger than Lune's (boar1 took a blade step straight ahead, which
  Lune's Vertical never does). B at 144 lag 0.1's row at clip 0.3505 reading 0.241 is not reproduced in Lune (0.256);
  item 516(i) logs it. A watcher's on-time ribbon starts on the copy's drawn blade while it still blends in (0.4–0.7
  off A's own first point), a late one on the clip's own blade (D-550); both follow the lines as written. Hud's close
  writes the Adornee nil under pcall, which Lune cannot check; item 521(e) checks it by eye.
- **From the rescued upright and sword grab fixes.** The release row's own FallingDown stays: no lever measured takes
  it out, and item 518(l) tries ChangeState(Running) right after the turn-on. Where the copy's Running on R+1 comes
  from (the server's replicated state or the engine's own step) is not known; 518(d) and (k) log GetState at
  PreSimulation. resumeSettleSteps is a step count, so at 30 fps a copy that really stays down is kept off after 0.4 s,
  with nothing shown meanwhile. A held, struck rescued kobold still plays stone footsteps (rescue path only). The sword
  grab assumes RunService.PreSimulation runs after the frame's render steps and draw and before that step's physics,
  and that a Part0 or C0 write there is solved by that physics; item 520's θP and P confirm it. The root move on B at
  144 fps lag 0.25 is not yet put down to A's root motion or the engine's interpolation; 520(g) logs both windows. The
  Sheathe's on-back landing has never been read on the PC; 520(e)'s θS asks for it.
- **From the wall stand-off, landing and rush hand-back fixes.** The bench's Head sits further forward on the torso
  than the owner's MeshPart Head, so the Head's depth is reasoned from the PC's numbers, and the PC's larger 144 fps
  back share in 519(a) (−0.158 against Lune's −0.0097) is not reproduced, though it passes. StandOffWall costs about 50
  s more CPU. The landing's halt row keeps whatever WalkSpeed was last written (the last pace, or 28 after an AI tick),
  since a halted Humanoid at its own goal does not move (D-548); 525(g) checks that the body stands. The Heartbeat
  order (the PC's log before EnemyService) is inferred, and the corrected lines use the halt row's left instead. The 30
  fps root lag behind D-602 is assumed (the PC did not log it; 527(d) does); a resting root that jitters toward the
  body faster than 0.5 studs/s would hold the slide for up to 0.6 s; and a hand-back that waits out settleSeconds with
  the root still farther than settleStuds slides as before. The 144 fps Torso row of 0.059 implies a row of about 12.6
  ms; 527(c) logs its dt.
- **From the enemy wheel and walk start fixes.** The kobold's idle stands its lowest foot corner at −0.0325, outside
  stride.contact and inside footSinkStuds, and the start rows' low bar uses that stand. The dev walk
  (EnemyService.walk) still walks straight at its goal while it turns, so it can crab from behind (dev only). The
  kobold's 0.25 s alert turn in place comes before row 0, so a log from the first root move never sees it; one from the
  release would.
- **From the held stance and kobold blade fixes.** 499(a) is not reproduced: Lune is out at every rate and idle phase,
  and a late HitConfirmed only moves the arm further out; a smaller avatar's arm reaches in at clip 0.45, past the
  plan's horizon, so a plan that runs past the clip's end against a flinching target is the next step if item 523 shows
  it. 499(c)'s keep(0.15) reads 0.30–0.45 corrected against Lune's 0.75–0.90; 523's new logs should settle it. The
  release plan's target clock runs about 0.15 s behind the kobold's real idle, which no read has shown. The stance plan
  poses the clip at the hold time while the game freezes up to a frame past it (Sharp Nail 0.009 on a 0.0349 s row,
  under the 0.01 bar). The press now pays a second plan, 43–62 ms in Lune against 25–30 ms for the release's; 522(e)
  times it. The keep-out's sideways step-aside still runs inside an Art's hold at some placements: a kobold 2.7 off at
  130°, turned 30°, steps the body up to 0.20 a 60 fps row sideways on the hold rows (0.64 in all unlocked, 0.42
  locked). It predates these fixes, the stance makes it smaller, and StandOffHold measures only the step back; it is
  queued for the next round.
- **From the dodge, Skid and lock-turn fixes.** 515(a)'s drawn walk F LeftLowerLeg 20.40 is not reproduced (the walk at
  8 reads ≤ 17.2 at one point of its stride), most likely a long row, which item 531 now scales; if it stays over,
  DodgeRun sweeps the walk. A dodge that cuts a Land or a Skid still gets the cancel's snap (not measured). An unlocked
  press turns the body to the stick first (the Humanoid's AutoRotate), which is where the PC's row-1 B and R reads came
  from. The Skid's onset also follows the Humanoid's own deceleration: a sprint let go to the run in about 0.01 s also
  passes 360 studs/s². The stop brake holds a Draw or Sheathe 0.1–0.4 s through a sprint-to-run toggle or a run-to-walk
  slow-down as well. DodgeForward's left forearm and hand peak at 19.5° in any 1/60 s, which leaves no margin for a
  long frame; easing those keys around clip 0.25 would give some. With the PC's row dt, −179's second plant touches
  down at up to 0.0128 on 7 of 48 idle phases (0.0049 at a steady 60 fps). A longer-legged avatar (legs × 1.1 in Lune)
  reads 0.011–0.016 on +135 and +179; pivoting the plant about the measured grounded corner would fix that if the PC
  shows it. The PC's +90 at 0.047 is above Lune's worst on c78acd1's code (0.031), perhaps a larger hip offset on the
  owner's avatar, which D-615 turns whatever its size. D-615 assumes the root joint's C0 on the root part's vertical
  axis, as on the R15 rig.
- **Owner calls from the moving-target keep-out, nameplate, enemy walk start and sheath-arm fixes (the default is
  chosen; say if not).**
  - A forward dodge into an enemy is the only path in play to 2.0–2.1 studs root to root, where the idle hands sit
    about 0.6 inside the kobold (D-567). It could stop at the walk shell's rest, as a walk does; the default leaves the
    dodge as it is, and item 498(e) logs where it ends.
  - Item 499(b) judges Basic1's key on the trail's line, which the plan caps at 0.205, with the Weapon part reported
    beside it. The other way keeps the Weapon part with a 0.41 bar (0.25 plus its 0.16 half-width); the default reads
    the line.
  - The keep-out holds the hands out of the kobold's body, not out of its axe, which only clashes (D-277), though the
    flinch the plan now knows carries the axe 0.39–0.50 into Rising Arc's left hand in Lune. Holding the hands out of
    the axe too is the other way; the default leaves it out, since the PC's reads (≤ 0.017) do not show it.
  - A server landing eases over its last 2 server frames (0.1 s at 60 fps, 0.035 s at 144), not over a fixed time
    (D-569). It shows nowhere on a rush, only on an enemy walk stopped at a wall on a high-refresh server; easing over
    landFrames / 60 s is the other way. The default keeps the frames.
  - At 30 fps the hand-back slides the boar back onto a root resting about 0.1 short, by up to 0.03 a row (about 0.1
    over 0.2 s). Item 506(c) accepts it; the other way is a 30 Hz server landing that puts the root on the line's end.
    The default accepts the settle.
  - The boar Stagger keeps its sway onto its left legs, as its header authors it (D-573). The other way re-keys
    0.45–0.73 so all four hooves stay planted after the crash (zero the Root's roll, x and y and the hips' counter-roll
    there, and flip one case in BoarStaggerHooves.spec). The default keeps the sway.
  - The wall slam's 1.5 s daze plays the 0.3 s FlinchFront (D-577). It could play enemy/Boar/Stagger (the rear, crash
    and sway, 1.0 s) instead: the spec is silent, D-208 says "like a parry", and it is the only way that clip would
    ever be seen in game. The default keeps the flinch.
  - The boar walk's first frame keeps its single ease up to its first sub-key (D-576), so its straight-line 144 Hz
    lift-off row reads 0.041 once a cycle. A full split reads 0.020 there but needs ClipAudit.spec's Boar Walk Lab
    drift PENDING raised from 0.21 to 0.23 (the Lab cut-in drift 0.459 → 0.472), a loosening. The default keeps the
    sub-key.
  - Item 511's planted foot is a corner within stride.contact (0.02) of the field on both rows, not under 0.05 (D-578);
    the default adopts it.
  - 448 and 477(b): on the screen order, Stride.spec's engine-steps block fails its frameBar (0.04, the worst frame) on
    36 of 36 cases under today's take-up (0.035–0.420) and under the proposed step predictor (0.024–0.396); only a
    perfect take-up passes (0.024–0.037), though the predictor improves the p90 the PC reads. The ways are (a) to keep
    the block in the chain order as the model's own check and add a screen-order spec judged on the walk's step p90,
    (b) to re-base the block and judge it on a p90, or (c) to wait for item 514(b) first. Item 514 read the PC's
    clocks; the newer take-up call above (item 532 first) replaces this one.
  - Through a dodge pressed mid-Draw or mid-Sheathe the right arm stays where the clip had it (the hand at the hilt)
    and the clip finishes after (D-580), so the dodge's own arm pose does not show on that arm. The other way is a
    longer arm blend for that case (about 0.35 s for ≤ 20° a row); the default keeps the arm with the clip.
  - Item 515 judges the dodge's blend-out rows against max(20, the gait's own + 1), and the takes over a Draw or
    Sheathe as their own row group (D-581); the default adopts both.
- **From the moving-target keep-out fixes.** In Lune the flinch carries the kobold's axe 0.39–0.50 into Rising Arc's
  left hand, on 006f057's code and now, where the PC read ≤ 0.017; item 498(c) logs the flinch. Basic1's 30 fps key row
  is the contact's held frame at 0.133, before the reach's key, with the trail 0.45–0.47 in: the reach is priced only
  at the key. Without the HeldBlocker, Basic1's blade after the cut reads 0.008–0.053 at idle phase 2, because the plan
  starts each flinch at the strike's key and the game 0.02–0.05 s earlier. The plan predicts a flinch for every cut,
  though Replication plays none on a kill or a break and masks the weapon arm during the kobold's own attack (D-173),
  so it over-holds there; at high ping the word may come after the hold. Basic2's blade from 3.5 is 0.12–0.21 inside at
  its clip end (Basic3 −0.27 to +0.07), outside item 499 and the specs. The PC's Weapon part at Basic1's key read
  0.43–0.57 against Lune's 0.25–0.31: the PC's taller avatar (root 3.24–3.29 against 2.54) or the idle moving the arm,
  which 499(b)'s trail log tells apart. Item 463(b) at clip 0.25 now reads more net back, by the plan's hold off the
  flinch (Basic3's keep(0.25) at 3.5 0.60–0.65 → 1.23–1.48 in Lune), and item 463's probe, which passes no target,
  still prints the old keep there.
- **From the boar landing, rush and nameplate fixes.** The server's landing eases over frames, so a walk a wall cuts
  short (cutStop, D-435) walks at full pace at 144 until 2 frames out (the boar's last 0.11 of 0.27 studs; not
  measured). Items 501 and 502 read WalkSpeed at PreSimulation, so they do not depend on the inferred Heartbeat order
  of the PC's log and EnemyService; item 503(d) measures the root's lag at the run's end, which Lune assumes is 0–0.2
  s. 487(a)'s 4–5 uphill rows over are unexplained in Lune (worst 0.028 / 0.036 under at 60 / 144), and the PC's flat
  runs also show more Torso motion against the drawn root than Lune (486: +0.067 against +0.030), so the cause may be
  Studio's Torso motion rather than the slope; item 507(b) splits it. The 30 fps back steps imply a root resting
  0.06–0.10 short (0.011–0.018 at 60 and 144), perhaps the server's landing on a 30 Hz Heartbeat; item 506(d) asks for
  that gap per take. SWITCH is now put on its rig's root part every frame through DrawnBody.adorn (D-583), and
  RushWorld's probe box is data (D-582).
- **From the enemy walk start fixes.** The boar at 90° at 144 reads 0.041 of 0.042 in Lune, and 0.045–0.048 with a 1 ms
  jitter on the drawn root, so the PC may read it a hair over. Its floor is the planted hooves sweeping round the
  110°/s turn (0.027 a 144 Hz row, 0.064 at 60), which a walking turn plant for enemy rigs, or the walking body drawn
  on a smoothed root as a rush is, would take out. The kobold at 135° and 180° now wheels on its feet (D-598: 0.052 /
  0.051 at 60, 0.024 / 0.022 at 144). Before 0.15 s, outside item 511's window, the Idle-to-Walk crossfade slides a
  planted foot 0.2–0.32 a row on rows 1–8, and the boar's hooves read down to −0.069 / −0.074 there. enemy/Boar/Idle's
  front left hoof is re-keyed out of the field (D-601). The fitted velocity under-read gives the PC's kobold at 0° and
  60° at 144 about 40% low (0.059 against 0.098 / 0.094).
- **From the sheath-arm, lock-turn and dodge fixes.** 476(a)'s pivot slide was the drawn idle's weight shift left on
  the turning root, fixed by D-615 (item 531). 448's take-up waits on item 532's step clocks (the newer owner call
  above). The dodge's legs into and out of the run are fixed by D-609 and D-610. A sprint stopped without a Skid under
  a mid-swing Sheathe is fixed by D-611 (item 530(e)).
- **Owner calls from the watcher hit-stop and wall stand-off fixes (the default is chosen; say if not).**
  - At lag 0.1 a watcher's copy of a swing starts about 0.134 s in and fades in from idle over 0.08 s, so the
    activation's 0.1 s still hold shows for only 0 / 2 / 5 rows at 30 / 60 / 144 fps (item 492(b)). A faster blend into
    the stance would show the hold at the cost of a quicker snap; the default keeps the blend.
  - A watcher's frozen copy still slides with its replicated root during a hit-stop (0.02–0.07 a row on the PC); the
    ribbon no longer follows it (D-556), the body does. Holding the drawn body still under a freeze (an offset like
    the boar's DrawnBody) is a follow-up; the default leaves the body to replication.
  - When an enemy pins a fighter to a wall closer than the fighter's drawn stance fits (under about 1.6 studs between
    the wall and the enemy's body), the engine pushes the body out sideways today. The other ways are an AI rule that
    keeps a pinning enemy at its stop distance from a fighter backed to the world, or a lean-off pose. A Brute's stop
    now reaches a milder squeeze in play, and the newer call above replaces this default.
  - Item 497(e) read θP 0.0–1.29° on every take, the back mount's rest turn for one row; D-590 fixed it, and item
    520(e) re-tests it.
- **From the watcher hit-stop, upright and stand-off fixes.** A held word waits at most 0.25 s for the watcher's copy
  to show its key (D-557), so a copy frozen by another blow first lets it go where it stands. A held, rescued copy
  still reads Air while held, by design (D-559), so a Stagger struck into it while held plays stone footsteps; item
  495(i) showed that a turn-on while held reads FallingDown for a row, and D-589 now stands such a copy up and waits
  for its release. D-559 assumes a state machine turned back on reads the floor on its next step (495(c) checks it).
  The wall slide the PC saw at the squeezed setup (5.7–5.9 studs) is not reproduced by Lune's Studio-like body; item
  496(g) settles it. StandOffWall's Studio-like takes add about 90 s to the Lune suite. Item 497(g) read no replicated
  speed over 0.25 studs/s while A stood, so no deadband was added (D-592). The PC's row-P hand moves are 1.5–2.5 times
  Lune's blank rig's; a Lune rig with the owner's avatar proportions would let them be compared directly.
- **Owner calls from the boar rush and sword fixes (the default is chosen; say if not).**
  - A replicated root that jumps more than 4 studs off its path in one step ends a drawn rush at once (D-553): that is
    over a late root's sideways move (never above 1.7 studs a row in the PC's logs) and under the P3 probe's 13–16-stud
    placements. A shorter placement keeps the hand-back's 0.2 s slide.
  - At 30 fps the boar's launch rows may lead the drawn root by 0.55, against 0.42 at 60 and 144 fps (D-554): it is the
    Charge clip's own snap off the haunches (0.771 in 0.05 s), and a slower frame holds more of it. Slowing the clip's
    launch snap is the other way (a clip change, with the review and audit to redo).
  - The sword's move waits for its pose on the Draw and Sheathe as well as on an attack's draw-cut (D-555), because
    they had the same one-frame mismatch (0.50–0.66 studs off on the swap row). Keeping it for draw-cuts only is a
    one-line change.
- **From the boar rush and sword fixes.** The slope settle (458(b)) is diagnosed, not fixed: its rows are hand-back
  rows whose vertical part is the gap between the drawn height (the ground probe plus the hover at the drawn spot) and
  the root's height while the root still climbs; once item 487 reads that split, the hand-back can close the height
  first or the settle can follow the root's height. The nameplate's Model adornee is fixed by D-571. The PC saw no back
  steps after the stop at lag 0.25, while Lune shows the daze recoil at every lag. RushDrawOrder spec's engine model
  encodes the P3 and P4 probes' readings and does not model C0 writes; 482(d) checks the hand-over row's PostSimulation
  read. The sword fix assumes the deferred Part0 write places the blade from the Transform the pin's release has just
  written; if the engine uses the last solved one, row P draws the blade at the hand's rest key for one row (490(e)
  reports it). SheathTip at 144 Hz (it runs at 60 and 240) flags two Draw cut-backs at 8 studs/s turning the blade
  1083–1089°/s against bladeTurnRate 1080: the existing cut-back fade, unchanged here, left until 144 Hz is a SheathTip
  rate.
- **Owner calls from the enemy clip fixes (the default is chosen; say if not).**
  - The boar's parry stagger keeps its rear-up, front hooves about 1.0 high, up in 0.1 s and down by 0.4 s (D-540); it
    reads from the gameplay camera and the spec only says a parry staggers for 1.0 s. A low recoil (6–8° of pitch,
    hooves about 0.3 high) would re-key its first 0.4 s with the same landing and footstep.
  - The Kobold Overhead's axe bites 0.95 into the ground from 1.37 to 2.17 s, as the clip authors it; kept.
  - A client copy rescued from a fall keeps its state machine off for the rest of its life (D-544); turning it back
    on at release waits on item 474(e)'s FloorMaterial reading. If 474(a) still fails, more Studio rounds follow
    rather than accepting the client's state as cosmetic (the P1 probe saw no drawn difference either way).
  - The boar rocks back 0.2 after every run, as its Charge clip's Recovery steps the forelegs back under it (kept; 480(d)
    reads the drawn root). Re-keying the Recovery so the body settles without moving back is the other way.
  - The landing keeps its ease over the last ~0.1 s at 60 fps (WalkSpeed halving each frame), as D-525 asked.
  - A late remote ribbon is aged by its own clip time, as an on-time one is, so at 30 fps with a catch-up of 0.12 or
    more the whole slash shows for only 2–4 frames; aging it from its first drawn frame instead would keep it 0.13 s.
    The ribbon's head leads the shown sword by 1–4 studs on the first frames because the shown clip is still fading
    in; starting a late clip's blend-in part done would fix that at the cost of a one-frame pose pop on every late
    remote clip (not done).
  - The locked walk's planted foot on screen (448, D-334): replaced by the newer call on 448 and 477(b) above.
    Workspace.PhysicsSteppingMethod stays at the place default (Fixed would cost physics time on every assembly).
- **From the enemy clip fixes.** A boar setting off from behind now passes (D-574 to D-576). The kobold's crab-walk
  from behind is fixed by the Brute wheel (D-598: 0.161 / 0.280 → 0.052 / 0.051 a 60 fps frame). The kobold's flinches
  put the axe 0.389 under and both flinches and its Stagger turn the axe about 22° in one frame (pending in
  EnemyWeaponGround); the audit has no Stagger-out-of-the-Overhead plan. Lune does not model the 144 Hz client's root
  interpolation (item 473 (g) reports it).
- **From the client upright and measure fixes.** An EntityId that arrived after the Humanoid would miss the arrival
  catch and fall once into the rescue (the PC data show EntityId arriving with the tag). The client's fall-state list
  is wider than the server's (it adds Physics and PlatformStanding). 448's take-up fix waits on item 532 (the newer
  owner call above); on item 282's irregular 2–6 pattern no take-up can hold 0.04 a frame at run speed.
- **From the landing and ribbon fixes.** The landing's Humanoid model is fitted to the PC's P2 rows, not engine
  internals, so items 479 and 480 are the real test; the pace drops below WalkSpeed 2 on the last rows, where P2 only
  measured starts from rest. A slam's landing aims 4 studs into the wall, so the Humanoid pushes on the face until the
  halt (under 0.1 s in Lune). 441(c)'s +0.043 one second after Done is not reproduced in Lune; the suspect is Recover's
  AlignOrientation turn about the centre of mass, which 480(c) logs. Set lags from about 0.116 give a catch-up of 0.15 or
  more, past the snap's landing, so they draw no ribbon.
- **From the ribbon fixes.** 376(b), the sword drawn in the idle hand for one frame as it leaves the back, is a
  real screen fault; its fix (WeaponMount's swap on the step that writes the grab pose) is approved and comes with the
  next guard and Draw round, and item 466 measures it until then. Studio's own lag adds about 0.034 s to the catch-up
  (0.134 at a set 0.1), so a lag-0.1 ribbon is very short there. Kobold Overhead's ribbon now ends at its snap's
  landing, 1.35, not at HitWindowClose 1.50.
- **Owner calls from the section AI fixes, fourth part (the default is chosen; say if not).**
  - The drawn hands stay fully out of the enemy (D-535), so Rising Arc's first key stands up to 0.20 further back at
    60 Hz (0.30 at 30 fps) and every cut still lands; the other way is to allow a hair of drawn overlap (≤ 0.05) for a
    closer cut.
  - At a flush wall the body slides about 0.3 toward the enemy over a basic, the engine pushing the clip's own lean
    out of the wall (accepted); taking the lean up smoothly in code would need the keep-out against the enemy in front.
  - A clip's forward lunge moves the root up to 0.40 in one 60 Hz frame (Horizontal at 0.367, Sharp Nail at 0.867),
    kept as authored (item 460(b) reports it).
- **From the section AI fixes, fourth part.** The PC's held kobold asks for little or no aside (0 for Basic1, 0.0287
  for Basic3, against Lune's square-on 0.166 / 0.228); item 463(d) logs its facing and its HeldBlocker to find why.
  The hit-matrix tool runs 18 s longer (a plan per client rate); if that matters, the 30 and 144 Hz plans could be
  made only for cells within reach.


- **From the section AI fixes, third part.** The lock camera, its framing and target distances still read
  DrawnBody.position (root·offset), so during a charge they trail the drawn body by the root's predicted move, as on
  4b18b5c; the same carrier read would fix it (proposed, not done). D-531 assumes engine behaviour item 453 checks
  (client-local Enabled and Anchored writes stick and never replicate, the anchored Torso is drawn where the render
  step writes it, the joint comes back on re-enable); if 453 fails, detachBody = false restores the joint draw.

- **Owner calls from the section AI fixes, second part (the default is chosen; say if not).**
  - The drawn guard raise is a 2-row snap (the arms turn 89–116° on the press row), kept as D-408's hand-over snap,
    which section 10 beat 2 asks for (a guard comes up in 2–4 frames), not eased over 3 rows (D-527).
  - A dodge's arms reach its pose by 0.18 s and its legs, spine and root by 0.12 s, not 0.05 s (kept); its move and
    i-frames are unchanged, and a dodge out of an attack still snaps (D-528).
  - The stride-own rule for one-shots out of a sprint (a row's foot turn within the shown gait's own per-row turn
    + 1°), already open from 436(b), now also reads 435(d) and 436(a) (D-529).
- **From the section AI fixes, second part.** At 144 fps the drawn walk's planted foot slides 0.050 p90 a row on
  screen (0.019 at 60): the gait builds its pose for the last frame's root travel (D-334) and physics moves the root
  over 1 or 2 substeps a frame. Proposed: build the pose for this frame's physics travel; item 448(c) first confirms
  the substep pattern. Out of a drawn sprint into an attack the arms still turn 21–22° a row (the Sprint@ hand-off);
  proposed: stretch locomotion.handOff's arm factors when the gait shown is a sprint, within the first strike key.
  A drawn guard's tip moves 340–358 studs/s for its one snap row at 60 Hz, by design, and no line judges it.

- **Owner calls from the section AI fixes, first part (the default is chosen; say if not).**
  - A client copy of an enemy found already fallen stands up to Running (chosen), not GettingUp: Running is the
    server's state on every held row, and GettingUp would add a get-up beat the server never plays (D-524).
  - After a slam or a run's end the server root eases into its stop over about 0.1 s, WalkSpeed halving each frame
    (kept), not stopping at full pace on the exact stop: a full-pace stop is what ran 0.126 past or braked 0.533 short
    in Studio, and the ease ends inside the daze or Recover (D-525).
  - After an open run the root reaches the line end up to 0.25 s after Done (Lune 0.083 s) while Recover plays (kept):
    Done, RushEnded and the hit sweep keep their clocks, so nothing the client or the hit timeline expects moves (D-525).
- **From the section AI fixes, first part.** The PC's cause for 425 is not proven (a dropped first turn-off, the
  connection order, or watch never running); item 442(c)'s attributes settle it. If UprightClient stays "Waiting" with
  "NotTaken" up to 240 tries, a client SetStateEnabled is not kept from this LocalScript at all, and the earlier probe's
  success needs explaining. If it reads "Off" but GetStateEnabled flips true later, the fix is a per-step check per enemy
  (about 3 engine calls an enemy a frame), not added. The server's Engine.standUp still names GettingUp in code, not in
  data (it could join ai.upright beside client.standUpState). The 1–2 FallingDown rows after a release at 0.1 s are
  assumed to be the engine's (the anchored copy runs its own state machine until physics takes it); item 442(d) logs
  them. The studio Humanoid's arrival braking in Lune is a fit to the PC's 60 fps rows (at 144 Hz it predicted −0.219 on
  4b18b5c where round G measured 0.015–0.03 past); items 440 and 441 decide. A hitch longer than landFrames times the
  last frame can carry a landing past its stop by up to speed × (hitch − 2 × the last dt); it stops on the next frame
  and is never walked back. A Humanoid that brakes a written velocity at once would land more slowly, still within
  0.25 s. A stall between 0.934 studs out and the stop is still caught only by the stuck clock.
- **The render check.** D-514's PostSimulation redraw has no visible effect: the screen shows the pose as physics
  solved it (BasePart.CFrame), a joint written on PostSimulation never shows, and one written in the render step at
  Camera−1 does (the boar's on PreSimulation too). Items 422(a), 423(b) and 424 stay open and are being re-worked.
- **After the recording.** Fill the section 16 numbers in the performance table: client fps during the recorded fight,
  draw calls (MicroProfiler), client memory (**View > Stats > Memory**), the 8 players + 30 enemies case and a 2020
  phone. Then merge `phase-0` into `main` and tag it once every gate line reads Met.

- **Owner calls (rounds F and G, and the section AH fixes).** Rush and camera: should a charging boar slow up a steep
  slope (D-495)? Should the crouch (Armed) smooth over a root that jumps instead of standing exactly on it (D-255;
  only if item 423(d) shows the jumps are the root's own)? Should the wall slam's "first frame largest" mean the offset
  from rest or the frame-to-frame move? AI timing: should every wait the AI tick judges round to the nearest tick
  (Recover, the interrupt resume), or only the alert (D-509)? Should staged beats be judged from the server's go with
  the network logged apart (item 425), or from the client's take start with a larger allowance? Bars: should the first
  step out of a freeze (0.25 a 60 Hz frame) cover the body's keep-out step too? Should the Draw and sheathed-guard tip
  bars be speeds (84 studs/s)? Should foot pops be judged against max(popDegrees 20, the stride's own per-frame turn) +
  1 for moves whose stride already turns more than 20 (the Skid, a landing on the move)? Should Rising Arc's head
  window end at the settle (0.517 s)? Should the head's 45° lead include the turn clip's own look? Restate AG item 396
  as the keep-out's step (the root's travel less the clip's lunge), with the chain reported apart? Walls and bodies:
  keep D-315's aside at a wall (the line becomes "slide beyond the aside ≤ 0.2") or drop it when the world is behind?
  Take the clips' own lean past the drawn idle (0.15–0.52 at a flush wall) out in the clips, now that D-517 keeps the
  plan's step out of the world? Accept that the keep-out keeps hands out of an enemy's body but not what it holds
  (D-277, D-501), with the gate kobold staged at 4.2 studs turned 10.35° (D-518) rather than the asked 3.27, where the
  lock's turn puts a hand 0.143 into its arm? In a fight the Brute walks in to its stopDistance 3.5, where the
  player's idle hand sits about 0.2 inside its axe (Lune 0.197 square on): raise the stopDistance, tuck the idle axe, or
  accept? Should a guard that comes back up after a stagger open no parry window (D-516, chosen because section 6 makes
  a parry a tap)? Should a wide sweep hit more than combat.maxTargetsPerWindow = 6 targets (AG item 379(b))? Should the
  Weapon motor's Part0 swap wait for the grip's drawn frame? Clips: keep Break's get-up inside its 3.0 s, or a full 3 s
  kneel? Is the boar's 0.30 s trot and the kobold's 0.50 s waddle the right read? Accept the kobold's hurtbox 0.2
  higher? Should the pivot foot raise its heel through a lock turn, as a dancer's pivot does (a clip or TurnPlant
  change)? After the cut, Basic1's blade now rolls flat out of the body and settles, and no basic has a Spring overshoot
  any more (D-522): is that the follow-through wanted, or should the basics get a small 5–8° spring at the end of the
  settle, kept under the snap? Keep review.audit.settle.maxSpeedShare at 1 (the spec's "the fastest motion"; the swings
  sit at 51–68% after the fix and the Arts at 7–46%) or tighten it, say to 0.75? Basic2: its mashed wind-up cannot meet
  speed ≤ 40% (judge after the hand-over, cock higher, or a softer hand-over?), and its cock sits 0.153 and 0.170 inside
  the kobold (accept, or move the cock pose and the hit path)? Should ClipAudit judge a carried loop only after the
  fallback idle fades? Systems: should AGI raise Art speed in Phase 0, and on what curve? Should post-motion scale with
  clip speed (chosen no)? Should a newer Switch window replace an older one on the same enemy? Only party members as
  Switch partners once parties exist? A catch-up rate for a late fast remote clip? Fold simultaneous kills of different
  weights into the heaviest shatter cue? The HUD vignette edge to edge on notched phones? The frame rule for distant
  Heartbeat-stepped rigs (AG item 387)?
- **Proposed fixes waiting on a Studio log or an owner call.** (The server body's landing and the client stand-up
  are done: D-525 and D-524. D-514's redraw is measured to show nothing: above.) Brain.ticksWaited for Recover and the
  interrupt resume (owner call). If item 430 still reads a hand over 0.05 with the owner's avatar, stage the gate kobold
  farther (the drawn shell clears the idling axe square on at 4.85). The torso at a wall: keep UpperTorso and Head within
  the drawn idle's back line in the clips (a forward room in the plan cannot clear it at the walk-in rest, which leaves
  about 0.05 in front). Clip re-keys for the sheathed player Idle's soles (0.061–0.068 below the floor) and the kobold
  Idle's 0.032 sink. A cover after the Draw's grab: a least blend-in for arm-keying covers over a live Draw or Sheathe,
  bounded by drawTipSpeed. Attacks out of a sprint: Sprint@ plans in ClipAudit with the drawnSprint additive. A late
  fast remote clip: a Mixer catch-up rate once an Art-speed source exists (raising catchUpMaxJump was tried and
  dropped). FollowThrough read at 240 Hz as well as 60, with its cut read at 240 too (Basic1's cut reads 0.549 at 240 Hz
  against 0.403 at 60).
- **Not built yet.** The FX have no time-scale hook, so Capture's slow motion slows only the animation (D-111).
  `Trails.reset()` has no caller until a place change or teleport flow exists.
- **Checks.** Round F's mutations found three places no spec covers: CharacterController's stance and dodge reads of
  `MoveInput`, the HUD's insets in `HudInstances`, and Trails' own light-serial check (Replication's check already
  stops the call); seven rows were not mutated (D-481, D-484, D-486, D-487, D-489 to D-491). The dense enemy clips'
  generators are scratch scripts outside the repository with no `--check`. The sfx coverage scan counts names inside comments. Not posed yet: a flinch over a FullBody one-shot,
  Draw with a flinch on top, the sheathed set with the sword still in the hand during `sheatheDelay`, the walk-run
  blends, gait weight pops. TrailRibbon's "holds its ages on the frames the rig's animator draws held" fails when the
  `client/Trail` filter group runs alone, though it passes alone and in the full suite: an order dependence to find.
- **Clean-up.** `SfxPool.hit`, `parry` and `hitStopTick` have no game caller: keep or delete.
- **From the aim fix (D-112 to D-116).** A swing sent during the lock's acquisition turn sweeps along the facing the
  server accepts, up to about 49 degrees short of the client's body, so it may miss until the turn has replicated
  (about latency + 0.11 s). Server lag past `combat.lagAllowance` can still get a mid-turn swing refused "Facing".
  The lock turn is worked out on the render step and written on PreSimulation (D-505), so it still stops while the
  display sleeps; DevAim "face" covers tests and keeps a one-frame lead, because it writes the root on Heartbeat. Strafing at walk
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
| `docs/clips/phase-0/locomotion.mp4` | 14 s | sheathed: walk, run, sprint with the sword on the back; lock on to draw; drawn: walk, run, sprint with the blade low and back; turn in place, skid stop, fall off a ledge and land (no jump, D-024); no T-pose, no sliding foot |

### First takes reviewed (2026-10-25)

The owner recorded eight of the ten shots on 66f85c7 (two Desktop recordings, 2560x1440 at 60 fps). Each was reviewed frame by frame at 0.25x; the review is in the project files at `reviews/2026-10-25-gate-shots/REVIEW.md`. The capture counter read one game frame per captured frame (for example 300 of 300 in art-rising-arc), so the game ran at 60 fps during the takes; no Stats readout was taken. Every shot is to be recorded again on the build with the gate shot fixes (D-227 to D-270), which stages each shot itself (D-242).

- fight-boar-kobold.mp4 (20 s): Not met. Not recorded.
- art-horizontal.mp4: Not met. The hit fires before the blade crosses the kobold (f73, f179), so snap/smear/settle are never seen; hit 2 was never registered by the server; take stopped at 3.9 s with two Arts.
- art-vertical.mp4: Not met. The overhead cut never shows: blade frozen straight up 7 frames, chop in 1 frame (f49-56, f167-174). The gauge-heavy hit itself is right.
- art-sharp-nail.mp4: Not met. Only 2 of 3 hit-stops visible (bodies overlap); trail lit between windows (clip data); tell after a hit out of stance; Final cut off.
- art-rising-arc.mp4: Not met. Both hits land on the first frame of the cut (blade still in the start pose); rise onto the toes hidden by the overlapping kobold.
- enemy-boar-charge.mp4: Not met. Take marked done at 0.6 s, before the launch.
- enemy-kobold-overhead.mp4: Not met. Recovery not recorded (stopped at 3.57 s); kobold hidden behind the player; tell ends 18 frames before the chop.
- parry-spark.mp4: Not met. The counted 5 s shows the player dying (guard held 0.45 s early at 18 HP); stagger barely reads even on the later parries.
- kill-shatter.mp4: Not met as cut; met in the take. All three points pass at src 6342; recut source A frames 6280-6579 (camera drift in the freeze still open).
- locomotion.mp4: Not met. 0.4 s of sheathed walk then a boar fight; no run/sprint/lock-to-draw/turn/skid/fall-land, feet never visible.

