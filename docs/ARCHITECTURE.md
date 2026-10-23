# Architecture (Phase 0)

The module map and the contracts between packages. `docs/GAME_SPEC.md` says what the game is;
this file says where each piece lives and how the pieces talk. Keep it current when a contract
changes. Decisions behind it are in `docs/DECISIONS.md`.

## Module map

```
src/shared/
  types.luau                   all shared types (ArtDef, EnemyDef, ClipDef, RigDef, HitResult...)
  data/                        every number in the game (see "Data tables")
  clips/                       Choreo clip data: player/<Weapon>/<Clip>.luau, enemy/<Rig>/<Clip>.luau
  choreo/ClipSampler.luau      pure clip sampling (offsets at time t, events, hit windows, root motion)
  choreo/Joints.luau           one view of a rig joint: Motor6D or AnimationConstraint (D-041)
  choreo/Pose.luau             forward kinematics over the rig's joints with offsets (server hit sweep);
                               Pose.chain reads the joints once for many solves
  net/Remotes.luau             remote definitions: kind, direction, schema, rate limit (from world.luau)
  net/Net.luau                 typed wrapper; server validates and rate-limits every payload
  net/TrailingSend.luau        paces a state request (lock-on target, held guard) to its rate limit with a client token bucket; the last state always goes out (D-056)
  util/                        Signal, Easing, Spring, Verlet, Rng, Check
src/server/
  Main.server.luau             starts services in order
  services/EntityService       entity registry, HP, Guard Gauge, states, death, regen, attributes
  services/CombatService       Art/basic/guard/dodge requests, timelines, hit sweep, damage, parry
  services/EnemyService        spawning, 20 Hz AI tick, threat, telegraphs, enemy strikes
  services/PlaygroundService   Playground spawn tables, player loadout, respawns
  services/AntiCheatService    speed/teleport/timing checks (sprint cap x speedMargin, D-052), Net abuse policy, shadow flag
  combat/DamageMath.luau       pure damage, crit, gauge and guard math (Lune-tested)
  combat/HitSweep.luau         overlap-tests the blade and casts along its arc per damage window (D-042, D-044);
                               never across a jumped root (D-048); only damageable targets count (D-049)
  ai/Brain.luau                archetype base: perception, threat target, decision loop
  ai/Charger.luau  ai/Brute.luau
  world/RigBuilder.luau        part-built placeholder rigs from rigs.luau (Motor6Ds, attachments)
  world/WeaponBuilder.luau     placeholder weapons with WeaponGrip / TrailStart / TrailEnd
  world/PlaygroundBuilder.luau rim, pillars, clouds, kill volume from playground.luau
  world/CharacterReady.luau    waits until the engine has parented, dressed and built a character (D-046)
src/client/
  Main.client.luau             starts controllers in order
  controllers/InputController  ContextActionService bindings (PC, gamepad, mobile), Art hold/release
  controllers/CharacterController  locomotion state, root motion, the two-step stop carry (D-059), dodge, requests to the server;
                               calls Impact.guardRaise / dodge / release / cancelActivation for the local fighter
  controllers/TargetController lock-on
  controllers/EntityTracker    client-side entity registry from CollectionService tags + attributes
  controllers/Replication      remote events -> Choreo, FX, HUD, camera
  choreo/Choreo.luau           per-rig animator: layers, clock, blend, root motion, events
  choreo/ClipLibrary.luau      loads clip modules by id
  choreo/Locomotion.luau       8-direction blend space paced to the root on one gait phase (D-054), turn-in-place, skid, landing squash, foot IK, the sheath
  choreo/LocomotionState.luau  pure blend-space weights: sheathed and drawn sets, gaits, turns, stops
  choreo/WeaponMount.luau      moves the client's copy of the sword between hand and back (D-050)
  choreo/SheathState.luau      pure: when Draw and Sheathe play, stop and move the sword (D-050)
  camera/CameraController      spring follow, FOV, nudge, shake, the FOV punch (D-072), lock-on framing, orbit presets
  fx/Trails, Smear, Shatter, Sparks, Telegraphs, OutlineManager, SwitchRing, Digits, Quality
                               (Trails also keeps each rig's swing direction, D-068)
  fx/Impact.luau               the impact director: one call per combat moment fires what moments.luau names (D-069)
  fx/ImpactFrames.luau         impact-frame overlay: pooled ScreenGui, ViewportFrame silhouettes, ink strokes, the soft dim (D-060)
  fx/ImpactSequence.luau       pure: look timing, per-region flash cost, the dim curve (D-061, D-064)
  fx/FlashBudget.luau          the 3-per-second full-screen flash budget and the Reduce flashing setting (D-061, D-062)
  fx/Glint, SlashArc, SpeedLines  flat reel accents: four-point glint, crescent and slash line, screen-edge speed lines (D-067)
  fx/AccentStep.luau           the accents' shared clock, render step and viewport seam
  ui/lib/                      el(), state cells
  ui/Hud, Nameplates, SystemLine
  audio/SfxPool                pooled voices: layered cues, EQ and reverb contours, trims, fades, playEndingAt, playLate, loops, preload (D-075 to D-094)
  audio/Ambience.luau          the island bed and the rim wind (D-095)
  audio/MusicDirector
  dev/Capture.client.luau      on-screen prompts for gate clips (Playground / ClipLab only)
  dev/ClipLab.client.luau      clip review scene at 0.25x / 0.5x / 1x with a frame counter
tests/                         Lune specs (*.spec.luau) and run-in-roblox smoke scripts (smoke/)
tests/project/                 project-file guards (empty Animate everywhere, HttpEnabled in dev places only)
tests/choreo/GroundClearance   every player clip at 240 Hz on the hit matrix's body: the sword stays above the field (D-047) and off the body, on the back or in the hand (D-050, D-055)
tests/choreo/TurnClearance    drawn turns through the real Locomotion at 240 Hz: the scabbard keeps the off-body margin (D-058)
tests/choreo/Stride           re-measures each gait clip's ground speed and feet against choreo.luau stride, and the pacing, starts and stops (D-054, D-059)
tools/validate.luau            runs tools/validators/*.luau
tools/smoke.sh                 runs the smoke scripts in Studio through tools/smoke-wrap.luau + smoke/SmokeRunner
tools/hit-matrix.luau          prints the server hit matrix (tools/hitmatrix/HitMatrix.luau, dev.luau hitMatrix, D-045);
                               HitMatrix.standing() lends its posed body and field to other specs
tools/PoseEditor/              Studio plugin (Rojo project) + tools/pose-server.luau (Lune, writes clips)
```

## Rules every module follows

- `--!strict` at the top. One module per responsibility. No `wait()`; `task.*` only.
- Every tunable comes from `src/shared/data/`. A numeric literal in a gameplay script other than
  0, 1, -1, 2 or a unit conversion (60 fps, 180 degrees, 100 percent) fails `tools/validate.luau`.
- Requires use Instance paths (`script.Parent.x`, `game:GetService("ReplicatedStorage").Shared.x`),
  never string paths (D-002). Shared modules must load in Lune: no Roblox datatypes at module load,
  no `game:GetService` at module load in `src/shared/data/` or `src/shared/clips/`.
- Services expose a small API and talk through `Signal`s. A service never reads another's state table.
- Errors are caught at service boundaries and logged with the player id; the server never crashes
  on a bad client message.
- Public functions have a one-line doc comment (`--- ...`).
- Every full-screen flash (anything that changes the whole picture's brightness: the impact frames and the soft dim
  today; later the finisher's fade to white and the teleport and login white-outs) asks
  `FlashBudget.request(Engine.now(), cost, seconds)` first, with its own per-region cost (`ImpactSequence.costOfLooks`)
  and the seconds its picture lasts, and falls back to a slow fade when refused. Never more than 3 in any second
  (D-061). Accents that cover a small part of the screen (glints, crescents, speed lines) are not full-screen flashes.
- ImpactFrames binds the render step `impact.overlay.renderStepName` (`SkyspireImpactFrames`) at
  `RenderPriority.Camera + 1`, after the camera's step; no other module reuses that name.

## Entities

Every fighter, player or enemy, is an entity. The server creates it, gives it an integer id, and
publishes its state as attributes on its Model (D-006):

| Attribute | Type | Meaning |
| --- | --- | --- |
| `EntityId` | number | integer id, unique per server |
| `EntityKind` | string | `"Player"` or `"Enemy"` |
| `DefId` | string | enemy def id from `enemies.luau`, or `"Player"` |
| `Rig` | string | rig id from `rigs.luau` (`PlayerR15`, `Boar`, `Kobold`) |
| `DisplayName` | string | name for nameplates |
| `HP`, `MaxHP` | number | server-owned hit points |
| `Gauge`, `MaxGauge` | number | Guard Gauge |
| `State` | string | `Types.EntityState` |
| `Cursor` | string | `"Green"`, `"Orange"`, `"Red"` (players only) |
| `Level` | number | |
| `ArtSlots` | string | players only: the quick-slot Art ids joined with commas, in slot order |
| `Drawn` | boolean | players only (nil means false): true while the combat tag holds; clients move the sword between hand and back from it (D-050) |
| `Elite` | boolean | enemies only: true on a spawn-time Elite variant (`EntityService.publish`, when `record.enemyDef.elite`), never set otherwise; `EntityTracker` reads it into `record.elite` (default false) and Replication picks the heavy shatter from it (D-079) |

A hit dealt or taken marks `lastCombatAt` and `combatUntil`; an Art, a basic swing, a guard or a
lock-on refreshes `combatUntil` only, and Art, PostMotion, Guard and a lock-on on a live target keep
it fresh. `EntityService.inCombat` and `Drawn` follow `combatUntil`; a new record (a respawn)
starts with `Drawn` false.

Tags (CollectionService): `SkyspireEntity` on every entity model, plus `SkyspirePlayer` or
`SkyspireEnemy`. Clients discover entities by tag and read attributes; remotes carry events only.

The model's `PrimaryPart` is the rig's root part (`HumanoidRootPart`). Enemy models have a
`Humanoid` for `MoveTo` only; its `Health` is pinned and ignored (D-012).

## Rigs, weapons and joints

- Rig definitions: `src/shared/data/rigs.luau`. Joint names are the rig's joint names and are the
  keys in every clip. Player: the 15 R15 joints (the root joint is `Root`, its live R15 name, D-016)
  plus `Weapon` (RightHand -> Weapon). On current Studio builds a player character carries the 15
  body joints as `AnimationConstraint`s (Avatar Joint Upgrade) and only `Weapon` as a Motor6D; the
  part-built enemy rigs are all Motor6Ds. Every reader goes through `choreo/Joints.luau`, which takes
  both classes, reads part and offset frames from either, and writes only `Transform` (D-041).
  The character's engine `Animator` puts every joint back to rest after RenderStepped, so Choreo
  writes the pose again on PreSimulation for any rig that has one (D-053). Boar and Kobold: see the file. `RigBuilder.build(rigId, name)` returns a Model with Motor6Ds whose `C0`/`C1` come from
  the rest pose, with a `WeaponGrip` attachment on the grip part and `TrailStart`/`TrailEnd`
  attachments on the weapon part.
- Weapons: `WeaponBuilder.build(weaponDef)` returns a Model named `Weapon` with a `Handle`/blade
  part named `Weapon`, `TrailStart` at the guard and `TrailEnd` at the tip; the server attaches it to
  the player's `RightHand` with a Motor6D named `Weapon` (C0 from `rigs.luau`). The player's
  equipped weapon def id is the attribute `WeaponId` on the character.
- Sheaths (D-050): when the weapon's category has a `weaponModels.luau` `sheaths` row and the
  character has that part, `WeaponBuilder.equip` also parents a Model `Sheath` (tagged Placeholder)
  next to `Weapon`. It holds one `Scabbard` part welded by a Weld `ScabbardWeld` at the back mount
  (UpperTorso for the one-handed sword), with CanCollide, CanTouch and CanQuery off and no
  attachments. A Weld is not a joint, so Joints, Pose and the rigs smoke never see it. The server's
  `Weapon` Motor6D always stays on RightHand (hits and the hit matrix never see the back); clients
  move their copy. `unequip` removes the sheath. Helpers: `WeaponBuilder.sheathOf(character)` and
  `WeaponBuilder.scabbardC0(category)`.

## Sheathed weapon (client, D-050)

- `Locomotion` (local and remote players) owns a `WeaponMount` and a `SheathState`. A step hook runs
  before the mixer: Locomotion scans the live handles (drawing, sheathing, cut, covered), SheathState
  plays or stops Draw and Sheathe, then WeaponMount sets the Weapon motor's Part0 and C0.
- The target is the `Drawn` attribute; the local player predicts `true` for `choreo.luau`
  `sheath.predictSeconds` after an attack, guard, parry or lock-on (`ActionLogic.drawnTarget`,
  `CharacterController.predictDraw()`, which `Main.client` calls when `TargetController.targetChanged`
  gets a target). Locomotion follows `Drawn` and `State` through `GetAttributeChangedSignal` (the
  `attributeSignal` dependency replaces it in tests; an instance with no signals falls back to one
  read per step); `locomotion:serverDrawn()` gives Drawn to CharacterController, and remote rigs feed
  `humanoidTracker` from the driver (`drawnOf`). No attribute is read per frame.
- Every attack clip and the clips in `sheath.drawCutClips` (Guard, GuardHit, Parry) are draw-cuts:
  the sword is in the hand on their first posed frame and a playing Draw stops. A lock-on or a hit taken plays Draw; Sheathe
  starts `sheath.sheatheDelay` after the target turns false. Dodges do not draw.
- The `WeaponDraw` and `WeaponSheathe` events move the sword mid-clip, only when they come from the
  live handle of that clip (not stopping, not done, its clock past the event) and the arm is not
  covered. Covered: a live FullBody clip, or an UpperBody clip above `priority.Sheath`, keys a joint
  Draw or Sheathe keys (Weapon excluded). While covered no Draw or Sheathe starts, one that has not
  moved the sword stops and plays again once the arm is free; a draw-cut still takes the sword at
  once. A clip that ends before its event, or a build without the clip, lands the sword where the
  target wants it.
- The drawn sprint additive follows SprintDrawn's live weight, scaled by 1 minus the visible weight of
  Draw or Sheathe, and is 0 while the sword is on the back.
- `WeaponMount`: `new(animator, model)`, `:set("Hand"|"Back")`, `:get()`, `:sheathable()`,
  `:refresh()`, `:generation()`, `:destroy()`, `WeaponMount.handFrame()`,
  `WeaponMount.backFrame(category)`. It writes only the client copy's Part0 and C0 (never C1), looks
  the hand and back parts up once per new Weapon motor, and pins the Weapon joint at rest while the
  sword is on the back. Mounts on one animator form a stack and the newest drives the sword; a new
  motor bumps `generation()`, which snaps the sword to the target with no clip.
- `SheathState` (pure, no Instances): `new(place, config?)`,
  `:step(dt, { target, cut, covered, drawing, sheathing, hold }) -> { place?, play?, stop? }`,
  `:onEvent(kind, input) -> place?`.
- Choreo: `animator:joint(name)` returns the joint Choreo writes for a name (or the new one after a
  replace); `animator:pin(name, on)` holds a joint at rest whatever any clip, additive or procedural
  key says, acts at once, and survives a joint rebuild.
- Footsteps (D-051): the Base layer runs every walk clip and its drawn twin at once. Only the Base
  clip with Footstep events that the limbs show most (eased fade times weight; the first wins a tie;
  nothing at weight 0) passes its Footstep on, so a rig standing still is silent. All gait clips run on
  one shared phase (D-054). FullBody clips add up per priority group as the Mixer blends them; while they
  cover more than half of the limbs (a dodge, a landing, a jump, a fall, an Art, a stagger), the walk is
  silent and only their own steps sound, so nothing steps in the air. FullBody and Additive clips with
  Footstep events (Land, a dodge, Stagger) fire their own. A step plays `footsteps.<Surface>Light` from
  `fx.audio.materialSurface` (D-089).
- The back mount (D-055): `weaponModels.luau` `sheaths.OneHandedSword.mount` puts the grip behind the right
  shoulder blade and the scabbard 0.2 stud off the back. `dev.luau` `groundClearance.offBody` holds the sword on
  the back, the scabbard and the sword in the hand off every body part (head 0.01, arms 0.03, legs 0.04, hips
  0.01 stud) in every pose GroundClearance and TurnClearance check.
- A remote player's driver reads `Drawn` through `SheathState.riseFilter(delay, initial)`: a rise counts only after
  `choreo.luau` `sheath.remoteDrawDelay` (0.06 s), a fall at once (D-057). `riseFilter(...):step(dt, raw)` returns
  the filtered value; Replication feeds it.

## Gait pacing and the stop (client, D-054, D-058, D-059)

- `choreo.luau` `locomotion.stride` holds each gait clip's measured `groundSpeed` (how fast its planted foot
  moves back at rate 1) and `touchdown` (where each foot is at its Footstep), with the pacing bounds
  (`rateFloor` 0.25, `rateCeiling` 3, `startPhase` 0.5, `turnYawRate` 300) and the check bars (`slideBar`,
  `transientBar`, `contact`). `tests/choreo/Stride.spec.luau` re-measures them on the hit matrix's player and
  prints the drift after a re-key.
- Locomotion keeps one gait phase (0 at every gait clip's left Footstep, 0.5 at its right) on the mixer's clock.
  Before each animator step it blends the shown clips' stride and duration by their shown weights, sets every
  gait clip that shows (or is about to) to the phase and plays it at stride over the root's speed, clamped to the
  rate bounds. `LocomotionState.gaitWeights` / `walkGait` / `walkWeights` give the cadence shares; `plantedAlong`
  and `settlePoints` read the feet. `walkSpeed`, `runSpeed` and `sprintSpeed` are movement speeds only.
- The lean (`locomotion.lean.upright`, today `WalkLeftDrawn = 1`): before `LocomotionState.leanOffsets` poses a lean
  toward a listed clip's side, Locomotion scales it by one minus that clip's shown weight (D-058).
- The two-step stop: `locomotion:stopGait(into)` writes the phase and where each foot of the last move's walk is
  over its Idle spot into a `StopGait` (no allocation). `ActionLogic.stopCarryStep(carry, moveX, moveZ, speed,
  walkSpeed, grounded, state, dt, config, gait)` returns this frame's carry speed along `(carry.x, carry.z)`,
  from `ActionLogic.newStopCarry()`; CharacterController feeds the result to the Humanoid while the stick is
  let go, and the dodge reads the stick, not the carry (`stopStepsSeconds`, `stopMinCycles`, `stopEndSpeed`).

## Clips

- Clip ids: players `player/<WeaponCategory>/<ClipName>` (for Arts the ClipName is the Art name
  without spaces: `player/OneHandedSword/SharpNail`); enemies `enemy/<RigId>/<ClipName>`.
- Files: `src/shared/clips/player/OneHandedSword/SharpNail.luau` returns one `Types.ClipDef`.
  `ClipLibrary.get(id)` maps the id to the module path.
- Required player clips (OneHandedSword, Phase 0): `Idle`, `IdleDrawn`, `WalkForward`,
  `WalkBack`, `WalkLeft`, `WalkRight`, `Run`, `Sprint`, `WalkForwardDrawn`, `WalkBackDrawn`,
  `WalkLeftDrawn`, `WalkRightDrawn`, `RunDrawn`, `SprintDrawn`, `Draw`, `Sheathe`, `Jump`, `Fall`, `Land`, `TurnLeft`,
  `TurnRight`, `Skid`, `Guard`, `GuardHit`, `GuardBreak`, `Parry`, `DodgeForward`, `DodgeBack`,
  `DodgeLeft`, `DodgeRight`, `FlinchFront`, `FlinchBack`, `FlinchLeft`, `FlinchRight`, `Stagger`,
  `DeathFreeze`, `Basic1`, `Basic2`, `Basic3`, `Horizontal`, `Vertical`, `RisingArc`, `SharpNail`.
  The plain `Idle`, walk, `Run` and `Sprint` names are the sheathed set (`sheathed = true`, sword on
  the back, empty hands); the `…Drawn` names are the drawn set. `LocomotionState.clipFor(name, drawn)`
  maps a plain name to its twin. The clips validator checks that every name in
  `choreo.locomotion.clips`, `sheath.clips` and `sheath.drawCutClips` has a file, that each sheathed
  clip matches its drawn twin (duration, loop, Footstep times and feet), and that Draw and Sheathe are
  UpperBody at `priority.Sheath` with one `WeaponDraw` or `WeaponSheathe` each.
- Sheath events: `WeaponDraw` (the hand takes the sword from its sheath) and `WeaponSheathe` (the
  sword goes back into it) carry no data. At the event the clip's Weapon key lines the blade up with
  the back mount. `ReviewMarkers.mountAt(clip, time)` ("Hand" or "Back") is the one source for where
  the sword is; `ReviewMarkers.mountProblems(clip)` lists the sheath rules. The clips validator,
  GroundClearance, the review and the ClipLab use them. GroundClearance also checks the handoff
  (`dev.luau` `groundClearance.handoff`), the sword and scabbard against the body in every checked pose
  (`offBody`, D-055) and the slide along the sheath from the event until the blade is clear, with Breathe and
  the flinches (`sheathSlide`).
  `src/shared/data/scope.luau` lists the Arts, enemies, bosses and rigs whose clips the current
  phase must ship; the clips validator fails on those and folds the later-phase backlog into one
  summary warning (D-015). Boss attack clips (`bosses.luau` phase attacks, id
  `enemy/<skin>/<clip>`) are cross-checked the same way as enemy attacks: `attack = true` and an
  `Anticipation` beat that holds for the attack's `windUp`.
- Required enemy clips: `enemy/Boar/{Idle,Walk,Charge,FlinchFront,FlinchBack,FlinchLeft,FlinchRight,Stagger,Break,DeathFreeze}`,
  `enemy/Kobold/{Idle,Walk,Overhead,FlinchFront,FlinchBack,FlinchLeft,FlinchRight,Stagger,Break,DeathFreeze}`.
  An enemy attack's `clip` in `enemies.luau` names one of these (`Charge`, `Overhead`).
- Attack clips set `attack = true`, define all six `beats`, carry `HitWindowOpen`/`HitWindowClose`
  pairs (one pair per hit), `TrailOn`/`TrailOff`, `SmearOn`/`SmearOff`, `ActivationHold` and
  `PostMotionStart` events, and `hitStop`. The clip validator enforces this and rejects `Linear` on
  any joint key (root keys may be Linear). The runtime blend is eased too: `Mixer` shapes every fade
  with `choreo.luau` `blendEasing` before it weights a limb, and blend-space weight ramps on one
  layer share one fraction so their sum stays 1 (D-032, D-033).
- Trail kinds: a `TrailOn`'s `data.kind` (`"Art"` or `"Basic"`) picks the trail kind, and the client
  remembers it for the rest of that clip's trail events (`HitWindowOpen`/`Close`, `TrailOff` and
  `PostMotionStart` carry no kind); without one, a clip id containing `/Basic` means Basic.
  `SmearOn`/`SmearOff` also turn the full-width `Smear` trail kind on and off. The width follows the
  kind that is on; the color follows the swing (Art over Basic), so a Basic swing's smear frames widen
  the trail but keep its whiter color, and the fading tail keeps the look of the swing that drew it.
- Sounds: a `Sfx` or `Voice` event carries `data.name = "family.Name"` from `sfx.luau`; the client
  plays it through `SfxPool.play` at the rig, and the clips validator rejects a name `Sfx.get`
  cannot resolve. Sounds a server remote already triggers (hits, parry, block, guard break) are not
  repeated as clip events (D-036); the impact director plays them (D-069). A whoosh sits at
  max(0, HitWindowOpen - `Sfx.peakLead(entry)`), no sound sits less than 0.05 s after an Art's
  ActivationHold before its first HitWindowOpen, and an enemy's strike vocal is a Voice event on its
  HitWindowOpen (D-082; `tests/data/sfx.spec.luau` holds all three). A remote clip started late replays
  the Sfx and Voice events it jumped over through `SfxPool.playLate` (D-101).
- Enemy attack clips: the wind-up pose must be held for the attack's `windUp` (the validator
  compares the clip's `Anticipation` beat to `enemies.luau`).
- Hit windows sit on the strike (D-043): the n-th `HitWindowOpen` is at or before the n-th snap's
  start and its `HitWindowClose` at or after that snap's end, within `dev.luau`
  `review.windowSnapToleranceFrames`. Snaps come from `ReviewMarkers.strikeSnaps`: the beats table's
  `Snap`, then each later ExpoOut key that moves a joint 2 to 4 frames after the key before it; the
  snap count must equal the window count. A `TrailOn` that names a trail kind is listed before the
  clip's first `HitWindowOpen` (they share the snap's first frame, and the client keeps the kind
  from the first event that names one). The clips validator and `ReviewMarkers.problems` both apply
  these rules.

## Combat flow (server authority)

1. Client `InputController` -> `CharacterController` sends `ArtRequest {artId, facing, clientTime}`
   and immediately starts the local clip (prediction).
2. `CombatService` validates: entity alive and in `Idle`/`Moving`, Art unlocked (proficiency from
   the entity record), Art in the fighter's quick slots (`artSlots` on the entity record, copied
   from the loadout; a record without slots, such as an enemy with Arts or a stand-in, skips this
   check), not inside a lock (`artRequestTolerance`), facing within tolerance, weapon category
   matches, clip exists. The `ActionRejected` reasons are `NoEntity`, `Dead`, `UnknownArt`,
   `NoWeapon`, `WeaponMismatch`, `Proficiency`, `NotSlotted`, `Locked`, `Busy:<state>`, `Facing`,
   `Stance` and `NoClip`. On failure it fires `ActionRejected` to that client (which cancels its
   prediction). On success it sets `State = "Art"`, fires `ActionStarted` to everyone (including the
   requester, who ignores its own), and schedules the timeline from the clip. The timeline starts at
   the request's `clientTime` clamped into `[max(now - lagAllowance, min(freeAt, now)), now]`, where
   `freeAt` is the fighter's `lockUntil` before the new action (`CombatService.runStartOf`, the 150 ms
   lag allowance, D-010), so a rewound action never overlaps the lock before it; a basic swing's chain
   index uses the same start, and `ActionStarted.serverTime` carries it: for each hit window it
   samples the clip at `hitSampleHz` through `ClipSampler` + `Pose`, adds arc sub-samples where the
   blade moves more than `sweepMaxTipStep` between two (at most `sweepMaxSubdivisions` per fighter
   per frame, `HitSweep.followArc`), and runs `HitSweep` over them: the whole blade is overlap-tested
   at every sample, the midpoint is cast between samples, plus the tip's or the guard's chord on a
   step the cap left longer than `sweepMaxTipStep`; in a hitch frame the samples' roots are spread
   between the two frames' roots (D-042, D-044). Each frame reads the fighter's joints once
   (`Pose.chain`) and every solve of that frame uses that list; a root that jumped farther than an
   honest body can travel starts a new chain at the live root instead of being swept across (D-048);
   only fighters `mayDamage` allows become hits or count toward the target cap (D-049). Every hit goes through `DamageMath` and `EntityService.applyHit`, then `HitConfirmed` is
   fired to all clients. After the last hit the entity enters `PostMotion` for `postMotion` seconds
   (zero if the target was in `Break`), then `Idle`.
3. Enemy attacks: `EnemyService` picks an attack, fires `Telegraph` (with `windUp` and the ground
   shape) and `StateChanged`, holds the wind-up, then calls `CombatService.enemyStrike(enemyId,
   attackDef, origin, facing)`, which checks each player in the cone/line: dodge invulnerability,
   parry (guard pressed within `parryWindow` before the hit lands: the guard timestamp is the
   server's receipt time of `GuardRequest {held = true}`), guard cone (judged against the player's
   root on the server at strike time; the request's `facing` is not read) and reduction, then damage.
   `HitConfirmed` carries the hit's `staggerDirection` (Front, Back, Left, Right in the target's frame).
   A parry staggers the enemy (`parryStagger`) and (Phase 1) opens a Switch window.
4. Death: `EntityService` sets `Dead`, fires `EntityDied {shatter}` to all; the client freezes the
   rig, waits out the kill's hit-stop, ducks the Music, SFX and UI groups by `deathDuckDb` for `deathFreeze`,
   plays `Shatter`, then shows the system line (D-035, D-073).

Hit-stop, trails, camera, digits, highlight flashes, impact frames, accents and hit sounds are client
reactions to `HitConfirmed`; nothing about animation runs on the server except the pose sampling used by
the sweep.

## Hit feel and sound (client, D-060 to D-102)

- **Start order.** `Main.client` loads its sibling packages in `SIBLING_ORDER` and starts each that exists:
  fx.Quality, audio.SfxPool, audio.Ambience, audio.MusicDirector, fx.OutlineManager, fx.Trails, fx.Shatter,
  fx.ImpactFrames, fx.Glint, fx.SlashArc, fx.SpeedLines, fx.Impact, fx.Sparks, fx.Digits, fx.SwitchRing,
  fx.Telegraphs, ui.Hud, ui.Nameplates, ui.SystemLine, then choreo.Choreo (not started there). Ambience comes
  right after SfxPool, and Impact after everything it fires; `tests/client/Impact.spec.luau` checks the order.
- **`fx/Impact`** (the director). `Impact.hit(info: HitInfo): string` picks the moment
  (`Impact.select`, moments.luau `select`) and fires its row: cue and extra sound, impact frames, glint,
  crescent, slash line, Highlight, trail flash, contour and punch, each for the audience `moments.audience`
  allows (D-070), once per sweep (D-098); the 3D accents wait `Impact.hiddenSeconds()` (D-071). HitInfo:
  `tier`, `position`, `attacker?`, `target?`, `involved`, `localAttacker`, `trailToken`, `parried`,
  `guarded`, `crit`, `isSwitch`, `killed`, `art?` (true an Art, false a player's basic, nil otherwise),
  `partner?`. Also: `activation(model, clipId, token, isLocal, speed?, lateBy?)`, `release(model, clipId,
  clipTime, frozenSeconds, speed?)`, `cancelActivation(model?)` (D-074); `dodge(model, isLocal)` (D-100);
  `guardBreak(model?, isLocal)`, `guardRaise(model?, isLocal)` (D-097); `shatterCue(boss, heavy?)` and
  `death(model?, position, boss, heavy?)` (D-079); `ownsHighlight(info)`; the pure helpers `swingTangent`,
  `planeNormal(tangent, radial?, toCamera?)` (D-096), `holdTime`, `windowAfter`, `riserLead`; `bind(deps)`
  and `start()` (loads its siblings through `Siblings`).
- **`fx/ImpactFrames`.** `play(sequence, models, opts?) -> seconds` (opts: `slashDirection?`, `now?`,
  `position?`) asks FlashBudget itself and shows the dim instead when refused or when Reduce flashing is on;
  `isShowing()`, `look()`, `remaining()`, `hiddenSeconds()` (seconds the opaque frames still hide the world,
  0 while idle or dimming), `cancel()`, `screenDirection(position, direction)`, `start()`, `bind(deps?)`.
  `ImpactSequence` is pure (`flashCost`, `costOfLooks`, `framesOf`, `capSeconds`, `dimOpacity`, `dimDip`,
  `luminanceOf`, `regionsOf`, ...), so the impact validator scores a table that is not the live one.
- **`fx/FlashBudget`.** `request(now, cost, seconds?) -> boolean` and `claim(...) -> Claim?` record a cost only
  when it fits; `hold(claim, at)` pushes a claim's finish while its picture shows; `raise(claim, now, cost)`
  charges a takeover's difference; `used(now)`; `reduced()` and `set(value)` for the Reduce flashing setting
  (the player attribute `impact.reduceFlashingAttribute`, watched after `start()`); `reset()`. Every caller
  passes times from `Engine.now()`.
- **Accents.** `Glint.play(position, size, token?)`, `SlashArc.play(position, tangent, normal, token, size)`,
  `SlashArc.line(position, tangent, size)`, `SpeedLines.play(kind)`; each has `step`, `bind(overrides?)`,
  `reset` and `start`, pools its instances and caps what plays at once by quality tier. `AccentStep` is their
  shared seam: `renderStepped(fn)`, `viewport()`, `deps(overrides?)` (clock, per-frame step, screen size).
- **`Trails.swingDirection(model): Vector3?`**: the strike's snap chord for `accents.swing.memorySeconds` after
  it was sampled, then the live ring while a trail kind is on, then the last good direction sampled while one
  was on (within memorySeconds), then the ring now. `setActive(model, true, kind)` with kind Art or Basic starts
  a new snap; Smear does not. `Trails.sample()` runs on Heartbeat (D-068).
- **`CameraController.punch(kind)`** (`"Final"` or `"Kill"`): the FOV push in, on top of the FOV spring (D-072).
- **`audio/SfxPool`.** `play(name, position?) -> Sound?`; `cue(name, position?)` (sub-frame layers play inside
  the call, D-084); `contour(name)`; `playEndingAt(name, seconds, position?) -> Sound?` (D-078);
  `playLate(name, lateBy, position?) -> Sound?` (a sound started as if `lateBy` seconds ago: speed first, then
  TimePosition = startAt + lateBy x speed; nil when deduped, a placeholder or already over, D-101);
  `loop(name, gain)` (D-087); `shatter(position?, weight?)` and `shatterCue(weight?) -> string` (weight
  `normal`, `heavy`, `boss`, a shatterCues cue name, or the old boolean; D-079, D-102); `footstep(model?,
  surface?, weight?)`, `surfaceOf`; `duck(db, seconds)`, `setGroupVolume`, `group`, `mixState(group)`;
  `cueNames`, `contourNames`; `preloadNames()` and `preload()` (D-093); `timeLength(sound)`; `stats()` ->
  { requested, played, deduped, placeholders, unloaded, lateStarts }; `reset()`, `start()`. `hit`, `parry`
  and `hitStopTick` stay as spec-tested helpers with no game caller. Engine seam, `bind(overrides?)`: `now`,
  `delay`, `onStep` (contours and fades), `play`, `stop`, `isPlaying`, `timeLength` (0 while unloaded),
  `preload`, `onEnded(sound, fn) -> disconnect?`. Play rule: Volume = entry volume x 10^(gainDb/20) (plus the
  heartbeat lift) clamped under `limits.maxPlayVolume` (D-086); PlaybackSpeed = the layer's pitch, else random
  in pitchRange, clamped to `engine.playbackSpeed` (D-085); a trimmed entry gets PlaybackRegion from
  `Sfx.region` and TimePosition on every play (D-088); fades and voice release follow D-090 to D-092.
- **`audio/Ambience`.** `start()` (idempotent), `stop()` (silences both beds, then disconnects),
  `bind(overrides?)` (stops first; nil restores the engine seams), `state()`, `edgeDistance(position)`,
  `rimGainAt(edge)`. Seams: `onStep` (Heartbeat), `position` (the local character's root) and `loop`
  (`SfxPool.loop`). It reads `fx.audio.ambience` and `playground.luau` fieldRadius and allocates nothing per
  frame (D-095).
- **`fx/Shatter.play(model, kind, weight?)`** plays `SfxPool.shatter` with the weight; a `Boss` kind always plays
  the boss shatter, and the two-argument call keeps the old behaviour.

### After the merge (D-103 to D-111)

- Choreo's Engine seam gains defer(fn) (default task.defer). It is used to destroy the default Animate after
  disabling it and stopping the animator tracks Choreo did not start (silenceAnimate, at attach and from
  DescendantAdded).
- Locomotion keeps one jumpHandoff connection on animator.finished. Only the jump clip's own end hands over to Fall
  (if still in Air); Land, a new Jump and destroy drop it.
- Smear.restSize(part) returns the weapon size stored before a stretch (nil when untouched or reset), and
  ImpactFrames draws a stretched sword at that size (Smear.restSize(part) or part.Size).
- Trails.sample is gated by swinging or by distance (accents.swing.sampleDistance from Engine.viewerPosition()) and
  reads tip.WorldPosition; Trails.reset() detaches every rig (only specs call it today).
- SlashArc prebuilds its wipe Transparency sequences (wipeSteps + 1 per layer and half) and its two line fades on
  start(); SlashArc.wipeStep(front) returns the snapped step and that step's front.
- **Audio.** SfxPool.cue(name, position?, lateBy?) and Impact.dodge(model, isLocal, lateBy?). Replication's
  ActionStarted passes lateOf(handle) = handle.time / handle.speed (nil when the clip started on time or is an
  engine Animation) for remote dodges. Timed plays (playEndingAt) correct for task.delay frame slip; cue layers keep
  their onset.
- **Client input.** Main.client gates Tab (SwitchCallRequest) with ActionLogic.basicReady at
  TrailingSend.gapOf("SwitchCallRequest") = 1/perSecond, so one-off presses are limited on the client to the server
  bucket's refill rate, like BasicAttackRequest.
- **Validators.** tools/validators/accents.luau also checks swing.memorySeconds (above the sample ring, below 1 s),
  swing.snapFrames (a whole number ≥ 1, inside memorySeconds), slashArc.tilt (0 < maxDegrees, 0 < faceDegrees < 90,
  90 - maxDegrees ≥ faceDegrees, 0 < minPlaneSine < 1), slashArc.wipeSteps (whole, ≥ 4 × the longest wipeFrames) and
  swing.sampleDistance (> 0, reaching moments.accentRange and every row's range). tools/validators/impact.luau also
  checks reduced.maxPerWindow (a whole number ≥ 1, costing fewer flashes than flash.maxPerWindow).

### After the play-test (D-112 to D-116)

- Aim (client, D-112): `controllers/AimLogic` (pure, tested) holds the lock-facing, snap, soft-assist and yaw-history
  rules. CharacterController applies them on its render step and before each BasicAttackRequest and ArtRequest, and
  samples the root's yaw on Heartbeat too. It reads the lock and the assist candidates from TargetController through
  Siblings. `TargetController.lockOn(entityId)` locks a named enemy through the F key's path; nil clears it.
- Sweep facing (server, D-113): a player's run carries its validated flat facing, and every blade sample is solved
  from `CFrame.lookAt(root position, root position + run.facing)`. Enemy strikes still read the server root.
- `CombatService.traceSink` (diagnostics, nil in play) receives a TraceEvent per closed window of a player's run:
  facing, root look, hits, and the nearest enemy's distance, bearing and blade clearance.
- Dev hooks (D-114): `client/dev/DevAim.client` (+ pure `DevAimLogic`) and `server/dev/DevCombat.server` (+ pure
  `DevTrace`) are Studio-only BindableFunctions (`SkyspireDevAim` under the LocalPlayer, `SkyspireDevCombat` under
  ServerScriptService), on only with Workspace `DevCapture`.
- Content (D-115): MusicDirector makes a stem Sound only for a real id; no code writes a placeholder id into a content
  property. `tools/validators/content.luau` checks asset-id safety and engine parent rules across source, project
  files and data.
- Sky (D-116): `PlaygroundBuilder.buildSkyClouds` puts the Clouds under `workspace.Terrain` at start; no place
  project sets a Clouds or any content property.
- Tests: `tests/_harness/SoundEngine.luau` (Harness.SoundEngine) is a frame-stepped model of the Sound facts measured
  in Studio: Ended at the region end, Play refused at or past the float32 region end, a loop's first pass starting at
  TimePosition, PlaybackLoudness 0 for two frames after Play. `tests/server/PlayerSwing.spec.luau` drives a real AJU
  player from the remote to the boar's HP.
- Data: `combat.luau` aim; `dev.luau` aim and trace; `sfx.luau` music.stemIds; `world.luau` clouds.textureAsset.

### After the render-stall test (D-117 to D-119)

- Render stalls: RenderStepped can stop while Heartbeat runs (display asleep, a minimised window, a long hitch).
  Anything that must end on time or free instances rides on Heartbeat or Engine.now, never on the render step alone.
- ImpactFrames (D-117): each picture has `requestedAt` and `drawn`. A Heartbeat watchdog ends stale or overdue
  pictures; only the render step finishes one as rendered. Any other finish of a picture on screen pins its flash
  claim and keeps the render step bound until the next rendered frame settles it. Spec seam: `Deps.onHeartbeat`.
- FlashBudget: `hold(claim, math.huge)` pins a claim and `settle(claim, at)` sets its end. A pinned claim is never
  pruned, so it counts in every request and in Reduce flashing's dim count.
- CameraController (D-118): steps by real time in pieces of at most 1/30 s and snaps past 2 s; punch, kick and shake
  are timed from the request.
- TargetController (D-119): tracks the local id (`ownerId`) and the local record's death; uses EntityTracker
  `peekLocalId`, `isLocal` and `localRecord`.
- Glint, SlashArc, SpeedLines and Smear are timed from deps.now() at play, so the first render step after a stall
  hides them. FrameClock, Trails, OutlineManager, SwitchRing, Shatter, Digits, Telegraphs, Hud, Nameplates,
  SystemLine and SfxPool run on Heartbeat, Engine.now or the wall clock. Choreo still steps on RenderStepped (open).

### Controlled fights and idle phase (D-120 to D-124)

- **EnemyService hold (D-120):**
  - API: `setHeld(id, on)`, `isHeld`, `heldIds`, `setHoldNew(on)`, `holdsNew`.
  - hold(entry) sets Entry.held, puts the brain to sleep, stops the mover and calls EntityService.setHpRegenHeld(id, true), when the bound EntityService has it.
  - refreshSleep skips held entries.
  - A release calls setHpRegenHeld(id, false) and makes the next sleep check run on the next tick. forget() does the same for a held entry (death, despawn, Unregistered, reset).
  - Hold-new is checked in spawn, after the entry is registered and before Spawned fires.
  - It is the cinematic hold and the Studio dev hook's tool.
- **EntityService (D-120, D-121):**
  - setHp is dev and GM only. It clamps to [1, maxHp], publishes, restarts the regen wait (lastCombatAt), and never kills, revives or draws.
  - setHpRegenHeld(id, held) sets record.hpRegenHeld (types.luau EntityRecord). stepAlive skips HP regen while it is set; Guard Gauge regen is unchanged. It returns false for an unknown or dead id. Only EnemyService's hold calls it.
- **DevCombat** (server hook, Studio and DevCapture only):
  - Commands: help, trace, events, basic, art, hp (now with `held`), hold, sethp, heal.
  - hold, sethp and heal only set a fight up; every hit and kill still comes from a real swing through CombatService.
- **ImpactFrames (D-122):**
  - `staleSeconds(current)` is the sequence's cap (its hit-stop) or the dim's own length. The watchdog, stepDim and stepSequence all use it.
  - `syncWhileFrozen(current, at)` copies the CurrentCamera and every rig part into the viewport only while `at - requestedAt < cap`. stepSequence (first drawn frame and each frame) and join use it; showSequence still syncs once at play. A sequence first drawn late therefore holds its last frozen frame past the hit-stop.
  - impact.overlay has no staleFrames; the impact validator requires every sequence's hit-stop to be at least 2 frames.
- **Idle phase (D-123):**
  - `Locomotion.idlePhase(id)` = (id x choreo.enemyIdlePhaseStep) % 1.
  - Locomotion.attach's `phase` option starts the enemy RigDriver's Idle and Walk at phase x their clip durations (Mixer wraps a loop's startTime).
  - Replication.attachDriver passes `{ phase = locomotion.idlePhase(record.id) }` for non-player records when the package has idlePhase.
- **Mixer:** a fallback handle whose targetWeight is 0 (another Base clip active) advances into a scratch list cleared every step, so its crossed events never reach Choreo's events signal. Root motion and the clock are unchanged.
- **Clips validator:** its choreo cross-check also owns the idle-phase spread (validator constants PHASE_RUN 8 and PHASE_SHARE 3) and the rule that every choreo.rigs entry with a walk has a looping idle and walk.

## Data tables (src/shared/data)

| File | Holds |
| --- | --- |
| `combat.luau` | section 6 tunables |
| `palette.luau` | color tokens |
| `rigs.luau` | rig joint lists and rest poses |
| `scope.luau` | the current `phase` and the Art, enemy, boss and rig ids whose clips it must ship, with `hasArt` / `hasEnemy` / `hasBoss` / `hasRig` (D-015) |
| `arts.luau` | every Art row from section 8 as `Types.ArtDef`, keyed by id |
| `weapons.luau` | weapon defs, named weapons, the starter `TrialistSword` |
| `armor.luau` | armor defs, the Trialist cloth set |
| `enemies.luau` | every enemy from the floors 1 to 10 bestiary; Frenzy Boar and Kobold Axeman complete |
| `bosses.luau` | Grolak in full (bars, phases, lockstep), floors 2 to 10 as rows |
| `tiers.luau` | per-tier multipliers for HP, attack, defense, gauge, XP |
| `floors.luau` | floors 1 to 25 from section 5 |
| `loot.luau` | drop tables and rarity weights |
| `origins.luau` | lineage/origin/mark weights (sum to 100 per roll) |
| `paths.luau` | the six Paths |
| `apex.luau` | floor 1 Apex set |
| `lighting.luau` | section 11 lighting values per floor |
| `sfx.luau` | every sound by `family.Name` (D-080): entries `{ id, placeholder, volume, pitchRange?, spatial, note?, startAt?, stopAt?, fadeOut?, loop?, length?, title?, creator?, peakAt? }` (times in asset seconds before PlaybackSpeed; `Sfx.isReal`, `Sfx.region`, `Sfx.peakLead`, `Sfx.gainOf`, `Sfx.vocalName`); `cues` (layers of `{ name, delay, gainDb, pitch? }`), `contours` (EQ and reverb steps per group), `effects`, `engine` (playbackSpeed, soundVolume), `limits` (cueLayers, hitCueMinLayers, cueDelaySeconds, layerGainDb, maxPlayVolume, loopMinSeconds, contourSeconds, subLayers, bassBackDb, sharedAssetSemitones), `playback` (openEndSeconds, sameFrameSeconds), `preload`, `shatterCues` (normal, heavy, boss), `mix`, `music` |
| `assets.luau` | asset ids by name; missing ids are reported |
| `choreo.luau` | animation tunables: blend times and the blend easing, smear scale, idle cycle, locomotion speeds and clip names, `locomotion.stride` (ground speeds, touchdowns, pacing bounds and check bars, D-054), the stop (`stopStepsSeconds`, `stopMinCycles`, `stopEndSpeed`, D-059), `locomotion.lean.upright` (D-058), `priority.Sheath` and the `sheath` table (clips, draw-cuts, predictSeconds, sheatheDelay, stopBlend, remoteDrawDelay) |
| `camera.luau` | section 10 camera numbers and the `punch` rows (Final, Kill; D-072) |
| `fx.luau` | budgets, shard counts, trail lifetimes, telegraph sizes, the parry spark burst, quality tiers; `audio` (dedupe, `maxSoundLength`, the heartbeat loop and ramp, `materialSurface`, `ambience`: bed, rim wind, ramp, sample rate, rim band and floor, D-095) |
| `playground.luau` | the Playground: field radius, rim, pillars, clouds, spawn tables, loadout |
| `ai.luau` | every AI tunable: perception, archetype tuning, pathing, tick rates |
| `world.luau` | world builder tunables (folders, railing, pillars, clouds, kill volume) and the anti-cheat policy, including the shadow and teleport-cap fractions, the per-remote rate limits (`anticheat.remoteRates`, with an optional `clientBurst` for a TrailingSend sender) and `anticheat.remoteStallSeconds` (a client burst plus perSecond times it must fit inside the server's burst, D-056) |
| `weaponModels.luau` | placeholder weapon geometry per category, the names the client relies on, and the back mounts (`sheaths`, `sheath(category)`, D-050; the one-handed sword's `mount`, D-055) |
| `input.luau` | key, gamepad and touch bindings |
| `ui.luau` | HUD, nameplate and system-line layout numbers, and the death system-line text |
| `impact.luau` | the impact frames (D-060 to D-066): looks, sequences (tier, rank, steps), the flash budget and the luminance curve, the reduced dim, the Reduce flashing attribute, the overlay, viewport, silhouette and strokes, quality part caps |
| `accents.luau` | the reel accents (D-067, D-068, D-096): glint, slashArc (with `tilt`), slashLine and speedLines sizes and timings, `limits`, `budget`, `swing` (samples, travel bounds, memorySeconds, snapFrames), quality caps |
| `moments.luau` | what each combat moment fires (D-069 to D-073, D-098): `effects`, default `audience`, `accentRange`, `select` rules and `fallback`, `hitFields`, `death.duckDelayFrames`, `sweep.mergeSeconds`, `rows`; `byId`, `rangeOf`, `audienceOf`, `selectFor`, `deathDuckDelay`, `deathFor` |
| `dev.luau` | dev tooling numbers: Capture panel, ClipLab, PoseEditor, pose server (D-028), clip review tolerances (D-043), hit matrix setups and real-fight ranges (D-045), ground clearance and the sheath checks (`groundClearance.offBody` with its `turns`, `sheathSlide`; D-047, D-050, D-055, D-058), the WeaponDraw and WeaponSheathe tokens |

Row convention (D-017): tables with many rows keep them under `Module.rows` with `byId(id)` and
`list()` functions; `list()` returns a clone. Validators read `rows` first and fall back to the
module table.

Each table has a validator in `tools/validators/`. The naming blocklist lives in
`tools/naming/blocklist.luau` (not shipped to clients, D-014) and `tools/validators/naming.luau`
scans every text file in the repo except `docs/GAME_SPEC.md` and the blocklist itself.

## Client reactions to remotes

| Remote | Client reaction |
| --- | --- |
| `ActionStarted` | `Choreo.play(rig, clipId, serverTime)` on that entity's rig at `payload.speed` (1 when absent); the local player ignores its own. It remembers `{ clipId, speed }` per entity, replays the Sfx and Voice events the catch-up start jumped over through `SfxPool.playLate`, and an ActivationHold it jumped over while the first damage window is still ahead (light, late chime, `Impact.activation` with `lateBy`; D-101). A clip whose id contains `/Dodge` calls `Impact.dodge(model, false)` |
| `Telegraph` | `Telegraphs.show(entity, kind, windUp, shape)`: weapon Highlight fill + ground decal |
| `HitConfirmed` | builds a `HitInfo` (`art` from the artId and the attacker's kind, the Switch `partner` from the open window, a blow that breaks a player's guard as `guarded`). Hit-stop on attacker and target rigs, `Digits`, the white outline flash unless `Impact.ownsHighlight(info)` or the blow breaks a player's guard (GuardBroken's HPRed fill stays), the GuardHit reaction, and on an enemy hit that neither kills nor breaks the additive `Flinch<staggerDirection>` clip. For the people in the hit: one camera nudge per attacker's sweep, `camera.shake(tier)` and one hit-stop tick per attacker's sweep (Final for a player's guard-breaking hit; a stronger tier takes over; D-098). Then the HUD HP flash and `Impact.hit(info)`, which plays every hit sound and reel accent (D-069). On a parry: `Impact.hit(info)`, then `Trails.flashWhite` and `Sparks.parry(position)` after `Impact.hiddenSeconds()`, the Parry reaction and `shake(Normal)` (D-071) |
| `StateChanged` | stagger/break/guard-break clips, HUD status; `Stagger`, `Break`, `GuardBroken` and `Dead` hide that enemy's telegraph. `GuardBroken` flashes HPRed and calls `Impact.guardBreak(model, isLocal)`; `Guard` on a remote player plays the guard pose and `Impact.guardRaise(model, false)` (the local raise is predicted in `CharacterController.setGuard`; D-097) |
| `EntityDied` | DeathFreeze, time scale 0, trails off and the enemy's death vocal at once (once per voice for one sweep's deaths). A death landing inside another death's silence first restores full volume (`SfxPool.duck(0, 0)`). At `Moments.deathDuckDelay()` (the kill's hit-stop) the newest death runs `SfxPool.duck(deathDuckDb, deathFreeze)` on the Music, SFX and UI groups; an older one does not. At that lead plus `deathFreeze`: `duck(0, 0)` when this is the newest death or the silence ends within `moments.sweep.mergeSeconds`; then `Shatter.play(model, kind, cueName)` (or `SfxPool.cue(cueName, position)` when the rig is already gone), then `Impact.death(model?, position, boss, heavy)`. `cueName` is `Impact.shatterCue(boss, heavy)` (heavy for a player or an Elite). The system line follows at lead + `deathFreeze` + shatter time: `ui.luau` `systemLine.deathSelf` for the dying player, `deathOther` with the name for everyone else (D-073, D-079, D-102) |
| `ActionRejected` | cancel the predicted clip, no digit |
| `SystemLine` | centered system text with chime |
| `SwitchWindow` | `SwitchRing` on the enemy, SWITCH prompt (Phase 1 logic, Phase 0 visuals); remembers the opener per enemy, and the window's own close clears only that window (D-099) |
| clip events (every watched rig) | trail, smear and footstep events to the FX and audio packages; `Sfx` and `Voice` through `SfxPool.play`; `ActivationHold` lights the blade, plays the art chime, kicks the FOV for the local player and calls `Impact.activation(model, clipId, token, isLocal, speed)` (D-074) |

Rig lifecycle: `EntityTracker.added` -> `Replication.watch(record)` registers the outline, attaches
the trail, routes the rig's clip events to the FX package and, for every rig the local
`CharacterController` does not own, drives locomotion with `Locomotion.attach(animator, model)`
(other players run the blend space, enemies their data Idle/Walk pair; a remote player's driver reads `Drawn`
through `SheathState.riseFilter`, D-057). Replication tells the local
rig apart by `EntityTracker.peekLocalId`, then by `Players.LocalPlayer.Character`, and drops a
driver that reached the local rig before its id resolved when `EntityTracker.localChanged` fires.
`EntityTracker.removed` -> `Replication.unwatch(record)` destroys that driver and releases the rig's
trails, telegraph, smear and state clip. `Main.client` wires
`Telegraphs.setIntensitySource(Hud.telegraphIntensity)` so the accessibility slider drives telegraph
intensity.

Clip tables are immutable after load: `ClipSampler` caches each clip's structure (the sorted joint
list and which key authors each joint's held value) and reads offset values live, so replacing a
joint's offset table needs no invalidate while adding or removing a key, a joint or the root does;
editors call `ClipSampler.invalidate(clip)` after such an edit. The PoseEditor `Session` cannot
require shared modules (it also runs under Lune), so the plugin host registers
`Session.setInvalidator(ClipSampler.invalidate)` and Session calls it after every edit, undo and
redo. A stale cache degrades to rest values for keys it never saw and never errors mid-frame.

## Places

- `places/Playground.project.json`: the 400-stud field, ceiling and lighting; `PlaygroundBuilder`
  adds the rim, pillars, clouds and kill volume at server start from `playground.luau`.
- `places/ClipLab.project.json`: the clip review scene (`ClipLab.client.luau` runs when
  `workspace:GetAttribute("ClipLab") == true`).
- Built with `tools/build-places.sh`; outputs are gitignored.
- Every project file (the game and each place) carries an empty LocalScript `Animate` in
  StarterCharacterScripts so Choreo is the only writer of joint `Transform`s on characters;
  `HttpService.HttpEnabled` is set in the dev places only (D-039).

## Smoke scripts (D-038)

`tests/smoke/*.smoke.luau` are plain server scripts: they wait for `workspace.SkyspireReady`, drive
the real services, and raise `error("[<name>] FAILED: ...", 0)` from a `check()` helper on the first
failed assertion. They never return at top level (the runner appends a done line). `tools/smoke.sh`
wraps each into a runner that run-in-roblox executes in a plugin: it installs the script as a
Script in ServerScriptService, starts a Run session (no player; stand-ins are registered through
`EntityService.registerPlayer` with a table for the Player), and prints one
`SMOKE-RESULT: PASS|FAIL <name>` line. Current scripts: playground, combat, archetypes, rigs
(joint names and `Rig` attributes from `rigs.luau`) and perf (section 16 server numbers from
`world.luau` `performance`).
