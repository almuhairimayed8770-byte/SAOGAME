# Skyspire — Claude Code Build Spec

Oct 17, 2026 · @Mayed Almheiri

## 0. How to use this spec

This is the complete, standing brief for Claude Code. Everything below is written to Claude Code in the second person. Put it where Claude Code reads it on every session:

1. Create the repo: `mkdir skyspire && cd skyspire && git init`.
2. Export this doc as Markdown. Save it as `docs/GAME_SPEC.md`. Create a 6-line `CLAUDE.md` at the repo root that says: `Read docs/GAME_SPEC.md in full before any work. It is the single source of truth. Track progress in docs/PROGRESS.md. Never ask design questions the spec already answers.` (If you run Claude Code from a claude.ai Project, paste the same Markdown into the Project's instructions too.)
3. Kickoff: run `claude`, then send: *"Read CLAUDE.md and docs/GAME\_SPEC.md completely. In one paragraph confirm the pillars, the solo gate, and the Phase 0 acceptance gate. Then start Phase 0."*
4. Work one phase at a time (section 20). At the end of each phase, Claude Code runs the gate checklist (section 21), records the result in `docs/PROGRESS.md`, and waits for your go-ahead before the next phase.
5. When you change a design decision, change it here first, re-export, and tell Claude Code to re-read the changed section.

Working title: **Skyspire**. Rename freely; every name in this doc is original on purpose (section 4) so the game can ship on Roblox without a DMCA takedown or moderation strike.

## 1. Role, mission and quality bar

You are the lead engineer, technical artist, animator, combat designer and producer of **Skyspire**: a 100-floor floating-tower action RPG on **Roblox**, written in strict-typed Luau, managed as a Rojo project in git, with Wally for packages and online co-op for 2 to 8 players per server. The reference feeling is Season 1 of a certain 2012 anime about a death-game MMO inside a floating castle. The benchmark to beat is Swordburst: fun loop, weak animation. Your job is that loop with anime-grade animation, a brutal difficulty curve, and a world that feels like a place, all inside what Roblox can render.

**Mission in one line:** every swing, menu, raid and death should feel like a frame of that anime, in a tower that is almost impossible to climb alone.

**The quality bar you hold yourself to**

- 60 fps on a mid-range PC and 30 fps on a 2020 phone with 8 players and 30 enemies on screen. Profile with the MicroProfiler before every phase gate; keep each floor under 60k parts loaded and under 1,500 draw calls.
- Every attack, player or enemy, has anticipation, a snap, a hold with hit-stop, and a recovery. No linear tweens on limbs, ever. No T-pose, A-pose or frozen rig visible at any time, including during loading, teleports or network hitches.
- Combat is readable at a glance: a new player can tell what will hit them 0.5 s before it lands, from the pose and the telegraph light alone.
- Zero placeholder art in a phase-gated build unless it is listed in `docs/PLACEHOLDERS.md` with a replacement plan.
- Every pure-logic module has Lune unit tests; every gameplay system has a `run-in-roblox` smoke script that spawns it and asserts it works. The server is authoritative for everything that affects HP, loot or position.

**How you work**

- Decide inside the spec; do not ask the user what the spec already answers. When the spec is silent, choose the option closest to the anime feel, write the choice into `docs/DECISIONS.md`, and continue.
- Build data-driven from day one: weapons, Arts, enemies, floors, loot and dialogue are Luau data tables in `src/shared/data/`, never hard-coded in gameplay scripts.
- Record 5-second clips of combat at every gate (ask the user to record in Studio with the capture script's on-screen prompts) and review them against section 10 before claiming a gate is met.
- Keep `docs/PROGRESS.md` current: phase, what shipped, what is stubbed, next three tasks.
- Commit small, commit often, with messages that say what changed in the game, not in the code.
- Anything that needs Roblox Studio by hand (uploading a mesh, publishing a place, setting a game setting) goes into `docs/STUDIO_TASKS.md` as a numbered checklist for the user, with exact menu paths.

## 2. Reference study: what Season 1 feels like to the watcher

This section is the taste. Every later section is a way of building it. When two implementation choices are both possible, pick the one that lands closer to a line in this section. Each bullet pairs the feeling with the design target.

**The login ritual.** The first episode spends real time on putting the headset on, the sensory calibration, the countdown, the word that starts the dive, and the rush of color as the world resolves around the player. *Target:* first launch is a 40-second sequence, never skipped on a new character: black screen, a system voice counting down sensory checks, a white-out, then the plaza of Floor 1 resolving in with sound fading up. Returning characters get a 4-second version.

**The castle in the sky.** The tower is a stack of stone discs, each a whole landscape, each ceiling the underside of the next floor about 100 m up, with sky and cloud visible past the rim. The scale is vertigo. *Target:* every floor has a reachable edge with a low railing or cliff, clouds below, the next floor's underside overhead rendered as a lit stone ceiling, and distant outer pillars. Looking up from any field should remind the player they are inside something.

**Floor 1 is bright and gentle before it is cruel.** Cobbled plaza, fountain, European-medieval stone, rolling green fields, cheap sunlight, blue-skinned boars that charge in straight lines. *Target:* Floor 1 is the warmest-lit floor in the game. Its first field is a tutorial without text: boars teach dodge, the first Art, and the HP bar.

**The announcement.** The sky goes red. Hexagonal system panels fill it from horizon to horizon. A giant hooded figure explains that logging out is gone and death here is death. A mirror item reveals everyone's real face. The crowd's silence is the loudest sound in the episode. *Target:* a scripted event at the end of the first play session (section 18) uses red hex panels, a robed original figure called the Architect, and the mirror beat. Permadeath is explained in-fiction, once, by the antagonist.

**The HP bar is a life.** Green, then yellow at half, then red at a quarter. Characters watch it the way people watch a pulse. Nobody goes into yellow casually. *Target:* HP never regenerates in combat. The bar colors are the only HUD element that is allowed to flash. Low HP tints the screen edge and slows the music.

**Combat is physical, not magical.** No mana, no spells. Strength and agility, a weapon, and Sword Skills: pre-choreographed techniques that start from a precise stance, glow in the weapon's color, carry the body through the motion automatically, and leave the user frozen for a beat afterward. The freeze is the price, and the anime makes it the moment of danger every time. *Target:* Blade Arts (section 7) with a visible start pose, a color trail, semi-automatic execution with root motion, and a post-motion lock that can get you killed. Basic swings are weak; Arts are how damage happens.

**Switch.** Two players alternate: one lands an Art, the enemy staggers, the partner steps in through the gap while the first recovers. The anime makes it feel like a dance between people who trust each other. *Target:* Switch is the central co-op mechanic and the main reason solo play fails (section 7b).

**Polygon death.** Monsters and players die the same way: the body freezes, cracks into blue-white glass-like shards, and the shards drift up and dissolve. It is beautiful and horrible. *Target:* one shatter effect for everything that dies, including the player, with a half-second of silence before it plays.

**The labyrinth and the raid.** Each floor's boss lives at the top of a dark stone tower at the floor's edge. Parties map it level by level over days. The boss door is a double door the size of a house. The boss room is lit by torches that flare when the boss stands. Floor bosses have several HP bars and change patterns as bars empty. The first floor's boss is a huge axe-wielding kobold with a guard of smaller kobolds, and it changes weapon in its last bar, which gets someone killed. The clearer of the last hit gets a unique drop. *Target:* a Labyrinth per floor, a boss chamber with a scripted entrance, 4 to 6 HP bars, phase changes on bar breaks, guard minions, and a Last Attack Bonus item.

**Players are the society.** Guilds, a large self-appointed army that taxes the lower floors, a blacksmith whose shop is a home, a merchant with a shop on a mid floor, a red guild of murderers, the stigma against beta testers, a stone monument where a line strikes through each dead player's name. *Target:* guilds with uniforms and emblems, a Roll of Names monument that updates live, player housing, player shops, a murderer flag that is visible from across a field.

**The quiet episodes.** Fishing with an old man by a lake. A cabin on a forested floor with a lake. A picnic on a hill. A feathered dragon pet that dies and is brought back. A child found in a forest who turns out to be part of the system. The anime earns its deaths with its calm. *Target:* every 5 floors has a settlement floor built for living, not fighting: cheap housing, fishing, cooking, weather, long sightlines, almost no enemies.

**The unique swordsman.** One player has a skill nobody else can get: two swords at once, and a 16-hit combo that he uses when a boss is about to wipe the raid. The watcher feels that this player is a different kind of thing. *Target:* the Dual Wielder origin (section 7b) is a 1% roll, visibly different in silhouette, and the only build that can climb alone.

**The final duel.** The strongest guild's leader uses a shield skill that never breaks. The reveal is that he is the Architect. The last fight is one on one, in a boss room, with the raid watching. *Target:* a late-game story beat where the Aegis origin is revealed to be system-granted, and a duel arena mode where spectators sit on the boss-room stairs.

**Visual language.** Cool cyan-white for anything the system does (menus, cursors, teleport light, shards). Warm orange for torches and inns. Deep saturated greens and blues outdoors. The hero wears a long black coat; the top guild wears white with red. Light trails are thick, saturated, and short-lived. Impacts spark. The camera sits low and close in duels, high and wide in raids. *Target:* section 11 color tokens and section 10 camera rules follow this exactly.

**Sound.** Strings and choir for raids, Celtic flute and piano for towns, a low synth drone in the labyrinth, a chime when an Art activates, a glass-like crack-and-ring when something shatters, and silence right before anything important. *Target:* section 15.

**Pacing of the climb.** Seventy-five floors took two in-world years and about fourteen episodes. Progress is slow, mid-floor players outnumber front-liners ten to one, and the front line is a small, tired, famous group. *Target:* floor clears are server-wide events, announced on every floor, with the clearing party's names on the Roll of Honor at the next floor's gate.

## 3. Original-IP rules and naming table

Skyspire copies a feeling, not a franchise. Use no names, logos, character designs, music, voice lines or text from the anime or the novels anywhere in the project, the store page, or the code comments. Roblox moderation and DMCA both act on names and likenesses; the feel is not protected, the names are. Use the table below everywhere, and add new rows to it before inventing a term.

| Anime concept | Skyspire term | Notes |
| --- | --- | --- |
| The floating castle | The Spire | The game world; the title |
| Town of Beginnings | Firstlight | Floor 1 hub town |
| Sword Skills | Blade Arts ("Arts") | Section 7 |
| Switch | Switch | Generic word; keep it |
| Col | Crowns | Currency |
| Teleport / healing / corridor crystals | Shards: Gate Shard, Mend Shard, Corridor Shard, Cleanse Shard | Section 7 |
| Dual Blades | Twin Fang (skill line); Dual Wielder (origin) | 1% roll, section 7b |
| Holy Sword | Aegis (origin) | 0.5% roll, story-locked reveal |
| Knights of the Blood Oath | The Ivory Vow | White and red uniform, top guild |
| The Army | The Bulwark Legion | Lower-floor faction, taxes and rules |
| Laughing Coffin | Hollow Grin | Red guild of murderers |
| Beta testers | Trialists | Stigmatized early players |
| Monument of Life | The Roll of Names | Live permadeath monument in Firstlight |
| Cardinal (system AI) | The Warden | Runs quests, balance, events |
| Game master figure | The Architect | Antagonist; in-game alias Castellan |
| Child AI | Lumi | Companion, section 18 |
| Feathered dragon pet | Plume (feathered wyrmling) | Beastbond origin pet |
| Black Swordsman's coat | Mantle of Last Light | Floor 1 Last Attack Bonus |
| Elucidator / Dark Repulser | Nightfall / Glacier Edge | Late-game twin swords |
| Lambent Light | Lucent Needle | Rapier line |
| Anneal Blade | Tempered Edge | Early 1H sword |
| Starburst Stream (16-hit) | Meteor Cascade | Twin Fang ultimate, tier 1 |
| The Eclipse (27-hit) | Umbral Reign | Twin Fang ultimate, tier 2 |
| Vorpal Strike | Lance Thrust | 1H sword heavy Art |
| Floor 1 kobold boss | Grolak, Kobold Warlord | Section 9 |
| Floor 74 demon boss | Stareblight Colossus | Section 9 |
| Floor 75 centipede boss | Ossuary Reaper | Section 9 |
| Floor 22 lake floor | Mirrorlake | Settlement floor |
| Immortal Object | Warded Object | System popup |

Original enemy, item, NPC and floor names must pass a check: no name from the source may appear as a substring. Add a Lune test (`tests/naming.spec.luau`) with a blocklist and run it in CI.

## 4. Design pillars

When two choices conflict, the higher pillar wins.

1. **Every swing is a frame of the anime.** Pose, timing, trail, impact and recovery are tuned to section 10 before anything else is tuned. A feature with ugly animation does not ship.
2. **The Spire kills you.** The game is balanced for a party of four. Solo is a boast, not a baseline, and is possible only for a Dual Wielder in that floor's Apex set (section 7b). Death is permanent in the main mode.
3. **The Spire is a place.** Floors are landscapes with weather, towns, homes and edges, not arenas. Players should be able to describe where they were when something happened.
4. **The 1% is real.** Rare rolls are permanent, server-visible, and never sold. A Dual Wielder walking through Firstlight should draw a crowd.
5. **Readable over spectacular.** Every telegraph is legible, every number honest, every death explainable. Spectacle is layered on top of readability, never instead of it.
6. **Earned power.** No pay-to-win. Robux buys cosmetics, private servers and housing decor only. Stats, Arts, gear and origins come from the climb.

## 5. The Spire: world structure and floors

The Spire is 100 floors. Floors 1 to 25 are hand-authored places; floors 26 to 100 are assembled at server start from biome kits by the Floor Generator, with hand-authored bosses on every fifth floor and on story floors. Launch is floors 1 to 10 complete; 11 to 25 follow in content phases; the generator ships with phase 6 (section 20).

**Anatomy of a floor (every floor, hand-built or generated)**

- A disc 2,000 to 4,000 studs across (Floor 1: 3,000), with a ceiling at 350 studs: the lit stone underside of the floor above. The rim is reachable everywhere: a railing in towns, cliffs in the wild, clouds below, outer pillars in the distance. Falling off the rim is death.
- **Main town** (safe zone): the Teleport Gate plaza, an inn, a smith, a general store, a tailor, a quest board, a Roll of Honor stone for that floor's clearing party, and 10 to 40 purchasable homes. Floor 1's town also holds the Roll of Names.
- **Two to four villages** with one vendor each and a side-quest chain.
- **Fields** in three threat bands: Verge (near town, tutorial-tier mobs), Reach (mid), and Blight (near the Labyrinth, elite packs with Mirror Shields).
- **Two or three mini-dungeons**: caves, ruins or crypts, 10 to 20 minutes for a party of four, with a mini-boss and a guaranteed Rare drop on first clear per character.
- **One field boss** that roams a fixed loop and respawns every 90 real minutes; its drops feed the Apex set (section 7b).
- **The Labyrinth**: a stone tower at the rim, 8 to 12 internal levels, no safe zones, respawning packs, traps, a map that fills in as parties explore, and a boss chamber at the top behind house-sized double doors. Stairs behind the boss chamber lead to the next floor and open only after the first clear.
- **Day and night**: one in-game day is 48 real minutes. Night raises spawn density 1.5x, adds Night-only variants, and has a 0.5% chance per night of a Blood Moon (section 9). Weather is per biome (rain, fog, snow, dust) and affects visibility and footing, never stats.

**Haven floors.** Every fifth floor (5, 10, 15, 20, 25...) is a Haven: a bigger town, cheaper homes, fishing, cooking, farms, long sightlines, sparse fields, and a harder boss that acts as a quarter-mark raid. Floor 22, Mirrorlake, is a non-fifth settlement floor with a forest, a lake, and cabins; it is the game's quiet place.

**Launch and content floors**

| Floor | Name | Biome and feel | Main town | Floor boss |
| --- | --- | --- | --- | --- |
| 1 | Firstlight Plains | Bright green plains, oak stands, cobbled roads | Firstlight | Grolak, Kobold Warlord |
| 2 | Thornmere | Reed marsh, boardwalks, dusk fog | Marrow | Mirefang Matriarch (giant wasp) |
| 3 | Emberwood | Autumn forest, red leaves, fallen logs | Duskwatch | Ashbark Treant |
| 4 | Saltwind Coast | Sea cliffs, gull rocks, a lighthouse | Gullhaven | Tidecaller Serpent |
| 5 | Vaelric Highlands (Haven) | Hills, terraced farms, wind | Vaelric | Iron Bulwark Golem |
| 6 | Hollowdeep | Cave floor, bioluminescent fungus, no sky | Lanternfall | Pale Crawler |
| 7 | Sunbreak Savanna | Dry grass, acacia, heat shimmer | Dunmoor | Khagan of Hooves (minotaur) |
| 8 | Frostvein | Snowfield, frozen river, pine | Greymantle | Rimeclaw Behemoth |
| 9 | Gloamwood | Twilight forest, fireflies, mist | Nightshade Crossing | Hexen Stag |
| 10 | Castellan's Reach (Haven) | Citadel floor, white walls, banners | Highwall | The Warden's Knight |
| 11 | Fenmoor Reaches | Peat bog, will-o-wisps | Sedge | Bogmother |
| 12 | Cinderspire Foothills | Volcanic rock, ash, lava seams | Kilnrest | Magmaw |
| 13 | Thundertop Mesas | Red mesas, canyons, storms | Rookery | Stormhorn Roc |
| 14 | Lantern Lake | Lakeside town, lantern festivals | Lantern | Drowned Choir |
| 15 | Aurelian Terraces (Haven) | Vineyards, gold evening light | Aurelia | Vintner's Colossus |
| 16 | Ironhollow Quarry | Open-pit mine, scaffolds, rust | Strake | The Overseer (clockwork) |
| 17 | Mistral Steppe | Windswept grass, nomad camps | Khoran | Windrider Warlord |
| 18 | Verdigris Ruins | Jungle over a drowned city | Tendril | Stone Idol of Verdigris |
| 19 | Hallowed Pines | Snowy cathedral forest, bells | Vespers | Bell Warden |
| 20 | Kingsmoor (Haven) | Royal moors, castles, tournament grounds | Kingsmoor | The Pale King |
| 21 | Blackreach Marsh | Dead trees, black water, Hollow Grin territory | Gallows Fen | Carrion Hydra |
| 22 | Mirrorlake | Forest, lake, cabins, the quiet floor | Mirrorlake | Lakewarden (optional, peaceful unless provoked) |
| 23 | Shalewind Gorge | Slot canyons, rope bridges, wind | Cleft | Gorgefang Wyrm |
| 24 | Oathfire Plateau | High plateau, braziers, ancient arena | Pyrehold | Oathbreaker Knight |
| 25 | Argent Crown (Haven) | Silver spires, the first quarter-mark | Argentis | The Silver Sovereign (the raid where the Legion breaks) |

**Floor Generator (26 to 100).** Twelve biome kits (plains, marsh, forest, coast, cave, savanna, snow, twilight, volcanic, canyon, jungle, ruin) each with a town prefab, three village prefabs, eight field chunks, two mini-dungeon layouts, a Labyrinth layout, and a creature roster. A floor is a seed plus a kit plus a difficulty tier. Every fifth floor and every story floor (55, 74, 75, 100) is hand-authored and overrides the generator. The generator must produce a floor in under 8 seconds on the server and never produce an unreachable Labyrinth; add a reachability test.

**World state.** The front line (highest cleared floor), each floor's first-clear party, the Roll of Names and the Roll of Honor are experience-wide: stored in a versioned DataStore, cached in MemoryStore, broadcast with MessagingService. A floor clear is announced on every server within 5 seconds.

## 6. Core combat

No mana, no spells, no cooldown bars. A weapon, two stats, Blade Arts, guard, Switch, and a post-motion lock that gets people killed. All numbers below are starting values in `src/shared/data/combat.luau`; tune them, never scatter them.

**Inputs (PC / gamepad / mobile all supported)**

- Basic attack: left click / R2 / tap. Three-hit chain per weapon, each hit about 30% of a tier-1 Art, mostly for finishing and for building the Guard Gauge a little.
- Art: hold Q (or the Art's quick slot) to enter the Art's **start pose**; the character auto-assumes the stance over 0.15 s, the blade glows in the Art's color, a chime plays, and releasing the key launches it. Holding past 1.0 s cancels (the glow fades). Different Arts share a key but need different pre-conditions (moving, standing, mid-air, after a parry) so the pose system picks the right one.
- Guard: hold right click / L2. Parry: tap guard inside the 150 ms before a hit lands.
- Dodge: space / B. A 0.25 s step with 100 ms of invulnerability and a 0.6 s cooldown. Weak against sweeps; positioning beats dodging.
- Switch call: Tab / L1 sends a SWITCH ping to the nearest party member (section 14). Target lock: F / R3. Interact: E / X. Quick-slot ring: hold R / D-pad.

**Blade Arts.** An Art is a pre-choreographed technique: start pose, activation, execution, post-motion.

1. *Start pose* (0.15 s): the body moves into the stance; visible to everyone.
2. *Activation*: trail color ignites on the blade, a chime, a 0.1 s hold. This is the tell. Enemies can hit you out of it.
3. *Execution*: root-motion animation, uncancelable, with one damage window per hit. The character moves with the Art (a thrust carries you 6 studs; a leaping Art 14 studs). Hit-stop on every connected hit: 3 frames (50 ms) normal, 6 frames on the final hit, 10 frames on a kill.
4. *Post-motion* (0.4 s for tier 1, up to 1.6 s for ultimates): frozen in the end pose, no guard, no dodge, no move. The only protection is a partner's Switch.

Damage per hit = weapon attack × Art multiplier × (1 + STR × 0.012) × crit (1.5x, chance from AGI) − target defense. Show the real number as a small floating digit that fades in 0.6 s; no damage inflation.

**Guard Gauge and Break.** Every enemy has a Guard Gauge beside its HP. Arts deal gauge damage; basic attacks deal a tenth of that. The gauge regenerates at 10% per second while the enemy is not being hit by Arts. At zero the enemy enters **Break** for 3 s: kneels, takes 2x damage, and Arts landed on it have zero post-motion. Elite and boss gauges are tuned so that one player's Art rate cannot outpace regen; two players Switching can; a Dual Wielder's Twin Fang Arts count as two Art hits and can (section 7b).

**Switch.** When player A's Art connects, a 0.8 s Switch window opens on that enemy. If partner B's Art lands inside it: B's Art gets +25% damage and +50% gauge damage, A's post-motion is cut to 0.2 s, and the enemy's current attack is interrupted. Chaining Switches builds **Tempo** (max 5 stacks, +4% damage per stack for the party, resets after 3 s without a Switch). A perfect parry also opens a Switch window. The Switch ping and the window are both drawn on the enemy (section 14) so it reads like the anime: one steps back, one steps in.

**Guard and parry.** Guard blocks a 120-degree cone for 70% damage reduction and drains the player's own Guard Gauge; an empty gauge means a 1.2 s guard-break stagger. A perfect parry costs nothing, deals no damage, staggers the enemy for 1.0 s, throws a spark burst with a metallic ring, and opens a Switch window. Shields widen the cone to 180 degrees and raise reduction to 85%.

**Enemy telegraphs.** Every enemy attack has a wind-up pose held for 0.4 to 1.2 s with a glowing edge (white for normal, red for unblockable, yellow for guard-breaking), then a strike with a visible arc. Unblockable attacks must be dodged or interrupted. Players should die to attacks they saw, never to attacks they did not.

**Status effects.** Bleed (damage over 8 s), Poison (slower, longer, blocks potions), Paralysis (3 s, cannot move or Art; the deadliest), Stun (1.5 s), Burn, Freeze (−40% speed). Cleanse Shards and a Haven-floor antidote recipe clear them.

**Consumables (quick-slot ring).** Potion: heals 30% over 10 s, useless in a burst. Mend Shard: instant full heal, rare (section 13). Gate Shard: teleport the user to any cleared town; blocked inside boss chambers and in Warded zones (a purple "Warded Zone" popup). Corridor Shard: opens a party portal to a town for 20 s. Cleanse Shard: clears all statuses.

**HP, defense and recovery.** HP never regenerates in combat (out of combat: 1% per second after 8 s). Defense is flat reduction from armor. Armor has weight; heavy sets cut AGI.

**Durability.** Weapons lose durability per hit; at zero the weapon shatters. Repair at any smith for Crowns. In the Labyrinth you carry a spare or you walk back.

**Threat.** Enemies attack whoever has the highest threat (damage dealt × 1.0, taunt × 3.0, healing others × 0.5). The Vanguard path has the only taunt. Without a taunt, the Switch rhythm decides who gets hit.

**PvP and the cursor.** Every player has a cursor over their head: green by default. Attacking a green player in the open world turns yours orange for 24 real hours. Killing one turns it red until a long redemption quest; red players are attacked by town guards and cannot enter safe zones. Duels are consensual: first strike, half HP, or total loss (total loss is a real death in Lucid mode and asks for confirmation twice).

**Death.** At 0 HP: 0.5 s of freeze and silence, then the shatter (section 11), then the system line "Your name has been struck from the Roll." In Lucid mode the character is deleted (section 7b). Party members see the shatter and hear the name read aloud by the system voice.

**Authority and feel.** The server owns HP, hits, positions and loot. Hit detection is a server-side capsule sweep along the weapon's path per damage window, with a 150 ms lag allowance. The client predicts animation, trails, hit-stop and camera instantly so the swing feels local; a rejected hit simply shows no number.

## 7. Difficulty, rare rolls, Paths and the solo gate

The Spire is balanced for four players who Switch well. One player at level with ordinary gear should lose to a Reach-band pack of four mobs about 80% of the time. Floor bosses are not soloable, by rule, with one exception that the whole game is built to make legendary: a Dual Wielder wearing that floor's full Apex set.

**Modes.** *Lucid* is the game: permanent death. On death the character is deleted, its name goes on the Roll of Names, and the account keeps only cosmetics, the Codex (bestiary, maps, recipes), 10% of carried Crowns into the estate bank, and one willed item chosen in advance (the Legacy slot). A new character re-rolls everything below. *Trial* is a training mode on separate servers: normal death with a 20% Crown loss, no floor-clear credit, no Roll of Honor, no Mythic rolls, and a visible "Trial" tag. Trial exists so Lucid can be merciless.

**Character creation rolls.** Three rolls at creation, permanent, shown on the character's profile and visible to other players. No re-rolls except the Mirror of Origins (below). Weights are data in `origins.luau`.

| Roll | Result | Chance | Effect and look |  |
| --- | --- | --- | --- | --- |
| Lineage | Lowlander | 16% | Vendor prices −5%; plain look |  |
| Lineage | Highborn | 16% | Defense +3%; tailored default clothes |  |
| Lineage | Woodling | 16% | Field move speed +5%; leaf-green eye tint |  |
| Lineage | Ironfolk | 16% | Durability loss −10%, smithing success +5%; broad build |  |
| Lineage | Driftkin | 16% | Fall damage −50%, faster climbing; wind-tousled hair |  |
| Lineage | Stormblood | 6% | AGI +8%; hair glows faint blue at night |  |
| Lineage | Nightveil | 6% | Damage +10% at night, −3% by day; black sclera |  |
| Lineage | Ashborn | 5% | Burn immune, STR +5%; ember freckles |  |
| Lineage | Starmarked | 2% | All stats +10%, one extra Art slot; constellation marks on skin |  |
| Lineage | Hollowkin | 1% | Max HP −50%, damage ×2; glowing cracks across the body |  |
| Origin | None | 92% | Standard swordsman |  |
| Origin | Ironhand | 3% | Guard Gauge +15%, parry window +50 ms |  |
| Origin | Beastbond | 2% | Can tame rare creatures as fighting pets (Plume first) |  |
| Origin | Flashdraw | 1.5% | Katana Arts skip the start pose; +30% post-motion |  |
| Origin | **Dual Wielder** | **1%** | Twin Fang skill line; two blades; the solo build |  |
| Origin | Aegis | 0.5% | Guard never breaks, parry window 250 ms, zero Art damage bonus; story reveal at floor 75 |  |
| Mark | Architect's Mark | 0.1% | Cosmetic glowing sigil on the back of the hand; a server-wide announcement |  |

A Dual Wielder or Aegis roll triggers a server-wide system line ("A Dual Wielder has entered the Spire") and a distinct silhouette: two crossed sheaths on the back, a different idle, a different run.

**The Dual Wielder.** Twin Fang Arts hit with both blades, count as two Art hits for Guard Gauge purposes (2.5x gauge damage versus a single wielder with the same gear), deal about 1.8x a single wielder's Art damage per second, and have no gap between combo stages because the second blade covers the first. Meteor Cascade (16 hits, 4.2 s, 1.6 s post-motion) unlocks at Twin Fang proficiency 500; Umbral Reign (27 hits, 7 s, 2.4 s post-motion) at 1000. The cost: no shield, a lighter armor cap, a 0.2 s activation hold on every Twin Fang Art (punishable), and doubled post-motion on a whiff. A Dual Wielder without Apex gear is a strong party member, not a soloist.

**Apex set.** Every floor defines one best-in-slot set in `apex.luau`: a weapon, four armor pieces and an accessory. Pieces come from that floor's Last Attack Bonus, the field boss, the mini-dungeon first-clear Rare, and a smith recipe needing an ingot from the Labyrinth's deepest level. Wearing all six grants **Apex** status: a faint white edge-light on the character and the only thing, together with Twin Fang, that turns off the solo gate on that floor. Apex is per floor; floor 6's set is ordinary gear on floor 9.

**The solo gate (the mechanics that make solo almost impossible).**

1. *Mirror Shield.* Every Blight-band elite, every mini-boss and every boss carries a Mirror Shield: a translucent hex barrier that breaks only when two Arts of different weapon categories land within 1 s (a Switch), or when a Twin Fang Art lands. Hitting it with anything else reflects 30% of the damage.
2. *Guard regen.* Elite and boss Guard Gauges regenerate faster than one player's Art rate can drain them; only a Switch chain or Twin Fang reaches Break.
3. *Lockstep attacks.* Bosses have attacks that must be interrupted by two players at once (twin pillars to strike, two tethers to cut, a charge that needs a parry on each flank). Unanswered, they wipe the room.
4. *Overwhelm.* If fewer than three players are in a boss chamber, the boss gains +40% attack speed and summons a guard pack every 20 s. Exception: a Dual Wielder with Apex status triggers **Duelist Protocol** instead: the boss sheds its minions, drops its Mirror Shield, and fights one on one with faster, fully readable patterns, torches dimming to a spotlight. It is still a 25% fight, and it is the best thing a server can watch.
5. *Paralysis and Poison* are common from floor 3 on. A paralyzed solo player dies; a paralyzed party member gets covered.

**Expected outcomes to tune toward (first-clear attempts, at-level gear)**

| Group | Floor boss success target |
| --- | --- |
| 1 player, any origin, no Apex | 0% (Overwhelm) |
| 1 Dual Wielder, no Apex | about 2% |
| 1 Dual Wielder with Apex (Duelist Protocol) | about 25% |
| 2 players | about 10% |
| 4 players, third attempt | about 40% |
| 8 players, coordinated | about 60% |

**Paths (the chosen part).** At level 10, at the Firstlight trainer, choose one of six Paths. A Path sets your starting Art slots, a signature mechanic, and the armor you can wear. Origins stack on top; a Dual Wielder can take any Path and keeps Twin Fang. One respec per ten floors at the Haven trainer for 20% of carried Crowns.

| Path | Weapons | Signature |
| --- | --- | --- |
| Vanguard | 1H sword or mace + shield | Taunt (3x threat for 8 s); Bulwark Stance (guard cone 360 degrees, cannot move) |
| Striker | 1H sword, katana | Momentum: each Art that lands cuts the next start pose by 50%, up to 3 stacks |
| Duelist | Rapier | Riposte: a perfect parry grants one free Art with no activation hold |
| Breaker | 2H sword, axe, spear | Shatter: +60% Guard Gauge damage; Arts knock back |
| Shade | Dagger | Hide out of combat; first strike from behind 2.5x and opens a Switch window |
| Herald | Any 1H + war horn | Rally: party Tempo cap +2 and +10% Art speed for 10 s; carries two extra Shards |

**Other rare mechanics (all permanent, all announced).**

- *Blood Moon* (0.5% per in-game night): the sky goes red, every mob becomes its elite variant, Hollow Grin NPC hunters spawn, drop rates triple.
- *Gilded variants* (0.1% per spawn): a gold-skinned version of any mob with 5x HP and a guaranteed Rare drop.
- *Mirror of Origins* (0.05% drop from Haven bosses): one re-roll of Lineage or Origin. The rarest item in the game.
- *Shard mutation* (1% on pickup): a Shard with a second effect (a Mend Shard that also cleanses).
- *The Warden's Favor* (one player per floor first clear, random): a cosmetic aura and a line on the Roll of Honor.
- *Hidden rooms* in every Labyrinth (one per floor, found by a Search proficiency check) with the floor's lore and an Epic.

All rolls happen on the server with `Random.new()` seeded per request, are logged with the player id, and are never influenced by anything purchasable.

## 8. Weapons, Arts and skill trees

Twelve weapon categories, each with its own proficiency (0 to 1000, raised by use) and its own Art list. Two are origin-locked. A weapon category occupies one skill slot; non-combat skills share the rest (2 slots at level 1, one more every 10 levels, max 12).

| Category | Role | Trail color | Feel |
| --- | --- | --- | --- |
| One-Handed Sword | All-rounder, the hero weapon | Cyan-white | Fast arcs, clean thrusts |
| Rapier | Precision, thrust combos | Pale gold | Linear, piercing, a blur of points |
| Two-Handed Sword | Heavy arcs, knockback | Crimson | Wide, slow, the ground shakes |
| Katana | Draw cuts, counters | Silver-blue | Sheathed stance, iaido lines |
| Dagger | Speed, backstabs | Violet | Twitchy, close, many hits |
| Spear | Reach, sweeps | Jade | Long thrusts, spinning sweeps |
| Axe | Guard breaking | Orange | Overhead chops, hooks |
| Mace | Stuns, shields | Amber | Blunt stagger, shield bash |
| Shield (off-hand) | Guard, bash | White | Wide cone, bash Arts |
| Martial Arts | Unarmed, mobility | Rose | Flips, kicks, wall runs |
| Twin Fang (Dual Wielder) | Two blades | Cyan and violet | Both colors in one trail |
| Aegis Blade (Aegis) | Unbreakable guard | Ivory | Immovable; counters only |

**Art list (starting data; times in seconds; unlock = proficiency).** Startup includes the 0.15 s start pose and 0.1 s activation hold. Post-motion is the lock after the last hit.

| Weapon | Art | Unlock | Hits | Startup | Total | Post-motion | Note |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1H Sword | Horizontal | 0 | 1 | 0.25 | 0.6 | 0.4 | The first Art every player learns |
| 1H Sword | Vertical | 0 | 1 | 0.25 | 0.6 | 0.4 | Guard-gauge heavy |
| 1H Sword | Rising Arc | 50 | 2 | 0.3 | 0.9 | 0.5 | Launches small enemies |
| 1H Sword | Sharp Nail | 150 | 3 | 0.3 | 1.1 | 0.6 | The bread-and-butter combo |
| 1H Sword | Sonic Leap | 250 | 1 | 0.35 | 0.8 | 0.6 | 14-stud gap closer |
| 1H Sword | Lance Thrust | 400 | 1 | 0.5 | 0.9 | 0.9 | Heavy, 6-stud lunge, pierces |
| 1H Sword | Howling Octave | 650 | 8 | 0.4 | 2.2 | 1.2 | Five thrusts, three arcs |
| 1H Sword | Nova Ascension | 900 | 10 | 0.5 | 2.8 | 1.4 | Ultimate; leaves a light pillar |
| Rapier | Linear | 0 | 1 | 0.22 | 0.5 | 0.35 |  |
| Rapier | Oblique | 50 | 1 | 0.22 | 0.5 | 0.35 | Angled, dodges low sweeps |
| Rapier | Quadruple Pain | 150 | 4 | 0.3 | 1.0 | 0.6 | Same-point hits, bleed |
| Rapier | Flashing Penetrator | 350 | 1 | 0.4 | 0.7 | 0.8 | 20-stud dash thrust |
| Rapier | Star Splash | 500 | 8 | 0.35 | 1.8 | 1.0 |  |
| Rapier | Crucifixion | 700 | 2 | 0.4 | 1.0 | 0.8 | Cross cut, stun |
| Rapier | Neutron | 900 | 5 | 0.45 | 1.5 | 1.2 | Ultimate; near-instant hits |
| 2H Sword | Avalanche | 0 | 1 | 0.4 | 1.0 | 0.7 | Overhead, knockdown |
| 2H Sword | Cyclone | 100 | 2 | 0.45 | 1.2 | 0.8 | 360-degree sweep |
| 2H Sword | Earth Splitter | 300 | 1 | 0.5 | 1.1 | 1.0 | Ground shock line |
| 2H Sword | Crescent Fall | 500 | 3 | 0.5 | 1.6 | 1.0 |  |
| 2H Sword | Titan Press | 700 | 4 | 0.6 | 2.0 | 1.3 | Breaks Guard Gauge hard |
| 2H Sword | Ragnarok Wheel | 900 | 6 | 0.6 | 2.6 | 1.6 | Ultimate |
| Katana | Iai Cut | 0 | 1 | 0.2 | 0.45 | 0.5 | Sheathed draw, long reach |
| Katana | Reaver | 100 | 2 | 0.3 | 0.9 | 0.5 |  |
| Katana | Tsujikaze | 250 | 1 | 0.3 | 0.6 | 0.6 | Dash through enemy |
| Katana | Gengetsu | 450 | 1 | 0.35 | 0.7 | 0.7 | Crescent, launches |
| Katana | Hiogi | 650 | 5 | 0.4 | 1.6 | 1.0 | Fan of cuts |
| Katana | Scarlet Fan | 900 | 7 | 0.5 | 2.2 | 1.4 | Ultimate |
| Dagger | Rapid Bite | 0 | 2 | 0.2 | 0.5 | 0.3 |  |
| Dagger | Fad Edge | 100 | 3 | 0.25 | 0.7 | 0.4 |  |
| Dagger | Shadow Stitch | 300 | 5 | 0.3 | 1.0 | 0.5 | Backstab bonus |
| Dagger | Venom Fang | 500 | 1 | 0.3 | 0.5 | 0.6 | Applies poison |
| Dagger | Mirage Step | 700 | 4 | 0.3 | 1.1 | 0.6 | Teleports behind target |
| Dagger | Thousand Cuts | 900 | 12 | 0.4 | 2.4 | 1.3 | Ultimate |
| Spear | Pierce | 0 | 1 | 0.3 | 0.7 | 0.5 | 10-stud reach |
| Spear | Sweep | 100 | 1 | 0.35 | 0.8 | 0.6 | Trips small enemies |
| Spear | Dragon Dive | 350 | 1 | 0.45 | 1.0 | 0.9 | Leap and plunge |
| Spear | Whirl | 550 | 4 | 0.4 | 1.5 | 0.9 |  |
| Spear | Skewer Tempest | 900 | 7 | 0.5 | 2.4 | 1.4 | Ultimate |
| Axe / Mace | Cleave | 0 | 1 | 0.35 | 0.8 | 0.6 | Heavy gauge damage |
| Axe / Mace | Hook | 150 | 1 | 0.35 | 0.8 | 0.6 | Pulls, opens Switch |
| Axe / Mace | Skull Crack | 350 | 2 | 0.45 | 1.1 | 0.9 | Stun |
| Axe / Mace | Quake | 600 | 1 | 0.5 | 1.2 | 1.1 | Area knockdown |
| Axe / Mace | Doom Spiral | 900 | 5 | 0.6 | 2.4 | 1.5 | Ultimate |
| Twin Fang | Double Circular | 0 | 2 | 0.3 | 0.7 | 0.3 | Both blades, both colors |
| Twin Fang | Cross Block | 100 | 0 | 0.15 | 0.4 | 0.2 | Guard that opens a Switch on parry |
| Twin Fang | Quad Fang | 250 | 4 | 0.35 | 1.0 | 0.4 |  |
| Twin Fang | Shearing Wind | 400 | 6 | 0.35 | 1.4 | 0.5 |  |
| Twin Fang | Twin Lance | 550 | 2 | 0.4 | 0.9 | 0.7 | Dual thrust, 8-stud lunge |
| Twin Fang | Meteor Cascade | 500 | 16 | 0.5 | 4.2 | 1.6 | Ultimate I; the raid-saver |
| Twin Fang | Umbral Reign | 1000 | 27 | 0.6 | 7.0 | 2.4 | Ultimate II; screen goes dark except the trails |

Martial Arts, Shield and Aegis Blade follow the same table shape with 5 Arts each; author them in data with the same columns. Every Art row maps to one animation clip definition in section 10.

**Weapon rarity.** Common (gray), Uncommon (green), Rare (blue), Epic (purple), Legendary (gold), Apex (white edge-light). Rarity sets base attack, the number of enhancement slots (0 to 5) and the drop weight. Apex pieces are never random drops; they come from the sources in section 7.

**Enhancement (at a smith).** Weapons go from +0 to +15. Each attempt needs ingots, Crowns and one of five attributes to raise: Sharpness (attack), Quickness (Art speed), Accuracy (crit), Heaviness (gauge damage), Durability. Success starts at 95% and falls 4 points per level; from +10 up, a failure has a 25% chance to break the weapon in Lucid. The smith animation is the anime beat: hammer, sparks, the blade lifts glowing or shatters.

**Named weapons (one line each in `weapons.luau`; add at least three per floor).** Tempered Edge (floor 1 Rare 1H), Mantle of Last Light (floor 1 LAB coat), Lucent Needle (floor 4 Epic rapier), Kobold Cleaver (floor 1 Uncommon axe), Glacier Edge (floor 55 Legendary 1H, smith-forged from a white wyrm's ingot), Nightfall (floor 50 LAB 1H, black blade), Sovereign's Oath (floor 25 Apex 2H).

**Non-combat skills (share the slots).** Searching (finds hidden rooms, reveals stealthed mobs), Hiding, Sprint, Acrobatics (double jump, wall-kick), Parry mastery (+ window), Cooking, Fishing, Smithing, Tailoring, Appraisal, Tracking, Trading (vendor prices).

## 9. Enemies, field bosses and floor bosses

Every enemy is an archetype plus a skin plus a floor tier. Archetypes define behavior, telegraph timing and Guard Gauge; skins define the model and shatter color; tiers scale numbers. New enemies are data rows, not new scripts.

**Archetypes (behavior modules in `src/server/ai/`)**

| Archetype | Behavior | Telegraph | Counter |
| --- | --- | --- | --- |
| Charger | Straight-line rush, turns slowly | 0.6 s crouch, red line on the ground | Sidestep, hit the flank |
| Brute | Slow heavy swings, big gauge | 1.0 s overhead, yellow edge | Parry, Breaker Arts |
| Skirmisher | Circles, quick jabs, retreats | 0.4 s shoulder dip, white edge | Lock target, Switch |
| Lancer | Long thrusts, keeps distance | 0.7 s draw-back, red line | Close in after a thrust |
| Swarm | Weak, in groups of 4 to 8, flank | 0.3 s hiss | Sweeps, Spear Whirl |
| Guard | Shield, blocks frontal Arts | Raises shield (no attack) | Hook, backstab, Switch |
| Caster-beast | Breath or spit cone, no magic lore | 1.2 s inhale, glow in the throat | Dodge sideways, punish the exhale |
| Stalker | Stealthed until close, paralysis bite | 0.3 s shimmer | Searching skill, Cleanse Shard |
| Warden-construct | Phase shields, Lockstep mechanics | Pillars light up | Two players, timed |

**Elite rule.** Blight-band packs have one Elite (1.5x stats, Mirror Shield, a second attack) per four mobs. Night adds a Night variant with +25% damage and glowing eyes. Blood Moon makes every mob an Elite.

**Bestiary, floors 1 to 10 (three to six per floor; skins described for the modeler)**

| Floor | Enemies |
| --- | --- |
| 1 | Frenzy Boar (Charger, blue hide), Dire Wolf (Skirmisher), Kobold Sentinel (Guard, round shield), Kobold Axeman (Brute), Nepenthe Bloom (Caster-beast, plant, spits acid) |
| 2 | Marsh Wasp (Swarm), Mire Leech (Stalker, paralysis), Bog Troll (Brute), Reed Lurker (Lancer, fishing-spear) |
| 3 | Ember Fox (Skirmisher), Treant Sapling (Guard), Ash Beetle (Charger), Will-Wisp Moth (Swarm, burn) |
| 4 | Gull Harpy (Skirmisher, dives), Tide Crab (Guard, huge claw), Sea Lizardman (Lancer, trident), Brine Serpent (Caster-beast, water jet) |
| 5 | Highland Ram (Charger), Scarecrow Construct (Warden-construct, light), Bandit Trialist (humanoid Skirmisher with Arts), Storm Hawk (Swarm) |
| 6 | Glow Spider (Stalker), Cave Ogre (Brute), Fungal Shambler (Caster-beast, poison cloud), Lantern Bat (Swarm) |
| 7 | Savanna Lion (Charger, pride of 3), Minotaur Guard (Guard + Brute), Dust Vulture (Swarm), Elephant Beetle (Brute, gauge 3x) |
| 8 | Frost Wolf (Skirmisher, pack), Ice Golem (Guard, freeze), Yeti (Brute), Rime Wisp (Caster-beast, freeze cone) |
| 9 | Shade Hound (Stalker), Dryad Knight (Lancer with Arts), Owlbear (Brute), Glow Mantis (Skirmisher, paralysis) |
| 10 | Citadel Knight (Guard with Arts and Mirror Shield), Warden Hound (Charger), Clockwork Archer (Lancer, ranged), Honor Guard Captain (Elite Skirmisher, Switches with his own squad) |

Floors 11 to 25 use the biome rosters from the Generator kits plus two unique enemies each, authored in the same table shape.

**Field bosses (one per floor; 90-minute respawn; 4x Elite stats; drops an Apex piece at 15%)**

Floor 1 Tusk, Warboar King; floor 2 the Reed Queen (wasp, flies between boardwalks); floor 3 Old Cinder (ancient treant); floor 4 the Lighthouse Serpent; floor 5 the Iron Ram; floor 6 Mother of Lanterns (giant spider); floor 7 the Pride Father; floor 8 Rimeback (mammoth); floor 9 the Hollow Stag; floor 10 the Deserter Captain (humanoid with a full Art list and a Mirror Shield).

**Floor boss template (every boss follows it; bosses are the game's set pieces)**

1. *Entrance.* Double doors open on a 3 s scripted camera: torches flare in sequence, the boss stands, its name card slides in, its HP bars (4 to 6) fill left to right with a sound per bar.
2. *Phases.* One phase per HP bar group. Each new phase adds a mechanic, changes the stance, and on the final bar changes the weapon or the body (the floor 1 boss drops its axe and draws a curved blade; a Lancer boss sheds its armor and becomes a Skirmisher).
3. *Minions.* A guard pack at the start and at each phase change; Overwhelm adds more (section 7).
4. *Lockstep mechanic.* At least one per boss that needs two players acting within 1 s.
5. *Enrage.* At 8 minutes the boss gains +10% damage per minute. No infinite fights.
6. *Wipe.* If the whole party shatters, the chamber resets after 60 s and the doors reopen; in Lucid the shattered do not come back.
7. *Last Attack Bonus.* Whoever lands the killing hit gets the floor's LAB item (always an Apex piece or a Legendary) and their name in gold on the Roll of Honor.
8. *First clear.* Server-wide announcement, the stairs open, the floor's gate activates on every server.

**Launch bosses (floors 1 to 10)**

| Floor | Boss | Bars | Phase mechanics and Lockstep |
| --- | --- | --- | --- |
| 1 | Grolak, Kobold Warlord | 4 | Axe and buckler with three Sentinels. Bar 3: throws the buckler, calls four more. Bar 4: draws a curved blade, gains Katana Arts and a jump cut that one-shots a yellow-HP player. Lockstep: two players must break two totems or the Sentinels respawn. |
| 2 | Mirefang Matriarch | 4 | Giant wasp, flies between three boardwalk platforms. Bar 2: lays eggs that hatch Swarm. Bar 4: poison fog fills the lower level; stand on the platforms. Lockstep: cut both wing tendons within 1 s to ground her. |
| 3 | Ashbark Treant | 5 | Rooted, reaches with branches. Bar 3: the room catches fire; burn pools. Bar 5: uproots and becomes a Brute. Lockstep: two saplings must be cut at once or it heals a bar. |
| 4 | Tidecaller Serpent | 5 | The chamber floods in waves (timed, 20 s cycle). Bar 2: water jet sweeps. Bar 4: lightning on the water; stand on rocks. Lockstep: strike both bell chains to drain the room. |
| 5 | Iron Bulwark Golem | 6 | Mirror Shield permanently; only Switch or Twin Fang damages it. Bar 3: splits into two golems. Bar 6: fuses and overloads; a 10 s burn-everything attack that needs both pillars struck. |
| 6 | Pale Crawler | 5 | Darkness: only the party's lanterns light the room. Bar 2: webs that paralyze. Bar 5: eats a lantern per 20 s. Lockstep: relight two braziers together. |
| 7 | Khagan of Hooves | 5 | Minotaur with a great axe; charges that cross the whole room. Bar 3: throws the axe, fights with fists (Martial Arts). Bar 5: picks the axe back up and gains Earth Splitter. Lockstep: parry a charge on both flanks. |
| 8 | Rimeclaw Behemoth | 6 | Freeze stacks; three stacks freeze solid. Bar 2: ice pillars for cover against a breath. Bar 4: the floor cracks. Bar 6: the room goes white-out, telegraphs are sound only. Lockstep: shatter two ice hearts together. |
| 9 | Hexen Stag | 5 | Teleports between four shrines; illusions. Bar 3: two false stags (hit the one with the Switch window). Bar 5: the forest grows into the room and Stalkers spawn. Lockstep: desecrate two shrines in sync. |
| 10 | The Warden's Knight | 6 | A humanoid knight with a full 1H Sword Art list and a shield; the first boss that Switches with its own Honor Guard. Bar 4: sheds the shield, takes Twin Fang Arts (a foreshadowing). Bar 6: Duelist Protocol is forced for everyone: minions leave and the raid fights a swordsman. Lockstep: two players must parry its Howling Octave's third and fifth hit. |

**The Labyrinth.** 8 to 12 levels of dark stone, torch-lit, with respawning packs every 6 minutes, pressure-plate traps (spikes, dart lines, collapsing bridges), a map that fills in per character, a hidden room (section 7), and the ingot node for the Apex recipe on the deepest level guarded by a mini-boss. No Gate Shards work on the top three levels. Parties should need two or three evenings to reach the doors on their first floor.

**Shatter colors.** Beasts shatter blue-white, constructs silver, plants green-gold, humanoid NPCs the same blue-white as players. Bosses shatter in a 3 s slow burst with the camera pulled back.

## 10. Animation spec (the part Swordburst got wrong)

Animation is the product. Swordburst's loop is fine and its animation is Roblox-default: linear tweens, no anticipation, no hit-stop, floaty slides, enemies that stand still and flinch. Skyspire fixes that with a code-driven animation system so every clip is authored as data in git, reviewable, tunable and never dependent on an upload.

**Choreo: the animation system.** Build `src/client/choreo/` as a client-side animator that drives every rig's `Motor6D.Transform` each `RenderStepped` from clip data. A clip is a Luau table: a list of keys, each with a time, a per-joint CFrame offset, an easing (expo-out for snaps, back-out for overshoot, spring for settles), and optional events (hit window open, trail on, footstep, voice). Features it must have:

- Layered blending: base locomotion layer, upper-body action layer, additive layers (breathing, lean into turns, hit flinch), and an IK layer (feet on stairs, hands on weapon grips).
- A clip clock that can **pause** (hit-stop), **scale** (Tempo, Quickness), and **jump** (network catch-up).
- Root motion from the clip, applied through the character's `HumanoidRootPart` with the server validating the resulting displacement.
- Playback of standard Roblox `Animation` ids on the same layers, so hand-authored Moon Animator clips can replace data clips later without touching gameplay code.
- A Studio plugin, `tools/PoseEditor`, that scrubs any clip, lets the user drag joints, and writes the data table back to the file.

**Rigs.** Players use an R15-compatible custom rig with anime proportions: head slightly large, long legs, narrow waist, big hands for weapon readability. Keep the 15 Motor6D names so layered clothing and accessories still work. Enemies use custom rigs defined in data (joint list and rest pose) with the same Choreo player; a boar is four legs and a spine, a boss can have 30 joints. Every rig has a tagged `WeaponGrip` attachment and a `TrailStart`/`TrailEnd` pair on each weapon.

**The six beats of every attack (player and enemy).** A clip that lacks any of these fails review.

1. *Anticipation* (4 to 10 frames at 60 fps): weight shifts back, the weapon pulls the opposite way, the torso twists, the free hand opens.
2. *Snap* (2 to 4 frames): the strike reaches its key pose with expo-out easing; the fastest motion in the game, deliberately under-animated so the eye reads the pose, not the path.
3. *Smear* (the 2 snap frames): the weapon mesh is scaled 1.6x along the swing axis and the Trail is at full width. On the third frame the scale returns.
4. *Hold* (hit-stop): on contact the clip clock pauses 3, 6 or 10 frames (section 6), the camera nudges toward the hit 0.4 studs, and the Highlight on the target flashes white for 2 frames.
5. *Overshoot and settle* (6 to 12 frames): the pose passes the key by 5 to 8 degrees and springs back.
6. *Recovery / post-motion*: the end pose is held with micro-motion only (breathing, blade tremor), then a 0.2 s blend back to locomotion. Post-motion must look like a person caught in a stance, not a paused game.

**Locomotion.** An 8-direction blend space for walk, run and sprint, separate sheathed and drawn sets, turn-in-place at 45 degrees, a two-step stop with a skid above run speed, a landing squash scaled by fall height, and raycast foot IK on slopes and stairs. Sprinting with a drawn weapon holds it low and back; the anime run is leaned forward with the free arm pumping. Idle has a 12-second cycle with a weight shift and, for drawn weapons, a blade re-grip.

**Secondary motion, done procedurally.** Roblox has no cloth, so build it: coats, capes, scarves, hair and tails are 3 to 6 segment part chains simulated on the client with a verlet solver (gravity, wind, drag, a collision sphere at the hips), attached to the rig and hidden on distant LOD. The long coat is the hero silhouette; it has to flare on dashes and settle on landings.

**Weapon trails and light.** Each weapon carries a `Trail` (width from the weapon data, lifetime 0.18 s, texture a soft gradient, color the Art's trail color, `LightEmission` 1) that is enabled only during Art damage windows and the smear frames, plus a `PointLight` on the blade during activation. Basic attacks get a thinner, whiter trail. Twin Fang trails are two colors and overlap into white where they cross.

**Enemy animation rules.** Wind-up poses are held and readable from behind as well as the front. The strike moves the whole body, not just a limb. Stagger has four directional clips. Break is a kneel with the weapon dropping. Death is a 0.5 s freeze in the last pose (no ragdoll), then the shatter. Bosses have an idle that breathes visibly and a phase-change clip that reads as a decision (a weapon switch, an armor shed) with the camera pulled back for it.

**Camera (`src/client/camera/`).** Third person, a spring-damped follow with 0.12 s lag, 60-degree FOV at rest, +8 degrees on Art activation and dashes, a 0.4-stud nudge toward every hit, shake amplitude 0.15 / 0.3 / 0.6 studs for the three hit-stop tiers, lock-on framing that keeps both fighters in view, a low tight orbit in duels, a high wide orbit in raids, and scripted shots for boss entrances and floor-clear moments. Mobile uses the same system with wider defaults.

**Networking animation.** The local client plays its own Choreo instantly. The server validates the action and broadcasts `ActionStarted(playerId, clipId, serverTime, facing)` on an unreliable remote; other clients start the same clip at the matching clock position. Hit confirmations arrive separately and drive hit-stop on everyone who can see the hit. Nothing about animation is simulated on the server.

**Review loop.** Each Art, locomotion state and enemy archetype has a scene in `places/ClipLab.rbxl` that plays it in a loop at 0.25x, 0.5x and 1x with a frame counter. Before any gate, record the six beats of every new clip and compare to this section. Write `docs/ANIMATION_REVIEW.md` with one line per clip: beats present, hit-stop tier, trail timing, problems.

## 11. Rendering, VFX and the anime look on Roblox

Roblox has no custom shaders, so the anime look is built from lighting, materials, Highlights, post effects and discipline. The goal is flat, saturated, high-contrast, with clean outlines and a lot of light.

**Lighting setup (per floor place, values in `lighting.luau`).** Technology Future; ShadowSoftness 0.2; EnvironmentDiffuseScale 0.6, EnvironmentSpecularScale 0.3; a ColorCorrection with Saturation +0.15 and Contrast +0.1 and a per-floor TintColor; Bloom Intensity 0.4, Size 24, Threshold 0.9; SunRays Intensity 0.1; Atmosphere with Density 0.3, Haze 1.5, Glare 0.4 and a per-biome color; a Clouds instance for the sky. Towns add a light DepthOfField (far distance 180, intensity 0.3). Night lowers Brightness to 0.8 and raises Bloom to 0.6.

**Materials.** Characters and enemies use SmoothPlastic with flat colors from a 24-color floor palette; no Plastic speckle, no PBR noise on characters. Environment uses Roblox PBR materials sparingly: stone, wood, grass on Terrain, with MaterialVariants tuned low in roughness noise. Avoid Neon on anything except trails, shards, system light and lava.

**Outlines.** A `Highlight` on every player and enemy within 120 studs: OutlineColor a near-black of the character's base color, OutlineTransparency 0, FillTransparency 1. The Highlight budget is 31 concurrent; `src/client/fx/OutlineManager.luau` ranks by distance and importance (party, lock target, boss always on). The same Highlight flashes white fill for 2 frames on a hit and red fill for a guard break.

**Color tokens (`palette.luau`; the only colors UI and FX may use)**

| Token | Hex | Use |
| --- | --- | --- |
| SystemCyan | #7FE8FF | Menus, cursors, teleport light, shard glow |
| SystemWhite | #F4FBFF | System text, Art activation flash |
| HPGreen | #4FE36B | HP bar above 50% |
| HPYellow | #FFD23F | HP bar 25 to 50% |
| HPRed | #FF3B3B | HP bar below 25%, unblockable telegraphs |
| CursorOrange | #FF8C1A | Orange players |
| CursorRed | #E01B1B | Red players, boss name cards |
| TorchWarm | #FFA347 | Torches, inns, smith fire |
| WardedPurple | #B57BFF | Warded Object and Warded Zone popups |
| ShardBlue | #9ADCFF | Shatter shards |
| ApexEdge | #FFFFFF | Apex edge-light |

Trail colors per weapon are in section 8.

**The shatter (`src/client/fx/Shatter.luau`).** One effect for every death, player included. On the death signal: the rig freezes 0.5 s with all sound ducked; a white flash from a single ParticleEmitter burst; the rig is hidden and replaced by 40 to 80 pooled wedge parts (Neon, ShardBlue or the type's color from section 9) spawned at the rig's limb positions with outward and upward CFrame animation on the client, no physics; the shards rotate slowly, rise 6 studs over 0.8 s, and fade to transparent while shrinking; a glass crack-and-ring sound plays once. Bosses use 300 shards over 3 s and a slow camera pull-back. The pool lives in ReplicatedStorage and is pre-warmed on floor load.

**Art activation.** A PointLight on the blade (range 8, brightness 2, the trail color), a 3-frame flash of SystemWhite on the weapon's Highlight, the chime, and a 0.1 s hold. It should be visible across a field.

**Telegraph light.** Enemy weapons get a Highlight fill in white, yellow or red during the wind-up (section 6), plus a flat Decal arc or line on the ground showing the hit area for ground attacks. Telegraphs are drawn by the client from the enemy's broadcast action, so they are never late.

**Switch window.** A thin SystemCyan ring expands from the enemy's hit point for 0.8 s; the partner's screen shows the SWITCH prompt (section 14). When the Switch lands, both weapons' trails flash white for 2 frames.

**Mirror Shield.** A translucent hex-cell shell (SurfaceGui tiles on a slightly larger invisible mesh) in WardedPurple at 40% transparency; a reflected hit sends a copy of the trail back at the attacker.

**Teleport Gate.** A 40-stud Beam pillar in SystemCyan with rising particles; on use, the player's rig dissolves upward in cyan shards (the shatter effect reversed and recolored), a white-out, then the place teleport. On arrival the same effect runs in reverse so the teleport itself is hidden inside the animation.

**System panels.** The Architect's announcement and floor-clear events use a sky of hexagonal SurfaceGui tiles on an inverted sphere in CursorRed or SystemCyan, animated tile by tile.

**The rim and the ceiling.** Each floor's ceiling is a MeshPart disc with a stone texture, lit from below by SurfaceLights at the pillars. Below the rim, a ring of large cloud billboards (ParticleEmitters on invisible parts, slow drift) sits 200 studs down, and the skybox has clouds at the horizon. Night turns the rim into a line of distant pillar lights.

**Budgets.** Per scene: 31 Highlights, 400 live particles, 20 active Trails, 60k parts, 1,500 draw calls. Shards and trails are pooled. Every FX module has a `quality` parameter (High, Medium, Low) read from the settings menu and defaulted from the device.

## 12. Character customization, skins and cosmetics

Players should recognize each other by silhouette at 100 studs. Customization is built in layers so gear and cosmetics never fight, and so rare rolls stay visible.

**Creation.** Body preset (4 builds per lineage), face preset (12), eyes (color plus the lineage tint), hair (24 styles with a procedural chain for anything past the shoulders), skin tone, voice set (6 grunt and effort sets, no speech), starting outfit (Trialist cloth). Lineage marks (Starmarked constellations, Hollowkin cracks, Nightveil sclera, Ashborn freckles) render on top of everything and cannot be hidden. The Dual Wielder's crossed sheaths and the Aegis shield mount are fixed.

**Armor layers (bottom to top).** Underlayer (tunic, trousers), Chest piece, Legs, Hands, Boots, Over-layer (coat, cape, tabard, scarf), Head (circlet, hood, helm with a visor state), Accessory (ring, charm, the Mark). Each is a layered-clothing asset or a part set on the rig; over-layers get the procedural chain from section 10. Armor has stats; the look is the look of the armor unless a skin overrides it.

**Skins (transmog).** Any owned armor or weapon look can be applied over any equipped piece of the same slot. Skins are unlocked by owning the item once (the Codex remembers it, even after a death), by cosmetic drops, and from the cosmetic shop. Apex sets keep their edge-light even under a skin, and the edge-light is the only cosmetic that cannot be bought.

**Dyes.** Three dye channels per piece (primary, secondary, trim) from a 48-dye palette; rare dyes (deep black, pure white, the system cyan) drop from Haven bosses and Blood Moons.

**Signature looks to ship at launch (originals).** A long black over-coat with a high collar (the Mantle of Last Light, floor 1 LAB); the Ivory Vow uniform (white with red trim, a long tabard); the Bulwark Legion's grey plate with a crowned shield; Hollow Grin's black leather with a cracked white mask; Firstlight cloth in undyed linen; a hooded wanderer's cloak; a smith's apron; a fisher's hat.

**Weapon skins.** Every named weapon is a skin once owned. Trails take the equipped weapon's category color, but a skin can carry a trail variant (a frosted trail, an ember trail) unlocked with the skin.

**Emotes and idles.** Twelve emotes (sheath flourish, bow, sit, lean, point, cheer, salute, kneel, stretch, whistle, flex, the Switch hand-signal) and four selectable idles per weapon category. The Dual Wielder's idle is unique and cannot be selected by others.

**Pets.** Beastbond origin only, plus one cosmetic companion slot for everyone (a cat, a small bird, a lantern wisp, no combat). Plume, the feathered wyrmling, is the first combat pet: a four-joint rig with a Choreo idle, a glide, a bite, and a heal lick with an 8-minute cooldown. Pets shatter and can be revived once per floor with a rare item from the floor 3 quest.

**Guilds.** A guild has a name, a two-color emblem built from 40 shapes and a 20-color palette, an optional uniform (a saved outfit that members can toggle), and a rank list. Emblems appear on tabards, shields, the guild hall banner and the Roll of Honor.

**Housing decor.** Homes have 10 to 60 decor slots; decor is cosmetic, craftable or bought. A trophy slot shows a boss's weapon on the wall for every floor the owner cleared.

**Shop rules.** Robux sells: cosmetic skins, dyes, emotes, companions, decor, private servers, extra character slots. Never stats, gear, Shards, Crowns or rolls.

## 13. Progression, crafting and economy

Power comes from three places: level (slow), proficiency (use), and gear (the floor). None of them can be bought.

**Levels and stats.** Level cap 100, one level per floor on average (XP to next level = 120 × level^1.6; mobs give XP by tier, bosses give a level's worth to the raid). Each level grants +10 max HP and 3 stat points into STR (damage, armor weight limit) or AGI (crit chance, dodge recovery, Art speed up to +15%). Being more than 5 levels above a floor's tier halves XP there; being 5 below doubles the damage taken. The anime's front line is always slightly under-leveled and that should be true here.

**Proficiency.** Each weapon category and each non-combat skill has 0 to 1000 proficiency, gained by use (an Art that lands gives 1 to 3 points scaled down as proficiency rises; a parry gives 2). Arts unlock at the thresholds in section 8. Proficiency is per character and dies with it.

**Crowns.** The only currency. Sources: mob drops (small), quest rewards, vendoring, player trades, the market. Sinks: repairs, enhancements, Shards, homes, respecs, Gate fees on floors taxed by the Bulwark Legion (floors 1 to 10 charge a 5% fee at the gate; the Legion story quest ends it). Inflation control: vendor prices rise 2% per cleared floor server-wide, and the market charges a 10% listing fee that is destroyed.

**Loot.** Every enemy has a drop table in `loot.luau`: Crowns, materials (hide, fang, ingot ore, reed, resin, ice-heart), consumables, and gear by rarity weight (Common 60%, Uncommon 25%, Rare 10%, Epic 4%, Legendary 1% on Elites and bosses only). Last Attack Bonus is deterministic (section 9). Gilded variants and Blood Moons multiply rates. Drops belong to the party and are split by a round-robin that the party leader can set to need/greed or free-for-all. A drop in Lucid that nobody takes in 60 s shatters.

**Shards.** Gate Shards are sold in every town at 500 Crowns on floor 1, +300 per floor. Mend Shards are not sold; they drop at 0.5% from Elites and come one per mini-dungeon first clear. Corridor Shards come from quests. Cleanse Shards are sold and craftable. Carrying more than five of any Shard is not allowed; hoarding is not a strategy.

**Smithing (the Lisbeth beat).** A smith NPC in every town, and a player skill. Forging needs a recipe, ingots and a 6-second minigame: three hammer strikes timed to a glowing bar, each hit a Choreo clip with sparks; perfect timing adds +1 to the result's enhancement. Repair, enhance (section 8), and reforge (change one attribute). Players with Smithing 500+ can buy a forge for their home and sell at the market with their name on the weapon.

**Tailoring.** Armor and over-layers from hides, cloth and thread; dye application; repair of armor durability. Tailoring 500+ unlocks guild uniform crafting.

**Cooking.** Ingredients from fields and vendors; recipes give 30-minute buffs (+5% STR, +5% AGI, +10% max HP, poison resistance, cold resistance for floor 8). Cooking at a home kitchen doubles the duration. The cooking animation is a Choreo clip with a pan and real timing.

**Fishing.** Every Haven and settlement floor has fishing spots; a two-stage minigame (hook on a timing ring, reel with alternating keys). Fish feed cooking, and each floor has one legendary fish with a 0.2% bite rate and a trophy mount. Floor 22's lake has the biggest.

**Appraisal and Searching.** Unidentified Rare+ drops need Appraisal (a vendor or the skill). Searching reveals hidden rooms, stealthed Stalkers, and tracks on the ground to the field boss.

**Quests.** Four types, all data in `quests.luau`: Main (floor clear chain, one per floor), Floor (a 4 to 8 step chain per floor with its own story), Board (repeatable kill, gather and escort from the town board, refreshed daily), and Hidden (triggered by items, times or rolls; the Mirror of Origins has one). Quest text is short; the anime tells its stories in moments, not paragraphs.

**Housing.** Homes are instanced interiors with a door in the town; buying one costs 5,000 Crowns on floor 1 and scales by floor and size. A home gives a bed (log out safely), storage (200 slots), a kitchen, a forge slot, a trophy wall, and, on Mirrorlake, a lake view and a dock. Guild halls are large homes with a banner, a roster board and a 1,000-slot bank.

**Market and trade.** A town market board lists items for Crowns with the 10% fee; face-to-face trade windows need both parties to confirm twice. Trade scams are a story beat (section 18), so the trade window shows the real item card, never a name string.

**Death economy.** A dead character's listed market items complete; its home returns to the market after 7 days with the trophies intact for the next owner; 10% of carried Crowns go to the account's estate bank; the Legacy item goes to the next character at level 1 with its enhancement reset to +0.

## 14. UI and UX: the diegetic system

The interface is part of the fiction: translucent panels of system light that the character summons with a gesture and that other players can see floating beside them. Nothing on screen looks like a website. Build everything in `src/client/ui/` with a small component library (Fusion or a hand-rolled one; pick one and record it in DECISIONS.md) over the palette in section 11.

**The menu gesture.** Opening the menu plays a Choreo clip: the character raises a hand and flicks two fingers downward; a panel of SystemCyan light unfolds beside them with a soft chime. On PC it is a key (M) that triggers the gesture; on mobile a two-finger swipe down. The panel is world-space (a SurfaceGui on a part attached to the character) so party members see you in your menu. The panel's tabs: Status, Items, Skills, Map, Party, Guild, Friends, Settings, Log out. Logging out plays the gesture in reverse.

**HUD (as little as possible).**

- Top-left: name, level, the HP bar (section 6 colors, the only element that flashes) with the numeric HP under it, and a thin Guard Gauge under that.
- Below it: party members' names and HP bars in a compact column, in the same colors, with a small weapon icon and a Lucid skull if they are in yellow.
- Over every player's head: the cursor (a small diamond in green, orange or red) and the name on hover; over enemies: a red diamond, the name, a short HP bar and the Guard Gauge; over bosses: nothing (their bars are at the top of the screen).
- Boss bars: a stack of 4 to 6 thin bars under the name card, each emptied left to right with a crack sound.
- Bottom-right: the quick-slot ring on hold; a transparent list of equipped Arts with their keys at the bottom-center that fades after 5 s of no use.
- Floating digits: real damage, 0.6 s fade, white for normal, yellow for crit, cyan for Switch, red for damage taken.
- Switch prompt: when a window opens on a target, the partner sees a thin cyan ring on the enemy and the word SWITCH in system text above it for 0.8 s; the caller's Tab press also shows their name beside it.
- Status icons beside the HP bar; Paralysis is a full-width red icon because it kills.

**System messages.** A system line is centered, SystemWhite in the system font, with a short chime: Warded Object, Warded Zone (purple), floor clears, level-ups, rare rolls, deaths ("\<name> has been struck from the Roll"). The Architect's announcement uses the red hex sky and a larger font.

**Item windows.** Item cards show the real model rotating, rarity color, stats, enhancement, durability, the smith's name if player-made, and a Skin button. Trade windows show two cards and two confirm steps.

**Map.** A floor map that reveals as the player explores (a fog texture cleared by a 60-stud radius), with town icons, the gate, discovered dungeons, the Labyrinth outline, party markers, the field boss's last known position if Tracking is slotted, and a Labyrinth level-by-level map in the dungeon. A minimap sits top-right only in the wild; towns hide it.

**Roll of Names and Roll of Honor.** World-space monuments: Firstlight's Roll of Names is a stone wall of carved names where a dead player's name gets a strike-through line within a minute of death; every floor's Roll of Honor lists its first-clear party in gold. Both pull from the DataStore and update live.

**Fonts.** Two: a rounded geometric sans for system text (Roblox's Gotham family is acceptable; prefer a custom uploaded font if the user supplies one) and a narrow serif for item and lore text. Never more.

**Accessibility and settings.** Remappable keys, a colorblind mode that changes HP bar hues and adds patterns, telegraph intensity slider (minimum is still visible), camera shake slider, UI scale, subtitles for the system voice, a reduced-FX quality mode, and a mobile layout with a left stick and right-side action buttons (attack, Art, guard, dodge, Switch).

**Flow rules.** No popups during combat except system lines. No tutorials with walls of text; Floor 1 teaches by doing (section 18). Every menu opens in under 100 ms and closes with escape. Loading screens are the login ritual (section 2) and are the only place with a tip line.

## 15. Audio direction

Music is Kajiura-style without Kajiura: strings and choir for raids, Celtic flute and piano for towns, low drones in the Labyrinth, and silence before anything important. All music is original (the user commissions or composes it; until then use clearly-labeled CC0 placeholders listed in `docs/PLACEHOLDERS.md`). Never use any track from the source.

**Adaptive music (`src/client/audio/MusicDirector.luau`).** Four layered stems per floor (ambient, explore, combat, boss) crossfaded by state with 2 s transitions; towns have a day and a night cue; Haven floors have a fishing cue that starts when the line is cast. Combat music starts on the first telegraph, not on aggro, and ends 6 s after the last enemy shatters. Below 25% HP the music ducks 6 dB and a heartbeat layer rises. Boss entrances cut to silence for 1 s, then the boss theme. The Duelist Protocol has its own sparse theme: one cello, one drum.

**Core SFX list (one asset per line in `sfx.luau`; pooled, 3D where in-world)**

- Art activation chime (one per trail color, pitched by weapon weight); Art whoosh per Art size; hit impacts in three tiers (flesh, armor, construct) layered with a short metallic ring; the hit-stop tick.
- Parry: a bright steel clash with a 0.3 s ring; guard: a dull block; guard break: a crack.
- Shatter: a glass crack, then a rising chime cluster, with a 0.5 s silence before it; the boss shatter is a slow version with a low boom.
- Footsteps by surface (stone, grass, wood, water, snow, gravel) and by weight (light, armored); landing thuds scaled by fall.
- Menu open and close gesture chimes; item pickup; Crowns; equip; a soft tone per rarity on drop (Legendary rings).
- System voice: a calm synthetic voice for the login countdown, floor clears, deaths and the Architect's lines (text-to-speech placeholder, replaced by a recorded original performance).
- Enemies: a vocalization per archetype for wind-up, strike, stagger and death; Swarm hiss; Charger snort; Brute roar; the Stalker's near-silence.
- Teleport gate rise and arrival; Shard use; smith hammer strikes with the forge crackle; fishing splash and reel.
- Ambience per biome: wind at the rim everywhere, birds, marsh frogs, cave drips, snow silence with wind, citadel bells.

**Mix rules.** Combat SFX sit above music; the HP heartbeat sits above both; the system voice ducks everything by 8 dB. Use `SoundGroup`s for Master, Music, SFX, UI, Voice with settings sliders. Mobile defaults music 2 dB lower.

## 16. Open-world tech on Roblox

One experience, many places. Each floor is its own place; the Teleport Gate is a real place teleport dressed as the gate effect. This keeps every server's world small enough to run well and lets the Floor Generator run per place.

**Place layout.** `Start` (login ritual and character select), `Floor_001` to `Floor_025` (hand-built), `FloorGen` (the generator place, parameterized by teleport data for floors 26 to 100), `Labyrinth` (one place for all Labyrinths, built from kits by floor), `BossArena` (reserved-server instance per raid), `Housing` (instanced interiors), `ClipLab` and `Playground` (dev only). Rojo manages the code; the places are `.rbxl` files in `places/` with their world content, and `docs/STUDIO_TASKS.md` lists what the user must publish.

**Streaming.** `StreamingEnabled` on every floor with `StreamingMinRadius` 128, `StreamingTargetRadius` 512, `StreamingIntegrityMode` PauseOutsideLoadedArea off (the game must not freeze), `ModelStreamingMode` Persistent for towns, gates and the rim. Characters and enemies use `Atomic` models so a half-streamed rig never appears. Field chunks are 256-stud models with `RenderFidelity` Automatic on their MeshParts and a 3-level LOD on anything taller than 20 studs.

**Terrain and ground.** Roblox Terrain for ground, water and cliffs with per-biome materials; MeshParts for towns, ruins and the Labyrinth. Water uses Terrain water with per-floor color. Floors are flat discs at Y=0 in their own place; the rim is a kill volume with the fall death.

**Spawning.** Server-side spawn tables per chunk: pack size, archetype mix, Elite ratio, threat band, respawn timer (6 minutes fields, 90 minutes field boss). Enemies only simulate within 300 studs of a player; beyond that they sleep. Enemy AI runs on the server at 20 Hz with movement via `Humanoid:MoveTo` for simple mobs and `PathfindingService` with custom material costs for anything that chases past 60 studs. Bosses run a dedicated state machine at 30 Hz.

**Time and weather.** The server owns a world clock (48 real minutes per in-game day) synced on join; `Lighting.ClockTime` tweens on the client. Weather is a per-biome client rig (particles, fog, sound) that follows the camera and is seeded by the server so a party sees the same storm.

**Transitions.** Gate use: the dissolve effect (section 11), `TeleportService:TeleportAsync` with teleport data (character id, destination gate id, party id), a loading screen that is the reverse dissolve, and the arrival effect. Boss raids and private groups use `ReserveServer`. The Labyrinth entrance is a teleport too, with the stairs animation hiding it. A failed teleport returns the player to the gate with a system line, never to a blank screen.

**Saving.** ProfileStore (loleris) with session locking, one profile per account holding up to 4 character slots, each a versioned table (level, stats, proficiencies, inventory, equipment, skins, Codex, quests, home, guild, rolls). Autosave every 60 s and on every teleport; a save on death that deletes the character and writes the Roll entry in the same transaction. Inventory and Crowns are never trusted from the client. World state (front line, Rolls, market) lives in its own DataStores with MemoryStore caches and `MessagingService` fan-out.

**Performance targets per place.** Under 60k parts and 1,500 draw calls loaded, server heartbeat under 12 ms with 8 players and 60 enemies, memory under 1.2 GB on PC and 600 MB on mobile. Run the MicroProfiler and `Stats` service checks in the Playground place before each gate and write the numbers into PROGRESS.md.

## 17. Online co-op architecture (2 to 8 players)

Roblox gives the server and the replication; Skyspire adds authority, a typed network layer, parties that survive teleports, and anti-cheat that assumes every client lies.

**Servers.** `MaxPlayers` 8 on every floor place. Friends can start a private server (Robux) or a free party server through the `ReserveServer` flow from the party menu. Join-in-progress is allowed anywhere except inside a boss chamber.

**Parties.** 2 to 8 players; one leader; shared XP within 200 studs; shared loot rules (section 13); shared quest progress for Board quests; the party list on the HUD. Party state lives in MemoryStore (`parties:<id>`) so it survives place teleports; teleports move the whole party with `TeleportAsync` and the party id in the teleport data. Two parties of four can merge into a raid of eight at the boss doors.

**Network layer (`src/shared/net/`).** A typed remote wrapper (write one or use ByteNet; record the choice) with: reliable remotes for actions, inventory, chat and trades; unreliable remotes for animation starts, positions beyond Roblox's own replication, telegraphs and hit-stop broadcasts; per-remote rate limits with a kick on sustained abuse; and a `serverTime` sync for clip clocks. All remote payloads are validated against a schema on the server before any handler runs.

**Authority.** The server owns HP, Guard Gauges, hits, kills, loot, Crowns, inventory, position validity, Shard effects, rolls and world state. The client owns animation, camera, VFX, input prediction and UI. An Art request from a client carries the Art id and facing; the server checks proficiency, slot, cooldown of the post-motion lock, distance to any target, and that the character is not dead, paralyzed or mid-Art; it then starts the authoritative timeline and broadcasts. Hits are server capsule sweeps per damage window (section 6).

**Anti-cheat basics.** Speed and teleport checks on `HumanoidRootPart` with root-motion allowances per Art; Art timing validation (an Art cannot be requested more often than its clip allows); hit distance validation with a 150 ms lag budget; server-only inventory and Crowns; trade and market transactions in DataStore transactions; roll logs; a shadow flag that routes suspected cheaters to Trial servers before any ban; never kick on a single anomaly.

**Raids.** At a boss door, the party leader starts a 30 s ready check; the group teleports to a reserved `BossArena` instance with the boss id, the floor, and the roster; Overwhelm and Duelist Protocol are decided from the roster size and the solo player's status at the moment the doors close; the fight, the Last Attack Bonus and the first-clear write-back all happen in that instance; the clear is broadcast experience-wide.

**Spectating.** Duels in towns and Duelist Protocol fights can be watched: spectators get a camera on the stairs of the chamber or the edge of the plaza, see the HP bars, and cannot interfere. Floor-clear fights are recorded as a replay stub (action log) for a later replay feature.

**Reconnection.** Profile session locks release on leave; a player who disconnects mid-fight stays in the arena as an idle character for 60 s (the party can cover them), then is removed; in Lucid, a disconnect is not a death, but an enemy can still kill the idle character.

**Social.** Friends list, guild chat, party chat, whisper, a floor chat with a 2 s slow mode, and Roblox voice chat where enabled. All chat goes through `TextService` filtering. Trade windows and guild invites are opt-in per player.

## 18. Narrative, companions, factions and quests

The story is told in moments, not cutscenes: a system line, an NPC's two sentences, a place that looks different after something happened. Write every line to be read in under four seconds. Melancholy, not grimdark; people are kind inside the Spire because the Spire is not.

**Premise (original).** Skyspire launched as the first full-dive world. On the first evening the sky turned red and the Architect, the game's designer, told ten thousand players that the headset would end their lives if they died here or if anyone removed it, and that the only way out was the top of the hundredth floor. The mirror item showed everyone their real face. Two years later the front line is floor 74 and the Roll of Names has four thousand lines. The player arrives in the last cohort to log in before the lockdown (the fiction for a new character after the first one).

**The first session (Floor 1, no text tutorial).** The login ritual; a field with boars that teaches movement and the first Art by placing the Art prompt only when the stance is right; a kobold that teaches guard and parry by holding its telegraph long; Brann waving the player over for a Switch on a boar pair; the walk into Firstlight at dusk; the announcement; the mirror. The Trial mode skips the announcement with a system line explaining why.

**Companions (story NPCs; they fight beside you in scripted quests, never as a permanent party member in Lucid)**

| Name | Role | Weapon | Analogue of the feeling |
| --- | --- | --- | --- |
| Sera Valdane | Vice-commander of the Ivory Vow, tactician, the best rapier in the Spire | Rapier (Lucent Needle) | The partner who Switches with you |
| Brann | Leader of Windfall, a six-person guild of friends; loud, loyal | 1H sword, bandana | The friend from the first day |
| Ogden | Merchant with a shop that moves up the floors; former axe fighter | Axe | The shopkeeper who knows everything |
| Thessaly "Tess" Rook | Smith; her forge is a home; will travel to the Labyrinth for an ingot | Mace | The smithing quest |
| Pip | Beastbond girl with Plume, her feathered wyrmling | Dagger | The pet that dies and comes back |
| Lumi | A child found in Gloamwood who does not remember logging in; a piece of the Warden | None | The lakeside family |
| The Castellan | Commander of the Ivory Vow, undefeated, an Aegis | 1H sword and tower shield | The final duel |
| The Grinning Man | Leader of Hollow Grin, never seen without the mask | Dagger | The red guild |
| Vorn Kibbet | Bulwark Legion officer who blames trialists for everything | 2H sword | The stigma |
| Old Niss | Fisherman on Mirrorlake who has never left the floor | Rod | The quiet episode |

**Factions.** The Ivory Vow (front-line guild, white and red, recruits by duel), the Bulwark Legion (floors 1 to 10, taxes, order, cowardice at the floor 25 raid), Hollow Grin (player-killer guild with a hidden base on floor 21; their quest line is a hunt), Windfall (the small guild the player can join first), the Trialists (a stigma, not a faction; several NPCs are secretly trialists).

**Floor story chains (one per floor; 4 to 8 steps; the launch set).** Floor 1: the first raid, assembling a party of strangers, the Sentinels' totems, the Mantle. Floor 2: a missing boardwalk crew, the Matriarch's nest. Floor 3: Pip's pet dies to an Ember Fox pack; the revival flower in the Labyrinth's hidden room. Floor 4: a smuggler on the lighthouse selling fake Mend Shards (teaches the trade window). Floor 5: Tess needs an ingot from the Iron Ram; the forge minigame; her shop opens. Floor 6: a murder in a safe zone that should be impossible; the sleep-PK trick; a Warded Object clue. Floor 7: the Legion's tax and Vorn's trialist purge. Floor 8: a frozen expedition and a lost guild's last stand (the Windfall tragedy beat, told in a found journal, not a cutscene). Floor 9: Lumi is found; she cannot be hit; she dissolves and is saved as an item for the Mirrorlake chain. Floor 10: the Warden's Knight, and the Castellan's first appearance at the doors.

**Later story floors (authored even if the floors are generated).** 21: the Hollow Grin hunt. 22: Mirrorlake, a cabin, Old Niss, the legendary fish, Lumi returns for a week. 25: the Silver Sovereign, the raid the Legion breaks on. 50: Nightfall. 55: the white wyrm's ingot and Glacier Edge. 74: the Stareblight Colossus and the first Meteor Cascade used in public. 75: the Ossuary Reaper, then the duel with the Castellan, the Aegis reveal, the Architect. 100: reserved; the ending is written with the user when floor 75 ships.

**Quest writing rules.** No fetch quest without a reason an NPC would actually have. No quest text over 60 words. Every chain ends in a place that changes (a lit lighthouse, a reopened bridge, a name on a stone). Deaths of named NPCs are permanent in the world state and are announced like player deaths.

**The Architect's lines.** Written once, kept short, used in the announcement, on floor clears every 25 floors, and in the final duel. He is calm, polite, and never explains himself.

## 19. Roblox project architecture and data pipeline

Code lives in git and syncs to Studio with Rojo. Places hold only world content. Everything that is a number lives in a data table. Everything that touches HP runs on the server.

**Repository layout**

```
skyspire/
  CLAUDE.md                  # points at docs/GAME_SPEC.md
  default.project.json       # Rojo project: src/ -> ReplicatedStorage / ServerScriptService / StarterPlayer
  wally.toml                 # packages: promise, signal, profile-store (loleris), t, fusion (if chosen), bytenet (if chosen)
  selene.toml  stylua.toml   # lint and format, enforced in CI
  aftman.toml                # tool versions: rojo, wally, selene, stylua, lune, run-in-roblox
  src/
    shared/
      data/                  # combat.luau, arts.luau, weapons.luau, armor.luau, enemies.luau, bosses.luau,
                             # floors.luau, loot.luau, quests.luau, origins.luau, paths.luau, apex.luau,
                             # palette.luau, lighting.luau, sfx.luau, assets.luau, naming.luau
      clips/                 # Choreo clip data: player/<weapon>/<art>.luau, enemies/<archetype>/*.luau
      net/                   # typed remote definitions and schemas
      types.luau             # all shared Luau types (Character, Item, Art, Enemy, Party...)
      util/                  # math, easing, spring, verlet, random, time sync
    server/
      services/              # CombatService, EnemyService, LootService, PartyService, SaveService,
                             # WorldStateService, QuestService, MarketService, RaidService, AntiCheatService
      ai/                    # archetype behavior modules, boss state machines
      gen/                   # Floor Generator, Labyrinth builder
    client/
      controllers/           # InputController, CharacterController, TargetController, UIController
      choreo/                # the animation system (section 10)
      camera/
      fx/                    # Shatter, Trails, Telegraphs, OutlineManager, Weather
      audio/                 # MusicDirector, SfxPool
      ui/                    # components, screens, HUD
  places/                    # Start.rbxl, Floor_001.rbxl ... BossArena.rbxl, ClipLab.rbxl, Playground.rbxl (Git LFS)
  tools/                     # PoseEditor plugin, capture script, data validators, asset id sync
  tests/                     # Lune unit tests (*.spec.luau), run-in-roblox smoke scripts
  docs/                      # GAME_SPEC.md, PROGRESS.md, DECISIONS.md, PLACEHOLDERS.md, STUDIO_TASKS.md, ANIMATION_REVIEW.md
```

**Code rules.** `--!strict` in every file. One module per responsibility; services expose a small API and communicate through Signals, never by reaching into each other's state. No `wait()`; use `task.*`. No `Instance.new` in hot loops; pool. All tunables come from `src/shared/data/`; a magic number in a gameplay script fails review. Public functions have a one-line doc comment. Errors are caught at service boundaries and logged with the player id; the server never crashes on a bad client message.

**Data tables.** Pure Luau tables with a validator per table in `tools/validate.luau` (run in CI): every Art has a clip, every enemy has an archetype and a skin asset, every floor has a boss and an Apex set, every weapon has a trail color from the palette, roll weights sum to 100. Tables are the source of truth for the wiki the game will need later.

**Testing.** Lune runs unit tests for everything pure (damage math, roll weights, loot tables, the Floor Generator's reachability, naming blocklist, clip data shape). `run-in-roblox` runs smoke scripts in the Playground place: spawn a character, equip a weapon, fire an Art, assert the server registered the hit, spawn each archetype and assert it telegraphs, teleport-stub a party. CI (GitHub Actions) runs StyLua check, Selene, Lune tests, validators and `rojo build` on every push; a red CI blocks a gate.

**Asset pipeline.** Meshes are authored in Blender (or sourced CC0, listed in `docs/ASSETS.md` with licenses) and uploaded by the user through Studio or the Open Cloud assets API; every uploaded id goes in `assets.luau` with a name, and `tools/assets.luau` reports missing ones. Until an asset exists, the game uses a part-built stand-in with the right size and the right `Highlight`, tagged `Placeholder`, and listed in `docs/PLACEHOLDERS.md`. Sounds follow the same flow. Fonts are uploaded by the user and referenced by id.

**Studio handoffs.** Anything you cannot do from the repo goes into `docs/STUDIO_TASKS.md` as a numbered checklist with exact steps: publishing places to the experience, setting `MaxPlayers`, enabling API services, enabling voice chat, uploading assets, setting the start place, creating the private-server product and cosmetic products, running the PoseEditor plugin to tune a clip. Keep the list short by doing everything else in code.

**Branching.** `main` is always publishable. One branch per phase, merged after the gate. Tag every gate (`phase-0`, `phase-1`...).

## 20. Build plan: phases and acceptance gates

Build the feel first, then the floor, then the tower. Each phase ends with a gate; a gate is met only when every line of its checklist is true in a recorded clip or a passing test. Do not start the next phase on a partial gate. Record each gate's result and the clips' file names in `docs/PROGRESS.md`.

1. **Phase 0: Foundations and the vertical slice (the feel).** Rojo project, Wally, lint, CI, Lune and run-in-roblox harnesses; data table skeletons with validators; the Playground place with a 400-stud field, a rim and a ceiling; the custom rig; Choreo with locomotion, Horizontal and Sharp Nail, hit-stop, trails and smears; one Charger (boar) and one Brute (kobold) with telegraphs; guard, parry, dodge; HP bars and the cursor; the shatter; the camera. *Gate:* a 20-second clip of a player fighting a boar and a kobold where every attack shows the six beats, the parry sparks, the kill shatters, and the server registered every hit; 60 fps in Studio; all tests green.
2. **Phase 1: Co-op combat core.** Party system, the network layer, Switch with the window ring and prompt, Tempo, Guard Gauge and Break, Mirror Shield on an Elite, server authority and anti-cheat basics, the full 1H Sword and Rapier Art lists, two more archetypes. *Gate:* two players in a test server kill a Mirror-Shielded Elite with a Switch chain; one player cannot; a cheat script that spams Arts is rejected; clips of every Art reviewed in ANIMATION\_REVIEW.md.
3. **Phase 2: Character and persistence.** Character creation with the three rolls and the announcement line, Lineage looks, the Dual Wielder rig and Twin Fang tier-1 Arts, Paths at level 10, ProfileStore saves with character slots, Lucid death with the Roll write and the Legacy slot, Trial servers, the inventory and equipment, the diegetic menu and the HUD. *Gate:* roll 10,000 characters in a Lune test and get weights within 0.2% of spec; a character dies in Lucid and is gone on rejoin with its name on the Roll; a Dual Wielder's silhouette is distinct at 100 studs in a clip.
4. **Phase 3: Floor 1 complete.** Firstlight, the plains, three threat bands, the field boss, a mini-dungeon, the Labyrinth from the kit, Grolak with all four bars and the Lockstep totems, the Last Attack Bonus, the floor-clear broadcast and the stairs, the first-session flow with the announcement, Floor 1's story chain, shops, the smith minigame, the Roll of Names and Roll of Honor monuments. *Gate:* four testers clear Floor 1 end to end on Lucid in one session; a solo tester with ordinary gear fails the boss to Overwhelm; a solo Dual Wielder in Floor 1 Apex triggers Duelist Protocol; performance numbers in PROGRESS.md are within section 16 targets.
5. **Phase 4: The remaining weapons and the economy.** All weapon categories and Art lists including Twin Fang through Meteor Cascade, enhancement with failure and breakage, tailoring, cooking, fishing, Appraisal and Searching, the market, housing with instanced interiors, guilds with emblems and uniforms, the cosmetic shop skeleton (no products live until the user says so). *Gate:* every Art in section 8 has a reviewed clip; a weapon reaches +15 and another breaks at +12 on camera; a home is bought, decorated, and persists.
6. **Phase 5: Floors 2 to 5 and the raid flow.** Four floors with their bosses, the BossArena reserved-server flow with ready check, two parties merging to eight, spectating, the Legion tax and Vorn's chain, Tess's forge chain, Pip and Plume, the Blood Moon and Gilded variants. *Gate:* an eight-player raid clears the Iron Bulwark Golem; a Blood Moon fires from a forced roll and every mob is an Elite; the weather and day-night cycle match across clients.
7. **Phase 6: Floors 6 to 10 and the Floor Generator.** Five floors, the Warden's Knight with forced Duelist Protocol, the Generator with all twelve kits, reachability tests, generated floors 26 to 30 playable, Castellan's first appearance. *Gate:* a generated floor builds in under 8 s on the server 100 times without a failed reachability test; Floor 10 is cleared by eight testers; a new player's first hour is watched and the tutorial-by-doing works without a single text box.
8. **Phase 7: Polish, mobile, launch.** Mobile layout and controls, quality tiers, accessibility settings, the login ritual at full fidelity, all placeholders replaced or listed with dates, music stems in place, the Studio task list completed by the user, a closed test with 50 players, bug triage. *Gate:* zero crashes in a 2-hour 50-player test; mobile holds 30 fps on a 2020 phone on Floor 1; PLACEHOLDERS.md is empty or dated; the naming test passes; the store page uses only Skyspire names.
9. **Phase 8 and on: Content cadence.** Floors 11 to 25 in groups of five with their stories, Mirrorlake, the Hollow Grin hunt, the floor 25 raid, Umbral Reign, then the story floors 50, 55, 74 and 75. Every content phase re-runs the Phase 0 clip review on anything new.

If a phase proves too large for one branch, split it and add a gate; never drop a checklist line to pass a gate.

## 21. Quality gates, self-review loop and hard rules

Before claiming any gate, run this list and paste the results into `docs/PROGRESS.md`. A "no" on any line means the gate is not met.

**Gate checklist**

- [ ] CI is green: StyLua, Selene, Lune tests, data validators, naming blocklist, `rojo build`.
- [ ] Every new clip is in `docs/ANIMATION_REVIEW.md` with the six beats marked present and the hit-stop tier noted.
- [ ] A recorded clip for every new Art, enemy and boss phase exists in `docs/clips/` and was watched at 0.25x.
- [ ] No T-pose, A-pose, frozen rig, popping limb or sliding foot appears in any clip.
- [ ] Every enemy attack in the phase has a wind-up of at least 0.3 s with a colored telegraph that reads from behind.
- [ ] The server rejects a scripted client that spams Arts, teleports, or reports its own hits.
- [ ] Part count, draw calls, server heartbeat and memory are measured in the Playground and are within section 16.
- [ ] `docs/PLACEHOLDERS.md` lists every stand-in asset with a replacement plan.
- [ ] `docs/STUDIO_TASKS.md` lists every manual Studio step the user must take, with exact menu paths.
- [ ] Every number introduced this phase lives in `src/shared/data/`, not in a script.
- [ ] Every new name passed the blocklist and is in the section 4 table or an addendum to it.
- [ ] The phase's story and quest text was read aloud and no line took over four seconds.

**Self-review loop (run after every feature, before the gate).** Play it; record it; watch it at quarter speed; compare it to the matching paragraph of section 2 and section 10; write three things that are worse than the anime and fix the worst one before moving on. Then ask: would a Swordburst player say this is better? If the honest answer is "about the same," it is not done.

**Hard rules (never break; if a request conflicts, stop and explain)**

1. No names, logos, designs, text, music or voice from the source franchise anywhere, including comments, test data and the store page.
2. Nothing purchasable affects stats, gear, rolls, drop rates or Crowns.
3. The server owns HP, hits, loot, inventory, rolls and world state; the client never decides damage.
4. No linear tweens on limbs; no attack without anticipation, hit-stop and recovery.
5. No death the player could not have seen coming; every killing attack had a telegraph.
6. No popups, tutorials or text walls during combat.
7. No infinite fights, no unreachable Labyrinths, no floor without an edge and a ceiling.
8. No placeholder ships silently; no gate passes with a missing checklist line.
9. Permadeath in Lucid is never softened by a feature that was not in section 7; the Legacy slot and the estate bank are the whole list.
10. Solo play is gated exactly as section 7 says. Do not add a "solo mode," a hireling, or a difficulty slider in Lucid.

## 22. Glossary

| Term | Meaning |
| --- | --- |
| Apex set | A floor's best-in-slot six pieces; wearing all six grants Apex status and the edge-light |
| Art (Blade Art) | A pre-choreographed technique with a start pose, activation, execution and post-motion lock |
| Archetype | An enemy behavior module (Charger, Brute, Skirmisher, Lancer, Swarm, Guard, Caster-beast, Stalker, Warden-construct) |
| Blight / Reach / Verge | The three threat bands of a floor's fields, hardest to easiest |
| Blood Moon | A 0.5%-per-night event: every mob becomes an Elite, Hollow Grin hunters spawn |
| Break | The state after an enemy's Guard Gauge empties: 3 s kneel, 2x damage, zero post-motion for Arts on it |
| Choreo | The client-side data-driven animation system |
| Crowns | The only currency |
| Duelist Protocol | A boss's one-on-one mode, triggered only by a Dual Wielder with Apex status alone in the chamber |
| Dual Wielder | The 1% origin with the Twin Fang skill line |
| Elite | A 1.5x mob with a Mirror Shield and a second attack |
| Gate (Teleport Gate) | The plaza pillar that teleports between cleared floors; a place teleport in disguise |
| Gilded | A 0.1% gold variant of any mob, 5x HP, guaranteed Rare |
| Guard Gauge | Poise, for players and enemies; empties into a guard break or a Break |
| Haven floor | Every fifth floor: a living floor with a bigger town and a quarter-mark boss |
| Labyrinth | The rim tower holding a floor's boss chamber |
| Last Attack Bonus (LAB) | The item given to whoever lands a boss's killing hit |
| Legacy slot | The one item a character wills to the account's next character |
| Lineage | The race-like creation roll (ten options, 1% to 16%) |
| Lockstep | A boss mechanic that needs two players acting within 1 s |
| Lucid / Trial | Permadeath mode (the game) / the training mode on separate servers |
| Mirror Shield | A barrier that only a Switch or a Twin Fang Art can break |
| Origin | The unique-skill creation roll (None, Ironhand, Beastbond, Flashdraw, Dual Wielder, Aegis) |
| Overwhelm | The boss buff when fewer than three players are in the chamber |
| Path | The chosen class-like template picked at level 10 |
| Post-motion | The lock after an Art's last hit |
| Roll of Names / Roll of Honor | The permadeath monument in Firstlight / each floor's first-clear plaque |
| Shards | Consumable crystals: Gate, Mend, Corridor, Cleanse |
| Switch | Landing an Art inside a partner's 0.8 s window: bonus damage, cut post-motion, interrupt |
| Tempo | Party stacks from chained Switches, max 5 |
| The Architect / The Warden | The antagonist designer / the system AI that runs the Spire |
| Twin Fang | The Dual Wielder's Art line, ending in Meteor Cascade (16 hits) and Umbral Reign (27 hits) |
| Warded | The system's purple "cannot be affected" state for objects and zones |
