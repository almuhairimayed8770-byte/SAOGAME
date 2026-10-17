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
  choreo/Pose.luau             forward kinematics over Motor6Ds with offsets (server hit sweep)
  net/Remotes.luau             remote definitions: kind, direction, schema, rate limit
  net/Net.luau                 typed wrapper; server validates and rate-limits every payload
  util/                        Signal, Easing, Spring, Verlet, Rng, Check
src/server/
  Main.server.luau             starts services in order
  services/EntityService       entity registry, HP, Guard Gauge, states, death, regen, attributes
  services/CombatService       Art/basic/guard/dodge requests, timelines, hit sweep, damage, parry
  services/EnemyService        spawning, 20 Hz AI tick, threat, telegraphs, enemy strikes
  services/PlaygroundService   Playground spawn tables, player loadout, respawns
  services/AntiCheatService    speed/teleport/timing checks, Net abuse policy, shadow flag
  combat/DamageMath.luau       pure damage, crit, gauge and guard math (Lune-tested)
  combat/HitSweep.luau         spherecasts along the weapon path per damage window
  ai/Brain.luau                archetype base: perception, threat target, decision loop
  ai/Charger.luau  ai/Brute.luau
  world/RigBuilder.luau        part-built placeholder rigs from rigs.luau (Motor6Ds, attachments)
  world/WeaponBuilder.luau     placeholder weapons with WeaponGrip / TrailStart / TrailEnd
  world/PlaygroundBuilder.luau rim, pillars, clouds, kill volume from playground.luau
src/client/
  Main.client.luau             starts controllers in order
  controllers/InputController  ContextActionService bindings (PC, gamepad, mobile), Art hold/release
  controllers/CharacterController  locomotion state, root motion, dodge, requests to the server
  controllers/TargetController lock-on
  controllers/EntityTracker    client-side entity registry from CollectionService tags + attributes
  controllers/Replication      remote events -> Choreo, FX, HUD, camera
  choreo/Choreo.luau           per-rig animator: layers, clock, blend, root motion, events
  choreo/ClipLibrary.luau      loads clip modules by id
  choreo/Locomotion.luau       8-direction blend space, turn-in-place, skid, landing squash, foot IK
  camera/CameraController      spring follow, FOV, nudge, shake, lock-on framing, orbit presets
  fx/Trails, Smear, Shatter, Telegraphs, OutlineManager, SwitchRing, Digits, Quality
  ui/lib/                      el(), state cells
  ui/Hud, Nameplates, SystemLine
  audio/SfxPool, MusicDirector
  dev/Capture.client.luau      on-screen prompts for gate clips (Playground / ClipLab only)
  dev/ClipLab.client.luau      clip review scene at 0.25x / 0.5x / 1x with a frame counter
tests/                         Lune specs (*.spec.luau) and run-in-roblox smoke scripts (smoke/)
tools/validate.luau            runs tools/validators/*.luau
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

Tags (CollectionService): `SkyspireEntity` on every entity model, plus `SkyspirePlayer` or
`SkyspireEnemy`. Clients discover entities by tag and read attributes; remotes carry events only.

The model's `PrimaryPart` is the rig's root part (`HumanoidRootPart`). Enemy models have a
`Humanoid` for `MoveTo` only; its `Health` is pinned and ignored (D-012).

## Rigs, weapons and joints

- Rig definitions: `src/shared/data/rigs.luau`. Joint names are Motor6D names and are the keys in
  every clip. Player: the 15 R15 Motor6Ds (the root motor is `Root`, its live R15 name, D-016) plus
  `Weapon` (RightHand -> Weapon). Boar and Kobold: see the file. `RigBuilder.build(rigId, name)` returns a Model with Motor6Ds whose `C0`/`C1` come from
  the rest pose, with a `WeaponGrip` attachment on the grip part and `TrailStart`/`TrailEnd`
  attachments on the weapon part.
- Weapons: `WeaponBuilder.build(weaponDef)` returns a Model named `Weapon` with a `Handle`/blade
  part named `Weapon`, `TrailStart` at the guard and `TrailEnd` at the tip; the server attaches it to
  the player's `RightHand` with a Motor6D named `Weapon` (C0 from `rigs.luau`). The player's
  equipped weapon def id is the attribute `WeaponId` on the character.

## Clips

- Clip ids: players `player/<WeaponCategory>/<ClipName>` (for Arts the ClipName is the Art name
  without spaces: `player/OneHandedSword/SharpNail`); enemies `enemy/<RigId>/<ClipName>`.
- Files: `src/shared/clips/player/OneHandedSword/SharpNail.luau` returns one `Types.ClipDef`.
  `ClipLibrary.get(id)` maps the id to the module path.
- Required player clips (OneHandedSword, Phase 0): `Idle`, `IdleDrawn`, `WalkForward`,
  `WalkBack`, `WalkLeft`, `WalkRight`, `Run`, `Sprint`, `Jump`, `Fall`, `Land`, `TurnLeft`,
  `TurnRight`, `Skid`, `Guard`, `GuardHit`, `GuardBreak`, `Parry`, `DodgeForward`, `DodgeBack`,
  `DodgeLeft`, `DodgeRight`, `FlinchFront`, `FlinchBack`, `FlinchLeft`, `FlinchRight`, `Stagger`,
  `DeathFreeze`, `Basic1`, `Basic2`, `Basic3`, `Horizontal`, `Vertical`, `RisingArc`, `SharpNail`.
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
  any joint key (root keys may be Linear).
- Enemy attack clips: the wind-up pose must be held for the attack's `windUp` (the validator
  compares the clip's `Anticipation` beat to `enemies.luau`).

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
   requester, who ignores its own), and schedules the timeline from the clip: for each hit window it
   samples the clip at `hitSampleHz` through `ClipSampler` + `Pose` and runs `HitSweep` between
   samples; every hit goes through `DamageMath` and `EntityService.applyHit`, then `HitConfirmed` is
   fired to all clients. After the last hit the entity enters `PostMotion` for `postMotion` seconds
   (zero if the target was in `Break`), then `Idle`.
3. Enemy attacks: `EnemyService` picks an attack, fires `Telegraph` (with `windUp` and the ground
   shape) and `StateChanged`, holds the wind-up, then calls `CombatService.enemyStrike(enemyId,
   attackDef, origin, facing)`, which checks each player in the cone/line: dodge invulnerability,
   parry (guard pressed within `parryWindow` before the hit lands: the guard timestamp is the
   server's receipt time of `GuardRequest {held = true}`), guard cone and reduction, then damage.
   A parry staggers the enemy (`parryStagger`) and (Phase 1) opens a Switch window.
4. Death: `EntityService` sets `Dead`, fires `EntityDied {shatter}` to all; the client freezes the
   rig for `deathFreeze` with sound ducked, then plays `Shatter`.

Hit-stop, trails, camera, digits and highlight flashes are client reactions to `HitConfirmed`;
nothing about animation runs on the server except the pose sampling used by the sweep.

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
| `sfx.luau` | sound ids (placeholders) by name |
| `assets.luau` | asset ids by name; missing ids are reported |
| `choreo.luau` | animation tunables: blend times, smear scale, idle cycle, locomotion speeds |
| `camera.luau` | section 10 camera numbers |
| `fx.luau` | budgets, shard counts, trail lifetimes, telegraph sizes, quality tiers |
| `playground.luau` | the Playground: field radius, rim, pillars, clouds, spawn tables, loadout |
| `ai.luau` | every AI tunable: perception, archetype tuning, pathing, tick rates |
| `world.luau` | world builder tunables (folders, railing, pillars, clouds, kill volume) and the anti-cheat policy |
| `weaponModels.luau` | placeholder weapon geometry per category and the names the client relies on |
| `input.luau` | key, gamepad and touch bindings |
| `ui.luau` | HUD, nameplate and system-line layout numbers |
| `dev.luau` | dev tooling numbers: Capture panel, ClipLab, PoseEditor, pose server (D-028) |

Row convention (D-017): tables with many rows keep them under `Module.rows` with `byId(id)` and
`list()` functions; `list()` returns a clone. Validators read `rows` first and fall back to the
module table.

Each table has a validator in `tools/validators/`. The naming blocklist lives in
`tools/naming/blocklist.luau` (not shipped to clients, D-014) and `tools/validators/naming.luau`
scans every text file in the repo except `docs/GAME_SPEC.md` and the blocklist itself.

## Client reactions to remotes

| Remote | Client reaction |
| --- | --- |
| `ActionStarted` | `Choreo.play(rig, clipId, serverTime)` on that entity's rig; local player ignores its own |
| `Telegraph` | `Telegraphs.show(entity, kind, windUp, shape)`: weapon Highlight fill + ground decal |
| `HitConfirmed` | hit-stop on attacker and target rigs, `Digits`, Highlight flash, `Trails` flash on Switch, camera nudge/shake, HUD HP flash |
| `StateChanged` | stagger/break/guard-break clips, HUD status |
| `EntityDied` | freeze `deathFreeze`, duck audio, `Shatter.play(model, shatterKind)` (which plays the crack); the crack plays directly through `SfxPool` only when the rig is already gone |
| `ActionRejected` | cancel the predicted clip, no digit |
| `SystemLine` | centered system text with chime |
| `SwitchWindow` | `SwitchRing` on the enemy, SWITCH prompt (Phase 1 logic, Phase 0 visuals) |

Rig lifecycle: `EntityTracker.added` -> `Replication.watch(record)` registers the outline, attaches
the trail, routes the rig's clip events to the FX package and, for every rig the local
`CharacterController` does not own, drives locomotion with `Locomotion.attach(animator, model)`
(other players run the blend space, enemies their data Idle/Walk pair). Replication tells the local
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
