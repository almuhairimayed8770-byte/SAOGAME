# Placeholders

Every stand-in asset in the build, with its replacement plan (section 1 quality bar: "zero placeholder art in a
phase-gated build unless it is listed here"; section 21 gate line 8). Regenerate the asset part of this list with
`lune run tools/assets.luau` (`--markdown` prints a table); the registry is `src/shared/data/assets.luau` and the
sounds are `src/shared/data/sfx.luau`. An entry leaves this file when its id is pasted into the registry and its
`placeholder` flag is set to `false`.

Stand-ins are built by code, tagged with the `Placeholder` attribute (D-009) and carry the right size and Highlight,
so swapping in the real asset changes nothing but the look. Lines marked *(integrator: confirm)* describe a sibling
package's behaviour as read from the tree.

## Rigs and weapons

| Asset | Where used | Stand-in now | Replacement | Source / license | Phase |
| --- | --- | --- | --- | --- | --- |
| `PlayerAnimeRig` (Mesh) | the player character, every `player/*` clip, `RigBuilder` | default R15 avatar with anime proportions applied as Humanoid scale values from `rigs.luau` (BodyHeight 1.08, width 0.92, depth 0.95, head 1.06) | R15-compatible mesh rig keeping the 15 Motor6D names (section 10 "Rigs") | author in Blender; own work | Phase 2 (character creation) |
| `BoarRig` (Mesh) | Frenzy Boar (`enemies.luau`), `enemy/Boar/*` clips, ClipLab pedestal | part-built by `RigBuilder` from `rigs.luau` (torso, head, snout, tusks, four legs, tail; `PlaceholderBoar` blue) | skinned mesh rig with the same joint names and rest pose | author in Blender; own work | Phase 1 |
| `KoboldRig` (Mesh) | Kobold Axeman, `enemy/Kobold/*` clips, ClipLab pedestal | part-built by `RigBuilder` (`PlaceholderKobold` brown), big hands, a `Weapon` part on the right arm | mesh rig, same joints | author in Blender; own work | Phase 1 |
| `TrialistSword` (Mesh) | starter weapon (`weapons.luau`, `playground.luau` loadout, `loot.luau`) | blade-shaped part from `WeaponBuilder` / `weaponModels.luau` with `TrailStart` / `TrailEnd` attachments; the ClipLab builds its own fallback blade when WeaponBuilder is absent | sword mesh; blade length must match `weapons.luau` reach | author in Blender or CC0 (Kenney / Poly Haven) | Phase 1 |

## FX textures and meshes

| Asset | Where used | Stand-in now | Replacement | Source / license | Phase |
| --- | --- | --- | --- | --- | --- |
| `TrailGradient` (Texture) | weapon Trails (`fx.luau`, `fx/Trails.luau`) | Trail with no texture (flat color, LightEmission 1) | soft white gradient, alpha fading to the tail | author (2D); own work | Phase 1 |
| `Shard` (Mesh) | the shatter pool (`fx/Shatter.luau`) | WedgeParts, Neon, `ShardBlue` | low-poly wedge shard mesh | author in Blender | Phase 1 |
| `TelegraphLine`, `TelegraphCone`, `TelegraphCircle` (Texture) | enemy telegraphs (`fx.luau`, `fx/Telegraphs.luau`) | flat Neon parts in the telegraph shapes *(integrator: confirm)* | ground decals with soft edges | author (2D) | Phase 1 |
| `HexTile` (Texture) | the red sky and Mirror Shields (section 11) | not used in Phase 0 | hexagonal panel tile | author (2D) | Phase 1 (Mirror Shield) |
| `CloudBillboard` (Texture) | the cloud ring below the rim (`PlaygroundBuilder`) | untextured billboard parts *(integrator: confirm)* | soft cloud sprite | author (2D) or CC0 photo | Phase 3 (Floor 1) |

## Fonts

| Asset | Where used | Stand-in now | Replacement | Source / license | Phase |
| --- | --- | --- | --- | --- | --- |
| `SystemFont` (Font) | every system text (`ui.luau`, `El.font("system")`) | `GothamSSm` (Roblox built-in) | rounded geometric sans uploaded by the user | Roblox Creator Store font with a commercial license, or a licensed TTF | Phase 2 (diegetic menu) |
| `SerifFont` (Font) | item and lore text (`El.font("lore")`) | `Garamond` (Roblox built-in) | narrow serif | Creator Store / licensed TTF | Phase 2 |

## Sounds and music

All 137 entries in `sfx.luau` (13 families: artChime, whoosh, impact, hitStopTick, guard, shatter, footsteps,
telegraph, enemy, ui, voice, ambience, smith / gate loops) point at `rbxassetid://0` with `placeholder = true`; the
`SfxPool` skips a placeholder id, so the Phase 0 build is silent *(integrator: confirm)*. `lune run tools/assets.luau`
lists every one with the module that references it.

| Family | Replacement | Source / license | Phase |
| --- | --- | --- | --- |
| artChime (one per trail color), whoosh, impact, hitStopTick, guard, shatter | short designed hits and ticks, section 15 mix rules | freesound.org CC0 picks, or own recordings | Phase 1 |
| footsteps, telegraph, enemy vocalizations | per-material steps, the three telegraph tones, boar / kobold calls | CC0 or own | Phase 1 |
| ui, voice | the system line clicks, the announcement voice | own recordings | Phase 2 |
| ambience, smith and gate loops, torch | per-floor loops | CC0 (Poly Haven / freesound) | Phase 3 |
| Music stems (`MusicDirector` states) | no stems exist; the director runs with silence | commissioned or CC-BY with credit in `ASSETS.md` | Phase 7 |

## Dev-only stand-ins (never shipped)

| Thing | Where | Note |
| --- | --- | --- |
| ClipLab stage, pedestals, key and fill lights | `src/server/dev/ClipLab.server.luau`, `places/ClipLab.project.json` | review scene only; the place is dev-only (section 16 place layout) |
| ClipLab fallback rigs and the fallback blade | `ClipLab.server.luau` | used only when `RigBuilder` / `WeaponBuilder` are not in the build |
| Playground field, ceiling, rim, pillars | `places/Playground.project.json`, `PlaygroundBuilder` | dev place; Floor 1 replaces it in Phase 3 |
