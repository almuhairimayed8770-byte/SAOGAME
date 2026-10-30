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
| All tests green | **Met** in Lune on the fourth-round build (2026-10-30: 3666 tests in 219 spec files, 39 validators, `tools/lint.sh --offline` ALL GREEN); CI runs on every push to `phase-0`; the six Studio smokes last passed on earlier builds and still have to run on this one |

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

## Next three tasks

1. Run section AF of `docs/STUDIO_TASKS.md` (items 329 to 371) on the fourth-round build on the owner's PC, at the
   frame rates and lags each item names, and report every pass line with its numbers; fix what fails the same way as
   the earlier rounds. The owner's calls listed in section AF (the trail lifetime against section 10, the kill number,
   the audio and video judgements, gamepad and touch) go to the owner.
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

