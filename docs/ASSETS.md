# Assets

The asset pipeline (section 19 "Asset pipeline"), the license ledger, and how `tools/assets.luau` keeps the registry
honest. Every asset the game loads is named in `src/shared/data/assets.luau` (meshes, textures, fonts, animations) or
`src/shared/data/sfx.luau` (sounds); gameplay code asks for an asset by name (`Assets.url("Shard")`,
`Sfx.get("impact", "slashFlesh")`), never by a raw id, so swapping an id is a one-line data change.

## Pipeline

1. **Author or source.** Meshes and rigs are authored in Blender (own work) or sourced CC0. Sounds come from own
   recordings or CC0 libraries. Fonts are Creator Store fonts or licensed TTFs. Every file gets a Skyspire name that
   passes the naming blocklist (`lune run tools/validate.luau`); the source franchise's names never appear in a file
   name, asset title or description (hard rule 1).
2. **Upload.** The user uploads through Studio (**View > Asset Manager > Bulk Import**) or the Open Cloud assets API
   (`docs/STUDIO_TASKS.md` E.16 to E.18). The repository never holds the binary.
3. **Register.** Paste the id into `assets.luau` (`id = 123456789, placeholder = false`) or `sfx.luau`
   (`id = "rbxassetid://123456789", placeholder = false`). Keep the `note` accurate: it is the brief for whoever makes
   the next version.
4. **Check.** `lune run tools/assets.luau` prints every entry grouped by kind (sounds by family) with its id, state and
   the modules under `src/` that reference the name; it exits 1 on an entry with no id that is not flagged as a
   placeholder. `lune run tools/validate.luau` runs the `assets` and `sfx` validators (shape, Phase 0 names present).
5. **Record.** Add the row to the ledger below (source, license, attribution) and delete its row in
   `docs/PLACEHOLDERS.md`. Until then the code uses the part-built stand-in tagged `Placeholder` (D-009).

`tools/assets.luau --markdown` prints the registry as a table for pasting here.

## Ledger

State at 2026-10-17: 150 entries, 0 uploaded, 150 placeholders, 0 missing without a placeholder flag.

### Meshes, textures and fonts

| Kind | Name | Id | State | Referenced by | Source | License | Attribution |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Font | `SerifFont` | 0 | placeholder | shared/data/ui | to pick (Creator Store) | per font | fallback `Garamond` (Roblox) |
| Font | `SystemFont` | 0 | placeholder | shared/data/ui | to pick (Creator Store) | per font | fallback `GothamSSm` (Roblox) |
| Mesh | `BoarRig` | 0 | placeholder | RigBuilder (by rig id) | author in Blender | own work | - |
| Mesh | `KoboldRig` | 0 | placeholder | RigBuilder (by rig id) | author in Blender | own work | - |
| Mesh | `PlayerAnimeRig` | 0 | placeholder | the player character | author in Blender | own work | - |
| Mesh | `Shard` | 0 | placeholder | client/fx/Shatter | author in Blender | own work | - |
| Mesh | `TrialistSword` | 0 | placeholder | shared/data/loot, playground, weapons | author in Blender or CC0 | own work / CC0 | note the pack if CC0 |
| Texture | `CloudBillboard` | 0 | placeholder | server/world/PlaygroundBuilder | author (2D) or CC0 photo | own work / CC0 | - |
| Texture | `HexTile` | 0 | placeholder | - (Phase 1) | author (2D) | own work | - |
| Texture | `TelegraphCircle` | 0 | placeholder | client/fx/Telegraphs, shared/data/fx | author (2D) | own work | - |
| Texture | `TelegraphCone` | 0 | placeholder | shared/data/fx | author (2D) | own work | - |
| Texture | `TelegraphLine` | 0 | placeholder | shared/data/fx | author (2D) | own work | - |
| Texture | `TrailGradient` | 0 | placeholder | shared/data/fx | author (2D) | own work | - |

### Sounds

137 entries in 13 families, all `rbxassetid://0` placeholders; `lune run tools/assets.luau` lists them. Sources will be
own recordings or CC0 (freesound.org CC0 filter, Poly Haven, Kenney audio packs). A CC-BY pick is allowed only with
the attribution line written here before the id goes in. Music stems are commissioned or CC-BY (credit here and on the
store page).

## License rules

- **Allowed without a row here:** own work.
- **Allowed with a row:** CC0 (no attribution required, still logged so the source can be re-downloaded), CC-BY and
  CC-BY-SA (attribution text in this file and in the game's credits panel when it exists), fonts with a commercial
  license covering games.
- **Not allowed:** anything with a non-commercial or no-derivatives clause, anything ripped from another game or
  show, and any asset whose name, look or sound identifies the source franchise (hard rule 1).

## Naming

Asset names in the registry are PascalCase Skyspire names (`TrialistSword`, not `starter_sword`). Sound entries are
camelCase inside their family (`impact.slashFlesh`). The naming validator scans this file too.
