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
tools/gaitgen.luau             regenerates the OneHandedSword gait loops from tools/gaitgen/ (GaitGen, Gaits, Ik, Emit,
                               Rig, sources/); --check exits 1 on drift; Run and Sprint are GaitGen.DRIFTED (D-140)
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
  Draw or Sheathe after this step (sheathShownAfter: the mixer's blend rule, read before it runs), and
  is 0 while the sword is on the back. The sheath step hook sets it before the mixer step; update sets
  it for a weapon with no sheath (D-225).
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
  SystemLine and SfxPool run on Heartbeat, Engine.now or the wall clock. Choreo steps rigs on RenderStepped, except the local character, which CharacterController steps from its render step (Choreo.stepLocal, D-139); a render stall's gap is handled as a jump (D-132).

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

### After the controlled fight (D-125 to D-131)

- src/client/fx/AccentStep.luau: `deps.onWatch` (Heartbeat) sits beside `deps.onStep` (render), and `AccentStep.connect(deps, render, watch)` binds both. Glint, SlashArc and SpeedLines draw and fade on the render step and end what has run its length on the watch, so no accent outlives a render stall (D-125, D-117).
- src/client/fx/Bursts.luau (new): one-shot ParticleEmitter bursts. `Bursts.emit(emitter, count, lifetime)` emits and Clear()s on Heartbeat once the longest particle is gone. `pending`, `step`, `reset` and `bind(overrides)` are seams for specs. Used by Sparks.parry and Shatter's flash (D-125).
- src/client/controllers/AimLogic.luau: snap turn helpers `snapShown`, `newSnap`, `snapStep`, `snapLeft` and `snapSeconds`. `Config` gains `snapTurnSeconds` and `snapTurnEasing` (D-126).
- src/client/controllers/CharacterController.luau: a swing or release faces the whole snap at once, and the body shows it over aim.snapTurnSeconds (render step and Heartbeat). `aimRotation` (the root plus the rest of the turn) is what requests, dodges, guard facing and root motion read. New `lastFacing()` and `setCaptureTimeScale(scale): boolean` (Studio capture places only). It passes Locomotion `clockScale` = the capture scale (D-126, D-127). Replace the D-112 wording "a swing turns the rest of the way at once" with "faces the rest of the way at once; the body whips round over aim.snapTurnSeconds".
- src/client/choreo/Locomotion.luau: State gains `clockScale: number?`, the clock the root itself moves on (the local body in a slowed capture; nil = real time). The blend reads speed and yaw rate at 1x (divided by clockScale); the pace still divides the real speed by the mixer's scale. In stepGait, walks advance by axis·move, and Run and Sprint by self.runAlong, set each update from LocomotionState.runAlong (D-127, D-129).
- src/client/choreo/LocomotionState.luau: moveWeights computes the cadence shares, then a held-facing pass (D-129) that gives Run's facing-push share to the side walk while the body is held off its move. Exposes LocomotionState.runAlong(input).
- src/client/dev/Capture.client.luau: the local character's time scale goes through CharacterController.setCaptureTimeScale, which in Studio also moves the body at that scale (D-127).
- src/client/dev/DevAim.client.luau: swing reports yawAtSend from the facing the request carried (CharacterController.lastFacing); the body's turn shows after the send (D-126).
- tools/validators/combat.luau: the snap whip rules (D-126). tools/validators/stride.luau: the gait pacing data rules (D-131).
- tests/choreo/GroundClearance.spec.luau also caps Sheathe's tip speed at choreo.sheath.sheatheTipSpeed (D-130).

### After the wake and feet round (D-132 to D-137)

- src/client/choreo/Mixer.luau: the `step(dt)` result carries `jumped` (dt > choreo.stall.jumpSeconds), and each FiredEvent carries `jumped`. A jump advances the clocks by the gap (minus a shorter pending pause), zeroes the root delta, and still collects the crossed events. PlayOptions.sinceStep (seconds between the mixer's last step and the play) makes a clip played inside the gap move only by its own age on the jump step; it is ignored on any other step (D-132).
- src/client/choreo/Choreo.luau: `animator.events` fires (clipId, event, jumped); rbx markers and ordinary steps pass false. When either dt or the clock's time since the rig's last step is longer than stall.jumpSeconds, `step(dt)` uses the clock's time (engine.now). `play` passes sinceStep from the same clock. `currentRootMotionDelta()` returns Vector3.zero when the last step is older than stall.jumpSeconds (D-132).
- src/client/controllers/Replication.luau: `routeClipEvent(record, clipId, event, jumped?)`. A jumped event only closes (trail/smear off, activation light off, post-motion) and starts no sound, voice, footstep, chime, FOV kick, impact activation, trail or smear; `Replication.clipEvent` fires (record, clipId, event, jumped) (D-132).
- src/client/choreo/LocomotionState.luau: settlePoints reroutes a late settle point (within locomotion.stopHandOverCycles of the other foot's Footstep) to the other foot's point half a cycle later, so StopGait leftAfter/rightAfter may exceed 0.5; ActionLogic.stopCarryStep sums them with the cycles to each Footstep (D-136).
- The drawn forward gait clips (WalkForwardDrawn, RunDrawn, SprintDrawn) are leg twins of the sheathed ones (same plans, key times and Footsteps); a change to one set's legs is a change to both (D-134, D-135).
- tests/choreo/Stride.spec.luau guards each clip's authored slide: every walk under slideBar, every gait clip under transientBar, and a lock-on forward walk at walkSpeed (the walk/Run cadence blend) within transientBar (D-133).
- The capture path: setCaptureTimeScale → WalkSpeed × scale + animator:setTimeScale (mixer:timeScale, which Locomotion.stepGait divides the root speed by) + Locomotion clockScale. Locomotion paces from |AssemblyLinearVelocity| with the direction from MoveDirection (D-127, D-137).
- tools/validators/choreo.luau (new): stall.jumpSeconds is at least 2/rate for every tier's distantHz and farHz and at most camera.stall.settleSeconds. tools/validators/stride.luau keeps locomotion.stopHandOverCycles inside (0, 0.5). The validator count is now 32.

### After the controller round (D-138 to D-140)

- src/client/choreo/Mixer.luau: `seek(handle, clipTime) -> { FiredEvent }` moves one handle's clock forward now, ignoring pause and time scale. It returns the crossed events unmarked and sets lastRoot, so the skipped span adds no root delta. It does nothing for a time at or before the handle's own, for a done handle, or for a looping clip at or past its end. A one-shot's end is reported by the next step (D-138).
- src/client/choreo/Choreo.luau:
  - `animator:seek(handle, clipTime)` fires the seek's events on `animator.events`, with the same footstep-source filter as step. It leaves engine Animation handles and destroyed animators alone.
  - `Choreo.setLocalModel(model, driven?)` marks the local rig; `Choreo.stepLocal(dt)` steps the driven local rig once and does nothing otherwise.
  - RenderStepped skips a driven local rig. `Choreo.stepAll` (ClipLab and tests) still steps every rig (D-138, D-139).
- src/client/controllers/ActionLogic.luau: `holdClipTime(clip, fallback) -> number?` and `freezeAt(pressedAt, now, holdAt?, steppedAt?) -> (clipTime, seek)` (D-138).
- src/client/controllers/CharacterController.luau:
  - It hooks `animator:onStep(beforeRigStep)`. Before each step of the local rig, a hold freezes at its hold pose when the step is a jump or would carry the clip past hold time + combat activationHold. This applies to a hold that is at least its hold time old, not yet frozen, and younger than combat activationCancelTime. The hook then records rigSteppedAt.
  - freezeHold seeks the clip when freezeAt says so.
  - step() calls Choreo.stepLocal between Locomotion:update and the root-motion read.
  - On spawn it calls setLocalModel(model, true), and clearCharacter unhooks the step hook.
  - The clipEvent listener takes `jumped` (D-138, D-139).
- tools/gaitgen.luau and tools/gaitgen/: the gait clip generator for the OneHandedSword locomotion loops (WalkForward, Back, Left and Right, Run, Sprint and their Drawn twins; D-054, D-128, D-134, D-135, D-140).
  - GaitGen holds the names, the DRIFTED list, and generate, write, check and compare.
  - Gaits.luau holds each gait's foot plans, key times and sheathed upper body.
  - Ik.luau is a damped least-squares leg solver.
  - Emit.luau writes the clip text already in StyLua format.
  - Rig.luau poses HitMatrix.standing's PlayerR15 rig through Pose.solve.
  - sources/ holds pinned copies of the drawn upper bodies and WalkForward's arm swing from git 927dbed.
  - `lune run tools/gaitgen.luau --check` regenerates in memory and exits 1 on drift. tests/tools/gaitgen.spec.luau runs the same check plus the ownership, hand-edit and Run/Sprint root-and-legs tests.
- Tests:
  - New spec files: tests/choreo/MixerSeek.spec.luau, tests/choreo/ChoreoLocalStep.spec.luau (a fresh Choreo copy on fake frame signals), tests/client/ActionLogicHold.spec.luau and tests/tools/gaitgen.spec.luau.
  - tests/client/CharacterController.spec.luau has a `choreo` option: a fresh real Choreo animating a real PlayerR15 rig on the spec clock, with task.delay on that clock, `renderOrder` ("bound" or "connections"), and `heartbeat()`, `wake()` and `hitch(seconds)` for render stalls and engine hitches. Its hold specs cover sleeps, jump and shorter hitches, hitches past the cancel time, 10, 20 and 30 fps holds and a slowed capture.

### After the wake round and the blocked feet (D-141 to D-144)

- ActionLogic.rigAsleep(heartbeatsSinceStep) is true when more than one Heartbeat ran with no rig step. ActionLogic.wokenDodge(pressedAt, now, jumpSeconds) returns "Show" or "Drop".
- CharacterController counts Heartbeats since the last rig step (beforeRigStep and clearCharacter reset the count).
  - dodge() always sends DodgeRequest at the press. While asleep, it plays no clip, leaves actionEndsAt nil, and parks the dodge in sleptDodge {pressedAt, token}.
  - wakeSleptDodge(t) runs in step() after the root-motion read and before recordYaw. It plays the clip, starts actionEndsAt and calls showDodge() (CameraController.fovKick("Dash") plus Impact.dodge), or ends the action on "Drop".
- Trails.bind(overrides?) is the seam for now, onRender, onWatch and clear (defaults: Engine.now, AccentStep.renderStepped, Engine.onHeartbeat, a pcall'd Trail:Clear()). The Heartbeat watchdog runs before sample and rebalance, and the stalled flag gates Enabled.
- AntiCheatService.serverMoved(player, settleSeconds): boolean (server code only; a spec pins its callers). It calls resetSample and extends settleUntil. sample() resets and judges nothing until settleUntil passes; the first sample after that only records.
- DevCombat "place" goes through the server BindableFunction only. help returns one usage line per command. src/shared/data/dev.luau gains place = { settleSeconds, maxCoordinate }.
- `Locomotion.State` has an optional `velocity: Vector3?`, and `Locomotion.humanoidTracker` fills it.
  - When it is nil (the local CharacterController passes none), Locomotion reads `root.AssemblyLinearVelocity` through a pcall and caches a root it cannot read.
  - The velocity is used only when its horizontal size matches `state.speed` within `blocked.matchSpeed`.
- The blocked latch (D-144, `stepBlocked`) runs right after `self.speed` is set in `update`.
  - While blocked, forward, right and speed come from the smoothed real velocity, or the body stands when that velocity is under the idle threshold.
  - Otherwise the stick drives the gait exactly as before.
- `LocomotionState.wholeWalkSpeed(forward, right, drawn)` is rateFloor × the walk gait speed for a stick: the slowest speed that paces a whole walk. It is the blocked latch's release bar.

### Hit on contact, camera and names (D-145 to D-164)

- CameraController: each frame builds two rigs on the subject's pivot (root + focusHeight). The free rig uses orbitOffset and shoulderLook; the lock rig uses twoShotCamera and twoShotLook. A blend spring lerps between them. The rig rides a lagged pivot leashed along the view (CameraMath.leash). Collision is a repeated spherecast that skips characters, accessories and see-through parts (CameraMath.blocksView); one reach fraction scales the camera and aim offsets together.
- CameraMath: adds shoulderLook, splitAngle, twoShot (with the TwoShotParams and TwoShot types), twoShotCamera, twoShotLook, lockSide, leash and blocksView. lockFrame, LockParams and LockFrame are removed.
- Nameplates: hide(model) is the shatter's hook. A Dead rig's plate also expires at deathDuckDelay + deathFreeze.
- Hud: the main gui sits in the safe area (ScreenInsets from ui.hud). The vignette has its own ScreenGui, exposed by Hud.vignetteGui().
- RigBuilder: every rig's Humanoid has DisplayDistanceType None.
- src/shared/choreo/BladeContact.luau: a pure blade solver.
  - chain(model): the joint path to the TrailStart/TrailEnd part.
  - read/copy: a pose (the root CFrame plus joint Transforms).
  - blade(chain, pose, from?, alpha?): forward kinematics, following the arc between two frames.
  - segmentBoxDistance: identical to HitSweep's.
  - touch, steps, queryable.
- src/client/controllers/ContactPredictor.luau: predicts the local swing's contacts.
  - begin({clip, handle, artId, finalHit, multiplier}), then step(clipTime, jumped?) once per rendered frame. A jumped step re-baselines the sweep and returns no contacts (D-164).
  - Gives at most one contact per target per window.
  - tierFor, leastDamage, provesKill.
  - It never decides damage.
- Frame order:
  - Camera at render step 200, ImpactFrames at 201, CharacterController at 301.
  - At 301: Choreo.stepLocal → root motion → stepContacts → Replication.contact.
  - The contact frame shows the contact pose, sound and flash. The hit-stop freezes the next steps, and the camera nudge and shake show on the frame after contact.
- CharacterController: rigJumped is set in beforeRigStep (dt > stall.jumpSeconds), then read and cleared by stepContacts.
- Replication.contact(contact) → boolean plays the local hit and records a prediction.
  - HitConfirmed matches predictions by (target, hitIndex, artId), oldest first, within combat.contact.confirmSeconds of play time.
  - An upgrade extends the running hold, using Animator:pauseRemaining(), but only when the contact's own hold run is the running one.
  - Replication.confirmedAlready(targetId, window, artId) handles a confirm that arrived before the local contact.
  - Every local-rig hold goes through holdLocal(animator, frames), which tracks holdRun and holdEnds: a hold joins the running one or starts a new run.
  - playClock() and tickPlay() keep a play clock on Deps.onHeartbeat, where a step counts at most stall.jumpSeconds; start() binds RunService.Heartbeat.
  - Prediction rows carry `at` (wall), `seen` (play) and `run`.
- Impact.hit(info, previous?) plays only what the moment adds over `previous`, by rank in the moments rows.
- Mixer: handles carry absorbKey and absorbSeconds; hitStop absorbs a strike's authored Hold (D-154). Choreo's Animator gains pauseRemaining().
- ClipSampler: snapEase, isStrikeSnap, strikeHoldAfter. The server samples the eased snaps too.
- FrameClock: render steps at First and Last priority, a Heartbeat watchdog, pace(), and bind() for specs.
- OutlineManager.tint/untint (used by Telegraphs on weaponless rigs). Trails: the weapon-only activation flash and the cancel fade. SfxPool.asOwn and the OwnSFX group. ImpactFrames.whenVisible and drawn-frame quotas.

### Enemy attacks on the server's beat (D-165 to D-182)

- **server/world/CollisionGroups** (D-167):
  - `register(physics?)`: Main calls it before any service starts; idempotent; warns on failure.
  - `assign(model, group)`.
  - `joinPlayers(character)`: CharacterReady's default collide.
  - `playerPartAdded`.
  - `clear(model, overlap?)`: the rejoin test.
  - Group names come from ai.luau `collision`.
- **EnemyService**:
  - `alignOf` looks the yaw aligner up by class (D-165).
  - `bodyExtents(model)` returns front and back in studs from the root, computed at spawn.
  - The engine seam gains optional `setCollisionGroup(model, group)` and `bodyClear(model)`.
  - Enemies spawn in the Enemies group, switch to Rushing at RushStarted, and rejoin when clear.
  - `pauseForHit(id, seconds)` returns the seconds added, or nil. bind installs it through `CombatService.setEnemyHitStop`.
  - The Brain context gains `bodyExtents`, `rushStarted`, `rushEnded` and `extendState`.
- **Brain**:
  - New: `strikeStretch(origin, facing, from, to, resolved)`, `pauseAttack(seconds)`, `frozen()`, `cancelAttack(reason)`.
  - Archetype hooks `contactStrike` and `onCancel`.
  - When the wind-up ends, the strike phase starts at phaseStart + windUp, the attack's own beat, not the tick (D-182).
  - Exported type `Rush`: startedAt is the launch beat (RushStarted.serverTime); bodyStartedAt is the AI tick the body started running.
- **Charger**: the line resolves on startedAt's clock. The body's jam check and its end use bodyStartedAt's clock.
- **CombatService**:
  - `enemyStrike(enemyId, attack, origin, facing, options?)` takes `Types.EnemyStrikeOptions` {span, resolved}.
  - `setEnemyHitStop(hook)`.
  - HitConfirmed gains `attackPause` and echoes `swing`. swingOf validates the request's swing number.
- **HitSweep**: `lineTargets(..., span?)` limits a line to [from, to] studs along it.
- **EntityService**: `extendState(id, seconds)` pushes a timed state's end (and its lock) without StateChanged.
- **CharacterReady**:
  - `join(character)`; Engine.collide puts a finished character in the Players group.
  - `unlabel(character)` turns off the engine's name and health display on each Humanoid; wait() calls it on the first frame and when ready (D-178).
- **Remotes**:
  - `RushStarted`, `RushEnded` and `RushTurned`: reliable RemoteEvents, server to client (D-221).
  - `HitConfirmed.attackPause`.
  - ArtRequest, BasicAttackRequest and HitConfirmed carry an optional `swing` (integer, 1 .. combat.contact.swingSequenceMax).
- **PlaygroundLayout / PlaygroundService**:
  - `spacedScatter(cx, cz, radius, spacing, occupied, random)` returns x, z and clear.
  - `PlaygroundService.occupied()`.
  - spawnCFrame keeps the spacing (D-170).
- **client/choreo/RushDraw** (pure): a Charger rush's drawn timeline on the server clock.
  - Functions: predict (from the Telegraph), start (RushStarted), delay, jam, stop, halt, freeze and step.
  - Replication steps it from the animator's onStep hook and draws the body with Animator.setBodyOffset (offset composed on the root joint), hiding the root part.
- **Mixer**: keepBeat(handle, untilTime, owed), shiftBeat(handle, seconds), beatOwed(handle).
- **Animator**: keepBeat(handle, serverTime), shiftBeat, setBodyOffset(offset?).
- **Telegraphs**: show(..., lateBy) shortens the telegraph by the time already gone; delay(model, seconds) moves a showing telegraph's end.
- **Replication**:
  - drawnAway(part) feeds ContactPredictor deps.hidden.
  - ContactPredictor deps.targets is EntityTracker.live. Contacts and confirmedAlready carry `swing`.
  - Replication requires Shared.choreo.ClipSampler for the strike-hold credit (D-176).
- **EntityTracker.live()**: one frozen, id-sorted list, replaced only when a record comes or goes (D-175).
- **client/fx/Shatter**: hideRig hides the rig's parts, suspends its outline, detaches trails, hides telegraphs and now hides the nameplate (Nameplates.hide).
- **client/ui/Nameplates**:
  - keepFolder() runs on attach, update and Heartbeat; it puts back or rebuilds the PlayerGui folder after a respawn reset.
  - Seams: Nameplates.step(dt) (one Heartbeat), Nameplates.folder(), Nameplates.setGuiParent(source).
- **client/camera/CameraController**: two render steps, SkyspireCamera at Camera (200) and SkyspireCameraLate at Last. The late pass redraws only when nudge() or shake() was called after this frame's main step.
- **client/camera/CameraMath.leash(focus, trailing, forward, closer, further, side?)**: clamps the lag along the view to [-further, closer] and, when side is given, across it to ±side.
- **shared/data/camera.luau**: follow.leash = { closer 0.75, further 2.5, side 1.0 }.

### Strikes on the frame, smooth turns and the ceiling shadow (D-183 to D-192)

- **server/services/EnemyService**:
  - `step(dt)` runs the whole 20 Hz ticks (at most maxTicksPerFrame), then the frame pass. For each awake entry it calls `Brain.frame()`, and the mover takes any goal handed over in that frame (D-184).
  - Mover fields: `direct` (the current move kind) and `pending` (a goal handed over since the last mover update).
  - The stuck clock restarts per movement: on a start from standing, or on a switch between direct and path-aware, which also drops a path in flight.
  - A late path skips a first waypoint within waypointReach of where the body asked from (D-183).
  - Entry gains `clearSince`. `rushEnded` starts the rejoin wait for every reason, a jam included.
  - `rejoin(entry, now)` runs on each tick. It sets the Enemies group once `bodyClear` has held for ai.collision.rejoinClearSeconds in a row; an overlap restarts the count (D-190).
- **server/ai/Brain**:
  - `frame()` runs on every server frame: the timed attack edges (`beat`) and the body turn (`advanceTurn`). `tick` keeps perception and decisions.
  - `beat(now, dt)`: the wind-up's end becomes the strike, then the strike's resolve. The tick and the frame both call it, so an edge resolves exactly once (D-184).
  - `advanceTurn(at)`: the per-frame yaw toward `turnGoal` at the phase's rate, capped after a hitch. `turnToward` only records the goal (D-185).
  - `moveDirect(position, speed)`: a strike's own move, straight and never pathfound. `moveToward` stays path-aware (D-183).
- **server/ai/Charger**:
  - `bodyStartedAt` is the server frame the body launched on.
  - A jam reports `rushEnded("Jammed")` and stops the body with `context.stop()`. The line keeps resolving on the clock to the run's end (D-190).
- **shared/data/ai.luau** `collision`: `clientDrawLagSeconds` (engine fact, 0.3) and `rejoinClearSeconds` (0.5). tools/validators/ai.luau checks rejoinClearSeconds > clientDrawLagSeconds, and every Charger rush's recovery > rejoinClearSeconds.
- **client/fx/Shatter.expect(model, seconds)** and **client/ui/Nameplates.expect(model, seconds)**:
  - Replication's EntityDied calls Shatter.expect where it schedules the shatter. The plate's fallback then waits ui.nameplates.shatterGraceSeconds past the shatter's time.
  - Shatter's hideRig, through Nameplates.hide, takes the plate on the body's frame (D-187).
  - An overdue plate goes on the Heartbeat after the first one that saw it overdue (`Plate.overdueBeat`, D-191).
- **client/choreo/Mixer.beatStep**: a kept beat's last step evens the whole balance: maxRate when the clip is behind, minRate when it is ahead (D-188).
- **places/Playground.project.json**: the Ceiling has CastShadow false. tests/project fails any part at or above 100 studs that casts a shadow (D-186).

### Rush followers, jam line and late paths (D-193 to D-198)

- **client/choreo/DrawnBody**: where a rig's body is drawn, meaning its root part moved by Choreo's body offset (a rush, D-171). Readers use DrawnBody.position and DrawnBody.cframe. DrawnBody.follow and unfollow keep a root-adorned BillboardGui over the body (D-193). Also add it to the client layout list.
- **client/choreo/Choreo**: applyOffsets publishes each offset from the same step that writes it into the root joint, which moves the following billboards. It publishes nil when the offset ends and on destroy.
- **Client readers of an enemy's position**, all through DrawnBody:
  - Nameplates (plate, fade, hover), Hud (SWITCH), CameraController (lock point);
  - Engine.modelPosition, which also feeds SfxPool, Trails, OutlineManager, ImpactFrames, Impact and Shatter;
  - the Replication sound position, Choreo.rerank and DevAim.
  - Digits, Sparks, SwitchRing and the telegraph decal stay on server points.
- **client/controllers/TargetController** `positionOf` and **CharacterController** `lockPosition`: the lock range, break distance, assist and lock turn are measured on the drawn body (D-194). Extend the TargetController line accordingly.
- **server/ai/Charger.sweep**:
  - Each stretch is capped at progressOf + front + speed × late start + keepUpStuds (D-195).
  - memory.rushResolved holds the furthest point resolved and starts the next stretch when that is behind the clock's back.
  - Nothing resolves after rushJammed.
  - The cap is also rootAt + brain:worldAhead(direction, to − rootAt) (D-197). A wall right at the crouch resolves nothing yet.
  - This replaces "The line keeps resolving on the clock to the run's end (D-190)" in the D-183 to D-192 section.
- **server/ai/Brain**: `worldAhead(direction, distance): number?` asks Context.worldAhead and returns nil when there is no hook or distance ≤ 0.
- **server/services/EnemyService**:
  - Mover gains pathFrom (where the body asked) and pathFresh (a path landed since the last update). firstAhead skips leading waypoints already passed on the first update after a path lands (D-196).
  - `worldAhead(model, direction, distance, cast?)` flattens the direction, starts the root's box with its front face at the root's centre, and returns the distance travelled or nil.
  - `WorldCast` type; `defaultWorldCast` is workspace:Blockcast with RaycastParams set to Exclude the model, RespectCanCollide on, and CollisionGroup set to the root's group.
  - The engine seam gains `worldAhead`, and makeContext wires it.
  - spawn calls rigBuilder.addBlocker before setting the enemies group (D-198).
- **server/world/RigBuilder**: `addBlocker(model): Part?` builds the invisible blocker: the root's footprint from the floor to blockerHeight, welded to the root, in the blockers group, named `RigBuilder.BLOCKER_NAME` ("Blocker"). It returns nil when there is no root or the rig is unknown.
- **server/world/CollisionGroups**:
  - names() returns four groups: players, enemies, rushing, blockers.
  - isBlocker(part) is new.
  - assign keeps a blocker in its group, with CanCollide on only for the enemies group.
  - clear checks the root against players and enemies, and each blocker against players.
- **shared/choreo/BladeContact.queryable**: (CanQuery or CanCollide) and not in a group kept apart from Default. HitSweep.isQueryable delegates to it, and ContactPredictor already uses it.
- **shared/data/ai.luau**: archetypes.Charger.keepUpStuds (1). collision.blockers ("SkyspireBlockers"), collision.blockerHeight (7), and new apart pairs: Enemies–Players, and Blockers–Default, Enemies, Rushing and Blockers.
- **tools/validators/ai.luau** requires:
  - keepUpStuds positive and below jamLagStuds;
  - four distinct groups;
  - apart pairs that name a fighter group or Default;
  - blockers kept from Default, enemies, rushing and blockers, but not from players;
  - enemies kept from players;
  - blockerHeight above every enemy rig's hipHeight + root height.

### The end of a charge (D-199 to D-204)

- **Client frame order:** FrameClock (First) → SkyspireRigs 199 (Choreo rig step, D-201) → SkyspireCamera 200 → ImpactFrames 201 → CharacterController/contact 301 (Character+1) → SkyspireCameraLate 2000 → FrameClock (Last).
- **client/choreo/Choreo**:
  - `RENDER_STEP` ("SkyspireRigs") and `renderPriority()` (Camera − 1).
  - Full-rate rigs step in that bound step; Engine.renderStepped defaults to it. The local driven rig is still stepped only by stepLocal at 301 (D-139).
- **client/choreo/RushDraw**:
  - `room(from, size, direction, distance, cast, exclude): number?` is the server's worldAhead cast made from the drawn body, in AI.collision.rushing. It returns the free distance, or nil for nothing in the way, a failed cast, or ground (D-199, D-204).
  - `isGround(normal)` applies ai.luau collision.groundSlopeDegrees.
  - `WorldCast` returns (distance?, normal?); `Room` type.
  - `step(state, now, dt, root, room?)` cuts a step the world stops and jams the limit there.
  - `retime` keeps the limit's world point.
- **client/controllers/Replication**:
  - The `worldCast` dependency defaults to workspace:Blockcast (cached RaycastParams: Exclude, RespectCanCollide, the given group) and returns Distance and Normal.
  - armRush builds `rush.room` from the root's size and its own model; stepRush passes it to RushDraw.step.
- **client/choreo/Locomotion**: `drawnTracker(animator, character)` feeds the gait from the drawn body's movement while a body offset is drawn (D-200).
- **server/ai/Charger**:
  - `stopAtWall(brain, rush, face)` (D-202) marks rushJammed, sends rushEnded("Jammed", clamp(face − rootReach, progress, length)), then moveDirects there or calls context.stop(). It does nothing unless the rush is rushing, not yet jammed, and in Strike.
  - `sweep` caps each stretch at any face worldAhead finds, and calls stopAtWall only when that face is not ground (D-204).
  - Past the strike beat, `sweep` casts once per pass (memory.rushLooked, reset in onStrikeStart) to min(speed × elapsed + front, reached, length + rootReach).
  - `onStrike`'s jamLagStuds check now covers only stops the cast misses.
- **server/ai/Brain**:
  - `rootReach(direction): number` asks Context.rootReach (0 with no hook, never negative).
  - `worldAhead(direction, distance): (number?, boolean)` returns the face and whether it is ground, or nil and false. This replaces "worldAhead(direction, distance): number?" in the D-193 to D-198 section.
  - Context gains `rootReach`; Context.worldAhead returns (number?, boolean?).
- **server/services/EnemyService**:
  - `rootReach(model, direction)`: half the root box's extent along the flattened direction; 0 with no root or a vertical direction.
  - `worldAhead(model, direction, distance, cast?)` starts the cast from rootReach and returns (distance?, isGround?).
  - `isGround(normal)`.
  - `WorldCast` returns (number?, Vector3?); defaultWorldCast returns Distance and Normal.
  - engine.worldAhead returns (number?, boolean?).
  - makeContext wires rootReach and passes both worldAhead values.
- **shared/data/ai**: `collision.groundSlopeDegrees` (45); the comment on archetypes.Charger.jamLagStuds is rewritten (the value stays 4).
- **tools/validators/ai**: groundSlopeDegrees must be a number below 90 and at least each Charger rig's atan(hipHeight / half its root's length).

### Wall slams and frame order (D-205 to D-218)

- **Module list.**
  - Under src/shared/, add `choreo/RushWorld.luau        pure rules for a rush meeting the world: path legs, body outline, ground, Slam / Glance / Clip contact (D-205 to D-209)`.
  - After line 60 (fx/AccentStep), add `fx/FrameOrder.luau           the client's render order: named bound steps that pose readers join (D-211)` and `fx/WallSlam.luau             the pooled dust a rush's slam throws off a wall (D-217)`.
- **src/shared/choreo/RushWorld.luau:** pure shared rules for a rush meeting the world. Covers:
  - path legs: line, legIndex, pointAt, timeAt, sameLegs, SAME_STUDS;
  - the body outline: profileOf, front;
  - ground: isGround, groundBelow, climbable, runsOver;
  - contact: Slam / Glance / Clip, lookLimit.
  - Used by Charger, EnemyService, RushDraw and Replication.
- **Remotes:** new RushTurned (reliable since D-221, ServerToClient: kind, at, legs up to ai.rushWorld.maxLegs, contact, normal). RushEnded gains reason "Wall" and optional contact and normal. After a Jammed or Wall, the interrupt that ends the rush is sent once more as RushEnded (D-210).
- **server/ai/Brain:** Context gains bodyProfile, rushTurned and daze. worldAhead gains an offset and returns the face normal. Brain.frame() runs the rush's look every server frame.
- **client/choreo/RushDraw:**
  - setBody(state, body, hover), ground(spot, cast, model), wall(state, distance, contact, normal), rest(state, distance), takeCues(state).
  - step(state, now, dt, root, room?, ground?).
  - halt(state, now) is ignored once a stop is told. With no stop told, it goes onto a face the own cast found and the timeline reached (D-218).
- **client/controllers/Replication:**
  - rushContact is a Signal fired as (record, kind "Slam", "Glance" or "Clip", point, normal) on the frame the drawn body reaches the contact. It fires in stepRush, inside Choreo's rig step (199).
  - A Slam also runs slamCue: WallSlam dust, sfx cue fx.wallSlam.cue at the point, and camera.shake(shakeTier) when the local body is within shakeRadius (D-217).
  - Deps gains wallSlam.
- **client/fx/WallSlam:** one anchored, invisible, non-colliding part with a world-space ParticleEmitter in workspace folder WallSlamDust.
  - start() builds it.
  - slam(point, normal) moves it to the point, faces it along the flat normal, and emits count(particleScale) puffs through Bursts.
  - count(scale) and emitter() are seams for specs.
  - No FlashBudget charge (lightEmission 0).
- **client/fx/FrameOrder:**
  - join(name, row, fn) returns leave, or nil under Lune. prepare(name, row) returns a boolean.
  - priority(row) returns the Enum.RenderPriority value of base plus offset.
  - Steps are bound once and stay bound. Callbacks run in join order, each in its own pcall. No per-frame allocation.
- **Start order (line 344):** add fx.WallSlam after fx.Sparks.
- **Lines 99–100:** replace with "ImpactFrames runs in the render step `impact.overlay.renderStepName` (`SkyspireImpactFrames`) at fx.luau renderOrder.impactFrames (Character+3, 303). It is joined through FrameOrder and bound from ImpactFrames.start. No other module reuses that name."
- **Line 467:** Trails' Heartbeat now runs only the watchdog, the fades and the re-rank; blade samples run in SkyspirePoseReaders (304). Choreo steps its full-rate rigs in SkyspireRigs (D-201), not on RenderStepped.
- **Lines 580–582 (Frame order):** replace with:
  - "SkyspireRigs 199 → CharacterController 301 (Choreo.stepLocal → root motion → stepContacts → Replication.contact) → SkyspireCamera 302 → SkyspireImpactFrames 303 → SkyspirePoseReaders 304 → SkyspireCameraLate and FrameClock's end at 2000, tied (D-211)."
  - "The contact frame shows the contact pose, the sound, the flash, the impact picture's first frame and the camera's nudge, shake and kick. The hit-stop freezes the steps after it."
- **Line 652:** "two render steps: SkyspireCamera at camera.luau renderOrder.main (Character+2, 302) and SkyspireCameraLate at renderOrder.late (Last)".
- **Line 722 (Client frame order):** "FrameClock (First) → SkyspireRigs 199 → SkyspireCharacter 301 (controller, contact) → SkyspireCamera 302 → SkyspireImpactFrames 303 → SkyspirePoseReaders 304 (Trails) → SkyspireCameraLate and FrameClock (Last), tied at 2000. The priorities are data rows in choreo, camera and fx .luau renderOrder (D-211)."
- **Line 724:** "`renderPriority()` reads choreo.luau renderOrder.rigs (Camera − 1)."

### Draw, sheathe and lost rush messages (D-219 to D-226)

- **tests/choreo/SheathTip.spec.luau:** Draw and Sheathe through the client's own path (Locomotion, SheathState, the Choreo mixer, WeaponMount) on the hit matrix's player.
  - It runs at 0/8/16/24 studs/s, stepped at 60 and 240 Hz, plus one 0.1 s frame after each of the clip's first 3 steps at 60 Hz.
  - The tip stays under sheath.drawTipSpeed and sheatheTipSpeed, and the blade under sheath.bladeTurnRate (D-219, D-225).
- **choreo.luau sheath:** drawTipSpeed, sheatheTipSpeed and bladeTurnRate are the speed caps (D-219).
- **dev.luau groundClearance.sheathTip:** the SheathTip cases (settle, after, speeds, stepHz, hitch).
- **Locomotion:**
  - While the target is sheathed and the sword is still in the hand, the base shows the drawn set until a live Sheathe has faded in (showsDrawn), then the sheathed set (D-220).
- **Remotes:**
  - RushStarted, RushEnded and RushTurned are reliable server-to-client RemoteEvents (kind "Event"). ActionStarted, Telegraph and SwitchWindow are UnreliableRemoteEvents (D-221).
- **Replication:** `launches[enemyId]` holds the serverTime of the last RushStarted heard. A Telegraph older than it is dropped before it shows a glow or arms a predicted rush. It is cleared on unwatch and bind (D-222).
- **ImpactFrames:**
  - The ScreenGui is turned on by stepSequence's first counted frame, or by run() when there is no render step (D-223).
  - showSequence turns it on at play only when taking over a picture already on screen: it holds that sequence's look (D-223), or the soft dim frozen at its drawn opacity (D-226), until the new sequence's first counted frame.
  - playDim still turns on at once.

### Gate shot fixes (D-227 to D-270)

- **ContactPredictor:**
  - step sweeps the clip's own arc between rendered frames (the clip pose times the drawn pose's interpolated residual, split adaptively within combat.contact.maxSubdivisions). It holds a touch predicted before its strike's key until the key frame (D-227, D-234).
  - standOff(model, clip, from, rootCFrame, target) is pure and plans the Art stand-off (D-235).
  - awaitsKey(self, windowIndex, artId?, swing?) → boolean: true while that hit's strike key (window.key) has not shown on the predicted clip (time < key − keyEpsilon, or not stepped yet). False with no swing, another Art, another swing number, or no such window (D-267).
- **CharacterController:**
  - planStandOff runs at ArtRequest. stepStandOff moves the root each frame after root motion and before stepContacts. AimLogic.standOffAt is the eased curve on the clip clock (D-235).
  - takeArtAway lets go of an Art the server took away and fades its light and glow (D-231). The heldYaw block holds the root's yaw under root motion (AimLogic.holdTurn, D-232).
  - awaitsKey(windowIndex, artId?, swing?) gives the predictor's answer for the swing being predicted, false with none (D-267).
- **Replication:**
  - heldFrames applies combat.hitStopShaveFrames to every animator hold (D-228). takenAway makes routeClipEvent close-only on a clip taken away (D-231).
  - Deps.keyAhead (optional) is bound in start() to CharacterController.awaitsKey through keyAheadOf (nil for a stub); the CharacterController module is loaded once and shared with localDefence.
  - heldWords holds the server's words for their key. Replication.contact plays a matching one right after the contact it predicted. stepWords() runs on the Heartbeat after stepStrikes and plays any whose key has passed, whose swing ended, or that waited combat.contact.wordWaitSeconds. Words are held only on a client with onHeartbeat; bind() clears the list (D-267).
  - stepStrikes runs on the Heartbeat beside tickPlay. It predicts the reaction to enemy blows on the local fighter (ai.strikePrediction; localDefence comes from CharacterController.state and stateChanged). HitConfirmed confirms the HP or takes the reaction back (D-258).
  - A parried HitConfirmed puts no hold on either rig (D-257). RushEnded "Dropped" drops the drawn attack, hides the telegraph and releases a swing clip (D-254). An ActionStarted heard after its own RushStarted starts no Charge clip (D-260).
- **tools/hitmatrix:** the server swing plus a client draw (Mixer and ContactPredictor) at dev.hitMatrix.clientFps × framePhases. It reports drawnNotCounted and countedNotDrawn, and models the Art stand-off for setups inside the assist cone and range (D-234, D-235).
- **Camera:**
  - CameraController.setStage(view?, target?, side?) and staged(): the capture's staged view. It anchors on the player, the target or their middle, and references the player-to-target line, the target's facing or the world, at side × degrees, at a distance and height. It uses the lock's turn cap and aim depth, takes priority over the lock and free cameras but not a scripted camera, and blends on lock.blendLag. The pure helpers are CameraMath.stageAnchor and stageReference (D-251).
  - holdLock(seconds), lockLive() and lockMove(direction) (D-238, D-239). camera.lock gains closeGap, openGap, closeSwingDegrees, closeHeight, maxTurnDegreesPerSecond, aimDepthFraction and footprintPart; CameraMath gains closeness, capTurn and holdAimDepth (D-236, D-240).
  - TargetController ends the lock at once when the target dies and calls holdLock for the death freeze (D-239).
- **Dev capture (module map, next to dev/Capture.client.luau):**
  - client/dev/CaptureLogic: pure rules for the counter text, K decisions, prompt lines and auto-perform presses (D-248 to D-250).
  - Capture.client: P stages, frames and counts 3-2-1; U toggles auto-perform; J gives the field back through giveBack(token), which asks again at the stage request rate, up to stageTimeoutSeconds, and drops out when stageToken changes. Only the server's agreement sets "Field given back" (D-268).
  - server/dev/DevStage.server: the Studio and DevCapture-only RemoteFunction DevStage, with stage, go and release (D-242 to D-247). It is a dev hook beside DevCombat (D-114), but a RemoteFunction, because the client's Capture panel calls it.
  - server/dev/DevStageLogic: pure rules for spots, holds and the rate limit, and the stand ring and walk route: ring(open, stage), inRing(ring, x, feetY, z), route(open, stage, built, fromX, fromZ) round the ledge and ramp ending with an approach along the spot's facing, crosses(box, ax, az, bx, bz), rampFrame(ledge), onRamp(ledge, x, z) (D-244).
  - DevStage "stage" never moves the player and no longer requires AntiCheatService (D-244). Outside the ring it replies { ok = false, error = "walk into the ring first", walk = { x, y, z, facing, radius, tolerance, over?, path } }; inside, it heals and spawns around the root's actual position and facing.
  - Capture.client phase "Walking": a flat SystemCyan disc marks the ring, and the render step "SkyspireCaptureWalk" at dev.luau capture.walk.renderOrder (Input + 1, after the control script's Move and before CharacterController reads MoveDirection) hands the route's direction to Humanoid:Move. It lets go 2 studs short so the two-step stop carries the body in, waits for rest, removes the disc and asks again. A movement key hands the walk over (the shot stages once the root stands in the ring); J and P end it; capture.walk.timeoutSeconds (15) ends it with a note. It is not a FrameOrder step. CaptureLogic.walkFrom, inRing, steer and askWait are its pure half.
  - dev.luau capture gains staging: shots (stage, camera, cameraSide, prompts, perform), cameras, stage, prompt, confirmSeconds, stageTimeoutSeconds, and hotkeys U and J.
- **Rigs:** RigBuilder.footprint(rigId), and the blocker over the rest footprint (D-237).
- **Enemies (server):**
  - server/ai/Spacing.luau: pure capsule spacing between enemies. footprintOf(profile) is taken from RushWorld.profileOf corners at spawn; clearance, standOff and steer cover the goal edge, the slide and the step out. EnemyService.keepRoom reads it every AI tick before moverUpdate, and Brain reads it through context.standOff for the Return home (D-259).
  - EnemyService entries carry footprint and stepping. keepRoom(entry) steers free enemies (ai.spacing.freePhases). context.attackDropped fires RushEnded "Dropped" when a held or sleeping enemy loses its wind-up (D-254).
  - Remotes: the RushEnded reasons gain "Dropped" (the server abandoned a wind-up before launch).
- **Telegraphs and rushes (client):**
  - A melee tell stays lit to the snap, with a steady glint over the parry window (ai.telegraph snapLeadSeconds, glintFillTransparency; D-252). Cones are WedgePart fans on the ground (RushDraw.ground; D-253).
  - RushDraw's Armed phase faces the Telegraph's facing (D-255) and infers a jam from a root at rest (ai.rushWorld restStuds, restSeconds, restSpeed; D-256).
- **Trails, glow, sound and HUD:**
  - TrailRibbon (client/fx): a ring of blade samples drawn as chained camera-facing Beams. Trails owns one per rig with a blade chain and feeds it the sub-step blades from BladeContact.blade between rendered frames. Trails.bind takes a held dependency so the ribbon's ages stand still during hit-stop. Trails.ribbonOf(model) is for specs (D-261, D-269).
  - Trails.activationLight also lights the blade's glow Beams (fx.activationLight.glow) and fades them with the light when cancelled (D-263).
  - Mixer.preview(handle, dt) reports what a handle's limbs will show after the next step, by Mixer.step's own rule. Mixer.hold(handle) stops its clock while the envelope keeps moving. Locomotion's sheath hook uses preview; SheathState cuts back with hold plus choreo.sheath.cutBackBlend (D-262).
  - SfxPool: each group's EQ is always in (flat while idle) and setEnabled switches only the reverb; sub-frame ramps land at once. The low-HP heartbeat loop ducks under the local player's own hit cues (sfx.mix.heartbeatDuck), stepped on Heartbeat (D-264).
  - HudLogic.declutter(boxes, gap, maxHeights, previous?) → (lifts, order) is pure: it returns each screen box's lift, the nearest first. PlateBox.key names a plate from update to update; with previous given, adjacent plates swap only past reorderStuds. HudLogic.easeLift eases a lift exponentially (D-265, D-270).
  - Nameplates: each update builds boxes for the shown plates, keyed by record.id, declutters them and keeps declutterOrder; each Heartbeat eases SizeOffset.Y. Nameplates.setProjector(fn) is for specs.
  - SpeedLines: each pooled line carries a UIStroke ink edge with its own UIGradient; lay() writes the edge's transparency with the core's.
- **Data tables:** combat.luau hitStopShaveFrames and contact (keyEpsilon, wordWaitSeconds, standOff); camera.luau lock keys; ai.luau telegraph, strikePrediction, rushWorld rest keys and spacing; fx.luau trail.ribbon, activationLight.glow and wallSlam; sfx.luau mix.heartbeatDuck, playback.sameFrameSeconds and shatterBalance; ui.luau systemLine, hud.artList and nameplates.declutter; accents.luau speedLines edge; choreo.luau sheath.cutBackBlend; dev.luau capture staging and hitMatrix.clientFps.

### Gate shot fixes, second round (D-271 to D-296)

- **Hit path (client):**
  - Mixer: a pause ends at the frame nearest its length. `owes(pause, dt)` is false once what is left is under half of dt. combat.hitStopShaveFrames is 0, so Replication.heldFrames passes holds through whole (D-271).
  - Replication: a kill's HitConfirmed is held for its strike key like any other word (D-267), and the kill's EntityDied waits with it (deaths kept per entity: takeDeaths, releaseDeaths, playDeath). The death freeze, silence and shatter start on the key frame (D-272).
  - Trails and TrailRibbon: a stroke starts at its window's open instant. The sub-steps between rendered frames are the clip's own poses at those times (residualsOf, followSource, bladeAt), not chords (D-273).
  - ContactPredictor:
    - worldCast(model, blockcast?, exclude?) → BoxCast, room(...) and fighters(model, scene?, players?) give the stand-off's world limit.
    - standOff(model, clip, time, rootCFrame, target, cast?) returns a plan with room(rootCFrame, distance) → number, which CharacterController.stepStandOff applies every frame (D-276).
    - A fighter judged beside the swing when a window opens (besideSwing; per-window aims and beside sets) is tested with the blade only (D-275).
    - Contacts use BladeContact.hurtbox (D-277).
- **BladeContact (shared by HitSweep, ContactPredictor and tools/hitmatrix):**
  - held(part) and hurtbox(part): a part named in its rig's trailParts, under a Model whose Rig attribute names a rigs.luau rig, is a weapon and never a hurtbox (D-277).
  - beside(...) judges a fighter outside the assist cone. sweptTouch, followTouch and rootBow test it along the drawn arc with besideHitRadius (D-275).
- **HitSweep and CombatService (server):**
  - The beside sweep (sweepBeside, nearBlade, besideOf) runs alongside the aimed sweep.
  - A cast that meets a held weapon excludes only that part and goes on.
  - CombatService keeps per-window aimOrigin and besideIds, and its traces use hurtbox (D-275, D-277).
- **Enemies (server):**
  - EnemyService movers (D-278, D-279, D-295):
    - snoutWalk returns the room and the face's normal, and snoutRoom slides a slanted walk along that face.
    - snoutAhead and canFace judge a turn where the body stands.
    - A rush stop within ai.movement.haltLeadSeconds is made exact through Engine.halt.
  - Brain.turnStep turns the short way unless context.canFace refuses. A free body then turns the long way (turnSense) until it is through the half turn; an attack's turn never does (D-295). Brain gains moveDirect and halt.
  - Charger: blocked(brain, rush, now, progress) is the blocked-step jam (archetypes.Charger runningFraction, blockedFraction, blockedSeconds; D-280).
  - EnemyService.blockerClear(model) runs a separating-axis test (uprightBoxesOverlap) between the model's blocker and every other entry's colliding blocker. The rejoin needs it as well as CollisionGroups.clear. ai.collision.apart no longer keeps blockers apart from enemies or from blockers (D-281).
  - EnemyService's endedPayload builds RushEnded as Types.RushEndedPayload, and Types.RushEndedReason is the wire's reason union (D-282).
- **Camera:**
  - CharacterController.step calls CameraController.lockMove right after reading Humanoid.MoveDirection, and writes a turned stick back with Humanoid:Move (D-284).
  - holdLock(seconds) holds for seconds + camera.lock.riseHoldSeconds with the framed point frozen (D-285).
  - The two-shot measures each shoulder's reach (reachLeft) and takes the open side once (CameraMath.takesOpenSide; D-286). A target that left the view raises the turn cap (turnCap, CameraMath.acrossView; D-287).
  - shake(tier, scale?) scales the tier's amplitude, and CameraMath.falloff(distance, full, radius) gives the scale. Replication.slamCue calls shake(tier, falloff(...)) and requires client/camera/CameraMath (D-288, D-296).
- **Telegraphs (D-289):**
  - Telegraphs keeps a ring of the last fx.telegraph.glintLeadSamples lateBy values. glintLead() is their minimum, capped by glintLeadMax. resetLatency() is for specs.
  - TelegraphShapes.timing(windUp, strike?, lead?) → (ends, glintFrom, glintUntil); fillTransparency(elapsed, windUp, intensity, ends?, glintFrom?, glintUntil?).
- **Dev capture (D-290):**
  - CaptureLogic.lockPress(stagedId, lockedId) → "Lock" | "Release" | "Key"; letGo(held, slotOf) → { action, slot? } in name order.
  - Capture.client routes LockOn presses through lockPress and stops a take through letGo, calling CharacterController.cancelArt before the key's End.
- **Animation:**
  - Locomotion: on the local rig (holdsCutAttacks true), an attack clip let go before its first HitWindowOpen, TrailOn or SmearOn is held (holdCutAttacks → Mixer.hold) and fades where it stood. Locomotion.attach (remote players) sets holdsCutAttacks false (D-294).
  - Flinch clips are impact frames: the hit pose is on key 0 and held to 0.04 s (D-294).
  - LocomotionState.heldShare(speed, input, walkSpeed): the walks play alone at walkSpeed when the move is held, and a run hands back over choreo locomotion.stride.heldRiseSeconds (D-292).
  - tools/gaitgen generates all 12 gait clips, Run and Sprint from sources/Run.luau and sources/Sprint.luau; GaitGen.DRIFTED is empty (D-291).
- **Validators (D-283):**
  - camera: close-shot and aim rules, footprintPart = RigBuilder.BLOCKER_NAME.
  - dev: capture cameras, shots, prompts, perform lists, hotkeys, ledge and ring geometry.
  - sfx: the shatter balance.
  - ai: haltLeadSeconds and snoutSlackStuds bounds.
- **Data tables:**
  - combat.luau: aim.assistConeDegrees 80, besideHitRadius, besideFollowStep, besideMaxSubdivisions, contact.standOff.wallGapStuds, hitStopShaveFrames 0.
  - ai.luau: movement.haltLeadSeconds, movement.snoutSlackStuds, archetypes.Charger runningFraction / blockedFraction / blockedSeconds, collision.apart.
  - camera.luau: lock riseHoldSeconds, wallBlockedFraction, wallGainFraction, catchUpDegreesPerSecond, catchUpMostDegrees, catchUpMargin, catchUpEase.
  - fx.luau: wallSlam.shakeFullRadius, telegraph.glintLeadMax and glintLeadSamples.
  - choreo.luau: sheath.movingTipShare, locomotion.stride.heldRiseSeconds.

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
| `choreo.luau` | animation tunables: blend times and the blend easing, smear scale, idle cycle, locomotion speeds and clip names, `locomotion.stride` (ground speeds, touchdowns, pacing bounds and check bars, D-054), the stop (`stopStepsSeconds`, `stopMinCycles`, `stopEndSpeed`, D-059), `locomotion.lean.upright` (D-058), `locomotion.stopHandOverCycles` (D-136), `locomotion.stride.blocked` (D-144), `stall.jumpSeconds` (D-132), `priority.Sheath` and the `sheath` table (clips, draw-cuts, predictSeconds, sheatheDelay, stopBlend, remoteDrawDelay) |
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
