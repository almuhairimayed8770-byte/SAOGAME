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
| `TrialistScabbard` (Mesh) | the one-handed sword's back sheath (D-050), `WeaponBuilder` | one `PlaceholderWood` SmoothPlastic block (`Sheath/Scabbard`, 0.44 x 3.35 x 0.22 studs) welded to UpperTorso at `weaponModels.luau` `sheaths.OneHandedSword`; the mount sits behind the right shoulder blade with the scabbard 0.2 stud off the back (D-055) | modeled scabbard with a mouth fitting, chape and strap, sized to the sword mesh; keep the mount data | author in Blender or CC0 (Kenney / Poly Haven) | Phase 1 |

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

`sfx.luau` holds 146 entries in 13 families (ambience, artChime, enemy, footsteps, guard, hitStopTick, impact,
shatter, telegraph, ui, voice, whoosh, world). 54 slots are real: 50 picks from Roblox's licensed sound library
(D-080; credits in `ASSETS.md`) and 4 enemy vocals that reuse one of those picks (D-081). The other 92 point at
`rbxassetid://0` with `placeholder = true`; `SfxPool` runs them through the whole play path but never calls Play, so
they are silent. `lune run tools/assets.luau` lists every entry. Times are seconds into the asset at PlaybackSpeed 1:
the trim is `startAt` to `stopAt` of the listed length, the fade is `fadeOut`. "2D" means `spatial = false` (heard the
same everywhere); every other entry is 3D at its position.

### Licensed picks (50)

These are real assets, not stand-ins, but each is a first pick made without Studio at hand: the table is the record
of what was chosen and how it is cut, and "Picks to improve" below lists the weak ones.

| Slot | Id | Title | Creator | Trim of length (s) | Fade (s) | Volume | Pitch | Loop / 2D |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ambience.Plains` | 9119383684 | Sonoma Morning Birds California Chirping 2 (SFX) | ProSoundEffects | 2 to 125 of 127.61 | 0 | 0.36 | 1 | loop, 2D |
| `ambience.RimWind` | 9113286782 | Barstow Wind Light Blustery Low Howl 1 (SFX) | ProSoundEffects | 0.3 to 11.5 of 11.95 | 0 | 1 | 1 | loop, 2D |
| `artChime.TrailCyanWhite` | 9119833793 | Synth Sparkle Tone High Pitch Tone Burst 4 (SFX) | ProSoundEffects | 0.035 to 0.35 of 1.23 | 0.06 | 0.6 | 0.95 to 1.05 | - |
| `enemy.BruteDeath` | 9113988191 | Creature Vocal Pterodactyl Death Shriek 2 (SFX) | ProSoundEffects | 0.04 to 0.76 of 0.84 | 0.1 | 1 | 0.85 to 0.92 | - |
| `enemy.BruteRoar` | 9114624343 | Goblin Growl 2 (SFX) | ProSoundEffects | 0.2 to 1.8 of 3 | 0.45 | 0.7 | 0.85 to 1 | - |
| `enemy.BruteWindUp` | 9114624510 | Goblin Growl 4 (SFX) | ProSoundEffects | 0.25 to 1.55 of 1.75 | 0.1 | 0.55 | 0.95 to 1.05 | - |
| `enemy.ChargerDeath` | 9118314102 | Robot Screams Pig Squeals 52 (SFX) | ProSoundEffects | 0.58 to 1.05 of 1.99 | 0.12 | 0.65 | 0.95 to 1.05 | - |
| `enemy.ChargerSnort` | 9113634896 | Bull Goblin Snorts 6 (SFX) | ProSoundEffects | 0.04 to 0.36 of 0.39 | 0.04 | 1 | 0.9 to 1.1 | - |
| `enemy.ChargerWindUp` | 9117369876 | Pig Squeals 1 (SFX) | ProSoundEffects | 0.2 to 0.85 of 2.54 | 0.2 | 0.75 | 0.9 to 1.1 | - |
| `footsteps.GrassLight` | 9120062559 | Tip Toe Of Object Onto Grass 1 (SFX) | ProSoundEffects | 0 to 0.3 of 0.8 | 0.1 | 1 | 0.92 to 1.08 | - |
| `footsteps.LandHard` | 9113480915 | Body Fall Thud 2 (SFX) | ProSoundEffects | 0.07 to 0.24 of 1.08 | 0.06 | 0.45 | 0.9 to 1 | - |
| `footsteps.LandSoft` | 9120879856 | Wood Grab Muted Thuds 10 (SFX) | ProSoundEffects | 0 to 0.15 of 2.31 | 0.06 | 1 | 0.95 to 1.05 | - |
| `footsteps.StoneLight` | 9118250959 | Robot Footsteps On Concrete 27 (SFX) | ProSoundEffects | 0 to 0.18 of 0.84 | 0.05 | 0.14 | 0.92 to 1.08 | - |
| `guard.Block` | 9116673678 | Metal Impact Heavy Clunking Hits Scraping 1 (SFX) | ProSoundEffects | 0.02 to 0.5 of 1.46 | 0.15 | 0.2 | 0.95 to 1.05 | - |
| `guard.GuardBreak` | 9120801590 | Wood Break 1 (SFX) | ProSoundEffects | 0.45 to 0.8 of 1.48 | 0.12 | 0.5 | 0.95 to 1 | - |
| `guard.GuardRaise` | 9119075376 | Shield Impacts 13 (SFX) | ProSoundEffects | 0.27 to 0.58 of 2.34 | 0.12 | 0.14 | 0.95 to 1.05 | - |
| `guard.Parry` | 9116690113 | Metal Impacts 3 (SFX) | ProSoundEffects | 0.39 to 0.82 of 3.39 | 0.12 | 1 | 0.98 to 1.02 | - |
| `guard.ParryRing` | 9119747479 | Sword Long Metallic Ring Decay 2 (SFX) | ProSoundEffects | 0.3 to 2.8 of 18.21 | 1.5 | 0.45 | 0.98 to 1.02 | - |
| `hitStopTick.Final` | 9120490110 | Wall Switch Turning On Off Clicking Thunks 4 (SFX) | ProSoundEffects | 0.05 to 0.22 of 0.43 | 0.05 | 0.74 | 1 | 2D |
| `hitStopTick.Kill` | 9116896380 | Metal Thunk 14 (SFX) | ProSoundEffects | 0 to 0.12 of 0.83 | 0.02 | 1 | 1 | 2D |
| `hitStopTick.Normal` | 9119717529 | Switch Click On Or Off Toggle Button 1 (SFX) | ProSoundEffects | 0 to 0.08 of 0.23 | 0.02 | 0.2 | 1 | 2D |
| `impact.Armor` | 9119072660 | Shield Clang As Hit Metal Sword Hubcap 1 (SFX) | ProSoundEffects | 0 to 0.3 of 0.74 | 0.05 | 0.28 | 0.95 to 1.05 | - |
| `impact.Body` | 9113502506 | Body Hits 8 (SFX) | ProSoundEffects | 0 to 0.5 of 1.12 | 0.3 | 0.8 | 0.95 to 1.05 | - |
| `impact.Construct` | 9118587701 | Rock Drop On Concrete Drops Breaks 4 (SFX) | ProSoundEffects | 0.25 to 0.5 of 2.01 | 0.08 | 1 | 0.95 to 1.05 | - |
| `impact.Crack` | 9120660382 | Whip Cracks 2 (SFX) | ProSoundEffects | 0.39 to 0.62 of 1.18 | 0.05 | 0.65 | 0.96 to 1.04 | - |
| `impact.FinalHit` | 9119746592 | Sword Hit 2 (SFX) | ProSoundEffects | 0.17 to 0.36 of 1.19 | 0.05 | 0.4 | 0.95 to 1 | - |
| `impact.Flesh` | 9116485156 | Meat Hack Fleshy Hits 2 (SFX) | ProSoundEffects | 0.27 to 0.72 of 1.37 | 0.15 | 0.6 | 0.95 to 1.05 | - |
| `impact.Kill` | 9120113588 | Tonal Impact 2 (SFX) | ProSoundEffects | 0.1 to 0.75 of 2.71 | 0.4 | 1 | 0.95 to 1 | - |
| `impact.Ring` | 9125362690 | Anvil Hits Ringing Metal Clinks Some Muted 3 (SFX) | ProSoundEffects | 0 to 0.27 of 1.09 | 0.05 | 0.65 | 0.98 to 1.02 | - |
| `impact.RingTail` | 9119747477 | Sword Long Metallic Ring Decay 1 (SFX) | ProSoundEffects | 0.25 to 2.5 of 18.4 | 1.4 | 0.38 | 0.98 to 1.02 | - |
| `impact.Sub` | 1837830050 | BOOM-Sub Boom 01 | APMOfficial | 0.04 to 0.85 of 4.32 | 0.55 | 0.7 | 0.97 to 1.02 | - |
| `impact.SubDrop` | 1835344220 | Super Predator Bass Drop | APMOfficial | 0.22 to 2.2 of 2.44 | 0.7 | 0.55 | 1 | - |
| `shatter.BossBoom` | 9120769456 | Wind Whoosh Sonic Boom Low End Impact 2 (SFX) | ProSoundEffects | 0.985 to 2 of 8.96 | 0.4 | 0.5 | 1 | 2D |
| `shatter.BossCrack` | 9114590265 | Glass Break 2 (SFX) | ProSoundEffects | 0.57 to 2.8 of 5.02 | 1 | 1 | 0.7 to 0.75 | - |
| `shatter.Chime` | 9125644310 | Magic Twirling Small High Pitch Spinning Chi (SFX) | ProSoundEffects | 0.18 to 1.25 of 1.9 | 0.3 | 0.7 | 1 | - |
| `shatter.Crack` | 9114615010 | Glass Smashes 7 (SFX) | ProSoundEffects | 0.3 to 0.64 of 2.06 | 0.1 | 1 | 0.97 to 1.03 | - |
| `shatter.Slam` | 9125484367 | Deep Hits Big Reverberant Booms Rumbling Tai (SFX) | ProSoundEffects | 0.07 to 1.2 of 4.44 | 0.7 | 0.9 | 0.97 to 1 | - |
| `telegraph.GuardBreak` | 9125673878 | Metallic Beeps Quick Tones Some Dual Bursts (SFX) | ProSoundEffects | 0 to 0.45 of 1.09 | 0.08 | 0.6 | 0.98 to 1.02 | - |
| `telegraph.Tick` | 9113399659 | Beeps Short And Long Bursts 10 (SFX) | ProSoundEffects | 0.085 to 0.32 of 1.4 | 0.1 | 0.55 | 0.98 to 1.02 | - |
| `telegraph.Unblockable` | 9113086354 | Alarm Buzzer 2 (SFX) | ProSoundEffects | 0.36 to 0.95 of 2.23 | 0.15 | 0.75 | 0.98 to 1.02 | - |
| `ui.LowHpHeartbeat` | 1841124374 | Heartbeat Pulse | APMOfficial | 0.18 to 1.12 of 29.21 | 0 | 0.7 | 1 | loop, 2D |
| `ui.SwitchLand` | 9116730789 | Metallic Beeps Quick Tones 5 (SFX) | ProSoundEffects | 0.12 to 0.45 of 1.09 | 0.1 | 0.3 | 1 | - |
| `ui.SwitchPrompt` | 15675037413 | Roblox_UI_Paper_Swipe | Roblox | 0.05 to 0.34 of 0.62 | 0.06 | 0.5 | 1 | 2D |
| `ui.SystemLine` | 9126072698 | Synth Sparkle Tone High Pitch Bell Tone Ding (SFX) | ProSoundEffects | 0.29 to 1.25 of 2.34 | 0.3 | 0.65 | 1 | 2D |
| `whoosh.Basic` | 9119750698 | Sword Whip 104 (SFX) | ProSoundEffects | 1.03 to 1.75 of 3.08 | 0.3 | 0.8 | 0.95 to 1.1 | - |
| `whoosh.Dodge` | 9114890978 | Jump Swish 1 (SFX) | ProSoundEffects | 0.2 to 0.58 of 0.91 | 0.08 | 0.5 | 0.95 to 1.08 | - |
| `whoosh.Large` | 9126229280 | Whoosh By Fast Airy Swooshing Whipping Thuds (SFX) | ProSoundEffects | 0.09 to 0.53 of 1.45 | 0.08 | 0.36 | 0.85 to 1 | - |
| `whoosh.Medium` | 9119749044 | Sword Swish 201 (SFX) | ProSoundEffects | 0.34 to 0.55 of 0.9 | 0.06 | 0.32 | 0.95 to 1.05 | - |
| `whoosh.Riser` | 9118158252 | Reversed Whoosh Backwards Hissing Burst 3 (SFX) | ProSoundEffects | 0.15 to 0.46 of 1.5 | 0 | 0.7 | 0.98 to 1.02 | - |
| `whoosh.Small` | 9119749145 | Sword Swish 102 (SFX) | ProSoundEffects | 0 to 0.32 of 0.96 | 0.06 | 0.35 | 0.95 to 1.1 | - |

### Reuses (4)

Each keeps its source's id, trim and title, and its note says "reuses <slot> until its own sound is picked". The
sfx validator holds every pair on one asset at least `sfx.limits.sharedAssetSemitones` (1 semitone) apart.

| Slot | Reuses | Volume | Pitch | Played by |
| --- | --- | --- | --- | --- |
| `enemy.ChargerStrike` | `enemy.ChargerSnort` (9113634896, 0.04 to 0.36) | 1 | 0.74 to 0.84 | Voice event at 0.6 s in `enemy/Boar/Charge` (the charge launch) |
| `enemy.ChargerStagger` | `enemy.ChargerDeath` (9118314102, 0.58 to 1.05) | 0.45 | 1.12 to 1.22 | Voice events in `enemy/Boar/Stagger` (0.05 s) and `Break` (0.08 s) |
| `enemy.BruteStrike` | `enemy.BruteDeath` (9113988191, 0.04 to 0.76) | 0.75 | 0.98 to 1.04 | Voice event at 1.3 s in `enemy/Kobold/Overhead` (the strike frame) |
| `enemy.BruteStagger` | `enemy.BruteDeath` (9113988191, 0.04 to 0.76) | 0.6 | 1.11 to 1.19 | Voice events in `enemy/Kobold/Stagger` (0.05 s) and `Break` (0.08 s) |

### Real but not played yet (5)

`tests/data/sfx.spec.luau` (`UNPLAYED`) pins this list; a slot leaves it when something plays it.

| Slot | Why nothing plays it |
| --- | --- |
| `impact.Armor`, `impact.Construct` | no in-scope enemy has an armored or construct surface; a hit cue plays `impact.Flesh` (a cue-level material slot is open) |
| `shatter.BossCrack`, `shatter.BossBoom` | Phase 0 has no boss to play the BossShatter cue |
| `telegraph.Tick` | every in-scope attack telegraphs Unblockable (Frenzy Boar) or GuardBreak (Kobold Axeman); it is also the one real one-shot not preloaded |

### Still silent (92)

| Family | Slots | Why silent | Replacement | Source / license | Phase |
| --- | --- | --- | --- | --- | --- |
| ambience (12) | Canyon, Cave, Coast, Forest, Jungle, Labyrinth, Marsh, Ruin, Savanna, Snow, Twilight, Volcanic | beds for floors past the Phase 0 slice; only the rim wind and the Plains birds play | one loop per biome, 60 s or more, no music | Roblox licensed library, CC0 or own | Phase 3 on |
| artChime (11) | TrailAmber, TrailCrimson, TrailIvory, TrailJade, TrailOrange, TrailPaleGold, TrailRose, TrailSilverBlue, TrailViolet, TrailWhite, TwinFang | Phase 0 has only the cyan-white trail; the other chimes come with their weapons | a chime per trail color, pitched down by weapon weight; TwinFang a two-note chime | as above | Phase 1 |
| enemy (29) | WindUp, Strike, Stagger and Death for CasterBeast, Guard, Lancer, Skirmisher, Stalker, Swarm and WardenConstruct; SwarmHiss | archetypes outside the slice (only Charger and Brute are in it) | vocals per archetype | as above | Phase 1 on |
| footsteps (10) | GravelLight, SnowLight, WaterLight, WoodLight; the six Armored steps | no Playground surface maps to the four Light ones; nothing writes `Armored` yet, so the Armored weight is never chosen (D-089) | 4 to 6 single-contact takes per surface and weight | as above | Phase 1 |
| guard (1) | MirrorReflect | no Mirror Shield in Phase 0; `preloadNames()` lists it through the guard family and `preload()` skips it | a Mirror Shield sending a hit back | as above | Phase 1 |
| shatter (2) | TeleportRise, TeleportArrive | the Teleport Gate comes later | the shatter reversed for the Gate, and the arrival | as above | Phase 3 |
| ui (14) | BossBarCrack, BossBarFill, Crowns, DropCommon, DropUncommon, DropRare, DropEpic, DropLegendary, Equip, LevelUp, MenuOpen, MenuClose, Pickup, SystemLineWarded | boss bars, loot and menus come later; SystemLineWarded is left out of coverage on purpose | system clicks and chimes | as above | Phase 1 to 2 |
| voice (5) | Architect, Countdown, Death, FloorClear, RareRoll | system-voice stubs | the announcement voice (TTS stub until then) | own recordings | Phase 2 |
| world (8) | BossDoors, FishingReel, FishingSplash, GateHum, ShardUse, SmithCrackle, SmithHammer, TorchFlare | world props from later phases | loops and one-shots per prop | Roblox licensed library, CC0 or own | Phase 3 on |
| Music stems (`MusicDirector` states) | - | no stems exist; the director runs with silence | stems per state | commissioned or CC-BY with credit in `ASSETS.md` | Phase 7 |

### Picks to improve

Each is a first pick that passed the validators but not yet an ear in Studio; the STUDIO_TASKS item that checks it is
named where there is one.

1. `impact.Body`: Body Hits 8 is a clean punch, not distorted. Search "distorted impact", "designed punch hit",
   "saturated hit layer" (under 0.5 s, mostly mid, peak 200 or more).
2. `impact.Crack`: Whip Cracks 2 has little low end and holds near its peak for about 100 ms, so it may read as a
   double crack. Search "designed impact transient", "snap hit full range" (attack under 20 ms, one spike).
3. `impact.Kill`: Tonal Impact 2 still carries much low end (about 37% of its energy) under a kill whose contour cuts
   the bass. Search "cinematic metal hit heavy", "designed sword impact" (instant attack, under 25% low, 0.3 to 0.6 s).
4. `whoosh.Riser`: the longest usable reverse swell found is 0.31 s, against the 1 to 2 s an ultimate or a boss wants.
   Search "reverse swell", "reverse cymbal short", "suck back riser" (0.5 to 1.5 s, ending abruptly on its peak).
5. `hitStopTick.Kill`: Metal Thunk 14 peaks only 0.9 dB over the Final tick. Search "heavy click thunk", "freeze
   frame stinger" (150 to 200 ms, under 20% low). STUDIO_TASKS item 59.
6. `shatter.Slam`: Deep Hits dips and swells again at 0.20 to 0.25 s and may read as boom-boom. Audition Sonic Boom 1
   (rbxassetid://9120769331, from about 0.29 s) in its place (STUDIO_TASKS item 68).
7. `whoosh.Basic`: Sword Whip 104 peaks 0.165 s after Play at mid pitch (`peakAt` 1.199), longer than the basics' 0.1 s
   anticipation, so its event sits at clip time 0 and the swell still lands about 54 to 69 ms after the snap, for the
   local player and remote ones alike (D-082). It is also quiet (peak 93). Replace it with a take that peaks within
   0.1 s of Play (search "sword swing light", "blade swish thin": one swell, early attack), then set its `peakAt`.
8. `ui.LowHpHeartbeat`: confirm the 0.18 to 1.12 s loop holds no music; it is 97% low and may vanish on a phone
   speaker, and 64 bpm reads calm. The speed is a Studio call (D-083, STUDIO_TASKS item 64): a pitch range of 1.15 to
   1.3 races it, or pick a heartbeat with more mid.
9. `enemy.ChargerDeath`, `enemy.BruteDeath`: the timbre is unchecked (the kobold's is a pterodactyl shriek pitched
   down), and neither peaks in its first 0.15 s while the death silence starts 10 frames after the kill (D-073) and cuts
   both. Search "boar death squeal short", "goblin death short", "creature death grunt" (STUDIO_TASKS item 69).
10. `footsteps.GrassLight`, `footsteps.StoneLight`: their peaks are 25 and 21 (volume cannot lift them), and one take
    per surface machine-guns at run speed. Search 4 to 6 single-contact takes per surface, and check that Robot
    Footsteps On Concrete 27 does not sound mechanical (STUDIO_TASKS item 38).
11. `footsteps.LandSoft`: the first 0.15 s of a wood-grab thud. Search "jump land soft", "feet landing dirt" (peak 60
    or more).
12. `ambience.RimWind` (now played by Ambience, D-095): 70 to 81% low, so it clashes with `impact.Sub` and
    `impact.SubDrop`; its gusts repeat every 11.2 s, and the LoopRegion jumps back with no crossfade. Search "high
    altitude wind loop", "mountain wind steady airy" (some highs, 60 s or more). STUDIO_TASKS item 63 checks the seam.
13. `ambience.Plains` (now played as the island bed, D-095): check that its 2 to 125 s loop has a clean seam
    (STUDIO_TASKS item 63), then replace it with the biome's final bed.
14. `impact.RingTail`, `guard.ParryRing`: both rings dip and swell again after the strike; check that this does not
    read as a second hit (STUDIO_TASKS items 49 and 52).
15. `ui.SwitchLand`: from the same family as the guard-break telegraph, and both play at the enemy. Check by ear
    (STUDIO_TASKS item 71), or search "ui confirm shimmer", "success sparkle short".
16. `guard.GuardRaise`: Shield Impacts 13 is close to Block's spectrum and may read as a quiet block (STUDIO_TASKS item
    65). Search "armor shift short", "sword ready", "gear rattle short".
17. `impact.SubDrop`: whether Super Predator Bass Drop really dives in pitch is unchecked (STUDIO_TASKS item 67).
18. `impact.Construct`, `shatter.BossCrack`: both are capped by their peaks (Construct 1 dB under the other materials;
    the boss glass 7 dB under BossBoom). Search louder stone-hit and long glass-break takes before they are played.
19. The four reuses (ChargerStrike, ChargerStagger, BruteStrike, BruteStagger) want picks of their own; BruteStrike is
    now played and preloaded as the kobold's strike shout (STUDIO_TASKS item 70 checks that each reads as its own).
20. `ShatterHeavy` (the player's and an Elite's death) reuses the Shatter layers with `impact.SubDrop` at 0 dB instead
    of -3 (D-079). A distinct heavier layer can replace it if sound design wants one.
21. `peakAt` on `whoosh.Small`, `Medium`, `Large` and `Basic` (0.066, 0.401, 0.234, 1.199) was measured on the current
    takes. Measure it again whenever a take is swapped (STUDIO_TASKS item 66); `tests/data/sfx.spec.luau` then reports
    the clip events to re-time.

## Dev-only stand-ins (never shipped)

| Thing | Where | Note |
| --- | --- | --- |
| ClipLab stage, pedestals, key and fill lights | `src/server/dev/ClipLab.server.luau`, `places/ClipLab.project.json` | review scene only; the place is dev-only (section 16 place layout) |
| ClipLab fallback rigs and the fallback blade | `ClipLab.server.luau` | used only when `RigBuilder` / `WeaponBuilder` are not in the build |
| Playground field, ceiling, rim, pillars | `places/Playground.project.json`, `PlaygroundBuilder` | dev place; Floor 1 replaces it in Phase 3 |
