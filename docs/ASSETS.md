# Assets

The asset pipeline (section 19 "Asset pipeline"), the license ledger, and how `tools/assets.luau` keeps the registry
honest. Every asset the game loads is named in `src/shared/data/assets.luau` (meshes, textures, fonts, animations) or
`src/shared/data/sfx.luau` (sounds); gameplay code asks for an asset by name (`Assets.url("Shard")`,
`Sfx.get("impact", "Flesh")`), never by a raw id, so swapping an id is a one-line data change.

## Pipeline

1. **Author or source.** Meshes and rigs are authored in Blender (own work) or sourced CC0. Sounds come from Roblox's
   licensed sound library (D-080), own recordings or CC0 libraries. Fonts are Creator Store fonts or licensed TTFs.
   Every file gets a Skyspire name that passes the naming blocklist (`lune run tools/validate.luau`); the source
   franchise's names never appear in a file name, asset title or description (hard rule 1).
2. **Upload.** The user uploads through Studio (**View > Asset Manager > Bulk Import**) or the Open Cloud assets API
   (`docs/STUDIO_TASKS.md` E.16 to E.18). The repository never holds the binary. A licensed-library sound needs no
   upload: its id is used as it is.
3. **Register.** Paste the id into `assets.luau` (`id = 123456789, placeholder = false`) or `sfx.luau`
   (`id = "rbxassetid://123456789", placeholder = false`, plus the library `title`, `creator`, listed `length` and
   the trim, D-080). Keep the `note` accurate: it is the brief for whoever makes the next version.
4. **Check.** `lune run tools/assets.luau` prints every entry grouped by kind (sounds by family) with its id, state and
   the modules under `src/` that reference the name; it exits 1 on an entry with no id that is not flagged as a
   placeholder. `lune run tools/validate.luau` runs the `assets` and `sfx` validators (shape, Phase 0 names present).
5. **Record.** Add the row to the ledger below (source, license, attribution) and delete its row in
   `docs/PLACEHOLDERS.md`. Until then the code uses the part-built stand-in tagged `Placeholder` (D-009).

`tools/assets.luau --markdown` prints the registry as a table for pasting here.

## Ledger

State at 2026-10-22: 159 entries (13 assets, 146 sounds), 54 uploaded, 105 placeholders, 0 missing without a
placeholder flag. The 54 uploaded entries are sound slots on 50 licensed-library sounds; every asset in the table
below is still a placeholder.

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

146 entries in 13 families; `lune run tools/assets.luau` lists them. 54 slots are real and point at 50 sounds from
Roblox's licensed sound library (the Creator Store's audio, uploaded by the creators below); the other 92 are
`rbxassetid://0` placeholders (`docs/PLACEHOLDERS.md`). These sounds are licensed through Roblox for use in Roblox
experiences only: never download them or use them outside Roblox. Each pick's title and creator are logged here (and
in each `sfx.luau` entry) as its credit line, so it can be found again and listed in the credits panel when that
exists. The sfx validator refuses a real entry from any other creator than ProSoundEffects, APMOfficial and Roblox.

| Id | Slots | Title | Creator | Source | License | Attribution |
| --- | --- | --- | --- | --- | --- | --- |
| 9119383684 | `ambience.Plains` | Sonoma Morning Birds California Chirping 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Sonoma Morning Birds California Chirping 2 (SFX)" |
| 9113286782 | `ambience.RimWind` | Barstow Wind Light Blustery Low Howl 1 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Barstow Wind Light Blustery Low Howl 1 (SFX)" |
| 9119833793 | `artChime.TrailCyanWhite` | Synth Sparkle Tone High Pitch Tone Burst 4 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Synth Sparkle Tone High Pitch Tone Burst 4 (SFX)" |
| 9113988191 | `enemy.BruteDeath`, `enemy.BruteStagger`, `enemy.BruteStrike` | Creature Vocal Pterodactyl Death Shriek 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Creature Vocal Pterodactyl Death Shriek 2 (SFX)" |
| 9114624343 | `enemy.BruteRoar` | Goblin Growl 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Goblin Growl 2 (SFX)" |
| 9114624510 | `enemy.BruteWindUp` | Goblin Growl 4 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Goblin Growl 4 (SFX)" |
| 9118314102 | `enemy.ChargerDeath`, `enemy.ChargerStagger` | Robot Screams Pig Squeals 52 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Robot Screams Pig Squeals 52 (SFX)" |
| 9113634896 | `enemy.ChargerSnort`, `enemy.ChargerStrike` | Bull Goblin Snorts 6 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Bull Goblin Snorts 6 (SFX)" |
| 9117369876 | `enemy.ChargerWindUp` | Pig Squeals 1 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Pig Squeals 1 (SFX)" |
| 9120062559 | `footsteps.GrassLight` | Tip Toe Of Object Onto Grass 1 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Tip Toe Of Object Onto Grass 1 (SFX)" |
| 9113480915 | `footsteps.LandHard` | Body Fall Thud 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Body Fall Thud 2 (SFX)" |
| 9120879856 | `footsteps.LandSoft` | Wood Grab Muted Thuds 10 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Wood Grab Muted Thuds 10 (SFX)" |
| 9118250959 | `footsteps.StoneLight` | Robot Footsteps On Concrete 27 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Robot Footsteps On Concrete 27 (SFX)" |
| 9116673678 | `guard.Block` | Metal Impact Heavy Clunking Hits Scraping 1 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Metal Impact Heavy Clunking Hits Scraping 1 (SFX)" |
| 9120801590 | `guard.GuardBreak` | Wood Break 1 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Wood Break 1 (SFX)" |
| 9119075376 | `guard.GuardRaise` | Shield Impacts 13 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Shield Impacts 13 (SFX)" |
| 9116690113 | `guard.Parry` | Metal Impacts 3 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Metal Impacts 3 (SFX)" |
| 9119747479 | `guard.ParryRing` | Sword Long Metallic Ring Decay 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Sword Long Metallic Ring Decay 2 (SFX)" |
| 9120490110 | `hitStopTick.Final` | Wall Switch Turning On Off Clicking Thunks 4 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Wall Switch Turning On Off Clicking Thunks 4 (SFX)" |
| 9116896380 | `hitStopTick.Kill` | Metal Thunk 14 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Metal Thunk 14 (SFX)" |
| 9119717529 | `hitStopTick.Normal` | Switch Click On Or Off Toggle Button 1 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Switch Click On Or Off Toggle Button 1 (SFX)" |
| 9119072660 | `impact.Armor` | Shield Clang As Hit Metal Sword Hubcap 1 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Shield Clang As Hit Metal Sword Hubcap 1 (SFX)" |
| 9113502506 | `impact.Body` | Body Hits 8 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Body Hits 8 (SFX)" |
| 9118587701 | `impact.Construct` | Rock Drop On Concrete Drops Breaks 4 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Rock Drop On Concrete Drops Breaks 4 (SFX)" |
| 9120660382 | `impact.Crack` | Whip Cracks 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Whip Cracks 2 (SFX)" |
| 9119746592 | `impact.FinalHit` | Sword Hit 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Sword Hit 2 (SFX)" |
| 9116485156 | `impact.Flesh` | Meat Hack Fleshy Hits 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Meat Hack Fleshy Hits 2 (SFX)" |
| 9120113588 | `impact.Kill` | Tonal Impact 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Tonal Impact 2 (SFX)" |
| 9125362690 | `impact.Ring` | Anvil Hits Ringing Metal Clinks Some Muted 3 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Anvil Hits Ringing Metal Clinks Some Muted 3 (SFX)" |
| 9119747477 | `impact.RingTail` | Sword Long Metallic Ring Decay 1 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Sword Long Metallic Ring Decay 1 (SFX)" |
| 1837830050 | `impact.Sub` | BOOM-Sub Boom 01 | APMOfficial | Roblox licensed library | Roblox licensed library | APMOfficial, "BOOM-Sub Boom 01" |
| 1835344220 | `impact.SubDrop` | Super Predator Bass Drop | APMOfficial | Roblox licensed library | Roblox licensed library | APMOfficial, "Super Predator Bass Drop" |
| 9120769456 | `shatter.BossBoom` | Wind Whoosh Sonic Boom Low End Impact 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Wind Whoosh Sonic Boom Low End Impact 2 (SFX)" |
| 9114590265 | `shatter.BossCrack` | Glass Break 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Glass Break 2 (SFX)" |
| 9125644310 | `shatter.Chime` | Magic Twirling Small High Pitch Spinning Chi (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Magic Twirling Small High Pitch Spinning Chi (SFX)" |
| 9114615010 | `shatter.Crack` | Glass Smashes 7 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Glass Smashes 7 (SFX)" |
| 9125484367 | `shatter.Slam` | Deep Hits Big Reverberant Booms Rumbling Tai (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Deep Hits Big Reverberant Booms Rumbling Tai (SFX)" |
| 9125673878 | `telegraph.GuardBreak` | Metallic Beeps Quick Tones Some Dual Bursts (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Metallic Beeps Quick Tones Some Dual Bursts (SFX)" |
| 9113399659 | `telegraph.Tick` | Beeps Short And Long Bursts 10 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Beeps Short And Long Bursts 10 (SFX)" |
| 9113086354 | `telegraph.Unblockable` | Alarm Buzzer 2 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Alarm Buzzer 2 (SFX)" |
| 1841124374 | `ui.LowHpHeartbeat` | Heartbeat Pulse | APMOfficial | Roblox licensed library | Roblox licensed library | APMOfficial, "Heartbeat Pulse" |
| 9116730789 | `ui.SwitchLand` | Metallic Beeps Quick Tones 5 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Metallic Beeps Quick Tones 5 (SFX)" |
| 15675037413 | `ui.SwitchPrompt` | Roblox_UI_Paper_Swipe | Roblox | Roblox licensed library | Roblox licensed library | Roblox, "Roblox_UI_Paper_Swipe" |
| 9126072698 | `ui.SystemLine` | Synth Sparkle Tone High Pitch Bell Tone Ding (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Synth Sparkle Tone High Pitch Bell Tone Ding (SFX)" |
| 9119750698 | `whoosh.Basic` | Sword Whip 104 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Sword Whip 104 (SFX)" |
| 9114890978 | `whoosh.Dodge` | Jump Swish 1 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Jump Swish 1 (SFX)" |
| 9126229280 | `whoosh.Large` | Whoosh By Fast Airy Swooshing Whipping Thuds (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Whoosh By Fast Airy Swooshing Whipping Thuds (SFX)" |
| 9119749044 | `whoosh.Medium` | Sword Swish 201 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Sword Swish 201 (SFX)" |
| 9118158252 | `whoosh.Riser` | Reversed Whoosh Backwards Hissing Burst 3 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Reversed Whoosh Backwards Hissing Burst 3 (SFX)" |
| 9119749145 | `whoosh.Small` | Sword Swish 102 (SFX) | ProSoundEffects | Roblox licensed library | Roblox licensed library | ProSoundEffects, "Sword Swish 102 (SFX)" |

Music stems do not exist yet; they will be commissioned or CC-BY (credit here and on the store page).

## License rules

- **Allowed without a row here:** own work.
- **Allowed with a row:** sounds from Roblox's licensed library by ProSoundEffects, APMOfficial or Roblox (D-080; in
  Roblox experiences only), CC0 (no attribution required, still logged so the source can be re-downloaded), CC-BY and
  CC-BY-SA (attribution text in this file and in the game's credits panel when it exists), fonts with a commercial
  license covering games.
- **Not allowed:** anything with a non-commercial or no-derivatives clause, anything ripped from another game or
  show, and any asset whose name, look or sound identifies the source franchise (hard rule 1).

## Naming

Asset names in the registry are PascalCase Skyspire names (`TrialistSword`, not `starter_sword`). Sound families are
camelCase and the entries inside them PascalCase (`impact.Flesh`, `hitStopTick.Kill`; D-036). The naming validator
scans this file too.
