# Studio tasks

Everything that needs Roblox Studio (or a machine with it) by hand, in the order to do it. Menu paths are for Studio
as of 2026; a path marked **(verify)** was written without Studio at hand and may have moved a tab. Tick the box and
note the date when you do one. Steps marked "done on the owner's PC" were run by a remote session on that PC
(Windows, Studio build `version-4f087c32742644ab` of 2026-10-14) with the repository cloned to
`Downloads\skyspire`; on another machine they still need doing. Steps 4, 24 and most of 25 are now done by the build
and the smoke scripts (D-039, D-038).

## A. First-time setup

1. [x] (2026-10-18, done on the owner's PC with Rokit 1.2.0) **Install the command-line tools.** Install [Aftman](https://github.com/LPGhatguy/aftman) (or Rokit), then in the
   repo root run `aftman install` (or `rokit install`). This gives you `rojo`, `wally`, `selene`, `stylua`, `lune` and
   `run-in-roblox` at the versions in `aftman.toml`.
2. [x] (2026-10-18, done on the owner's PC; `rojo plugin install` wrote `RojoManagedPlugin.rbxm`) **Install the Rojo Studio plugin.** In a terminal: `rojo plugin install`. Then in Studio: **Plugins tab > Manage
   Plugins** and confirm "Rojo" is listed and enabled. (Alternative: Creator Store > search "Rojo" > Install.)
3. [x] (2026-10-18, done on the owner's PC; `--install` copied it to `%LOCALAPPDATA%\Roblox\Plugins`) **Install the PoseEditor plugin.** `tools/build-plugin.sh` writes `build/SkyspirePoseEditor.rbxm`. In Studio:
   **Plugins tab > Plugins Folder** (opens your local plugins directory); copy the `.rbxm` there; restart Studio or
   **Plugins tab > Manage Plugins > (the plugin) > reload**. A "Skyspire" toolbar with a "PoseEditor" button appears.
   `tools/build-plugin.sh --install` does the copy on macOS and Windows (verify the folder it picks).
4. [x] **HTTP requests are allowed by the build** (D-039). `places/Playground.project.json` and
   `places/ClipLab.project.json` set `HttpService.HttpEnabled = true`; the shipped game (`default.project.json`) never
   does, and `tests/project/projectFiles.spec.luau` keeps it that way. Rebuild old place files with
   `tools/build-places.sh`. Check once: **Home tab > Game Settings > Security > Allow HTTP Requests** reads On
   (verify). The first PoseEditor **Save (server)** may show Studio's plugin permission prompt for `localhost`; allow it.
5. [ ] **Enable Studio access to API services** (needed by run-in-roblox smoke scripts that touch DataStores later;
   harmless now): **Home tab > Game Settings > Security > Enable Studio Access to API Services: On** (verify).

## B. Open and sync the dev places

6. [x] (2026-10-18, done on the owner's PC) **Build the places.** `tools/build-places.sh` writes `places/Playground.rbxl` and `places/ClipLab.rbxl` (gitignored,
   D-005). `rojo build default.project.json -o build/Skyspire.rbxl` builds the game without a world.
7. [ ] **Open the Playground.** Studio: **File > Open from File...** > `places/Playground.rbxl`. In a terminal:
   `rojo serve places/Playground.project.json`. In Studio: **Plugins tab > Rojo > Connect** (default `localhost:34872`).
   The project JSON carries the `DevCapture` Workspace attribute, so the Capture panel appears when you press Play.
8. [ ] **Open the ClipLab the same way** with `places/ClipLab.rbxl` and `rojo serve places/ClipLab.project.json`. The
   `ClipLab` attribute switches the review scene on; `Main.server.luau` / `Main.client.luau` are excluded from this
   place so no gameplay runs there.
9. [ ] **Play-test.** **Test tab > Play** (F5) puts your character on the field (Playground) or on the PlayerR15 pedestal
   with the Trialist Sword (ClipLab). **Test tab > Stop** (Shift+F5) ends it. Hotkeys for the dev panels are listed on
   the panels and in `src/shared/data/dev.luau` (none of them is a function key: F9 stays the Developer Console).

## C. The clip review loop (section 10)

10. [ ] **Run the pose server** before editing a clip: `lune run tools/pose-server.luau` in the repo root (it prints the
    URL; `--port N` overrides `dev.luau`). Leave it running.
11. [ ] **Edit a clip with the PoseEditor.** With the ClipLab (or Playground) open and synced, click **Skyspire >
    PoseEditor**. Type a clip id (`player/OneHandedSword/SharpNail`), **Load**. The rig on stage with a matching `Rig`
    attribute is posed as you scrub; or select a rig Model in the Explorer and press **Use selection**. Select a key,
    then a joint: Handles (move) and ArcHandles (rotate) appear on that joint's part; drags snap to
    `poseEditor.positionHandleStuds` / `rotationHandleDegrees`. **Save (server)** writes `src/shared/clips/<id>.luau`,
    runs StyLua and shows the validators' verdict; **Write Source** edits the module in Studio instead (Rojo two-way sync
    then writes the file; **Plugins > Rojo > Settings > Two-way sync** must be on (verify)). Then `git diff` the clip.
    (verify) that the joint `Transform` moves the rig in edit mode on your Studio build (the editor drives Motor6Ds and
    the `AnimationConstraint` joints of the upgraded avatar rig alike, D-041); if it does not, scrub in Play mode with
    the ClipLab instead and use the editor for the numbers.
12. [ ] **Review every attack in the ClipLab at 0.25x.** Play the ClipLab, pick the clip in the left list (Up / Down),
    `1` / `2` / `3` for 0.25x / 0.5x / 1x, Space to pause, `,` / `.` to step a frame, `R` to restart, `B` for the A/B
    with the rest pose, `H` toggles the hit-stop preview, Left / Right orbit the camera. The timeline bar shows the six
    beats, the hit windows, the trail / smear spans and the other events; the problems box lists the review-rule
    findings. Then fill the three hand columns of `docs/ANIMATION_REVIEW.md` (regenerate with
    `lune run tools/animation-review.luau`; your cells survive).
13. [ ] **Record the gate shots.** In the Playground press Play, then on the Capture panel: `[` / `]` pick the shot,
    `P` starts the 3-2-1 countdown (the panel hides, the frame counter runs bottom-left), `K` marks the shot done,
    `O` cycles the time scale, `H` hides the panel. Record with **View tab > Video Record** (verify; Windows Studio
    only) or any screen recorder, and save the file under the name the panel shows
    (`docs/clips/phase-0/<shot>.mp4`, see `docs/clips/phase-0/README.md`). Git LFS: `.gitattributes` tracks
    `docs/clips/*.mp4`; add a `docs/clips/**/*.mp4` line before committing files in the `phase-0/` folder (verify LFS
    is installed: `git lfs install`).

## D. Smoke tests and performance

14. [x] (2026-10-18, done on the owner's PC; rerun after every change to the server, the rigs or a smoke) **Run the smoke scripts** on a machine with Studio installed and logged in, with every Studio window closed
    (the script refuses to start otherwise): `tools/smoke.sh` builds the Playground and runs every
    `tests/smoke/*.smoke.luau` through `run-in-roblox` (on Windows use Git Bash by its full path,
    `"C:\Program Files\Git\bin\bash.exe" tools/smoke.sh`; a bare `bash` may be WSL's). `tools/smoke.sh --list`
    only lists them; `tools/smoke.sh perf` runs the ones whose name contains `perf`. run-in-roblox runs a script in a
    plugin in Edit mode, so each one is wrapped (`tools/smoke-wrap.luau`) into a runner that installs it as a server
    Script and starts a Run session (D-038). A script passes on its one `SMOKE-RESULT: PASS <name>` line; a failure
    prints the assertion or error that stopped it, and each run's full output is kept in `build/smoke/<name>.log`.
    First run on the owner's PC (2026-10-18): archetypes and playground passed; combat failed (the Horizontal never
    registered on the boar: the upgraded avatar rig has no body Motor6Ds, D-041, and a shapecast misses a boar the blade
    starts inside, D-042). After those fixes all six pass: archetypes, combat (the Horizontal lands on the boar for the
    section 6 damage), hitsweep, perf, playground and rigs. run-in-roblox exits 1 on archetypes, combat and perf only
    because Studio warns "Remote event invocation discarded ... did you forget to implement OnClientEvent?" when the
    server fires remotes with no client connected; the `SMOKE-RESULT` line is the verdict. Two more log lines are
    expected: the playground smoke's anti-cheat warns "system line failed: Unable to cast value to Object" after it
    kicks its stand-in (a stand-in is not a `Player`, so the kick line has no client to go to), and Studio's own
    MaterialManager plugin can print "debug.profileEnd() - No active profile annotation". Rerun after D-046
    (2026-10-18): all six pass.
15. [ ] **Measure section 16 numbers in the Playground** and paste them into the table in `docs/PROGRESS.md`. The server
    rows come from `tools/smoke.sh perf` (8 stand-ins and 60 enemies, `world.luau` `performance`): it asserts the
    95th-percentile server frame time and the part count and prints Markdown rows to paste. The rest needs Play mode
    (F5) by hand: **View tab > Stats > Summary / Render** for fps and part count, **MicroProfiler** (Ctrl+F6, or
    **View tab > MicroProfiler**) for draw calls and frame time (verify), **Developer Console** (F9) **> Server >
    ServerJobs** for the heartbeat time with real players (verify). Note what was on the field.
    The arc sub-sample cap went from 4 to 12 after that run (D-044): rerun `tools/smoke.sh perf` and keep 12 only if the
    server work stays at or under p95 2.72 ms and max 8.27 ms; otherwise set `combat.luau` `sweepMaxSubdivisions = 8`,
    rerun the smoke and `lune run tools/hit-matrix.luau --check`, and write both runs into D-044.
    Rerun on the owner's PC with cap 12 (2026-10-18): server work p95 2.01 ms, so 12 stays; the max of that run still
    goes into the table.

## E. Assets (as they arrive; see `docs/ASSETS.md`)

16. [ ] **Upload meshes and textures.** **View tab > Asset Manager > Bulk Import** (or the Creator Hub > Creations >
    Development Items), pick the files, wait for moderation, right-click > **Copy Asset ID**. Paste the id into
    `src/shared/data/assets.luau`, set `placeholder = false`, run `lune run tools/assets.luau` and remove the row from
    `docs/PLACEHOLDERS.md`.
17. [ ] **Upload sounds** the same way (Asset Manager > Audio, or Creator Hub); ids go into `src/shared/data/sfx.luau`
    as `rbxassetid://<id>` with `placeholder = false`. Audio over 6 s needs the place to be the uploader's (verify
    current audio permission rules).
18. [ ] **Fonts.** Pick the two fonts on the Creator Store (Studio: **Properties > FontFace > ...** opens the picker);
    copy the font family asset id into `assets.luau` (`SystemFont`, `SerifFont`) and `ui.luau` (verify how the family
    URL is referenced for Creator Store fonts).

## F. Publishing (not before the Phase 0 gate is met)

19. [ ] **Publish the experience.** **File > Publish to Roblox As...** > Create new experience named "Skyspire" (the game
    name; the repository's GitHub name is never used in Roblox, D-001). Publish `places/Playground.rbxl` as the start place
    for now; the ClipLab stays local.
20. [ ] **Keep it private.** **Home tab > Game Settings > Permissions > Private** until the user says otherwise.
21. [ ] **Max players.** **Home tab > Game Settings > Places > (the place) > Edit > Max Players: 8** (verify; section 17
    says 2 to 8 per server).
22. [ ] **Avatar settings.** **Home tab > Game Settings > Avatar > Avatar Type: R15**, body type and scale sliders
    locked so the anime proportions from `rigs.luau` apply (verify labels).
23. [ ] **Store page text** uses Skyspire names only (hard rule 1); run `lune run tools/validate.luau` on any text you
    paste into the repo first.

## G. Choreo (the animator; do before recording the gate clips)

24. [x] **The empty `Animate` script ships with the build** (D-039). Every project file puts an empty LocalScript named
    `Animate` in **StarterPlayer > StarterCharacterScripts**, so the engine never adds its default animation script,
    which writes `Motor6D.Transform` too and would fight Choreo; `tests/project/projectFiles.spec.luau` guards it.
    Check once in Play mode: your character has no running default `Animate` (Choreo also destroys the empty copy on
    the client) and its Humanoid keeps its `Animator`. Checked on the owner's PC (2026-10-18) by an automated solo
    Play session (a run-in-roblox script that starts Play through `StudioTestService` and reads the client): no
    `Animate` under the character, `Animator` present.
25. [x] **Confirm the joint names and the `Rig` attribute.** `tools/smoke.sh rigs` asserts this for a stand-in R15
    character (through the same `PlaygroundService` character path a player takes) and for every in-scope enemy rig
    (through `EnemyService.spawn`), from `rigs.luau`. On the owner's PC (2026-10-18) it passed: the stand-in carries the
    15 R15 joints as `AnimationConstraint`s (Avatar Joint Upgrade, D-041) plus the `Weapon` Motor6D, and the server's
    pose solve puts every part within 0.0001 studs of where the engine has it; the boar and the kobold match `rigs.luau`
    joint for joint. What is left by hand is your own avatar: in Play mode, select your character in the Explorer and
    check its joints (`AnimationConstraint`s on current Studio builds, Motor6Ds on older ones) are the 15 R15 joints
    `rigs.luau` lists plus `Weapon` on `RightHand`, with no extra joints from layered clothing or a custom body (Choreo
    ignores extras, but a renamed joint leaves that limb in its rest pose). An enemy whose `Rig` attribute is missing is posed as a player; the smoke
    catches that for the spawn path, so a mismatch seen by hand means something else replaced the model.
    Your own avatar was checked on 2026-10-18 by the automated solo Play session (step 24). The first run found the
    character never registered (no `Rig` attribute) and the sword gone, because the server prepared it before the
    engine had parented and dressed it; fixed by D-046. Rerun after the fix: the 15 R15 joints as
    `AnimationConstraint`s plus the `Weapon` Motor6D, no extra or missing joints (3 accessories), `Rig` = `PlayerR15`
    on the client and the server, registered as a fighter with 300 HP, and the scale values at `rigs.luau`'s
    1.08 / 0.92 / 0.95 / 1.06. Recheck by hand only if you change avatars to layered clothing or a custom body.
26. [ ] **Watch the write order.** In Play mode open **View tab > Script Performance** (verify) and confirm the
    Choreo RenderStepped step is the last thing that touches `Transform` each frame: a rig that snaps to rest for a
    frame means something else (an `AnimationTrack`, a plugin) writes after it.

## H. The sheathed sword (D-050; do before recording `locomotion.mp4`)

27. [ ] **Rerun the rigs and combat smokes** (`tools/smoke.sh rigs`, `tools/smoke.sh combat`). Rigs now also checks that
    `Sheath/Scabbard` is welded to UpperTorso by `ScabbardWeld` with CanQuery off and that a freshly registered
    stand-in has `Drawn` = false. Combat now also checks `Drawn` false, then true as the Horizontal starts, the `Weapon`
    Motor6D on RightHand at the strike, and `Drawn` false again about 6 s after the post-motion (about 7 s longer).
28. [ ] **Draw at 0.25x in the ClipLab.** Play `Draw` over IdleDrawn and over RunDrawn. The hand dips, reaches back over
    the right shoulder and takes the hilt behind it at 0.22 s, and the blade slides straight up out of the scabbard as
    the arm rises, with no edge through its side; the
    wrist turns a little on the grip, the blade swings out over the top and settles with its point a little higher
    than the drawn carry, with a small spring, then eases into the base's carry as Draw blends out. From 0.284 to
    0.295 s (between two frames at 1x, about three at 0.25x) the last 2 studs of blade leave the sheath by swinging over
    the mouth: note whether that reads as cutting through it.
29. [ ] **Sheathe at 0.25x.** Play `Sheathe` over Idle and over Run. Over Run the guard stays clear of the rising thigh at the
    start. The point swings in over the mouth at 0.36 s (about two frames at 0.25x) and the blade slides home; at 0.42 s the hand lets go with a snap and falls to the side. Fill the Draw and Sheathe cells of
    `docs/ANIMATION_REVIEW.md`.
30. [ ] **The hilt behind a real head.** With your avatar (hair and accessories on), watch from the side: the sheathed
    idle (the glance at 10 s), the walks, Run and Sprint. The hilt must stay behind the head, not through hair or ears.
    If it goes through, the mount in `weaponModels.luau` `sheaths.OneHandedSword` moves back and the Draw and Sheathe
    grab keys are solved again (ask in the project). Also watch from behind: the scabbard now lies 0.2 stud off the back
    (D-055); note whether it reads as worn or as floating, and whether its lower end touches the hips in RisingArc or
    the left leg in DodgeLeft.
31. [ ] **The arm rule in the Playground**, sheathed: lock on and at once turn in place; take a hit (Draw plays after the
    Stagger). In each, Draw plays after the other clip ends with no frame where the sword jumps from the back to the
    hand. Then lock on while sprinting and check that the hand meets the hilt.
32. [ ] **Two clients** (**Test tab > Clients and Servers > 2 Players**, verify), both near an enemy. Player A locks on
    and off and attacks while player B watches A's sword: B sees it draw, sheathe and draw-cut, with no one- or
    two-frame Draw flash before a draw-cut. Then A taps the lock key six or more times quickly and ends unlocked: A's
    sword sheathes about 6 s later.
33. [ ] **Footsteps, once real step sounds exist:** standing still is silent; walking, running and sprinting make one
    step per foot plant, drawn or sheathed; an idle enemy makes none.

## I. Play check after the pose rewrite, the sprint margin, walk pacing and the mount move (D-052 to D-059)

34. [ ] **The legs move in Play.** Pull the latest `phase-0`, build, open the Playground and press **Play**. Walk,
    run (W) and sprint (Shift + W) on flat ground: the knees bend, each foot lifts and plants, and a planted foot
    does not slide. Stand still: the body breathes and the sword sits on the back.
35. [x] **A long sprint is not kicked.** Sprint in a large circle for 30 s. No "anomalous movement" line appears and
    the session stays open. (Done 2026-10-20 on 6d6eb74: 32 s, 766 studs, no anti-cheat line.)
36. [ ] **The draw on lock-on.** Walk up to the kobold and lock on: Draw plays, the hand meets the hilt and the sword
    comes out; lock off and about 6 s later Sheathe puts it back.

Items 37 to 81 are one sitting, top to bottom: one solo Play of the Playground (37 to 71), one two-player test (72
to 80), then the ClipLab (81). Items 33, 34 and 36 above fit into it: do 33 with item 38, 34 with item 37 and 36 with
item 47. Items marked **(listen)** are judged by ear: wear headphones. A screen recorder that keeps the sound is
needed for the items that ask for a recording.

Setup: pull the latest `phase-0`, run `tools/build-places.sh`, open the Playground and connect Rojo (items 6 and 7),
then press **Play** (F5). The **Test** tab's Server/Client toggle switches between the two views (verify); open
**View > Command Bar** as well. The field is all grass and Phase 0 has no jump (Space is the dodge), so in the Server
view paste this once: it adds a slate slab at X 0, Z 40 (the spawn is at the middle) and a ramp up to a 4-stud ledge
at X -40, Z 0.

```lua
local s=Instance.new('Part'); s.Name='StoneSlab'; s.Anchored=true; s.Material=Enum.Material.Slate; s.Size=Vector3.new(40,0.4,40); s.Position=Vector3.new(0,0.2,40); s.Parent=workspace
local p=Instance.new('Part'); p.Name='Ledge'; p.Anchored=true; p.Size=Vector3.new(12,4,12); p.Position=Vector3.new(-40,2,0); p.Parent=workspace
local w=Instance.new('WedgePart'); w.Name='Ramp'; w.Anchored=true; w.Size=Vector3.new(12,4,16); w.CFrame=CFrame.new(-40,2,14)*CFrame.Angles(0,math.pi,0); w.Parent=workspace
```

The ramp's high end must meet the ledge; if it slopes the other way, set the Ramp's Orientation Y to 0 (verify). Then
switch back to the Client view for everything below. The enemies stand where `playground.luau` puts them: boar packs
of one or two at X 60, Z -40; X -90, Z 30; X 20, Z 110, and one kobold each at X -70, Z -50 and X 85, Z 45. A dead one
comes back after 20 s. The Arts are Q (Horizontal), 2 (Vertical), 3 (Rising Arc) and 4 (Sharp Nail); LMB is the
basic attack, RMB the guard, Space the dodge, F the lock-on and Shift the sprint.

37. [ ] **Feet stay planted at every speed (D-054; also item 34).** On the grass near the spawn, walk (hold guard,
    RMB, + W), run (W) and sprint (Shift + W) in straight lines and wide curves, sheathed and drawn (tap guard once to
    draw; the sword stays out about 6 s). Pass: each planted foot stays put on the grass while the body passes over
    it, and the steps quicken as the speed rises: no slow-motion walk at full speed, no flurry of steps at a walk.
    From standing into each speed, the first steps push off with no skate. Walk backward a few steps (S): the feet push
    off with no toe drag. Note any foot that scrapes the grass as it swings forward (the drawn walk and run are known
    to, D-054).
38. [ ] **Footsteps on grass and stone (D-051, D-089; also item 33) (listen).** Stand still for 5 s, then walk, run and
    sprint on the grass and then on the slate slab, sheathed and drawn. Pass: standing still is silent; there is one
    step per foot plant at every speed, a soft contact on the grass and a hard click on the slate; nothing steps while
    a dodge or a landing plays; an idle enemy makes no steps. Note whether one take per surface sounds like a machine
    gun at a sprint and whether the slate step sounds mechanical (`PLACEHOLDERS.md`, picks to improve 10).
39. [ ] **Stops (D-059).** Run and Guard-walk, and let go at random moments. Pass: the body takes one more step, slows
    and stands with both feet planted, not on one foot; nothing slides once it stands, and there is no hitch where the
    control script and the carry fight. Let go of W during a sprint: Skid plays. Let go of Shift only, still holding W:
    Skid plays as well; note whether that reads wrong (D-059). Let go of a run and press Space at once: the dodge steps
    back, not forward.
40. [ ] **Turns into a walk and landings on the move (D-059) (listen).** Stand still facing away from the camera, then
    press S: the character turns as it walks off, with no turn-in-place clip over the first steps. Run up the ramp
    onto the ledge and straight off its far side: the run carries on mid-stride with one landing thud and no crouch.
    Walk off the ledge and let go of the keys before you land: the landing crouch plays; walk off again and press W as
    you land: the crouch is cut short with no slide.
41. [ ] **Run and sprint look (D-054).** Run (W) for 5 s: the Run clip shows, never the Sprint lean, and drawn, never
    the low-and-back sword. Sprint: the Sprint lean shows. (The remote view is item 72.)
42. [ ] **Reversals and drawn turns (D-054, D-058).** Drawn and locked on (F) to a boar, walk backward (S): the walk-back
    plays, never a run. Unlocked, reverse direction at a run, sheathed and drawn: the turn reads as a turn with no long
    skate (note anything over half a stride). Drawn, run and swing round hard to the left, then to the right. In a
    recording watched at 0.25x from behind, the scabbard's lower end stays clear of the left leg, and the body leans
    into the right turns, and into the left ones until the side walk shows.
43. [ ] **Dev slow motion.** Press O (the Capture panel's time-scale key, `dev.luau` `capture.hotkeys`) until it reads
    0.5x, then walk and run: the feet stay planted. Press O until it reads 1x again.
44. [ ] **Ambience on the island (D-095) (listen).** Stand at the middle: the Plains birds play steadily with a faint
    wind under them, never twice over. Walk straight out to the railing (200 studs). Pass: from about 60 studs out
    (`fx.audio.ambience.rimBand.far`, 140 studs inside the edge) the wind starts to rise, slowly at first, and it is
    full within 15 studs of the railing; walking back, it falls to its faint floor. No click or jump in level anywhere.
45. [ ] **Ambience off the island and back (D-095) (listen).** Face the railing up close and step past it from the
    command bar (Client view): `local c=game.Players.LocalPlayer.Character; c:PivotTo(c:GetPivot()*CFrame.new(0,2,-8))`.
    Pass: as you fall, both beds fade out over about 2 s, and in the Explorer no Sound named `ambience.Plains` or
    `ambience.RimWind` under SoundService is still playing; after the respawn both fade back in over about 2 s.

## J. Hit feel and the real sounds (same Play, D-060 to D-102)

46. [ ] **The first hits of the session are heard (D-093) (listen).** Before any fight, look under SoundService in the
    Explorer: about 200 pooled Sounds (4 for each of the 50 preloaded names, named like `impact.Flesh`). Click
    `impact.Flesh`, `telegraph.Unblockable` and `enemy.ChargerDeath`: IsLoaded is true and TimeLength is above 0.
    Pass: the first basic hit, the first boar telegraph and the first kobold wind-up of the session (items 47 and 50)
    are all heard; write down any that is silent.
47. [ ] **Basic chain (D-069, D-082) (listen; do item 36 first).** Walk up to the kobold at X -70, Z -50 and lock on
    (F). Chain basic 1-2-3 (LMB three times) ten times, then swing five times quickly. Pass: each swing whooshes once,
    with the swing, swelling no later than about 70 ms after the hit spark (`whoosh.Basic` is a known late take: 54 to 69 ms, D-082); each
    hit plays the basic cue (crack, flesh, body and ring, the crack and body a little down) with no impact frames and
    no push in; the third swing ticks the Final click; no sound ends in a click or pop, and a quick swing never
    carries the tail of the one before. If a basic swing kills, the kill's slash line and ink strokes run along the
    swing, never back toward where it started.
48. [ ] **An Art's final hit, the look (D-060, D-066, D-071, D-072, D-096).** At the boar pack at X 60, Z -40, press Q
    and let the Art's last hit land; repeat with 2, 3 and 4, watching from behind and from above. Pass: on the final
    hit two frames of white figures on black, then the white flash on the target and the slash line in the world, and
    the view pushes in about 3 degrees and springs back. The crescent lies in the swing's plane, bulging away from
    you, never edge-on (turned at most 30 degrees toward the camera); Sharp Nail's stands upright along the thrust.
    The sword shows inside the white figure at its rest size, never the smear's stretch (D-066). A hit that kills shows the kill frames instead (item 54).
49. [ ] **An Art's sounds (D-074, D-075, D-077, D-082) (listen).** Record this one. Use each Art three times on any
    target, once with a quick tap and once holding the key about 0.8 s before letting go. Then cap the frame rate at
    20 fps (the graphics driver's per-app frame limit, or a low-end device) and use Vertical (2) five times. Pass: the
    chime plays as the stance completes; the reverse riser builds and stops at full level exactly on the first damage
    frame, for a tap and a 0.8 s hold alike, the first Art of the session included; each whoosh is loudest on the
    frame the hit spark appears, with no swell after the spark, none starting before the hold ends and none while the
    stance glows (at 20 fps too); each hit is one stacked hit, not a flam; on a final hit the bass drops out under the
    frames and the sub thumps back after the 6-frame hold; the long ring tail's dip is not heard as a second hit.
50. [ ] **Enemy strikes and telegraphs (D-081, D-082) (listen).** Stand about 6 studs from a kobold and let it do its
    Overhead three times (dodge out each time), then let a boar charge you three times. Pass, kobold: the yellow
    edge's two-burst tone and the growl from the start of the wind-up, the axe's whoosh swelling as it lands, the
    strike shout once on the strike frame, then the thud. Boar: the red edge's buzzer and the squeal over the 0.6 s
    crouch, and the strike snort once at the charge launch.
51. [ ] **Guard raise and guard break (D-097) (listen).** Hold RMB: the quiet raise plays once (no second one a moment
    later from the server). Keep holding through a kobold's Overhead. Pass: the guard-break crack with its sub, the
    block thud and the whoosh, and no clean flesh hit; the red fill shows on you with no white flash over it; one Final
    hit-stop click.
52. [ ] **Parry (D-060, D-071) (listen).** Let go of the guard, wait at least 0.25 s, then raise it (RMB) just before
    the kobold's axe lands (the window is 0.15 s). Pass: one cyan inverted frame, then the big rainbow-edged glint,
    the blade flash and the sparks right after it, not under it; the clash and its 2.5 s ring play as one clash with a
    long tail, and the ring's dip and swell is not heard as a second hit.
53. [ ] **Dodge (D-067, D-100) (listen).** Dodge four times each way (W, A, S or D, plus Space) on the grass and on the
    slab, then swing at a target for 5 s and dodge out. Pass: one whoosh per dodge; no landing sound at the start and
    one soft landing at the end; the quiet step about 50 ms after it does not read as a second landing (flag any
    double near 0.25 to 0.3 s); speed lines only at the screen edges, never in the middle third, gone within 0.25 s; no
    ring is cut short when the dodge ends a chain.
54. [ ] **Kills (D-060, D-073, D-079) (listen).** Kill a boar, then a kobold. Pass: a black beat, then white figures,
    then ink strokes on white; the kill's crack is heard at full; the death scream starts with the kill; about 10
    frames later everything goes silent (the birds and wind too) for 0.5 s with the body frozen; the shatter cracks as
    the silence ends, and its slam does not read as boom-boom. Note any dead-still hold after the death tremor fades
    (D-073). Then wear down both boars of a pack and kill one with Rising Arc's (3) first hit and the other with its
    second, about 0.4 s apart. Pass: both cracks at full; the first shatter stays quiet inside the second silence; the
    second silence lasts its full half second and ends on the second shatter.
55. [ ] **A pack in one sweep (D-098, D-102) (listen).** Bring a boar pack and a kobold together, 2 to 9 studs apart,
    wear one down, and sweep them with Horizontal (Q) so one dies (a pack of 6 needs a spawn tool the Playground does
    not have yet). Pass: one hit cue (no doubled crack or flesh), one push in, one camera nudge, one hit-stop click and
    one impact-frame picture, though the hits confirm over several frames; the kill's bass cut holds to its end; one
    death scream per enemy kind and one shatter crack; every target's glint, crescent and white flash appear after
    the black frames, never under them.
56. [ ] **Flash budget (D-061, D-063).** Record at 60 fps while chaining Arts and kills on everything in reach for
    10 s, then step through the recording a frame at a time. Pass: at most 3 full-screen flashes in any one second (a
    flash is a change to a dark or white picture and back), and a kill's frames are never replaced by a dim while
    nothing else flashed in the second before. Note the busiest second's count.
57. [ ] **Reduce flashing (D-062).** In the command bar run
    `game.Players.LocalPlayer:SetAttribute("SettingReduceFlashing", true)`, then land Arts and kills as fast as you
    can for 10 s with a white trail or the sky behind the target. Pass: only the soft dim shows, starting at most once
    in any second (a hit inside that second shows none), and the dodge's speed lines still show. Set it back to
    `false`: the frames return on the next final hit.
58. [ ] **Quality Low (D-065).** Run `game.Players.LocalPlayer:SetAttribute("SettingQuality", "Low")` and land a final
    hit and a kill. Pass: the impact frames still show the figures and the strokes, with fewer parts. Set it back to
    `"High"`.
59. [ ] **Volume balance (D-075, D-077, D-083) (listen).** Over the fights above: a hit, a crit, a final hit, a kill and
    a shatter step up in weight; a crit is brighter than a hit but not heavier; a final hit is heavier, with the sub
    after the hold; a kill is heavier again, with no bass under its frames; the shatter's slam is the loudest moment.
    Nothing distorts, and the kill's click stays audible over the final hit's.
60. [ ] **Low HP and your own death (D-079, D-083, D-095) (listen).** Let a kobold hit you until your HP is under 25%
    (75 of 300). Pass: one steady lub-dub fades in over about 1.5 s with no click at the loop seam (under SoundService,
    `ui.LowHpHeartbeat` shows Looped on and LoopRegion 0.18 to 1.12). Then let it kill you: your shatter has the
    deeper, louder bass dive of a player's death, the birds and wind drop out with the silence, and after the respawn
    the beds fade back in and the heartbeat is gone.

## K. Listening in the command bar (same Play, Client view)

A command-bar `require` gets its own module cache and does not see the game's sound pool, so these snippets make their
own Sound. Paste this helper once, and destroy each Sound (`s:Destroy()`) before the next:

```lua
_G.try=function(id,a,b,vol,speed,loop) local s=Instance.new('Sound'); s.SoundId='rbxassetid://'..id; s.Volume=vol or 1; s.PlaybackSpeed=speed or 1; s.PlaybackRegionsEnabled=true; s.PlaybackRegion=NumberRange.new(a,b); if loop then s.Looped=true; s.LoopRegion=NumberRange.new(a,b) end; s.Parent=game:GetService('SoundService'); if not s.IsLoaded then s.Loaded:Wait() end; s.TimePosition=a; s:Play(); return s end
```

61. [ ] **A region's end, and a start inside it (D-088, D-091) (listen).** Run
    `local s=Instance.new('Sound'); s.SoundId='rbxassetid://9119749044'; s.PlaybackRegionsEnabled=true; s.PlaybackRegion=NumberRange.new(0.34,0.55); s.Parent=game:GetService('SoundService'); if not s.IsLoaded then s.Loaded:Wait() end; s.Ended:Connect(function() print('Ended', s.IsPlaying, s.TimePosition) end); s.TimePosition=0.34; s:Play(); task.wait(0.5); print('after 0.5 s', s.IsPlaying, s.TimePosition)`.
    The Ended half is measured (2026-10-23, written into D-091: Ended fires at the region end and IsPlaying is false
    then); only the late-start half below is still open. Then run
    `s.TimePosition=0.45; s:Play(); task.wait(0.2); print(s.IsPlaying, s.TimePosition)`. Pass: only the last 0.1 s of
    the swish is heard and it stops at 0.55 (the late start's path).
62. [ ] **A start before the sound has loaded (D-092).** `telegraph.Tick` is not preloaded and nothing in the game
    plays it. Run
    `local t=Instance.new('Sound'); t.SoundId='rbxassetid://9113399659'; t.PlaybackRegionsEnabled=true; t.PlaybackRegion=NumberRange.new(0.085,0.32); t.Parent=game:GetService('SoundService'); print('TimeLength at Play', t.TimeLength); t.Ended:Connect(function() print('Ended', t.TimePosition) end); t.TimePosition=0.085; t:Play()`.
    Pass: TimeLength prints 0; the beep is heard from 0.085 once it loads and stops at 0.32. Note whether Ended
    prints.
63. [ ] **Loop seams (D-087, D-095) (listen).** `local w=_G.try(9113286782,0.3,11.5,1,1,true)` and listen for 30 s
    across the 11.5-to-0.3 seam, then `w:Destroy()`. `local p=_G.try(9119383684,2,125,0.36,1,true); p.TimePosition=120`
    and listen across the 125-to-2 seam, then `p:Destroy()`. Pass: no pop or gap at either seam.
64. [ ] **Heartbeat speed (D-083) (listen).** Compare `_G.try(1841124374,0.18,1.12,0.7,1,true)` with the same call at
    speed 1.2, then play the one you prefer on a phone speaker. Decide whether low HP should race (a pitch range of
    1.15 to 1.3 in `sfx.luau`, about 74 to 83 bpm) and write the answer into D-083. Pass: the chosen speed is still
    heard on the phone.
65. [ ] **The guard raise against the block (D-097) (listen).** `_G.try(9119075376,0.27,0.58,0.14)`, then
    `_G.try(9116673678,0.02,0.5,0.2)`. Pass: the raise does not read as a quiet block.
66. [ ] **Whoosh peaks (D-082).** Paste this; it plays each whoosh asset whole and prints the time of its loudest frame:
    `local function peak(id,len) local s=_G.try(id,0,len,1,1); local best,at=0,0; local c=game:GetService('RunService').RenderStepped:Connect(function() if s.PlaybackLoudness>best then best=s.PlaybackLoudness; at=s.TimePosition end end); task.wait(len+0.1); c:Disconnect(); s:Destroy(); print(id,at,best) end; peak(9119749145,0.96); peak(9119749044,0.9); peak(9126229280,1.45); peak(9119750698,3.08)`.
    Pass: each time is within 0.02 s of `sfx.luau` `peakAt` (Small 0.066, Medium 0.401, Large 0.234, Basic 1.199).
    Report any miss: the `peakAt` changes and the specs re-time the clips.
67. [ ] **The bass dive (listen).** `_G.try(1835344220,0.22,2.2,0.55)`. Pass: it dives in pitch over about 2 s.
68. [ ] **The slam, A/B (listen).** `_G.try(9125484367,0.07,1.2,0.9)`, then `_G.try(9120769331,0.29,1.3,0.9)` (Sonic
    Boom 1 from about 0.29 s). Pass: note which reads as one slam (the first swells again at 0.20 to 0.25 s); report
    it if Sonic Boom 1 wins.
69. [ ] **Death vocals (D-073) (listen).** `_G.try(9118314102,0.58,1.05,0.65)` (boar) and
    `_G.try(9113988191,0.04,0.76,1,0.88)` (kobold). Pass: the boar reads as a boar and the kobold as a kobold; with
    item 54 in mind, note whether the silence cutting each scream reads as intended.
70. [ ] **The reuses are distinct (D-081) (listen).** Compare `_G.try(9113634896,0.04,0.36,1,0.79)` (ChargerStrike)
    with `_G.try(9113634896,0.04,0.36,1,1)` (the snort); `_G.try(9118314102,0.58,1.05,0.45,1.17)` (ChargerStagger)
    with `_G.try(9118314102,0.58,1.05,0.65,1)` (ChargerDeath); `_G.try(9113988191,0.04,0.76,0.6,1.15)` (BruteStagger)
    and `_G.try(9113988191,0.04,0.76,0.75,1.01)` (BruteStrike) with `_G.try(9113988191,0.04,0.76,1,0.88)`
    (BruteDeath). Pass: each reads as its own sound, and no stagger is heard as a death (in the game too: items 50
    and 54).
71. [ ] **The Switch landing against the guard-break telegraph (listen).** A Switch does not land in the game yet (the
    server sends no `isSwitch`), so compare `_G.try(9116730789,0.12,0.45,0.3)` with `_G.try(9125673878,0,0.45,0.6)`.
    Pass: the Switch landing is not heard as a guard-break warning.

## L. Two players (D-054 to D-057, D-097 to D-102)

Stop Play, then **Test tab > Clients and Servers > 2 Players > Start** (verify); player A and player B are the two
client windows. Add the slab and the ramp again from the server window if you want them. Items 74 and 75 add lag with
**File > Studio Settings > Network > Incoming Replication Lag** (verify) on both clients; set it back to 0 after them.

72. [ ] **A remote run and sprint (D-054, D-059).** B runs and sprints in front of A for 10 s and stops a few times.
    Pass on A: B's rig takes the Sprint lean only while B sprints, with no flicker at a steady run, and its feet
    plant. B's stops slide as before (remote rigs do not run the stop carry, D-059): note how far.
73. [ ] **Guard taps and a remote draw-cut (D-056, D-057).** A, not locked on, taps guard about 10 times a second for
    2 s and lets go: about 6 s later A's sword sheathes on both screens (the server heard the last release). Then A,
    sheathed, attacks a boar: on B's screen the attack draw-cuts with no Draw flashing in first. Then A taps guard
    once, and about 0.3 s after letting go raises it into a kobold's Overhead: the parry sparks (the guard sender's
    burst of 2 sends the tap's release at once).
74. [ ] **Remote swings under lag (D-082, D-101) (listen).** Lag 0.1 s, then 0.15 s. B chains basic 1-2-3 and uses Q,
    2, 3 and 4 within 20 studs of A. Pass on A: every one of B's swings whooshes once, peaking with the swing as on B's
    own screen, never silent or doubled; every one of B's Arts lights the blade and chimes.
75. [ ] **A remote Art's riser (D-074, D-101) (listen).** Same lag. B uses each Art near A, once tapped and once held
    about 0.8 s. Pass on A: the riser ends on the first damage frame. Every remote clip plays at speed 1 until the
    server sends `ActionStarted.speed`; repeat with an Art at another speed once it does.
76. [ ] **A remote dodge, a remote guard and a bystander (D-070, D-097, D-100) (listen).** No lag. B dodges within 60
    studs of A, then 80 studs away; then B raises guard within 60 studs, then farther. Pass on A: B's dodge whoosh and
    guard raise are heard only within 60 studs, and A never sees speed lines for B's dodge. Then B walks 100 or more
    studs away and kills an enemy: A sees no impact frames, no push in and no full-screen dim.
77. [ ] **A cleave through two players (D-098) (listen).** A and B stand side by side in front of a kobold so its
    Overhead hits both, with B worn down so the blow kills B. Do it three times: A takes the hit, A parries, A holds
    the guard (it breaks). Pass on A: A's own hit, parry or guard break always sounds, at A's position, whatever
    happens to B.
78. [ ] **A player's heavy shatter (D-079) (listen).** Kill a mob near both players, then let B die near A. Pass on A:
    B's shatter has a clearly deeper, louder bass dive than the mob's (3 dB more) with the same slam, crack and chime,
    and each death plays one shatter. The Playground has no Elite or boss yet; check those when one spawns.
79. [ ] **Shatters far apart (D-102) (listen).** B kills a mob 150 or more studs from A at the same moment that A kills
    one next to A (count down together). Pass on A: A's kill shatters with its full crack. Then A kills both boars of
    a worn-down pack with one Horizontal: one shatter crack, not two.
80. [ ] **Remote Draw flash under jitter (D-057).** Run the Playground with two clients behind a network shaper that
    adds jitter (about 100 ms delay, 50 ms jitter). Studio's Incoming Replication Lag adds only fixed lag, which
    delays both messages equally and so does not show the flash. On client A, attack from sheathed 20 times. On client
    B, count how often the Draw shows before the attack starts. Report the count and the longest flash in frames.

## M. The ClipLab after the mount move (D-055)

81. [ ] **The re-keyed one-shots at 0.25x (D-055).** In the ClipLab, play DodgeLeft (now leaning 30 degrees),
    DodgeBack (18), DodgeForward, DodgeRight, TurnRight (the torso turns 24, the head 12 past it), TurnLeft, Skid,
    Stagger and GuardBreak. Then play the four flinches over Idle and IdleDrawn, Sprint (the left arm swings wider),
    the Idle glance at 10 s, RisingArc (the re-cock at 0.56 s), and Draw over RunDrawn and SprintDrawn (the point stays
    well above the grass). Each keeps its timing and snap, and the sheathed hilt and scabbard stay clear of the head,
    arms and legs. Note any that now look stiffer than before, in the hand columns of `docs/ANIMATION_REVIEW.md` (item 12).

## N. After the merge: leftover fixes and engine checks (D-103 to D-111)

All in the Playground (places/Playground.rbxl, or `rojo build places/Playground.project.json`) unless said otherwise.

82. [ ] **Default Animate removal.** Press F5 and open View > Output. Press Esc > Reset Character twice. Pass: no
    'Something unexpectedly tried to set the parent of Animate to NULL' warning; in Explorer, Workspace > <your
    player> has no Animate LocalScript once spawned; no default idle frame shows before the Choreo idle.
83. [ ] **Slash line placement.** Land an Art's final hit on a kobold (Q), then press Test > Pause at once. In
    Explorer open Workspace > FxSlashLines > SlashLine. Pass: the StartSystemWhite and EndSystemWhite attachments sit
    on either side of the hit point along the swing, the Core beam crosses the hit, and the two Edge copies (rose,
    cyan) sit one on each side of it.
84. [ ] **(optional) Far swing on Low quality.** Test > Clients and Servers, 2 players. In client 1's command bar run
    `game.Players.LocalPlayer:SetAttribute("SettingQuality", "Low")` and stand about 100 studs from client 2, who
    swings at a kobold (LMB). Pass on client 1: the crescent bulges along client 2's swing, not in a flat default
    direction.
85. [ ] **Jump-to-Fall under a hit.** Stand beside a Kobold Axeman holding RMB (guard). When it winds up, run
    `game.Players.LocalPlayer.Character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 50, 0)` in the client
    command bar (the Jump pose plays above choreo jumpVelocity). Pass: the guard hit (or a flinch) plays mid-air, the
    Fall pose still plays before landing, and the character never freezes in the Jump pose.
86. [ ] **Tab mash.** Lock onto a kobold (F), then mash Tab at about 4 to 10 presses a second for 10 s. Pass: no kick,
    no anticheat anomaly in the server Output, and at most 2 Switch prompts a second.
87. [ ] **Remote dodge landing (listen).** Test > Clients and Servers, 2 players. Set 100 ms incoming lag (File >
    Studio Settings > Network > Incoming Replication Lag = 0.1, or the Test tab's network simulator; verify). Client A
    runs (W) and dodges (Space) while client B watches from within 60 studs. Pass on B: the dodge's landing thud plays
    before or with the clip's footstep, never after it.
88. [ ] **Capture time-scale label.** Press O to cycle the time scale on the Capture panel (press H if the panel is
    hidden). Pass: it reads 'Time scale 0.5x (animation only: hit FX and sounds run at 1x)' at 0.5x, the same note at
    0.25x, and just 'Time scale 1x' at 1x; the line wraps inside the panel.
89. [ ] **Riser at 30 fps (listen).** Cap the frame rate at 30 (Esc > Settings > Maximum Frame Rate 30, or a low-end
    phone; verify). Hold Q for an Art that has a hold and release it onto a kobold. Pass: the riser's end and its fade
    land on the hit frame, not a frame after.
90. [ ] **Humanoid writes.** In the client command bar run `local h = game.Players.LocalPlayer.Character.Humanoid
    h:GetPropertyChangedSignal("WalkSpeed"):Connect(function() print("WS", h.WalkSpeed, os.clock()) end)
    h:GetPropertyChangedSignal("AutoRotate"):Connect(function() print("AR", h.AutoRotate) end)`. Run with W and let
    go. Pass: at most one WS print a frame during the stop carry, and no AR print unless a dodge or an attack locks
    movement.
91. [ ] **Sprint into a dodge, one landing (listen).** Test > Clients and Servers, 2 players; B watches A from within
    60 studs. A sprints (LeftShift + W) for 2 s and presses Space at once. Pass on B and on A: exactly one landing
    thud, at the end of the dodge (no Skid LandSoft about 0.18 s before the Dodge cue's). Repeat at run speed (W
    only): one thud. If two thuds sound, note how loud the first is.
92. [ ] **Remote opener from the sheath.** Test > Clients and Servers, 2 players; set B's incoming lag to 0.09 s (as
    in step 6). A lands no hit for 7 s so the sword goes onto the back (combatTagDuration 6 s plus sheatheDelay), then
    opens with LMB (Basic1) on a kobold while B watches. Pass on B: the slash crescent follows the blade's arc, not
    back over A's shoulder. Repeat at 0 lag for comparison.
93. [ ] **Stop carry without a controller (PC, then Device emulator phone).** (a) Press F5, sprint forward 2 s and
    release W. Watch Workspace > <player> > HumanoidRootPart.AssemblyLinearVelocity: it falls to 0 within choreo
    stopStepsSeconds (1.2 s), and Humanoid.MoveDirection reads (0, 0, 0) after the carry. (b) In Test > Device
    emulator (a phone), spawn and act with only a tap and the dodge button, never touching the thumbstick: the
    character never walks on its own. (c) During a run, run
    `require(game.Players.LocalPlayer.PlayerScripts.PlayerModule):GetControls():Disable()` in the client command bar,
    then release: the character stops and stays stopped.
94. [ ] **Impact overlay on a notched phone.** Test > Device emulator, iPhone 14 Pro (or another notched phone),
    landscape. Land a Kill or an Art final hit on a kobold and pause on the impact frame (Test > Pause, or 0.25x with
    O on the Capture panel). Pass: the white or ink fill reaches every screen edge, including the notch side and the
    rounded corners. Then hold the thumbstick through an impact frame: the character keeps moving and the stick does
    not drop.
95. [ ] **Highlight budget under a wide kill.** Before pressing F5, open ReplicatedStorage > Shared > data >
    playground and set the first KoboldAxeman spawn's packSize to { min = 35, max = 35 } (Studio only, never saved to
    the repo). Press F5, lock one kobold (F) and get a telegraph showing. Hit 6 or more unranked kobolds with a wide
    Art that ends in a Kill. Pass: during the white flash the locked target's outline and the telegraph's weapon fill
    stay visible.
96. [ ] **Impact-frame clone hitch (phone).** Test > Device emulator, a phone; open View > MicroProfiler. Land the
    session's first Kill and look for a spike on the impact frame (labels with Clone); then land a second Kill on the
    same enemy type and compare. Pass: no frame spike on the first impact large enough to read as a stutter; note the
    ms in PROGRESS either way.

## O. After the play-test: aim, console errors and the dev hooks (D-112 to D-116)

All in the Playground. Items 99 to 103 need the display awake (the lock turn runs on the render step).

97. [ ] **Rebuild and a clean console.** Rebuild the places (`tools/build-places.sh`, or
    `rojo build places/Playground.project.json -o <file>.rbxl`), open the Playground and press F5. Pass: View > Output
    has no "Cloud instance must exist under Terrain node", no "Failed to load sound rbxassetid://0" and no
    "ContentId: rbxassetid://0" line; in Explorer, Workspace > Terrain holds Clouds (Cover 0.55, Density 0.3) and
    Lighting holds none.
98. [ ] **Where rbxassetid://203785492 comes from.** It is in no repo file and no built place. During Play, search the
    content properties of every instance (server and client, CoreGui too) for 203785492; check the avatar's
    accessories and the installed plugins. Note the owner in docs/PLACEHOLDERS.md.
99. [ ] **Lock facing.** Walk away from a boar so the body faces away, press F. Pass: the body turns to the boar in
    about a quarter second, stepping round; A and D strafe round it facing it, S backs off facing it. Shift + W
    sprints with the body turned to the stick; letting go turns back to the lock. Dodge and guard still work, and a
    guard raised while locked faces the boar and blocks its strike.
100. [ ] **Swings land.** Locked on a boar, then a kobold, at about 5 studs: the basic chain three times, then Q.
    Pass: HP drops on every swing and View > Output shows no ActionRejected "Facing". Unlocked, with the boar about
    30 degrees off the body, swing: the body snaps to it and the swing lands; with the boar behind, nothing snaps.
101. [ ] **Lock and swing at once.** Facing away from a boar, press F and click at once. Pass: the swing comes out (no
    "Facing" rejection); note whether it lands, then whether the next swing does.
102. [ ] **The 40 degree snap at 0.25x.** Capture panel time scale 0.25x (O). Unlocked, boar 35 degrees off, swing.
    Pass: the turn reads as part of the wind-up, not a pop. If it pops, note it for a turn clip or a smaller snap.
103. [ ] **Strafe feet at walk speed.** Locked on a boar, hold D for 3 s at 0.25x. Pass: the WalkLeft/WalkRight feet
    do not slide visibly; if they do, note it for the stride tuning (D-054).
104. [ ] **(listen, later) Music stems.** Once real stem ids are in `sfx.luau` music.stemIds, walk into combat and
    out. Pass: the stems crossfade. Decide whether a stem resumes or restarts (Sound:Stop() rewinds it today).
105. [ ] **(optional) PlaybackLoudness lag.** Play a sustained sound, Stop() it and log PlaybackLoudness for the
    next 3 Heartbeats, and log the first 3 after a Play. The harness assumes 0 for 2 frames after Play; if real,
    item 66's peakAt readings are about 33 ms late.
106. [ ] **Dev hooks (D-114).** Press F5 and wait for the spawn. Each line is one execute_luau (or command bar) call
    in the context named; each returns JSON.
    - Server, trace on: `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("trace", {on = true}))`
    - Client, enemies with ids, distances and yaw: `local f = game.Players.LocalPlayer:WaitForChild("SkyspireDevAim", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("status"))`
    - Client, lock one (an id from status): `local f = game.Players.LocalPlayer:WaitForChild("SkyspireDevAim", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("lock", {id = 12}))`. If it replies faced = false (the display is
      asleep), turn with `local f = game.Players.LocalPlayer:WaitForChild("SkyspireDevAim", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("face"))`.
    - Client, swing through the real request path: `local f = game.Players.LocalPlayer:WaitForChild("SkyspireDevAim", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("swing", {kind = "basic", count = 3}))`, or
      `local f = game.Players.LocalPlayer:WaitForChild("SkyspireDevAim", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("swing", {kind = "art", slot = 1}))`; also `local f = game.Players.LocalPlayer:WaitForChild("SkyspireDevAim", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("guard", {held = true}))` and `local f = game.Players.LocalPlayer:WaitForChild("SkyspireDevAim", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("dodge"))`.
    - Server, why a swing missed (facing, the root's turn off it, the nearest enemy's distance, bearing and blade
      clearance): `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("events", {count = 10}))`
    - Server, the sweep alone with no client: `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("basic"))`, `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("art", {artId = "OneHandedSword.Horizontal"}))`,
      `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("hp"))`
    - Server, trace off: `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("trace", {on = false}))`
    - Server, hold every enemy now and every one spawned later (respawns too): `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("hold", {all = true}))`
    - Server, hold every enemy but one (an id from "hp"): `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("hold", {except = {12}}))`
    - Server, hold some, or release some: `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("hold", {ids = {12, 14}}))`, `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("hold", {ids = {12}, on = false}))`
    - Server, release everything and stop holding new spawns: `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("hold", {all = true, on = false}))`
    - Server, set one fighter's HP (clamped to 1 .. max, never a kill; a held enemy never regenerates, anyone else waits 8 s again before regen): `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("sethp", {entityId = 12, hp = 1}))`
    - Server, full HP (your own entity when no id is given, or any entity): `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("heal"))`, `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("heal", {entityId = 12}))`
    Pass: every client swing at a faced enemy reports hits > 0 and no rejection, and each server window prints one
    [DevCombat] line. Outside the Playground (no DevCapture attribute) neither BindableFunction exists.
    - Server, put yourself somewhere safely (the anti-cheat lets the move settle; facing in degrees, 0 = -Z, + = left): `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke("place", {position = {0, 3, -10}, facing = 180}))`
    "hp" shows held = true on each held enemy and its entityId is yours. A held enemy never walks or attacks, yet flinches, staggers and dies to hits, and its HP never climbs back. "sethp" with hp = 0 replies after = 1.

## P. Render stalls and the lock (D-117 to D-119)

107. [ ] **Render stalls and the lock across respawn.**
    (a) Display asleep: fight a boar and land a hit with impact frames, let the PC display sleep for about 55 s, then
    wake it. Pass: during the sleep (Client command bar) PlayerGui.SkyspireImpact.Enabled is false and no Rig folder
    under its ViewportFrame holds parts; nothing flashes on wake.
    (b) Minimise and restore Studio right after a hit with impact frames, then drag the window during a hit to cause a
    hitch. Pass: no stale black or white frame on restore; the camera neither jumps nor replays a shake or punch.
    (c) Print the first RenderStepped dt after a 5 s stall (a temporary LocalScript). Note in PROGRESS whether the
    engine reports one frame or the whole gap; the specs cover both.
    (d) Lock a boar, die, respawn. Pass: you respawn unlocked, swings do not aim at the old boar, and F locks again
    once the character is back. Note how long F does nothing after the respawn.
    (e) With the display asleep, let hits land (a kill shatter and parry sparks if possible), then wake it. Pass: no
    burst of sparks or shards plays on wake (ParticleEmitter:Emit during a stall is untested).
    (f) Reduce flashing on (SettingReduceFlashing true): with sleeps or hitches between hits, at most one dim a second.

## Q. A controlled fight (D-120 to D-124)

108. [ ] **A controlled fight.** In the Playground press F5 and wait for the spawn. Each step is one execute_luau (or command bar) call.
    Shorthand: S(cmd, args) is the Server line `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke(cmd, args))`. C(cmd, args) is the Client line `local f = game.Players.LocalPlayer:WaitForChild("SkyspireDevAim", 5); return game:GetService("HttpService"):JSONEncode(f:Invoke(cmd, args))`. The full one-liners are in item 106.
    Set up: S("hold", {all = true}), then S("hp") for the enemy ids, their distances and your entityId. A held enemy never regenerates HP, so a value set with "sethp" waits for the swing however long you take. A released enemy, and you, regenerate 1% a second after 8 s without a hit.
    (a) The kill sequence. S("sethp", {entityId = <boar>, hp = 1}), then walk to about 5 studs from that boar, C("lock", {id = <boar>}), C("swing", {kind = "basic", count = 1}) (or click). Pass:
        - S("hp") still shows hp = 1 for it however long the walk took.
        - The one swing kills it with the kill hit-stop, the Kill impact frames (black beat, white figures, ink strokes), the shatter and the death vocal.
        - Afterwards S("hp") lists it as Dead with held = false until its corpse goes about 4 s later, then not at all.
        - Its respawn about 20 s later shows held = true.
    (b) Sheathe after lock-off. Lock a held boar (F) and swing once so the sword is out. Clear the lock (F, or C("lock", {clear = true})) and stand still. Pass: about 6 s after the swing (the combat tag) the Sheathe clip plays once and the sword lands on the back with no pop. Nothing interrupts it, because the boar is held.
    (c) Item 103 (strafe feet): locked on a held boar, Capture time scale 0.25x (O), hold D for 3 s. Pass as item 103.
    (d) Item 99 (lock facing): walk away from a held boar until the body faces away, press F, then strafe with A and D and back off with S. Pass as item 99. The guard part needs a strike; do it in (g).
    (e) Item 101: facing away from a held boar, press F and click at once. Pass as item 101. Between tries, S("heal", {entityId = <boar>}) so it does not die.
    (f) Item 102: unlocked, a held boar 35 degrees off the body, 0.25x, swing. Pass as item 102.
    (g) The parry.
        1. Release one Kobold Axeman only: S("hold", {ids = {<kobold>}, on = false}).
        2. Run S("heal") so you are at full HP.
        3. Stand about 4 studs in front of it, lock it (F), and raise the guard (RMB) just before its strike lands.
        4. Pass: the parry's inverted impact frame, the parry sparks, its Parry reaction and the Switch window ring. A guard raised while locked faces it and blocks (the guard part of item 99).
        5. Then hold it again: S("hold", {ids = {<kobold>}}).
    (h) Item 107(d).
        1. Lock a held boar.
        2. Run S("sethp", {entityId = <you>, hp = 1}), then S("hold", {ids = {<kobold>}, on = false}) right after; you are not held, so your HP starts climbing 8 s after the sethp.
        3. Let the kobold land a hit (or press Esc > Reset Character), and respawn.
        4. Pass as item 107(d).
        5. Then S("hold", {all = true}) again.
    (i) (optional) Item 85 against the released kobold of (g).
    (j) Idle phase (D-123). Stand among a held herd at 1x for 10 s. Pass: no two neighbours sway in step; each Kobold roars once per 4 s idle loop, never in unison, and no roar sounds doubled.
    (k) A Kill drawn at a low frame rate (D-122).
        1. Client: `game:GetService("RunService"):BindToRenderStep("SkyspireSlow", 0, function() local t = os.clock() while os.clock() - t < 0.06 do end end)` (about 15 fps).
        2. Repeat (a) on another held boar.
        3. Pass: the Kill frames play (black beat, white figures, ink). The white figures never move while they show, even as the world starts moving under them, and the overlay is gone within about a quarter second.
        4. Then: `game:GetService("RunService"):UnbindFromRenderStep("SkyspireSlow")`.
    End: S("hold", {all = true, on = false}). Pass: every enemy wakes and fights again. Outside the Playground (no DevCapture attribute) neither BindableFunction exists.

## R. After the controlled fight (D-125 to D-131)

109. [ ] **Re-test item 107e (wake).** In Playground, let the display sleep, kill a 1 HP enemy with a basic swing, and leave a boar fight running about a minute; then wake. Expect no starburst behind the player, and every Workspace.FxGlints GlintAnchor Glint BillboardGui disabled at wake (not 3 s later). The ParrySparks and shatter flash emitters should show no particles at wake. Note whether the ~0.22 s render hitch about 2 s after wake is still there, and whether a stale whoosh or footstep sound or a small body jump comes at wake (known open issue: the Choreo stall replay).
110. [ ] **Re-test item 102 at 0.25x capture.** Unlocked, with an enemy 35° off at 4 studs, make one basic swing. Expect the body to turn over about 20 rendered frames (5 at 1x), with no single frame turning more than about 4° (about 13° at 1x). DevAim's swing yawAtSend should equal the request's facing, and hits should be unchanged.
111. [ ] **Item 102's 12° follow-up.** Run DevAim "status" just before the two-boar swing and note each boar's bearing and distance. If the second boar is about 23° off and nearer than about 5.3 studs, the 12° is the soft assist picking it (by design); otherwise report the numbers.
112. [ ] **Capture walk at 0.25x and 0.5x, in Studio.** Lock a boar, strafe left and right, walk forward and back, then let go of the stick. Expect the body to move at the slowed pace with feet planted (no 2-stud slide), the two-step stop to run slowed, and no anti-cheat flags in the server output. Press O to go back to 1x: full speed again. In the published Playground (live, STUDIO_TASKS 19) the time scale must only slow the animation; the body keeps full speed.
113. [ ] **Capture Art hold at 0.25x.** Hold an Art key for more than 0.5 s. The glowing stance should stay frozen (the 0.5 s re-apply no longer unfreezes it), and releasing it launches the Art.
114. [ ] **Capture run at 0.25x.** Run forward, then sprint, then curve. Expect the Run set (Sprint while sprinting) slowed with feet planted, not a fast walk (D-127 clockScale), and the turn lean to show on the curve.
115. [ ] **Lock-on strafe.** Lock onto a boar and hold A, then D, for 4 s each, sheathed and drawn. Check at 0.25x time scale that the planted foot stays put. Expected: Studio-criterion slide ≤ 0.02 and about 22 stances in 4 s. Also try W+A and W+D (expect ≤ 0.1 sheathed, ≤ 0.25 drawn) and S+A and S+D (≤ 0.12). Judge by eye whether the ~5.5 steps/s chassé reads as a quick guarded sidestep and not a scurry.
116. [ ] **Sheathe at 60 fps.** Draw, then sheathe, and frame-step the flip over the shoulder into the sheath. Expected: no frame moves the tip more than about 1.8 studs, the blade slides in with no teleport, and no edge pokes out of the back past the hilt.
117. [ ] **Direction snaps while locked.** Tap A to D, and W to A, at walkSpeed. Note any one-step foot skate; the probe shows up to about 1.9 studs on the first plant after a full reversal.
118. [ ] **Light stick tilt on diagonals while locked (gamepad).** Lock a boar and tilt the stick only slightly forward-right, then back-right (about 2 studs/s), sheathed and drawn. Watch for the trailing foot briefly tapping or scuffing the ground mid-swing with no footstep sound (the probe shows 0.12–0.23 s taps at ±22.5°, ±45° and ±157.5°), and report whether it is visible.
119. [ ] **Draw at 60 fps.** Frame-step a Draw. The probe has the tip moving about 3.4 studs in one frame near 0.45 s (unchanged from before). Report whether it reads as a whip or a pop; this decides whether Draw needs a tip-speed cap like Sheathe's.

## S. After the wake and feet round (D-132 to D-137)

120. [ ] **Render-stall wake (D-132).** In Playground with DevAim, swing two Arts and get a kill, then let the display sleep (or minimise the window) for at least 10 s. Wake it and confirm: (a) no Art chime, whoosh, footstep, trail or FOV kick plays on wake; (b) the character does not step or slide on the first frame; (c) the trail and activation light are off and the sword is in the right hand or on the back as before the stall.
121. [ ] **Render-stall wake, remote.** Repeat item 120 with a second player swinging nearby while the first one's display sleeps. On wake, the remote's Art does not replay.
122. [ ] **Normal play unchanged.** A full Art, a dodge and a kill hit-stop at 60 fps keep every sound, trail, kick and lunge distance. A forced 0.6 s hitch (heavy part spawn) is allowed to drop that span's one-shots and lunge.
123. [ ] **Wake into an action (D-132).** (a) Let the display sleep at least 10 s, then wake it by pressing the swing key. The swing plays from its start with its whoosh, trail and step forward: not skipped, not doubled. Repeat with the dodge key and expect the full dodge distance. If the waking key press never reaches the game, note that and go on to (b). (b) With a second player: have them start a swing just as the first display wakes. Separately, have them walk in from beyond 80 studs during the sleep and swing as it wakes. On wake their swing plays on with its sound and trail. (c) With a LocalScript, log the first RenderStepped dt after each wake and how far workspace:GetServerTimeNow() moved since the last frame before the sleep. Both should be about the gap; if GetServerTimeNow stood still, report it.
124. [ ] **Slowed capture re-measure (D-127, D-137).** Drawn and sheathed, at 0.5x and 0.25x: locked W on a boar 18 studs away; run 4.00, sprint 6.00 and a W+D curve. Expect 0.15 per stance or less with this scale-aware recipe:
   1. Each Heartbeat, record per foot the world position of the lowest corner of the foot part, and the capture scale s in use.
   2. Planted = height within 0.1 of that stance's lowest Y and |vy| < 1.5 × s studs/s. Equivalently, keep every round(1/s)-th frame so the samples sit at 1x spacing and use |vy| < 1.5.
   3. Slide per stance = the farthest horizontal distance of the planted corner from where it was at that foot's Footstep (before the Footstep, use its touchdown). Do not sum the path, which adds jitter.
   4. Skip the first 1.5 s of clip time (1.5 / s of real time) and anything within 0.3 s of a gait or lock change.
   5. Report, per foot, the median and max over at least 6 stances, plus stances per second of clip time (a merged stance shows as too few).
   6. Also log mixer:timeScale(), Humanoid.WalkSpeed and |AssemblyLinearVelocity| once a second to confirm the path is live.
   Note (D-144 round): Lune at 0.5x and 0.25x shows the following, identical on HEAD and after D-144: - sheathed run: L 0.068–0.090 (max 0.10), R 0.078–0.104 (max 0.11) - sprint ≤ 0.136; W+D curve ≤ 0.113 - 1.67–2.17 stances per clip-second Studio's R at 3.7 per clip-second is about 2.2× that cadence (split stances), and its L 0.20–0.22 depends on sampling phase. Re-run with the blank R15 avatar (no accessories or layered clothing on the feet), and log each Footstep time beside the stances.
125. [ ] **Locked drawn walk at 1x.** Lock on a boar about 7 studs ahead with the sword drawn, then W at walk speed: expect under 0.3 per stance (Lune: drag 0.03, plant 0.2). Repeat with Guard held.
126. [ ] **Walking into a held boar.** Hold a boar (DevCombat hold) and walk into it locked, with W. Each frame, log rootPart.AssemblyLinearVelocity, the root's position delta / dt and Humanoid.MoveDirection. Report whether the engine gives zero, the intended velocity while the root stays put, or a sideways slide along the flank. Lune: 0 / 0.23 / 1.1 per stance.
127. [ ] **Drawn gait look.** In ClipLab and in play, check the drawn forward walk, run and sprint: the legs now match the sheathed set (narrower than before), the sword point stays clear of the grass, and the 0.50625 s toe-off reads as a brisk walk. For the two-step stop from a drawn walk released early in the stride, expect an extra half step into the fighting stance.
128. [ ] **Half-stick walk (gamepad).** Push the stick half-forward (4–6 studs/s), both sets, and record the feet with item 124's recipe. This walk/Run cadence blend is known to slide 0.33–0.57 per stance in Lune and is not fixed; report whether it shows.

## T. After the controller round (D-138 to D-140)

129. [ ] **Art hold across a client hitch (D-138).** In Playground, press and hold Q. Within about 0.1 s, run a busy loop on the client with a dev LocalScript bound to another key (`local t = os.clock() while os.clock() - t < S do end`), and keep holding. (a) S = 0.6: right after the hitch the stance shows its hold pose with the blade lit, not mid-swing or finished, and the chime plays once. Release: the Art launches about as long after the release as a hold without the hitch does (compare 5 of each by eye or with a frame capture). (b) S = 0.3: the same, and no trail, smear or swing whoosh shows at the wake. (c) S = 1.5 (past the 1.0 s cancel time): no chime and no FOV kick at the wake, the stance relaxes to idle, and releasing Q fires no Art.
130. [ ] **Art hold across a display sleep (D-138).** Hold Q, minimise the window and restore it within about 0.7 s (inside the 1.0 s cancel time), still holding. The stance glows on restore, and the release launches on normal timing. Note whether the chime and FOV kick played while the window was minimised; today they fire in the dark when the timer freezes the hold.
131. [ ] **Root motion read in the frame it was stepped (D-139).** At 60 fps, dodge forward on flat ground with a temporary client log. Each frame, after the controller's render step, log the root's horizontal displacement since the press, and `ClipSampler.rootMotionAt(clip, handle.time)` minus `rootMotionAt(clip, 0)`. They agree every frame, with no one-frame lag. Repeat with a lunging Art.
132. [ ] **Rigs still animate (D-139).** The local character animates normally (idle, walk, sprint, guard, hit-stop freeze). Remote players and enemies still animate near and far, and the ClipLab character still animates.

## U. After the wake round and the blocked feet (D-141 to D-144)

133. [ ] **Dodge woken into (D-141, follows 123a).** Sleep the display and press dodge just before the wake. (a) The body travels 0 studs at the wake frame and the whole dodge over the frames after it. (b) The whoosh plays at the start of the travel and LandSoft at its end, and nothing plays in the dark. (c) Press about 1 s before the wake: nothing shows or sounds. (d) A normal dodge with the display awake is unchanged.
134. [ ] **Trail across a display sleep (D-142).** Sleep the display mid-Art, locally and while watching a remote player. The first presented or captured frame after the wake shows no trail streak, and trail.Enabled reads false within about 0.5 s of going dark.
135. [ ] **DevCombat place (D-143).** Use DevCombat place to move yourself 200 studs away and back, also with simulated replication lag: no [AntiCheat] flag appears. A client-side teleport of the same size made more than 1 s after the place still flags a teleport.
136. [ ] **Blocked body (D-144).** Check at 1x and at 0.25x capture, sheathed and drawn. (a) Hold a boar (DevCombat hold) and walk W into it, then into a wall. Within about 0.3 s the body stands in Idle (sheathed) or guard stance (drawn), with no walking in place. With the item 124 recipe, no stance slides more than 0.15 (stride.slideBar) after the settle. Lune max per stance: 0.11–0.34 when deflected (HEAD 1.29–1.74); 0.10–0.28 in about 2 stances for jitter only (HEAD 0.29–0.55 over 28–52 stances). (b) Hold W+A or W+D against the boar's flank so the body slides along it: the legs step sideways in the slide's direction, at its speed. (c) Let go of W: the body stands. Jump: a normal jump. (d) Walk away along the stick: a normal walk within one stride.
137. [ ] **Open ground unchanged (D-144 guard).** At 1x and 0.25x, check that these look and sound as before: start, stop, strafe under lock, 180° turn, sprint, a quick camera pan while running, and a jump. Then add a temporary client log on open flat ground. Each frame, record the angle between the root's horizontal AssemblyLinearVelocity and Humanoid.MoveDirection, during a 90° turn at a walk and at a run and during a straight sprint. Expect under 3° within 0.2 s of the stick settling, staying there. In Lune, a velocity that trails the stick by a time constant of about 0.07 s or more makes such a turn latch blocked for 3–5 frames (a one-frame pace dip). Report it if Studio shows that, or if the angle jitters past 3° on stairs or bumpy terrain.

## V. Hit on contact, camera and names (D-145 to D-164)

138. [ ] **Shadow band at B 9.13 (lighting check).** In Playground, select Workspace.Playground.Ceiling (the 900-stud Slate disc at y = 350) and set CastShadow off. Play the recorded path again: the band that pops in as the camera moves should be gone. No lighting.luau value explains the band. Future, ShadowSoftness 0.2 and GlobalShadows are standard, and no setting there controls shadow distance; the Ceiling is the only large caster over the field. If the band is still there, turn Lighting.GlobalShadows off for a moment to confirm it is a shadow, then find the caster and report it. Once confirmed, apply the place-file change (CastShadow false on the Ceiling).
139. [ ] **Camera framing (D-145, D-146, D-149).** On PC and in mobile emulation: (a) Free camera: the player stands left of center, the camera about head height with a shallow look down. (b) Lock a boar at about 3, 6 and 10 studs: both fighters are on screen side by side, and the target is never behind the player. (c) Lock on, release, and draw: each eases with no jump. Lock a target behind the camera: the camera eases around and never passes through the player. Report the fastest per-frame turn (Lune measured up to 6.6°/frame on a 180° lock). (d) Dodge back, locked and free: the lens never pushes into the player and the view does not tilt. (e) Kill the locked target: the camera eases out from where it stood. (f) Mouse look and the right stick do nothing while locked; after release the free camera continues from the lock's yaw. (g) Back against a pillar: the camera pulls in and keeps its view direction. Stand behind another player wearing hats, or turn your drawn sword toward the camera: no pull-in. (h) Lock a target standing on a ledge about 8 studs above you, and dodge left with the camera free: note whether your feet leave the bottom of the screen or your body reaches the screen edge (Lune: feet at −1.26 of the half height, body edge at 0.87 of the half width).
140. [ ] **HUD clear of the top bar (D-148).** In Studio's device emulator, check a notched phone, a tablet, a 4:3 tablet and a 1080p desktop. The HUD name and level sit fully below and right of the top bar's buttons, 24 px from the safe-area corner. Set HP low with DevCombat sethp: the low-HP vignette still covers the whole screen, under the top bar too.
141. [ ] **One name per enemy, death plate (D-147).** At every distance each enemy shows only our nameplate, never the engine's name or health bar. Kill one: the plate's HP bar empties and holds over the frozen rig, then disappears on the same frame the rig shatters. Check a boss: no plate at all. With a second player, note whether their name shows twice (see openIssues).
142. [ ] **Frame counts on screen (D-155, D-159).** Record at 60 fps and step frame by frame. A basic hit's white flash shows on exactly 2 frames. Hit-stop: Normal is still for 3 frames, Final for 6, Kill for 10. The Kill picture shows 2/2/2 and the Final picture 2. Repeat with the frame rate capped at 30.
143. [ ] **The flash on a boar (D-156).** Hit a boar during its red wind-up tint: white shows for 2 frames over the tint, then the tint returns. Hit it after its strike: it flashes white like any rig.
144. [ ] **Weapon-only activation flash and the cancel fade (D-157, D-161).** Hold an Art: only the sword flashes white, for 3 frames, and the body outline does not flash. Cancel the Art with a dodge: the blade light fades out over about 0.2 s instead of cutting off.
145. [ ] **The kill hold (D-150, D-151, D-152, D-154).** At 0, 100 and 250 ms of incoming replication lag, finish a boar with SharpNail. The flash and sound land on the frame the blade touches, and one 10-frame still follows. There is no second still at snap 2, and the confirm never adds a second freeze. Also do a kill the client cannot prove (the boar regenerating): the 3-frame hold runs on to 10 when the confirm arrives in time.
146. [ ] **Sound through the silence (D-158).** Kill an enemy, then swing, dodge and walk during the death silence. Your own sounds play at full while the music, the beds, other fighters and the UI stay down. Moving the SFX slider changes both.
147. [ ] **The snap and the trail (D-153, D-160).** Basic1–3 and SharpNail: each cut reads over 2 or more frames, not 1. The trail never draws a streak from the last cut's blade when the next window opens, including across SharpNail's hold.
148. [ ] **Hits across a hitch and a stall (D-163, D-164).** (a) Mid-SharpNail on a boar, run the item 129 busy loop for about 1.2 s right after a cut lands. At the wake each hit shows once: one number, one hit sound, one still, and no second still or kill cue. Repeat with the boar at kill HP. (b) Minimise the window for about 1 s just before a SharpNail cut lands, then restore it. No flash or hold plays at the wake for the cut that was never drawn. If the server registered that cut, its number and moment play once when the confirm arrives.
149. [ ] **A later cut's hold (D-162).** With about 250 ms of incoming replication lag, stand two boars side by side. Set the near one to low HP and let it regenerate (DevCombat sethp), so the client cannot prove the kill. Swing SharpNail so its first cut finishes the near boar and a later cut hits the far one. The later cut's still keeps its own length (3 frames Normal, 6 Final). The near boar's late Kill confirm plays its kill sound and picture but adds no still to the later cut.

## W. Enemy attacks on the server's beat (D-165 to D-182)

150. [ ] **Bodies turn (D-165).** Aggro a boar and a kobold and circle them. The whole body turns at the slow Charger or Brute rate, and every strike faces you.
151. [ ] **Rush on contact (D-166).** Stand about 10 studs down a boar's line: the hit lands when the snout reaches you. At the line's end it lands late in the run (by 0.5 s). Step in behind the boar after it has passed: no hit. Dodge through the snout: one dodge per rush.
152. [ ] **Rush passes through (D-167).** Stand still in the line. The boar passes through you on the client and on the server view (Current: Server): no jam, no slide. A packmate in the line is passed too. A boar that stops overlapping you is never pushed upward, and it collides again once clear (you cannot walk through a walking boar).
153. [ ] **Groups registered (D-167).** Output shows no "[CollisionGroups] registering the fighter groups failed" and no "[Main] collision groups failed". The Collision Groups editor shows Rushing unticked against Players, Enemies and Rushing, and everything else ticked.
154. [ ] **Character group (D-167).** After spawning and after a respawn, the body parts, the sword and the accessories show CollisionGroup SkyspirePlayers.
155. [ ] **Hit-stop pause (D-168).** Hit a kobold during its overhead wind-up with a combo ending in an Art. The chop lands after the freeze, at the telegraph's end, and never before the clip's strike frame. Same for a boar's crouch. A launched rush never freezes.
156. [ ] **Rush timing under lag, server side (D-169).** With Incoming Replication Lag 0.2, the boar's snout reaches you on the frame the hit lands. Item 158 has the full client check.
157. [ ] **Spawns spaced (D-170).** Start the Playground 5 times. No two enemies overlap and no boar stands on another (every root at about Y 2.85). Stand on a boar spawn point and let a boar respawn there: it appears at least 12 studs away.
158. [ ] **Rush under replication lag (D-171).** In Playground (Play Solo), set File > Studio Settings > Network > Incoming Replication Lag to 0, then 0.2, then 0.5.
   (a) Stand 7, 10 and 14 studs in front of a Frenzy Boar and let it charge.
   (b) Pass: the tusks reach you as your HP drops (the number may trail by the lag).
   (c) The boar never jumps at its launch or at the end of its run, and the root box is never seen apart from the body.
   (d) After the skid, the body slides back onto its root without a pop.
   (e) Repeat with a wall about 9 studs down the line (a jam), and with a hit that staggers it mid-rush.
   (f) Note whether the nameplate and camera trail the body (a known open issue).
159. [ ] **Chop after 0, 1 and 4 hits (D-172, D-176).** Use Incoming Replication Lag 0.1 and a Kobold Axeman Overhead.
   (a) Land no hit, then one basic hit about 0.4 s into the wind-up, then four hits spread across the wind-up.
   (b) Pass: the chop lands as the telegraph finishes and your HP drops with it.
   (c) The rig freezes only for each hit's 3 frames.
   (d) With six or more hits, the chop comes at most 0.25 s later than with none.
   (e) When the chop hits you, there is one still at the impact, not a second freeze in the rebound.
160. [ ] **Flinch during the wind-up (D-173).**
   (a) Hit the Kobold 0.9 to 1.3 s into its wind-up, from the front, back, left and right. The body recoils, but the raised axe stays up with no dip that reads as a chop, and the real chop follows on its beat.
   (b) A hit during its recovery plays the full flinch.
161. [ ] **Nameplates across a respawn (D-177).**
   (a) In Playground, with enemies alive and one enemy just killed (in its freeze), reset or LoadCharacter.
   (b) Every plate stays over its rig, and PlayerGui.SkyspireNameplates is back within a frame.
   (c) The dead enemy's plate still leaves with its shatter, and your own player plate is back.
162. [ ] **No engine labels (D-178).** On a two-player test server, look at the other player from near and far. There is no engine name or health bar, before and after either player respawns.
163. [ ] **Plate on the shatter frame (D-147, amended).** Kill a boar and step frames, or record at 60 fps. The plate disappears on the same frame as the white burst and shards.
164. [ ] **Dodge hop (D-179).** Record each dodge direction at 60 fps.
   (a) The first 2 to 3 frames read as a snap, not a teleport or a slide.
   (b) The body lean, which now also eases QuadOut on that key, still lands crisply.
   (c) Compare the camera on a back dodge, free and locked.
165. [ ] **Contact-frame nudge (D-180).** Hit a boar with Horizontal and step frames. The nudge and shake start on the frame the blade meets the body, not one frame later, and there is no double kick against ImpactFrames.
166. [ ] **Sideways dodge framing (D-181).** Dodge left and right, free and locked. The player stays near their spot on screen (about 0.1 of the half width in Lune). Judge whether the world sliding about 1.5 studs in one frame during the hop feels harsh; if it does, tune camera.follow.leash.side between 0.75 and 1.5.
167. [ ] **High-target feet crop.** Lock onto a target 8 studs above the player (a ledge). Measured in Lune, the player's body column spans y −1.47..−0.32 of the half height, so the feet are below the frame. For comparison, a target at +4 studs gives −1.06..−0.05, and a level target gives −0.73..0.21. Decide whether this is acceptable or the two-shot needs a cap on how far its aim rises. A cap needs code plus a new camera.lock key; changing focusBias would also move the level two-shot.
168. [ ] **Shadow band after the Ceiling change.** Run this once the Ceiling place-file change (CastShadow false) is applied. It is the same check as item 138: replay the B 9.13 path, confirm the band is gone, and mark item 138 done.
169. [ ] **Strike on the beat (D-182).**
   (a) Add a temporary server log of each enemy strike's HitConfirmed time minus (the Telegraph's serverTime + windUp + strike + the attackPause total of the hits on that attack).
   (b) Against a Kobold Overhead, with and without hits during the wind-up, the value is between 0 and about 0.067 s every time, and never negative.
   (c) Against a boar, log RushStarted.serverTime minus (Telegraph serverTime + windUp + pauses): it is 0.
   (d) With Incoming Replication Lag 0.2, stand 7, 10 and 14 studs down a boar's line. HP drops within 3 frames of the drawn tusk contact and never before it.
   (e) In the open the boar still runs its full 22 studs and never reports Jammed.

## X. Strikes on the frame, smooth turns and the ceiling shadow (D-183 to D-192)

170. [ ] **Hold and release a lined-up boar (D-183).** In Playground with the dev hold, hold a boar about 15 studs from you, lined up, for 3 s or more, then release it.
   (a) It rushes straight down its telegraph line: no step back, no Jammed end.
   (b) Repeat the a1 setup three times (hold, stand 14 studs in front, release, step to 12 studs at the wind-up): no Jammed end.
   (c) Repeat with the boar held on a slope and next to a pillar.
171. [ ] **HP drop on the beat (D-184).**
   (a) Stand in a kobold's Overhead with 0, 1 and 3 hits landed during its wind-up. Your HP drops on the frame the telegraph ends, never before it.
   (b) Let a boar rush you from 7, 10 and 14 studs: the HP drop comes at snout contact.
   (c) If you can, repeat with the server capped at 30 fps.
172. [ ] **Smooth turns (D-185).** Watch a kobold chase and a boar wheel around you. The body turn looks smooth, with no 8° snaps. The boar's crouch line leaves from its snout, with no turn after the line appears.
173. [ ] **No ceiling shadow (D-186; closes items 138 and 168).** Build the Playground from the place file.
   (a) At midday and at a low sun, the field and the players are lit and characters cast normal shadows.
   (b) Replay the B 9.13 path: the band is gone. Mark items 138 and 168 done.
174. [ ] **Archetype smoke with the frame pass (D-184).** Run `tools/smoke.sh archetypes` in Studio and confirm it passes.
175. [ ] **Plate and body on the same frame (D-187).** Kill a boar and a kobold with a basic swing and with an Art's final cut. On a second client, watch a remote player's kill. Step the capture frame by frame: the plate and the body's parts go on the same rendered frame (at c73cfa8: plate 0.834 s, body 0.852 s).
176. [ ] **Launch head lift (D-188, D-189).** Watch a boar's launch from the side at 0.25x, with Incoming Replication Lag 0, then 0.1 to 0.2 s.
   (a) The head lift (about 1 stud on the first frame, about 2.5 studs over 3 to 4 frames) starts on the frame the body starts running, never a frame before.
   (b) Note whether it reads as a burst or a pop.
177. [ ] **Plate during a rush (optional).** During a boar's rush, and a death mid-rush, note where the plate sits against the drawn body. It follows the root, up to about 7 studs behind at 0.25 s root lag.
178. [ ] **A jammed rush never carries you (D-190).** Add a temporary server log, per Heartbeat, of the boar root's CollisionGroup and velocity, and a client log of your root's position.
   (a) Run the a1 setup three times. Then run three rushes with a pillar or wall a few studs down the boar's line so it jams (as in item 158 (e)). Stand still on the line each time.
   (b) Pass: a jammed boar stops where it jammed, and you are never pushed or lifted. Its root returns to SkyspireEnemies about 0.5 s after it stops, and never while it overlaps you.
   (c) Stand at the end of a clean run's line (about 22 studs) so the boar stops on you. It stays SkyspireRushing until you step off, then turns solid about 0.5 s later. You are never lifted.
   (d) Repeat (a) with Incoming Replication Lag 0.2.
179. [ ] **Plate across a render stall at the shatter (D-191).** Kill a boar. During its 0.67 s freeze, drag the Studio window for about 0.5 s, then for about 1 s, so the stall spans the shatter. Pass: when frames resume, the plate and the shards go on the same frame; the plate never vanishes while the body still stands.
180. [ ] **Jumping onto an enemy (D-192).** Jump onto a standing boar's back and onto a kobold. Report whether you can stand there, for how long, and whether the enemy's movement carries you. This decides whether the slide-off follow-up is needed.
