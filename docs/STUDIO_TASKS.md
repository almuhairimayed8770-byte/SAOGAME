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
13. [ ] **Record the gate shots.** In the Playground press Play, then on the Capture panel: `[` / `]` pick the shot, Its K step is superseded by item 229.
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
49. [ ] **An Art's sounds (D-074, D-075, D-077, D-082) (listen).** Record this one. Use each Art three times on any Its final-hit bass check is superseded by item 247.
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
116. [ ] **Sheathe at 60 fps.** Draw, then sheathe, and frame-step the flip over the shoulder into the sheath. Expected: no frame moves the tip more than about 1.8 studs, the blade slides in with no teleport, and no edge pokes out of the back past the hilt. Superseded by item 213.
117. [ ] **Direction snaps while locked.** Tap A to D, and W to A, at walkSpeed. Note any one-step foot skate; the probe shows up to about 1.9 studs on the first plant after a full reversal.
118. [ ] **Light stick tilt on diagonals while locked (gamepad).** Lock a boar and tilt the stick only slightly forward-right, then back-right (about 2 studs/s), sheathed and drawn. Watch for the trailing foot briefly tapping or scuffing the ground mid-swing with no footstep sound (the probe shows 0.12–0.23 s taps at ±22.5°, ±45° and ±157.5°), and report whether it is visible.
119. [ ] **Draw at 60 fps.** Frame-step a Draw. The probe has the tip moving about 3.4 studs in one frame near 0.45 s (unchanged from before). Report whether it reads as a whip or a pop; this decides whether Draw needs a tip-speed cap like Sheathe's. Superseded by item 212 (D-219 gives Draw a cap).

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
142. [ ] **Frame counts on screen (D-155, D-159).** Record at 60 fps and step frame by frame. A basic hit's white flash shows on exactly 2 frames. Hit-stop: Normal is still for 3 frames, Final for 6, Kill for 10. The Kill picture shows 2/2/2 and the Final picture 2. Repeat with the frame rate capped at 30. Its the impact-picture counts are superseded by item 305.
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

## Y. Rush followers, jam line and late paths (D-193 to D-198)

181. [ ] **Plate and SWITCH over a charging boar (D-193; replaces item 177).** Set Incoming Replication Lag to 0.25 s, then 0.5 s.
   (a) Lock a boar and let it charge past you, at 0.25x capture and at 1x. Pass: the plate stays over the boar's back for the whole run.
   (b) Kill one mid-rush. The plate stays over the frozen body until the shatter.
   (c) Parry one mid-rush. SWITCH sits over the staggered body, and both slide back with it at the hand-back, with no jump.
182. [ ] **Lock camera on a charging boar (D-193).** Use the same lag as item 181. Pass: the boar stays inside the frame for the whole run.
   (a) Step frame by frame and note whether the framing is a frame behind the body's motion. That would mean Choreo's RenderStepped runs after the camera (measured worst: 0.9 studs / 3.9°). Superseded by item 194.
183. [ ] **Nothing of the hidden parts shows (D-193, D-198).**
   (a) During a rush, the Highlight outline and the shadow never draw the boar's hidden 2.4×2.4×5 root box where the root trails behind the body.
   (b) While a boar and a kobold telegraph (outline and tint) and while they stand, at midday and at a low sun, there is no outline or shadow of the 7-stud blocker box.
184. [ ] **Legs at the end of a rush (D-193).** With 0.5 s of lag, watch the frames after the rush clip ends while the hidden root catches up (Settle and HandBack). Note whether the legs run in place on a body that has stopped. Superseded by item 193.
185. [ ] **Free-rush lag under keepUpStuds (D-195).** On flat ground, log a real boar's free-rush lag every server frame: speed × (now − bodyStartedAt) − progress.
   (a) It must stay below keepUpStuds (1). If it does not, hits land late.
   (b) If it stays well under, lower keepUpStuds to shrink the remaining gap.
186. [ ] **A rush into a wall hits only what it reaches (D-195, D-197).** Use anchored walls across the boar's line. Distances are measured from the boar's root at its crouch along the telegraph.
   (a) Repeat the ef698e5 setup: a wall face 8 studs down the line, you 12 studs out behind it. Pass: no hit. RushEnded says Jammed, with the root against the face (distance about face − 2.5).
   (b) Wall faces at 6, 8 and 10, with dummies at 5, 9.5 and 14. Pass: wall 6 and wall 8 hit only 5; wall 10 hits 5 and 9.5; 14 is never hit.
   (c) Note how far the drawn boar overruns before the report, and how far its head shows through the wall once it is held. Superseded by item 191.
   (d) If the Playground has a ramp or a low step, rush along it. The line must not end early (it should hit a dummy up the ramp). Superseded by item 196.
187. [ ] **Late paths never turn a walk back (D-196).** Watch a kobold walk to a goal more than 60 studs away over open ground. It must never turn back to a waypoint it passed.
   (a) Wedge it in a dead end. It still backs out along the route.
188. [ ] **Walking into an enemy is a solid stop (D-198; supersedes item 180).** Log your root's Y every frame.
   (a) Hold a boar with the dev hold. Walk W into it from the front, the side and the back, for 3 s each. Pass: you stop flat against an invisible face at the boar's body width, with no bob (Y within 0.05 of standing), no sideways slide onto it, and never on top.
   (b) Repeat on a kobold.
   (c) Repeat while the boar walks toward you (not held).
   (d) If the Playground has a ledge or a slope above an enemy, try to step onto it from there. Report whether you can stand on the blocker's top (7 studs).
189. [ ] **The blocker stays out of the fight (D-198).**
   (a) Swing over a held boar's back (above the body, inside its 7-stud column) from both sides. No hit, no spark, no HP change.
   (b) Swings through the body still hit as before.
   (c) Lock-on and the soft assist still pick the boar.
190. [ ] **A rush still passes through you and rejoins cleanly (D-167, D-190, D-198).**
   (a) Stand on a boar's line. The rush passes through you, and you are never pushed or lifted.
   (b) Repeat the item 178 setup with the D-190 log. The boar turns solid again only after you have been clear of it (root and blocker) for 0.5 s.

## Z. The end of a charge (D-199 to D-204)

191. [ ] **A charge into a wall stops at the face, on the server and on screen (D-199, D-202; replaces item 186(c)).** Use anchored wall faces 6, 8 and 10 studs down the line, with dummies at 5, 6.5, 9.5 and 14. Log server times.
   (a) RushEnded "Jammed" arrives before the root touches the face, with distance about face − 2.5.
   (b) Set Incoming Replication Lag to 0.25 s, then 0.5 s. The drawn boar stops at the face: no overrun, and no snap back at RushEnded.
   (c) Hits match item 186(b).
   (d) Note how much of the head shows through the wall (3.1 studs expected). Superseded by item 199.
192. [ ] **The client can cast in the rushing group (D-199, D-204).** On a client, call workspace:Blockcast with RaycastParams.CollisionGroup = "SkyspireRushing" against a wall and against a WedgePart ramp.
   (a) It does not error. If it does, the drawn rush silently falls back to the jam path.
   (b) The result has a Normal: about horizontal for the wall, tilted up for the ramp.
193. [ ] **Legs stop with the body (D-200; answers item 184).** With 0.5 s of lag, charge a boar into a wall and watch the frames frame by frame through Settle and HandBack.
   (a) The legs stop when the body stops: no running in place, no foot slide.
   (b) Repeat with a free rush and with a parry mid-rush.
194. [ ] **The lock camera has no one-frame lag behind the drawn body (D-201; answers item 182(a)).** Record the lock camera during a charge and step through it frame by frame.
   (a) Do it with the default load and with a heavy RenderStepped load.
   (b) Pass: the framing never trails the body's motion by a frame.
195. [ ] **Hit holds start on the same frame (D-201).** Hit a remote enemy and the local rig in the same swing. Pass: both hit holds start on the same frame.
196. [ ] **A charge up a ramp runs on (D-204; replaces item 186(d)).** Build anchored WedgePart ramps at 10°, 20° and 30°, and a 40° one, with a dummy up each. Rush up each at no lag and at 0.5 s.
   (a) Pass for 10°, 20° and 30°: the rush is not ended "Jammed" at the foot, the dummy up the ramp is hit, and the drawn boar runs up with its root, with no stop partway and no slide at the hand-back.
   (b) Put a wall across the top of the 20° ramp. Pass: nobody behind the wall is hit. Note how far the drawn boar overruns.
   (c) On the 40° ramp, report whether the boar climbs it or stops, and when it is reported "Jammed".
   (d) Rush up a flight of steps and note whether the drawn boar stops at a riser while the server's runs on. Superseded by item 201.
197. [ ] **Glancing walls and pillars (D-202).** Superseded by item 200.
   (a) Line a rush so that only a corner of the root's box clips a pillar beside the line. Note whether it ends "Jammed" at the pillar or carries on.
   (b) Rush into a wall at 60° to the line. The rush now stops dead where it meets the wall instead of sliding along it.
   (c) Say whether each stop reads right.
198. [ ] **Free-rush lag against jamLagStuds (D-203; extends item 185).** Every server frame, log speed × (now − bodyStartedAt) − progress.
   (a) Log it for a flat free rush at the default frame rate and with a capped client frame rate.
   (b) Log it once across a forced server hitch.
   (c) Pass: it stays below 4, and below 1 on flat ground.

## AA. Wall slams and frame order (D-205 to D-218)

199. [ ] **A head-on ram stops with the snout on the face (D-205, D-208; replaces item 191(d)).** Ram a Boar head-on into anchored walls 6, 8 and 10 studs down the line.
   (a) Pass: the snout rests on the face and no head shows through the wall.
   (b) Note how far the Humanoid mover overshoots before it settles. In Lune the mover went up to 0.63 into the wall and settled at 0.03, and the drawn hand-back followed it up to 0.34 in.
200. [ ] **Glance and clip at full speed (D-206, D-207; replaces item 197).** Charge along a wall at about 30°, then past a pillar whose corner the root's box clips by 0.5 studs.
   (a) Pass: the glance bends along the face at full speed, and the sidestep reads as a shoulder past the corner, not a stop.
   (b) Say whether each reads right.
201. [ ] **Stairs and ramps (D-209; replaces item 196(d)).** Charge up 1-stud stairs and a 15° ramp.
   (a) Pass: the body climbs with no Jammed, and its HipHeight hover holds.
202. [ ] **The turn after a slam (D-208).** Slam a boar with its target standing behind the wall.
   (a) Pass: the Recover turn toward the target does not swing the snout through the wall.
203. [ ] **The order in the MicroProfiler (D-211).** In Play on a client, open the MicroProfiler and read one frame's render steps.
   (a) Pass: SkyspireRigs (199), then SkyspireCharacter (301), SkyspireCamera (302), SkyspireImpactFrames (303) and SkyspirePoseReaders (304), then SkyspireCameraLate and FrameClockFrameEnd (2000). Note which of the two at 2000 runs first.
   (b) Check it on two machines, one at 60 fps and one capped at 30.
204. [ ] **A step bound mid-frame (D-212).** In a scratch LocalScript, from inside a step at 301, BindToRenderStep a new step at 303 and log whether it runs on that frame.
   (a) Note the answer. FrameOrder.prepare makes ImpactFrames independent of it either way.
205. [ ] **The trail head on the blade (D-215).** Swing Horizontal and Sharp Nail with the local character and with a second client's character, at 60 fps and at a 30 fps cap.
   (a) In a step at 304, place a small neon Part at TrailEnd.WorldPosition and record frames.
   (b) Pass: the part sits on the drawn blade tip on every frame, local and remote. This also confirms that WorldPosition read at 304 reflects the Transforms written at 199 and 301.
206. [ ] **The camera on the contact frame (D-213; extends item 165).** Lock onto a dummy and hit it with a frame capture running; also dodge in every direction.
   (a) Pass: the nudge, shake and FOV kick start on the frame the white flash first shows.
   (b) Pass: the body never shudders a frame ahead of the camera on a dodge or a lunge.
207. [ ] **The Final picture's frames (D-214; replaces the Final count in item 142).** Capture a Final and a Kill at 60 fps and at a 30 fps cap.
   (a) Pass at 60 fps: Final shows exactly 2 frames, counted from the contact frame; Kill shows 2/2/2.
   (b) Pass at the 30 fps cap: Final shows 1 frame.
   (c) Say whether 2 frames of Final reads strong enough. If not, the fix is one more Dark frame in impact.luau, a data change only.
208. [ ] **A render stall mid-swing (D-215; extends item 147).** Minimise the window for 1 s in the middle of a swing, then restore it.
   (a) Pass: no trail streak across the gap.
   (b) Pass: the next swing's trail and slash line point the right way from their first frames.
209. [ ] **Slam dust, thud and shake (D-217).** Ram a boar into a wall close to the player, then again from about 30 studs away. Its far-slam check (a) is superseded by item 254.
   (a) Pass: on the frame the snout meets the face, grey dust bursts off the face at the snout and the stone thud plays from that point. Up close the camera gives a short shake; from 30 studs there is no shake.
   (b) Turn Reduce flashing on and ram again. Pass: the slam looks and sounds the same, with no full-screen flash.
   (c) Slam two boars at once. Pass: two puffs and two thuds.
   (d) At Low quality there are fewer puffs. Say whether the dust reads against the wall and whether the thud is heavy enough. Tune fx.wallSlam and sfx.cues.WallSlam (data only).
   (e) A 30° glance and a pillar clip. Pass: no dust and no thud.
210. [ ] **A hit right after the slam (D-208, D-210; extends item 199).** Ram a boar into a wall, then hit the dazed boar within about 0.1 s of the stop, and again at about 0.3 s.
   (a) Pass: the snout stays on the face, not frozen inside the wall. In Lune, a second Stagger within about 0.1 s left the body up to 0.63 into the wall because the mover overshot.
211. [ ] **A lost RushEnded (D-218).** In a scratch copy of the client, make handlers.RushEnded return at once, then ram a boar into a wall at 0 and 0.25 s of Incoming Replication Lag.
   (a) Pass: the snout reaches the face, the dust and thud play once there, and the hand-back finishes in about 1 s with no visible slide.
   (b) Restore the handler afterwards.

## AB. Draw, sheathe and lost rush messages (D-219 to D-226)

212. [ ] **Draw as one whip (D-219; replaces item 119).** In Playground at 1x and 60 fps, lock on while standing, walking, running and sprinting.
   (a) Pass: the Draw reads as one continuous whip: off the back, over the shoulder, up to straight, then down into the carry with a small spring back.
   (b) Pass: no frame jumps the blade from straight up to the guard.
213. [ ] **Sheathe after the combat tag (D-219, D-220; replaces item 116).** Let the combat tag run out (6 s + 0.3 s) while standing, walking, running and sprinting.
   (a) Pass: the arm keeps the drawn carry through the delay, with no arm pump while the sword is in the hand.
   (b) Pass: the swing up, over and down into the sheath is continuous, with no jump from overhead to low across the back. No frame moves the tip more than about 1.4 studs.
   (c) Pass: the legs switch to the sheathed run or sprint during the Sheathe.
214. [ ] **Draw and Sheathe at 0.25x (D-219).** Repeat items 212 and 213 with the Capture panel at 0.25x.
   (a) Pass: the tip moves about 2.3 studs or less per 9 fps capture.
   (b) Blends (blend in and out, set crossfades) run on real time, so at 0.25x they look about 4 times as abrupt as in play. The Draw's blend-out shows about 1 stud per capture. Note it; it is not a fail.
   (c) Say whether the edge over the scabbard mouth (out for 12–14 ms) shows in any capture.
215. [ ] **A remote player's Draw and Sheathe (D-219, D-220).** From a second client, watch the first player draw and sheathe while running and turning under lock-on.
   (a) Pass: the same continuous whip as in items 212 and 213, with no jump.
216. [ ] **Kill and Final frames heard late (D-223; extends item 207).** At 60 fps with the frame-by-frame recorder, kill a FrenzyBoar 10 times with the last hit confirmed by the server. Stand still and hit; do not rely on the local contact.
   (a) Pass: each Kill shows exactly 2 black, 2 white-figure and 2 ink frames.
   (b) Pass: each Final shows exactly 2 dark frames.
   (c) Pass: when a Kill takes over a Final, no frame of the 3D world shows between them.
217. [ ] **Rush messages under lag and loss (D-221, D-222).** In Studio's network settings, set Incoming Replication Lag to 0.25 s, with packet loss if available.
   (a) Let 10 boar rushes run past you, including one jammed on a pillar and one staggered. Pass: the drawn body follows the server body, and jammed and staggered rushes stop where the server's did.
   (b) Pass: no body jumps back toward the crouch.
   (c) In ReplicatedStorage's remotes folder, RushStarted, RushEnded and RushTurned are RemoteEvents, not UnreliableRemoteEvents.
218. [ ] **No ride on a boar (D-221).** Stand in a boar's lane with 0.25 s of lag and let its rush pass through you and stop.
   (a) Walk into its standing body from every side, and stand where it stops while it turns solid again.
   (b) Pass: the invisible face blocks you or pushes you out sideways; you are never lifted onto its back.
219. [ ] **A hitch at the sprint's Sheathe (D-225).** Sprint with the sword drawn and hit a dummy once. With the command bar set to Client, run `task.delay(6.3, function() local t = os.clock() while os.clock() - t < 0.1 do end end)` and keep sprinting, so a 0.1 s hitch lands as the Sheathe starts. Try a few times, record at 60 fps and step through the frames.
   (a) Pass: on the frames after the hitch the blade keeps moving as one whip; no single frame moves it about 2 studs.
220. [ ] **A kill over the soft dim (D-226).** Set three boars to 1 HP (DevCombat sethp) and kill them about 0, 0.9 and 1.15 s apart, so the second kill shows the soft dim and the third takes it over. Record at 60 fps and step through the frames.
   (a) Pass: the dim goes straight to the black frames, with no frame of the bright world between them.

## AC. Gate shot fixes (D-227 to D-270)

221. [ ] **Point-blank Horizontal is counted (D-234).** Turn the DevCombat trace on, hold a kobold at your right shoulder about 1.5 studs off, and cast Horizontal 10 times.
   (a) Pass: every flash on the kobold shows a number. Otherwise save the trace lines for the flash that had none (the server's clip time, root and the window's samples).
222. [ ] **The stand-off reads as a push-off (D-235).** Lock onto a side-on boar at the touch (about 1.8 studs) and cast Rising Arc 5 times. Record at 60 fps and step through the frames. Superseded by item 286.
   (a) Pass: the body eases back about half a stud during the wind-up, and the blade starts outside the boar's flank and cuts into it.
   (b) Pass: no anti-cheat correction or snap-back.
223. [ ] **The stand-off against a wall (D-235).** Stand with your back against a pillar, lock a kobold at the touch, and cast Rising Arc. Superseded by item 267.
   (a) Pass: the body does not go into the pillar and is not rubber-banded. If it is, report it; the step is a CFrame move with no world check.
224. [ ] **Re-record the Art shots at 60 fps (D-227 to D-230).** Record the four Art shots and step through the frames.
   (a) Pass: each contact frame shows the blade on its strike key.
   (b) Pass: Normal freezes 3 frames and Final 6. Superseded by item 288.
   (c) Pass: the smear shows only on the two frames where the blade moves.
   (d) Pass: Sharp Nail's trail goes out between cuts.
225. [ ] **An Art taken away shows nothing (D-231).** Let a kobold hit you during an Art's wind-up so you are staggered.
   (a) Pass: no flash, chime, trail or smear; the blade light and glow fade over about 0.2 s.
226. [ ] **No spin after Sharp Nail (D-232).** Cast Sharp Nail into a boar's side.
   (a) Pass: the body does not turn after the Final.
227. [ ] **Cost of the client sweep (D-234).** Open the MicroProfiler during Sharp Nail at 60 and 144 fps.
   (a) Pass: the ContactPredictor step costs under 0.3 ms a frame.
228. [ ] **Staged gate shots (D-242, D-251).** Open the Playground place in Studio and Play. In the Capture panel, select each of the 10 shots with [ and ] and press P.
   (a) Pass: the player walks into the shot's ring (item 259) and is healed; the shot's enemies stand at their distance and side, facing the player; no field enemy is within 70 studs.
   (b) Pass: the camera takes the shot's view (Side square to the line, ThreeQuarter about 50° off it, Behind behind the boar, Open from the side), the 3-2-1 runs, and the prompt line changes on its beats. Superseded by item 320.
   (c) Pass: the take stops itself at its target length and the panel says done.
   (d) Pass: no anti-cheat flag or kick after a staging (the staging never moves the player, D-244).
229. [ ] **Counter, cursor and K (D-249, D-250).** Record art-vertical at 60 fps.
   (a) Pass: f0 shows the new shot's counter text, and the counter stays on screen past the target.
   (b) Pass: no mouse cursor appears on any frame.
   (c) Pass: a K at 2 s asks to confirm, and a second K stops the take without marking it done.
230. [ ] **Ledge fall (D-247).** Stage the locomotion shot.
   (a) Pass: the player starts on the slate ledge facing -Z; walking right (D) runs off the edge, falls and lands.
   (b) Pass: the kobold is lockable with F at about 5 s. Superseded by item 323.
231. [ ] **Auto-perform at 1x (D-248).** Press U, then P, on art-horizontal, kill-shatter and parry-spark. Superseded by item 319.
   (a) Pass: the Art fires at 1.0 s; the kill shatters the 1-HP kobold; the parry spark shows on the overhead.
   (b) Pass: at 0.5x, U presses nothing.
232. [ ] **Field back (D-245, D-246, D-268).** After staging, press J.
   (a) Pass: the staged enemies are gone, and field enemies move and attack again.
   (b) Pass: an enemy held by DevCombat hold before the first staging stays held.
   (c) Press P for a staged shot and then J at once, while the boars are still spawning. Pass: the panel reads "Giving the field back" and then "Field given back"; the boars despawn and the player is no longer held.
   (d) Press J straight after a staging that failed. Pass: the field comes back.
233. [ ] **Hold never mid-attack (D-245).** Let a boar start its crouch and press P during the crouch.
   (a) Pass: staging waits, then holds it after the strike, or reports "still mid-attack" after 3 s. A drawn crouch never ends without its rush.
234. [ ] **Live game has no staging (D-242, D-243).** Publish to a test place without DevCapture, or run outside Studio.
   (a) Pass: ReplicatedStorage has no DevStage RemoteFunction, and P on the panel (if it shows) says staging is absent.
235. [ ] **Close-fight framing and the freeze (D-236, D-239, D-240).** Lock on a kobold and fight toe to toe; then kill it.
   (a) Pass: the camera sits three-quarter to the side and the target is not behind the hat.
   (b) Pass: through the 0.5 s freeze the frame does not move until the shatter. Then say whether the camera's blend during the shard rise reads as a cut or as drift. Superseded by item 274.
   (c) Pass: a boar rushing past swings the shot as a pan, never a 2-frame whip or a top-down look.
   (d) Let a Charger rush past you from 1.8 studs to the side and count the frames it is off screen (Lune: 23, against 12 on HEAD). Say whether the turn cap reads as calm or as losing the target. Superseded by item 276.
236. [ ] **Walk into enemies (D-237).** Walk into a boar and a kobold from the front, both flanks and the back. Superseded by item 284.
   (a) Pass: the player stops touching the body on every side, never inside it.
   (b) Under a lock, walking at the target's flank still circles it until D-238 is wired. Note it; it is not a fail. Superseded by item 273.
237. [ ] **Recorder hygiene (review issue 21, not code).** Record the game window only, not the whole desktop, at a steady 60 fps.
   (a) Check for repeated or dropped frames before handing off.
238. [ ] **Kobold tell holds to the snap (D-252).** Stand in front of a kobold and let it wind up. Watch the yellow wedge from the start of the crouch to the swing.
   (a) Pass: the wedge stays lit until the axe snaps, about 1.3 s after the crouch starts, and goes white for its last instant. A parry pressed during the white lands. Superseded by item 291.
239. [ ] **Cone on the ground (D-253).** Watch a kobold and a boar telegraph on flat ground, on a slope and on a step edge.
   (a) Pass: each cone lies flat on the ground under the enemy, with no seams between triangles and no float at hip height. It never draws over your character's body.
240. [ ] **Held wind-up leaves nothing behind (D-254).** Start a boar's wind-up, then hold it (DevStage or DevCombat hold) or walk away until it sleeps mid-crouch. Do the same with a Brute.
   (a) Pass: no rush is drawn, the telegraph glow disappears at once, and the Brute's swing clip stops.
241. [ ] **No snap at launch (D-255, D-256).** With Incoming Replication Lag at 0.15 s and then 0.3 s, let a boar wind up while you circle it, then launch into a wall 6 studs away.
   (a) Pass: the body turns smoothly through the crouch and the launch, with no visible snap of 30° or more.
   (b) Pass: the jammed run stops well short of HEAD's 16-stud overrun (Lune: about 9 studs past at 0.25 s of lag) and settles back on the body.
242. [ ] **Predicted flinch at real latency (D-258).** With Incoming Replication Lag at 0.1 s and then 0.25 s, stand inside a kobold's cone and take the hit. Then repeat while dodging, guarding, and tap-parrying on the glint.
   (a) Pass: the flinch, flash and sound land on the frame the axe arrives; the HP bar drops a moment later.
   (b) Pass: dodge, guard and parry never show a flinch, and a server miss (step out at the last frame) shows the flinch undone at worst, never HP lost.
243. [ ] **Parry and stagger read (D-257).** Parry a kobold's overhead with the Capture panel at 0.25x.
   (a) Pass: the sword turns into the deflect on the spark frame, with no freeze on either side, and the kobold's recoil pose holds clearly for most of its stagger before it returns to stance.
244. [ ] **Kobold and boar stay apart (D-259).** Replay the parry take: shatter the boar, then let the kobold return home past it. Also spawn two kobolds on one spot.
   (a) Pass: no enemy's arms, axe or snout ever pass into another's body. The kobold walks round the boar and stops beside its home, and the twins step apart and stand still.
245. [ ] **Trail ribbon at 60 fps (D-261, D-269).** In Playground at 60 fps, record Basic1–3, Horizontal, Vertical, Sharp Nail and Rising Arc on a boar and step through the frames.
   (a) Pass: each cut draws a curved arc around the shoulder, never a straight chord or a flat slab.
   (b) Pass: it is thick and clearly in the trail colour over the bright sky, and shows only during the hit windows. Superseded by item 325.
   (c) Pass: it holds through hit-stop, then fades where it was drawn.
   (d) Note any Rising Arc frame where the ribbon visibly leaves the blade's path (up to about 1 stud is expected).
   (e) At a 30 fps cap, film Sharp Nail (window 3) and Basic3 in slow motion. Note any hook at the start of the trail that points back along the wind-up, against the cut. Superseded by item 263.
246. [ ] **Activation glow in daylight (D-263).** Activate each Art with the sword close to the camera, in full daylight.
   (a) Pass: the blade glows clearly in the Art's colour from the activation, past the white flash, to the first hit.
   (b) Pass: a cancelled Art's glow fades out with its light.
247. [ ] **FinalHit bass (D-264; replaces the final-hit bass check in item 49) (listen).** Land 5 Art final hits with headphones and step through the recording.
   (a) Pass: the bass is cut on the hit frame and the first 3 freeze frames.
   (b) Pass: the sub slams back in at the end of the hold.
248. [ ] **Heartbeat duck (D-264) (listen).** Set the player to 20% HP (DevCombat sethp) and let a kobold hit you, block it and parry it.
   (a) Pass: each hit, block or parry clearly rises over the heartbeat, and the heartbeat comes back within about half a second.
249. [ ] **Shatter balance (D-264) (listen).** Kill a boar, then (with a second client) a player, then a boss stand-in if one is available.
   (a) Pass: the glass reads clearly over the low slam and bass on each.
   (b) Pass: the death never sounds bass-only.
250. [ ] **A/V sync clap (review F15).** With the recorder used for the gate shots, record a sharp in-game cue (a parry through DevCombat) and a real hand clap in front of the camera and the mic.
   (a) Measure the frame offset between picture and sound for both.
   (b) Pass: the in-game offset matches the recorder's own offset, so the 3–5 frames come from the recorder, not the game.
251. [ ] **Plates declutter (D-265, D-270).** Hold two boars side by side (about 2 studs apart, 10 and 14 studs from you) and walk around them. Then lock on to two boars standing side by side at about 10 studs and walk slowly sideways for 10 s.
   (a) Pass: the nearer plate stays on its boar and the farther one lifts clear above it, never overlapping, and the climbing plate does not flicker between them.
   (b) Pass: when they separate, the lifted plate eases back down, never jumping.
   (c) If plates move down instead of up, flip the sign in Nameplates.setLift (BillboardGui.SizeOffset Y).
252. [ ] **Death line and hotbar (D-265).** Die, and watch another player die.
   (a) Pass: the death line reads at about 25 px glyphs or more, with a dark edge, over the bright sky.
   (b) Pass: the hotbar keys and names are clearly readable while in use and fade out together, stroke included, after 5 s idle.
253. [ ] **Speed lines on the sky (D-265).** Dodge and dash with the camera facing the open sky, then the floor.
   (a) Pass: the lines read clearly on both: a white core with a thin dark edge.
   (b) Pass: the middle third stays clear.
254. [ ] **Wall-slam shake (D-266; replaces the far-slam check in item 209(a)).** Lock on to a boar and stand about 20 studs behind it as it rams a wall, and once at about 8 studs. Record at 60 fps and step through the frames.
   (a) Pass: on the stop frame the camera gives a short, sharp shake, clearly bigger per frame than the lock ease, and settled within about 10 frames.
   (b) Pass: a slam more than 32 studs from you does not shake the view.
   (c) Trigger slams about 5, 15 and 30 studs away. The shake is the same at all three; say whether the far ones should shake less. Superseded by item 277.
255. [ ] **The server's word under lag (D-267).** Set Incoming Replication Lag to 0.05 s and then 0.1 s. Cast Sharp Nail and Rising Arc on a kobold at point blank (1.5–2 studs), then the basic chain. Superseded by item 298.
   (a) Pass: every freeze shows the blade at the end of its snap, never raised, and the damage number appears with the freeze.
256. [ ] **A point-blank kill under lag (D-267).** With the lag of item 255, land a killing blow at point blank. Superseded by item 264.
   (a) Note whether the 10-frame kill freeze lands before the cut. Kill words are not held yet.
257. [ ] **Parry at your normal latency (D-252).** With no network simulation, parry the Kobold Axeman's Overhead 20 times, half pressing at the start of the glint and half in its last third. Superseded by item 292.
   (a) Pass: presses at the start of the glint parry.
   (b) Record how many presses in the last third fail. In Lune the whole glint parries up to 50 ms of one-way latency, 83% of it at 67 ms and 50% at 100 ms. Superseded by item 278.
258. [ ] **Hit weight at 120 and 144 Hz (D-228).** On a 120 or 144 Hz display with no frame cap, compare a Normal hit's weight with 60 Hz. Superseded by item 265.
   (a) Holds measure 41.7 ms there against 50 ms at 60 Hz (Lune). Say whether the hit feels lighter.

259. [ ] **Walk into the ring (D-244).** Open places/Playground.rbxl and Play (F5). Walk 20 or more studs from the stage area, choose an Art shot with ] or [, and press P.
   (a) Pass: a cyan disc shows on the spot and the panel says "Walk into the ring"; the body walks itself in (no teleport), the disc goes, the shot stages around where you stand and counts down. Superseded by item 316.
   (b) Pass: the Output shows no anti-cheat flag.
260. [ ] **Auto-walk to the locomotion shot (D-244).** From the stage area choose the locomotion shot and press P.
   (a) Pass: the body walks round the ledge without catching on it, climbs the ramp and stops on the ledge's top facing its -Z edge, and the take counts down. Superseded by item 316.
261. [ ] **The ledge ramp (D-244).** Look at the ledge from the side.
   (a) Pass: the ramp slopes up to the ledge (tall end against the ledge's +Z face, low end on the field), you can walk up it with W, and it is behind the start, not in the run off the -Z edge.
262. [ ] **Taking the walk over, and J (D-244).** Start a walk with P, then press W. Superseded by item 317.
   (a) Pass: the auto-walk stops, the disc stays and the note says to walk in yourself; walk into the disc and stand still, and the shot stages.
   (b) Start another walk and press J. Pass: the disc goes, the body stops being walked, and the panel says "Field given back".

## AD. Gate shot fixes, second round (D-271 to D-296)

263. [ ] **Trail from the cut's first frame (D-273).** Cap the frame rate at 30, then 60, then 144 (Esc > Settings > Maximum Frame Rate where offered, otherwise the GPU driver's limiter). Swing Basic 1–3, Horizontal, Vertical, Sharp Nail and Rising Arc at a boar, record, and step through the frames.
   (a) Pass: the trail starts on the blade at the cut's first frame and follows the arc, with no straight or backwards streak at its start.
264. [ ] **A kill lands on the cut under lag (D-272).** In File > Studio Settings > Network set Incoming Replication Lag to 0, then 0.05 s, then 0.1 s. Kill a Kobold and a Boar at point blank (1.5–2 studs) with Sharp Nail, Rising Arc and a basic swing.
   (a) Pass: the freeze, the silence and the shatter never come before the blade reaches the body.
   (b) Pass: the 10-frame Kill freeze shows the blade at the end of its snap.
265. [ ] **Hit weight at any refresh rate (D-271).** On a 120, 144 or 240 Hz display with no frame cap, land Normal, Final and Kill hits.
   (a) Pass: each pause feels as long as at 60 Hz (about 50, 100 and 167 ms; at 120 Hz 6, 12 and 20 frames).
   (b) Cap at 30 fps (or use a 30 fps phone), land 20 Normal hits, and count the frozen frames on each. Note how many hold only 1 frame (Lune: about half under frame-time jitter; HEAD always held 2). Superseded by item 303.
266. [ ] **A swing at an enemy off your look (D-275).** Turn the DevCombat trace on. With a boar about 5 studs away, swing Basic 1 with it 30°, 45°, 60° and 90° off your look, first with no lock, then locked.
   (a) Pass, no lock: at 30° the body turns onto the boar and hits; at 45° or more it does not turn and misses. Superseded by item 290.
   (b) Pass, locked: the body turns 40° and hits up to 75°, and misses at 90°.
   (c) Pass: no damage number appears without a visible cut. Save the trace lines of any that does.
267. [ ] **The stand-off against a wall (D-276).** Lock a side-on boar at the touch (about 1.8 studs) and cast Rising Arc with your back flush to a wall, then to a pillar, then 0.3 studs off the wall. Superseded by item 287.
   (a) Pass: the body never sinks into the wall or the pillar, and it steps back only as far as there is room (none when flush).
   (b) Pass: no anti-cheat correction or snap-back.
   (c) With the pillar beside you rather than behind, the full step (about half a stud) is taken.
268. [ ] **A blade on the kobold's axe (D-277).** Lock a kobold and cut so the blade meets its axe first (Rising Arc from its weapon side), then swing a basic at the axe alone.
   (a) Pass: no damage number on the axe contact, and the hit on the body behind it lands.
   (b) Pass: cutting only the axe gives no damage. No clash spark or sound plays yet; note whether one is wanted.
269. [ ] **A slam rests at the wall (D-278, D-279).** Charge a boar into a wall head-on and at 45°. Superseded by item 306.
   (a) Pass: it rests touching the wall with its snout outside it, and the daze shows no push-back pop.
270. [ ] **A jam is told early (D-280).** Charge a boar up a steep slope (about 35–45°), then into a part moved into its path mid-rush.
   (a) Pass: the rush stops and plays Jammed within about 0.07 s, with no long grinding run. Superseded by item 308.
   (b) Charge a boar up and down the playground stairs at several speeds. Pass: no rush ends Jammed on a stair it can climb. Superseded by item 309.
271. [ ] **Enemies never stand inside each other (D-281).** Make two boars bump while walking, and charge one past the other. Superseded by item 310.
   (a) Pass: neither jitters, lifts or stands inside the other.
   (b) Pass: a rush that stops over a packmate stays passable until they separate, then turns solid with no pop.
   (c) Kill an enemy right beside a packmate and watch for 4 s. Pass: the corpse's blocker does not push or lift the packmate.
   (d) Jam a boar's rush against a fresh corpse at a wall. Pass: it does not pop up or shove the corpse when it turns solid again.
272. [ ] **Snouts by walls (D-278, D-295).** Walk a boar along a wall and turn it in a corner. Then stand with your back to a playground wall and let a FrenzyBoar and a KoboldAxeman come at you along the wall, from behind them, and from 45°. Superseded by item 311.
   (a) Pass: the snout never clips into the wall.
   (b) Pass: each enemy reaches you and attacks within about 5 s, and neither stands facing the wall or pushes its snout or axe visibly into it.
   (c) Note any turn where a boar's rear swings into the wall (Lune: up to 0.77 studs on a Recover turn after a rush along a wall).
273. [ ] **Walk in at a locked flank (D-284).** Lock a kobold and walk at its flank.
   (a) Pass: the body walks in and stops at its side (about 1.8 studs root to root), with no circling. Superseded by item 289.
   (b) Pass: free walk, sprint and the skid stop are unchanged, and the capture shots' staged views still walk on the camera's frame.
274. [ ] **Still through the shard rise (D-285).** Kill a locked kobold.
   (a) Pass: the camera stays still through the freeze and the whole shard rise, then eases out smoothly. Superseded by item 300.
   (b) Say whether look input waiting about 1.5 s after the kill feels stuck. Superseded by item 293.
275. [ ] **The open shoulder by a wall (D-286).** Lock on with a wall about 2.5 studs off your right shoulder, then with a wall on the left only, then in a narrow corridor.
   (a) Pass: by the right wall the camera takes the left shoulder at full distance without a whip. With the left wall nothing changes. In the corridor it stays on its side and pulls in.
   (b) Walk past pillars that alternate sides about 2.5 studs out. Say whether the shoulder swaps (Lune: one per pillar) read as busy. Superseded by item 294.
276. [ ] **A rush past the lock (D-287).** Hold the lock and let a boar rush past at about 2–4 studs.
   (a) Pass: it is off screen for no more than about 12 frames, and the camera never turns more than about 7° in a frame.
   (b) Pass: a boar grazing the screen edge does not trigger a catch-up.
277. [ ] **Wall-slam shake by distance (D-288, D-296).** Lock a kobold, have a boar slam a wall about 10, 22, 28, 29, 31 and 34 studs from you, and record at 60 fps. Superseded by item 312.
   (a) Pass: at 10 and 22 studs the shake looks like the old one; at 28–29 it is clearly smaller (about half at 29); at 31 it is barely visible; past 32 there is none.
278. [ ] **Parry the glint under lag (D-289).** Fight the Kobold Axeman's Overhead.
   (a) In File > Studio Settings > Network set Incoming Replication Lag to 0.1 s, and press guard on the glint's first frame. Pass: it parries. Superseded by item 301.
   (b) Repeat at 0 lag. Pass: it parries. Superseded by item 292.
   (c) Pass: the tell still holds until the axe falls, and the glint ends a little before the snap.
279. [ ] **Capture auto-perform: lock and stop (D-290).** Open the Capture panel.
   (a) On the locomotion shot with auto-perform on and a field enemy walked within lock range. Pass: the first F locks the staged kobold and the second releases it; no field enemy is locked.
   (b) On an Art shot, stop the take with K, K while the Art key is held. Pass: no Art launches, and the next real Art press works.
280. [ ] **A flinch out of a stance (D-294).** In the art-sharp-nail staged shot, take a kobold hit during the activation hold and step through at 60 fps.
   (a) Pass: the flinch pose shows on the strike frame.
   (b) Pass: the stance fades back to drawn idle over 0.2 s without moving toward the cut, and no whoosh, trail or smear plays. Superseded by item 295.
   (c) Note what the body shows over the frames after the fade (the review's 26-frame low pose, f63–88). Drawn idle during the Stagger is by design.
281. [ ] **A Draw at a sprint (D-293).** Sprint, run and stand still, then Draw, at several points of the stride.
   (a) Step frame by frame at 60 Hz. Pass: the root-relative tip moves under 1.4 studs a frame.
   (b) On a 240 Hz display with the MicroProfiler recording, read the largest tip step around 0.8 s into the Draw (Lune: up to 79.5 studs/s at some stride points, against the 77.3 moving cap and the 84 cap). Superseded by item 297.
282. [ ] **No skating feet (D-291, D-292).** Lock on and walk forward, back, left and right with the sword drawn, then run and sprint unlocked, at 1x and at the Capture 0.25x scale. Superseded by item 296.
   (a) Pass: the planted feet do not visibly skate (Lune median slide under 0.1 studs).
   (b) Note the walk-to-run speed-up around 12 studs/s, where the blend still slides about 0.15 studs (open).
283. [ ] **A remote player's cancelled Art (D-294).** With two clients, watch the other player's Art be cancelled before its first cut (dodge or GuardBreak).
   (a) Pass: its blade light still goes out.
   (b) Note whether its cut, trail and smear still play on your screen after the server staggered it (open: Replication does not stop a remote player's Art).

## AE. Gate shot fixes, third round (D-297 to D-341)

284. [ ] **Walk into enemies (D-315, D-318; replaces item 236).** Setup A, used by the items below that name it: Playground, Play Solo, no network simulation, 60 fps cap. Walk into a boar and a kobold from the front, both flanks and the back, slowly and then sprinting. Superseded by item 338.
   (a) Pass: you stop touching on every side, never inside, including the kobold's idle hunch, both arms and the axe ahead of its right hand: you stop at the axe. Kobold front/right/back/left about 1.86/3.43/1.69/3.08 studs root to root; boar head-on about 6.25, flanks about 1.94–2.04, tail-on about 3.93.
   (b) Circling a locked flank is not a fail.
   (c) Note, not a fail: limbs can reach in during attacks, flinches and staggers (Lune: kobold Overhead 1.13, Stagger 1.22; boar Charge 1.12).
285. [ ] **Beside the kobold's axe (D-314, D-315).** Setup A. Stand touching a kobold's front, just left of its axe. Lock it and cast Sharp Nail 3 times, then the basic chain 3 times. Superseded by item 336.
   (a) Pass: the body slides aside up to about 0.2 studs off the axe, never through it and never a jump.
   (b) Pass: every cut lands with its number, with no anti-cheat correction or snap-back.
286. [ ] **The stand-off at the real touch (D-235, D-314; replaces item 222).** Setup A. Walk into a side-on boar's flank and stop where you touch: about 2.3–2.4 studs root to root (the colliders never allow 1.8). Lock it and cast Rising Arc 5 times at 60 fps. Superseded by item 331.
   (a) Pass: the blade starts outside the flank and cuts in. The wind-up step back is 0.1 studs or less; none is fine (the old "about half a stud" no longer applies).
   (b) Pass: the body never goes into the boar and never jumps. It may give way smoothly, up to about 1 stud (Lune 0.93–0.95), and stands still in each freeze.
   (c) Pass: no anti-cheat correction or snap-back.
287. [ ] **The stand-off at a wall and a pillar (D-276, D-314; replaces item 267).** Setup A with the DevCombat trace on. At item 286's touch, cast Rising Arc with your back flush to a wall, then a pillar behind you, then 0.3 studs off the wall, then with a pillar beside you. Log the root box's gap to the wall or pillar every frame of the Art, and the pillar's size and shape. Then stand back against a pillar, touching a kobold in front, and cast Sharp Nail and Vertical. Superseded by item 337.
   (a) Pass: the root never sinks into the wall or the pillar (Lune keeps 0.05). If something sinks, say whether it is the root or only the arms (in the wind-up the arms reach 0.9–2.0 studs behind the root).
   (b) Pass: no anti-cheat correction or snap-back, and no frame step over about 0.5 studs.
   (c) With the pillar beside you the step is 0.1 studs or less, as in item 286; the old "full step of about half a stud" was written for a 1.8-stud touch that never happens.
   (d) Note, not a fail: a little overlap with the kobold when there is no room to give way.
288. [ ] **Still freezes at 60 and 144 Hz (D-271, D-314; replaces item 224(b)).** Setup A. At a point-blank kobold (1.5–2 studs) and a side-on boar, cast all four Arts and the basic chain, recorded at 60 fps. Repeat with the cap at 144 Hz (or the PC's highest). Superseded by item 331.
   (a) Pass: Normal freezes 3 frames, Final 6 and Kill 10 at 60 Hz; 7, 14 and 24 at 144 Hz.
   (b) Pass: body, head and blade are still on every frame of every Normal and Final freeze. Rising Arc's Normal shows no drift (2727b4c: 0.08–0.2 studs a frame). Camera shake is fine.
   (c) Item 224(a), (c) and (d) as written.
289. [ ] **A kobold's flank, walking in and turning onto you (D-315; replaces item 273(a)).** Setup A. Lock a kobold and walk at each flank with W held. Then stand touching its flank or front and let it turn onto you, idle and while attacking.
   (a) Pass: the body walks in with no circling and stops at its side: about 3.1 studs root to root on its left flank and about 3.4 on its axe side. About 1.8 is the front stop, not the flank.
   (b) Pass: your root never ends inside its body (c2f76c1: 1.07 at the left flank). Log root-to-root distance and the blocker faces' CFrames on any frame under 1.5.
   (c) Item 273(b) as written.
290. [ ] **A swing at an enemy off your look (D-275 as corrected; replaces item 266(a)).** Setup A, the DevCombat trace on, a boar about 5 studs away (trace d about 8), swung at 30°, 45°, 60° and 90° off your look with no lock. Superseded by item 339.
   (a) Pass: at 30° the body turns onto the boar and hits. At 45° or more on your left it does not turn and misses. On your right (45–90°) the swing's arc cuts the boar's head and snout, and that hit is drawn and counted (c2f76c1's hits at bearings −46, −78 and −93 with clear −0.15 are this).
   (b) Item 266(b) and (c) as written.
291. [ ] **The white glint, frame by frame (D-316, D-317; replaces item 238(a)).** Setup A. The glint is the axe's fill going white, never the clash-star billboard (2727b4c timed the billboard). Stand 4 studs in front of the Kobold Axeman and let it wind up its Overhead 5 times. Log every frame the axe's TelegraphFill FillColor and FillTransparency and one TelegraphWedge part's Color, timed from the Telegraph's arrival.
   (a) Pass: 5 of 5 show yellow, then white (FillTransparency 0, fill and wedge together) for 3 frames in a row (2–4 at a hitch), then yellow, then out.
   (b) Pass: the white starts +1.15 to +1.22 s and ends at least one frame before the wedge goes out (about +1.27 to +1.29 s). The wedge goes out within one frame of the snap.
   (c) Pass: no Unblockable tell ever turns white.
292. [ ] **Parry on the white, no lag (D-316; replaces items 257 and 278(b)).** Setup A. Parry the Overhead 20 times: 10 presses on the first white frame and 10 on the last.
   (a) Pass: 10 of 10 on each (c2f76c1: 2 of 10 on the first frame).
293. [ ] **A look ends the death's still shot (D-324; replaces item 274(b)).** Setup A. During a locked kill's freeze, flick the mouse about 20 px or more. Repeat with a 2–5 px twitch, then with the right stick.
   (a) Pass: the flick ends the hold and the view turns within 3 frames, eased.
   (b) Pass: the twitch does not move it.
294. [ ] **The shoulder dwell past pillars (D-325; replaces item 275(b)).** Setup A. Place pillars about 2.5 studs to alternate sides of a straight run, 8 studs apart. Lock an enemy ahead and sprint past them.
   (a) Pass: the shot changes shoulder at most once every 2 s and never ping-pongs.
   (b) Item 275(a) as written.
295. [ ] **A struck stance lowers slowly (D-340; replaces item 280(b)).** Setup A at 60 fps. Take a kobold hit while holding Sharp Nail's stance, then the Vertical's. Superseded by item 340.
   (a) Pass: the sword lowers over about half a second within the stagger and never sweeps down past the front of the body like a cut. Frame by frame the tip moves about a stud a frame or less, except on the flinch's own hit frame.
   (b) Pass: no Art, whoosh, trail or smear plays.
   (c) Pass: a dodge or cancel out of a stance still drops it quickly (0.2 s).
296. [ ] **No skating feet (D-334; replaces item 282).** Setup A. Log per-frame foot and root positions (the feetcheck CSV) for 10 s of straight flat-ground movement in each gait, sheathed and drawn: walk (W), back (S), strafe left and right locked on a held kobold, run, and sprint (Shift+W), at 1x and at the Capture 0.25x. Then run and sprint without stopping for 10–20 s. Superseded by item 368.
   (a) Pass, while a foot is flat (its centre within 0.09 studs of its standing height): it moves 0.04 studs or less between consecutive rendered frames, including frames where PostSimulation ran 2 or 6 substeps, and under 0.1 studs net per plant.
   (b) Pass: on video no 5–7 px foot hop and back, and no skating that starts late in the 10–20 s runs.
   (c) Pass: no anti-cheat correction.
   (d) Note the walk-to-run speed-up around 12 studs/s.
297. [ ] **A sprint Draw at 240 fps (D-330; replaces item 281(b)).** Setup A. Sprint, then Draw, 5 times, captured at 240 fps. Superseded by item 345.
   (a) Pass: no tip jump over 1.3 studs per 60 Hz frame (74.6 studs/s is about 1.24).
   (b) Pass: the settle springs over its last 0.18 s with no pop at 0.97 s, and the blade never passes through the body.
   (c) Note, open: a guard pressed with the sword sheathed still snaps the tip about 6.2 studs in one frame (c2f76c1, 3 of 3). The fix is in guard-draw.patch, not applied; the gate shots never guard sheathed. Superseded by item 344.
298. [ ] **The hold waits for its word (D-312; replaces item 255).** Setup B, used by the items below that name it: setup A with File > Studio Settings > Network > Incoming Replication Lag set as given. Here 0.05 s, then 0.1 s. Cast Sharp Nail, then Rising Arc, at a kobold 1.5–2 studs away, then the basic chain, recorded at 60 fps. Superseded by item 332.
   (a) Pass: every freeze shows the blade at the end of its snap and the number appears inside the freeze. At 0.1 s a Normal freeze may run 4 frames.
   (b) At 0.25 s: the freeze runs at most 12 frames (0.2 s), then lets go; the number follows, and nothing freezes twice.
299. [ ] **A kill under lag is one freeze (D-313; extends item 264).** Setup B at each lag of item 298. Land a point-blank kill with Basic1, and once with a Sharp Nail Final. Superseded by item 332.
   (a) Pass: one unbroken 10-frame freeze from the contact frame, with no second freeze and no blade jump back.
   (b) Pass: the number shows inside it, the music ducks 10 frames after the contact, and the shatter comes about 41 frames (0.683 s) after the kill word. The PC's "about 0.75 s" includes the word's wait.
300. [ ] **The death's still shot (D-323; replaces item 274(a)).** Setup B at 0, then 50, then 100 ms. Lock a kobold and kill it with Basic3, then with Rising Arc, recording at 60 fps. Superseded by item 334.
   (a) Pass: from the first frozen frame to the shatter the picture does not move at all (c2f76c1: 0.45–0.76 studs a frame for the first 6 frames), then eases out smoothly.
   (b) Pass: the freeze starts on the frame the death shows.
301. [ ] **Parry the white under lag (D-289, D-316; replaces item 278(a)).** Setup B at 0.05 s, then 0.1 s. Repeat item 292's 10 first-frame and 10 last-frame presses.
   (a) Pass at 0.05 s: at least 9 of 10 on each.
   (b) At 0.1 s, record both counts (expected: the first frame 10 of 10; the last frame may land a frame late if Studio delays only incoming traffic).
   (c) Pass: the tell holds until the axe falls, and the white ends a little before the snap.
302. [ ] **A doomed Art never lights (D-326).** Setup B at 150 ms. Stand in a kobold's swing and press an Art within about 0.15 s before the axe lands.
   (a) Pass: no blade light, chime or FOV kick plays, and the Stagger ends the stance. Superseded by item 340.
   (b) Make the blow miss: just before it lands, move the player out of the cone with DevCombat "place" on the server. Pass: the stance lights and chimes about 0.5 s later at its hold pose, and releasing launches normally. Superseded by item 346.
303. [ ] **Holds at 30 fps (D-327; replaces item 265(b)).** Setup A with the client capped at 30 fps. Land 20 Normal hits, five Art Finals and a kill. Then a kill at 100 ms of lag. Superseded by item 333.
   (a) Pass: a Normal freezes 2 frames every time, a Final 3 and a Kill 5, with no 1-frame Normal hold in the 20 hits.
   (b) At 100 ms of lag, note whether the kill freeze is 5 or 6 frames (Lune gives 6) and whether a one-frame kill freeze is visible.
304. [ ] **Holds below 60 fps (D-341).** Whenever Studio drops below 60 fps while recording (45 fps on a 60 Hz display is typical), count Final and Kill freezes on the r counter.
   (a) Pass: a Final freezes about 100 ms (5 frames at 45 fps, not 6–8) and a Kill about 167 ms (8 frames).
305. [ ] **Impact-frame counts (D-155, D-159; replaces item 142's picture counts).** Setup A at 60 fps. Count the impact-picture frames of five Finals (Horizontal, Vertical, Rising Arc) and a Kill on the r counter.
   (a) Until the FrameClock patch (frameclock-pace.patch) lands, 2 or 3 frames per Final is the known cause: the median of the last 5 frame lengths lands on the short side under jitter. The PC's 3/3/2 is this, not a new bug. Superseded by item 333.
   (b) After the patch: each Final shows 2 and a Kill 2/2/2. Superseded by item 333.
   (c) Item 142's flash and hit-stop counts as written.
306. [ ] **A slam rests at the wall, with the hooks (D-278, D-279, D-322, D-333; replaces item 269).** Setup C, used by items 306–315: setup A, then in the Server command bar run `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); local function S(c, a) return game:GetService("HttpService"):JSONEncode(f:Invoke(c, a)) end`, S("hp") for the ids, S("place", {position = {0, 3, 25}, facing = 0}) to move the player clear, and S("hold", {except = {boarId}}). The floor is at y = 0. Superseded by item 347.
   (a) Head-on: S("part", {size = {16, 8, 1}, position = {0, 4, -12.5}, name = "Wall"}), then S("enemy", {entityId = boarId, position = {0, 0, 0}, facing = 0, hold = true}), then S("charge", {entityId = boarId, toward = {0, 0, -20}}). Pass: the reply's stops are "Wall", then "Interrupted", and the boar never ends inside the wall.
   (b) 45°: S("clearparts"), then the same wall with tilt = {0, 45, 0}. Pass: the stop is "Glance" or "Wall" by the 40° glance rule, never "Jammed".
   (c) Pass, both: the client draws the rush and the drawn snout stops flush with the wall face, never short of it or inside it, with the slam cue on that frame and no drawn step over about 0.5 studs a frame (c2f76c1: a 9.4-stud jump). Do 5 head-on and 5 glancing.
307. [ ] **A charge right after a hold (D-339).** Setup C. With a boar mid-wind-up, run S("enemy", …) or S("hold") and then S("charge", …) at once. Superseded by item 348.
   (a) Pass: the line and the crouch show, and the run starts from the crouch, not from standing.
   (b) Log the drawn body (Torso, root.CFrame * bodyOffset) and the replicated root separately every frame. Pass: no drawn step over about 0.5 studs a frame.
308. [ ] **A slope and a part dropped mid-rush (D-280; replaces item 270(a)).** Setup C.
   (a) Slope: S("part", {size = {10, 1, 24}, position = {0, 7.7, -19.2}, tilt = 40}); for 35°, position {0, 6.9, -19.8} with tilt = 35. Boar at {0, 0, 0} facing 0, held; charge toward {0, 0, -30}. Pass: at 35° and 40° the boar runs up the slope with no "Jammed" stop. Superseded by item 349.
   (b) Late part, as one chunk: f:Invoke("clearparts"); f:Invoke("enemy", {entityId = boarId, position = {0, 0, 0}, facing = 0, hold = true}); f:Invoke("part", {size = {16, 8, 1}, position = {0, 4, -14.5}, after = 0.75, name = "Late"}); return S("charge", {entityId = boarId, toward = {0, 0, -30}}). Pass: the part appears 0.75 s after the call, the stops show "Wall" at about 8.4 studs about 0.18 s after the part lands, and no rush passes through it.
309. [ ] **Stairs (D-280; replaces item 270(b)).** Setup C. Build: for k = 1, 8 do f:Invoke("part", {size = {8, 0.5*k, 2}, position = {0, 0.25*k, -(9 + 2*k)}, name = "Step"..k}) end; f:Invoke("part", {size = {8, 4, 12}, position = {0, 2, -32}, name = "Landing"}).
   (a) Up: charge from {0, 0, 0} toward {0, 0, -30}. Down: S("enemy") the boar onto the landing at {0, 4, -32} (floor y 4), facing 180, and charge toward {0, 0, 5}. Pass: no "Jammed" in the stops either way.
   (b) Pass: the body follows the steps without sinking or floating more than a riser, and the client's drawn body matches the server's.
310. [ ] **Enemies never stand inside each other (D-281, D-318, D-329; replaces item 271).** Setup C.
   (a) Boar A at {0, 0, 0} facing 0 and boar B at {0, 0, -16} facing 180, both held. S("walk", {entityId = A, toward = {0, 0, -16}, wait = true}), and B toward {0, 0, 0}. Pass: each reply is arrived = false at the 30 s timeout, or arrived with the room kept; the boars never overlap, jitter, lift or shove.
   (b) B at {0, 0, -8} facing 90, held; A charges toward {0, 0, -20}. Pass: a rush that stops over B stays passable until they separate, then turns solid with no pop; B is never pushed through the floor or shoved away.
   (c) S("sethp", {entityId = X, hp = 1}) on an enemy beside a held packmate at {0, 0, -4.5}; kill it with one hit. Pass: the corpse never pushes or lifts the packmate, and from the shatter (about 0.67 s after the death) it no longer blocks.
   (d) A wall part at z −12.5 and a corpse made at {0, 0, -9} the same way; A charges toward {0, 0, -20}. Pass: the rush is not stopped by the corpse after the shatter and stops at the wall, with no pop or shove.
311. [ ] **Snouts by walls (D-278, D-295; replaces item 272).** Setup C. Wall parts {size = {1, 8, 40}, position = {4, 4, -20}} and {size = {16, 8, 1}, position = {-3.5, 4, -40.5}}. Boar at {2.2, 0, 0} facing 0, held; walk it to {2.2, 0, -36}, then to {-8, 0, -37}. Superseded by item 350.
   (a) Pass: the walk along the wall reaches {2.2, 0, -36} within 1 stud, the turn goes round without passing through the end wall, and the snout never clips into either wall.
   (b) Stand with your back to the long wall and place a FrenzyBoar and a KoboldAxeman unheld with "enemy" along the wall, behind them and at 45°. Pass: they take over in Idle, each reaches you and attacks within about 5 s, and neither stands facing the wall or pushes its snout or axe visibly into it.
   (c) Note any turn where a boar's rear swings into the wall (Lune: up to 0.77 studs on a Recover turn).
312. [ ] **Wall-slam shake by distance (D-288, D-296; replaces item 277).** Setup C. S("place", {position = {0, 3, 0}, facing = -90}); a kobold held at {6, 0, 4} facing 90, locked. For each slam distance d of 10, 22, 28, 29, 31 and 34 studs, with xf 8.0, 21.17, 27.35, 28.37, 30.41 and 33.47: a wall part {size = {1, 8, 16}, position = {xf + 0.5, 4, -6}}, the boar at {xf − 12, 0, -6} facing −90 and held, then charge toward {xf + 5, 0, -6}. Record at 60 fps. Superseded by item 351.
   (a) Pass: full shake at 10 and 22; clearly smaller at 28–29 (about half at 29); barely visible at 31; none at 34.
313. [ ] **A rush ending beside the axe (D-318).** Setup C. Place a kobold and a boar so that the boar's charge passes beside the kobold and ends next to its axe (its right side). Do it 5 times.
   (a) Pass: no body is pushed, lifted or popped when the boar turns solid again, and the boar never stands inside the axe face.
314. [ ] **A corpse bump (D-329).** Setup C. S("sethp", {entityId = koboldId, hp = 1}) on a kobold standing at {0, 0, -9}, with a held boar at {0, 0, 0} facing 0. Kill the kobold, then charge the boar toward {0, 0, -20} 1 s after the kill.
   (a) Pass: the stops show no "Jammed" or "Wall" at the corpse's spot, the boar is not pushed, and nothing blocks there once the shatter has played.
315. [ ] **A kobold pack never shoves (D-332).** Setup C. Let a kobold pack spawn and respawn 5 times, or place 3 kobolds 1 stud apart with "enemy" and release them. Superseded by item 352.
   (a) Pass: in the first second no kobold jumps more than 0.5 studs sideways.
   (b) Pass: S("hp") shows them apart, and while chasing the player they never stand inside each other's axe face. Note, open: four chasing can still end about 0.2 inside.
316. [ ] **Walk into the ring (D-302, D-303; replaces items 259(a) and 260(a)).** Setup D, used by items 316–328: the Playground place with DevCapture, no network simulation, capture at 1x. Press P on every shot from 8 bearings and from below the ledge. Then put an obstacle or slope in the way so the stop overshoots. Superseded by item 356.
   (a) Pass: the body sprints in and skids to rest within 1 stud of the spot and 5° of its facing, with no auto motion after the stop (2727b4c shot 4: 3.13 studs against radius 3).
   (b) Pass: an overshoot walks the last leg again at most 2 times, then stages within 1 stud or asks from outside without staging. It is never staged outside the ring.
   (c) Items 259(b) and 260's route round the ledge as written.
317. [ ] **Taking the walk over, and J (D-304, D-305; replaces item 262).** Setup D. Superseded by item 357.
   (a) Tap W during a walk and again while P's ask shows; separately, hold D while pressing P. Pass: only your own keys move the body until P is pressed again, and the ring and the ask stay. (2727b4c's "about 7 studs after a W tap" was the body's own run carry, never auto motion.)
   (b) Press J mid-walk. Pass: a sprint skid stop with under 0.5 studs of slide (2727b4c: about 3.5).
   (c) Repeat (a) with Incoming Replication Lag at 0.3 s.
318. [ ] **A take ends with its enemies held (D-297; extends item 232).** Setup D, across the takes of items 316–327.
   (a) Pass: the staged enemies freeze at each take's end, and no hits or damage numbers land between takes or during the next walk-in (2727b4c: shot 1's enemies killed the player about 5 s after the take; shots 7–9 took leftover hits during the walk).
   (b) Pass: J still gives the field back.
319. [ ] **Art shots press and hold (D-298; replaces item 231).** Setup D. Press U, then P, on the four Art shots, kill-shatter and parry-spark.
   (a) Pass: the prompt says Hold, the key goes down at 0.5 s, the Art launches on release at 1.0 s (2727b4c: +1.39 to +1.42 s), and the glow lasts about 1/3 s. Superseded by item 343.
   (b) Pass: the kill shatters the 1-HP kobold, and the parry spark shows on the Overhead.
   (c) At 0.5x, U presses nothing on any shot, shots 1 and 10 included (no stick and no sprint).
320. [ ] **Staged views (D-299, D-301; replaces items 228(b) and 230(b)'s camera).** Setup D.
   (a) ThreeQuarter shots (enemy-kobold-overhead, parry-spark). Pass: the kobold and its axe stay in frame for the whole swing, seen from about 75° on its weapon side at 14 studs (2727b4c shot 7: the kobold was mostly hidden behind the player). Superseded by item 360.
   (b) Open view (locomotion) with the lock held. Pass: the camera stays beside the run and square to it within 1°, through the lock at 5 s and its release; the run prompts name D or A, never W or S.
   (c) Side and Behind, and items 228(a), (c) and (d), as written.
321. [ ] **The boar charge at 12 studs (D-300).** Setup D. Stage enemy-boar-charge with U on. Superseded by item 355.
   (a) Pass: the staged charge (Meets) takes exactly one counted hit at about 1.1 s, and no second charge lands after the take (2727b4c: the first charge missed and a second hit for 16 after it).
322. [ ] **Shot 1, the gate fight (D-306, D-308 to D-310, D-319, D-320).** Setup D. Choose shot 1 (fight-boar-kobold), press U, then P, and record 20 s at 60 fps. Superseded by item 362.
   (a) Pass: about 6 parries (sparks at about 2.2, 5.6, 8.9, 12.2, 15.5 and 18.8 s), the first four each followed by an Art (Q, 2, 4, 3); no Art launches after about 19 s.
   (b) Pass: the boar is let go at about 8.6 s under its prompt, crouches, and the player dodges back across its line at about 9.3 s with no hit taken.
   (c) Pass: the player locks the boar, sprints to its skid, and one basic kills it at about 10.8–10.9 s with the freeze and the shatter.
   (d) Pass: the digits match the server's count: at least 10 hits (12 expected at low latency), all four Arts land, full HP, nothing hits the player, and every digit lands inside the 20 s take.
   (e) Pass: after the take the kobold stops, and J gives the field back.
   (f) Repeat at 0.05 s of lag. Pass: (a)–(e) hold, with at least 10 hits and 6 parries.
323. [ ] **Shot 10, the locomotion pass (D-307, D-311; replaces item 230(b)).** Setup D, Open view. Start from the field, not from shot 9's spot (that walk still fails, open). Choose shot 10, press U, then P, and record 14 s at 60 fps. Superseded by item 363.
   (a) Pass: a sheathed walk at about 8 studs/s (a half stick, not a run) goes off the ledge: Fall at about 1.8 s, Land at about 2.0 s.
   (b) Pass: run, sprint, then a skid at about 4.85 s. F at 5 s draws the sword with TurnLeft; F at 5.8 s lets go.
   (c) Pass: drawn walk, run and sprint, a skid at about 8.8 s, and the body stands.
   (d) Pass: F at 10.2 s turns the standing body to the kobold behind it with TurnRight, feet moving under 1 stud; F at 11.2 s lets go.
   (e) Pass: a drawn sprint let go at 13.2 s plays the skid. The body stays in frame and ends about 14 studs from the centre, with no T-pose and no sliding foot.
   (f) If the half stick runs at full speed in Studio, note it: CharacterController would then need a WalkSpeed scale for the capture stick.
324. [ ] **The parry-spark take (D-319).** Setup D. Shot parry-spark, U on, press P, at no lag and again at Incoming Replication Lag 0.1 s. Superseded by item 357.
   (a) Pass, both: the guard comes down and the take parries (spark, kobold staggered, 0 damage). Lune: 33 ms early and 100 ms late to spare on Studio's link; before, 6 of 12 failed at 0.1 s.
325. [ ] **The Horizontal ribbon (D-335; replaces item 245(b)).** Setup D. Staged shot 2 (art-horizontal), Side camera, U at 1x; frame 0 is the cut's first frame. Repeat once from above (Open camera or free cam). Superseded by item 342.
   (a) Pass, every frame: the ribbon is widest at the blade and at blade height, its lowest edge stays at least about 0.3 studs above the floor, and side-on it reads as a curved arc round the body, never a flat band on the ground. From above, the arc sweeps round the body.
   (b) Pass: it shows on about 10 frames at most (was 16) and is gone 8–9 frames (0.13 s) after the blade stops, not about 12; the blade's settle after the cut lays no new band over its end.
326. [ ] **The kill trail's first frame (D-336).** Setup D. Staged shot 9 (kill-shatter), U at 1x, 60 fps; again at 144 fps if Studio allows (restore the cap after). Number frames with the r counter; frame 0 is the first frame the blade moves into the Basic 1 cut.
   (a) Pass, 5 of 5 takes: the trail shows on frame 0, not first on frame 1; its first segment starts where the blade was at the window's open; nothing is drawn on the settle after the cut.
327. [ ] **The r counter and frame tick (D-337).** Setup D, any staged take (shot 9). Superseded by item 364.
   (a) Pass: during the take the panel reads "f N  r M", and through the kill's freeze f holds while r rises by exactly 1 per rendered frame.
   (b) Pass: in the 60 fps recording the bottom-right 12 px square swaps SystemCyan and DigitYellow on every recorded frame. Two same-coloured frames in a row are a duplicated capture frame (r repeats too): count them and report.
   (c) Pass: the square is hidden outside a take and never changes brightness (a hue swap only).
328. [ ] **Sprint per source (D-338).** Setup D. Stage art-horizontal from about 25 studs off the spot and press P. While the auto-walk sprints, tap Shift (about 0.1 s).
   (a) Pass: the body stays at sprint speed through and after the tap, stops within 1 stud and stages in the same time as an untapped walk (within a frame or two), with the same number of asks.
   (b) Pass, outside the panel: Shift+W sprints and letting go of Shift drops to the run; L3 or the touch Sprint button toggles sprint as before.

## AF. Gate shot fixes, fourth round (D-342 to D-468)

329. [ ] **The per-frame logger and the setups (D-342, D-353, D-465; replaces the logger method of items 288(b), 290, 297, 303, 325 and 327).** Every item below reads this logger. Bind it with RunService:BindToRenderStep at Enum.RenderPriority.Last.Value + 1, one row per rendered frame, numbered by the capture panel's r (or a local counter outside a take). Per row log: (1) the drawn body: the visible Torso (or UpperTorso) position of the player and of each enemy, or for a rushing boar HumanoidRootPart.CFrame * DrawnBody.offset(model); (2) the hidden root (HumanoidRootPart) position; (3) the root before physics (read in a PreSimulation connection) and after physics (read in a PostSimulation connection) of the same frame; (4) each foot's lowest corner (LeftFoot, RightFoot; the boar's four hooves; the kobold's feet); (5) the blade tip from the Motor6D transforms (not Weapon.CFrame, which reads a frame stale); (6) Choreo isPaused read at Enum.RenderPriority.Input.Value + 1 and Mixer heldShown; (7) Camera.CFrame position and look; (8) the white flash, impact picture look, floating number text and HitConfirmed arrival; (9) torsoVisible (the Torso's viewport point is on screen, a ray from the camera reaches it first, LocalTransparencyModifier < 1). Frame names used below: F is the first frame isPaused reads true; the contact pose is first drawn on F+1; heldShown is true from F+2; W is the frame the word's number first shows. Setups: A is the Playground, Play Solo, no network simulation, 60 fps cap. B is A with File > Studio Settings > Network > Incoming Replication Lag set as given. C is A plus, in the Server command bar, `local f = game:GetService("ServerScriptService"):WaitForChild("SkyspireDevCombat", 5); local function S(c, a) return game:GetService("HttpService"):JSONEncode(f:Invoke(c, a)) end`, S("hp") for the ids, S("place", {position = {0, 3, 25}, facing = 0}), and S("hold", {except = {boarId}}); the floor is at y = 0. D is the Playground with Workspace DevCapture = true, capture at 1x. Log the owner's avatar part sizes once (Head drawn size and mesh scale, UpperTorso, LowerTorso, RightLowerArm, RightHand, both feet), because Lune's blank avatar reads overlaps 0.1–0.3 deeper.
   (a) Pass: on a still idle, the drawn body and the root before and after physics differ by ≤ 0.01 studs a frame, and each foot's lowest corner stays within 0.02 of the floor.
   (b) Pass: through any kill freeze, f holds on exactly the frames heldShown is true and r rises by 1 every frame.
330. [ ] **The hit on its drawn frame, lag 0 (D-342, D-345, D-349, D-353, D-356; new).** Setup A, inside a capture take so the frame-tick square shows (setup D's shot keys start one), or number the frames with the logger's own counter. Hold a kobold 2.2 studs in front, locked. Run the basic chain, Horizontal, Sharp Nail, then a kill at 1 HP (S("sethp", {entityId = koboldId, hp = 1}) in setup C).
   (a) Pass: on F nothing of the hit shows (no white, picture, number or camera nudge); the blade moves on F and F+1 and is still from F+2 to two frames after the freeze's last flagged frame (F+11 for the kill in (c)).
   (b) Pass: basic Normal: flag F..F+2, white F+1 and F+2, number "2" on F+1. Basic3 (Final): flag F..F+5, no picture, white F+1 and F+2. Horizontal: flag F..F+5, Dark F+1 and F+2, white F+3 and F+4, number 16 on F+1. Sharp Nail Final: F = W+2, Dark F+1 and F+2, white F+3 and F+4.
   (c) Pass: the kill: flag F..F+9, blade still F+2..F+11, Black F+1–F+2, Dark F+3–F+4, Ink F+5–F+6, white F+7–F+8, number "1" on F+1.
   (d) Pass: the blade is stretched (smear) on exactly the 2 snap frames before F+1 and at rest on the third.
331. [ ] **Still freezes as drawn (D-353, D-354, D-427, D-428; replaces items 288 and 286).** Setup A. A kobold at 1.5–2 studs and a side-on boar; all four Arts and the basic chain, at 60 and at 144 Hz.
   (a) Pass: on every frame heldShown is true, the blade tip, head and root move ≤ 0.01 studs, and no player part is more than 0.005 inside the enemy.
   (b) Pass: heldShown frames per freeze: Normal 3, Final 6, Kill 10 at 60 Hz; 7, 14, 24 at 144 Hz.
   (c) Pass: the root moves ≤ 0.005 on every frozen frame, Rising Arc at the side-on boar included.
332. [ ] **The word inside the freeze under lag (D-347, D-348, D-350, D-354; replaces items 298 and 299).** Setup B at 0.05, 0.1, 0.15 and 0.25 s. The basic chain, Sharp Nail and Rising Arc at a kobold 1.5–2 studs away, then a 1-HP kill with Basic1 and with a Sharp Nail Final.
   (a) Pass: at 0.05 and 0.1 s the flag is one run F..max(F+2, W) for a Normal, F..max(F+5, W) for a Final, with no unflagged frame; the frame W has heldShown true.
   (b) Pass: the kill at 0.1–0.15 s is one run F..max(F+9, W+3); Black W–W+1, Dark W+2–W+3, Ink W+4–W+5, white W+6–W+7, number "1" on W; the blade and kobold move 0 on every Black, Dark and Ink frame.
   (c) Pass: at 0.25 s the flag runs F..F+11 (the cap) once; the kill's number, kill sound and white show on W with no Black, Dark or Ink, no camera punch, and no second freeze of the player.
   (d) Pass: after each run, the blade's first move is ≤ 0.25 studs.
333. [ ] **Holds and pictures at 30 fps, 144 Hz and under jitter (D-351, D-354, D-468; replaces items 303 and 305(a) and (b)).** Setup A with Workspace DevCapture = true, then in the command bar workspace:SetAttribute("DevFrameCap", 30); clear it with nil afterwards. Repeat at 144 Hz, and at 60 fps under a background load that makes frame times uneven.
   (a) Pass: at the 30 cap r rises by 300 ± 3 over any 10 s of a take (shot 1's 20 s take ends near r600) and each frame is 33.3 ± 1 ms.
   (b) Pass: at 30 fps, lag 0: Normal 2, Final 3, Kill 5 frozen frames; at 0.1 s a kill is 5 frames, not 6; a Kill picture draws 1/1/1.
   (c) Pass: at 144 Hz: Normal 7, Final 14, Kill 24; Kill picture 5/5/5; a Kill heard 0.15–0.2 s late keeps the blade still under all 15 picture frames (up to 41 frozen frames).
   (d) Pass: under jitter at 60 fps every Final draws exactly 2 picture frames and every Kill 2/2/2, over five of each.
334. [ ] **The camera stands with the freeze (D-357, D-358; replaces item 300).** Setup B at 0, 0.05 and 0.1 s. Lock a kobold; kill it with Basic3, then Rising Arc; then a Normal hit on a kobold not locked.
   (a) Pass: on every frame heldShown is true (the wait for the word included) the camera moves ≤ 0.01 studs plus the nudge, ≤ 0.4 in total.
   (b) Pass: a kill proven at the contact on the locked target moves the camera 0.000 from F+1 through the still shot, with 0 move at the hand-over to the still shot; an unlocked kill still shakes.
   (c) Pass: after a Normal the camera follows again within 2 frames of heldShown going false.
335. [ ] **An enemy blow on you (D-355, D-350; new).** Setup B at 0 and 0.1 s, then 0.12, 0.15 and 0.2 s for (b). Let a kobold's Overhead land on you; E is the first frame your isPaused reads true.
   (a) Pass: your white flash is first on E+1, the axe reaches its strike pose on E+1 and is still from E+2; both flags stay up with no gap until W (capped at 0.2 s).
   (b) Pass: at 1 HP the kill's Black W–W+1, Dark W+2–W+3, Ink W+4–W+5 draw the axe and your body still (0 move); both flags fall once.
   (c) Pass: a boar's rush blow freezes you only; the boar's drawn body keeps moving on every frame.
336. [ ] **Beside the kobold's axe (D-424, D-426, D-427; replaces item 285).** Setup A. Stand touching a kobold's front just left of its axe; lock it; Sharp Nail 3 times, the basic chain 3 times, then Rising Arc from 4.8 studs; at 60 and 144 Hz.
   (a) Pass: the root's step back or aside is ≤ 0.20 studs per frame at 60 Hz and ≤ 0.083 at 144 Hz on every frame, the frame after each freeze included.
   (b) Pass: on each freeze's first frame the blade is ≤ 0.2 studs into the kobold and no hand or arm is inside its torso; every hit's number shows.
   (c) Pass: Rising Arc from 4.8 steps ≤ 0.20 on the frame after its first freeze (it stands about 0.51 back at its key).
337. [ ] **The stand-off at a wall and a pillar (D-429; replaces item 287).** Setup C with the DevCombat trace on. A held kobold in front; your back flush to a wall, then to a pillar; Basic1, then Sharp Nail 3 times.
   (a) Pass: the root moves ≤ 0.001 toward the kobold over Basic1.
   (b) Pass: the root box is ≤ 0.05 inside the wall or pillar on every frame, no frame steps more than 0.20, and the slide off the pillar is ≤ 0.2 in total.
338. [ ] **Walk into enemies with the body shell (D-430, D-436; replaces item 284).** Setup C. Hold a kobold, then a boar (S("hold")). Walk (8) and sprint (24) straight into each from the front, right, back and left, sheathed and drawn, then at 45° to a flank; camera on your hands.
   (a) Pass: the held enemy moves 0.00 studs on every frame and shows Anchored = true in the Explorer; after release Anchored is false.
   (b) Pass: no hand or arm is more than 0.05 inside the enemy on any frame; drawn rests (root to root) are within 0.1 of kobold 3.27/4.42/3.05/4.44 and boar 7.62/3.30/5.30/3.40 for front/right/back/left. Log the sheathed rests; they have no Lune figure yet.
   (c) Pass: the 45° walk slides along the side with no stall, and the walk speed is back to full on the first frame the stick turns away.
   (d) Pass: swinging Basic1 while walking into a kobold, the shell does not hold during the swing and the walk speed is full on the first free frame.
339. [ ] **A swing at an enemy off your look (D-275 as corrected; replaces item 290).** Setup A, the DevCombat trace on, a boar about 5 studs away. Swing at 30°, 45°, 60° and 90° off your look on each side. Log the boar's root yaw every frame and each trace line's bearing and clear (the trace prints one line per closed damage window).
   (a) Pass: every trace window that counts a hit shows clear ≤ 0.
   (b) Pass: no window whose clear is > 0 counts a hit.
340. [ ] **Ribbons by owner and struck stances (D-362, D-422, D-423; replaces items 295 and 302(a)).** Setup B at 0 and 0.15 s. The logger reads each TrailRibbon host's TrailOwner attribute and counts only hosts named after your character. Take a kobold hit while holding Sharp Nail's stance, then Vertical's; then press an Art within about 0.15 s before an axe lands. With two clients, let a kobold stagger player B in Sharp Nail's stance from the front and from behind and watch from A.
   (a) Pass: your own lit ribbon count is 0 on every frame of a struck stance and of a doomed press; enemy ribbons are logged apart.
   (b) Pass: your sword lowers over about 0.5 s with the tip ≤ 1 stud per frame except the flinch's hit frame.
   (c) Pass: on A's screen B's tip moves ≤ 1 stud per frame (≤ 60 studs/s) after the word, and no trail, smear or whoosh lights on B.
341. [ ] **Trail windows and the edge-on streak (D-360, D-361, D-410; new).** Setup D. Shot 4 (Sharp Nail), shot 5 (Rising Arc) and shot 2 (Horizontal) with the Side camera, at 60, 30 and 144 fps. Count lit ribbon frames by r. Then cut Basic1 with a dodge at about 0.125 s.
   (a) Pass: each Sharp Nail cut's ribbon is gone 2 frames after its window closes at 60 fps (1 at 30, 5 at 144), with at least one frame with no ribbon between the three cuts (one between Rising Arc's two).
   (b) Pass: Horizontal seen edge-on draws a band ≤ 30 px tall at 1080p on every frame; face-on stays full width (about 217 px at 60 fps, 274 at 144, on the first smear frame).
   (c) Pass: after the dodge cuts Basic1, every trail and the smear are off on the first frame after the cut.
342. [ ] **The Horizontal ribbon (D-406, D-353; replaces item 325).** Setup D, shot 2 (art-horizontal), Side camera, U at 1x, then once from above. Count frames where your ribbon is lit and heldShown is false.
   (a) Pass: about 10 unfrozen lit frames, gone 8–9 unfrozen frames after the blade stops.
   (b) Pass: the ribbon's lowest edge stays ≥ 0.3 studs over the floor on every frame (Lune 0.353).
343. [ ] **Art glow length (D-298 corrected; replaces item 319(a)).** Setup D. U then P on the four Art shots, r counter on.
   (a) Pass: the glow runs from the press + 0.15 s to the first damage frame: 0.68 s ± 1 frame for Sharp Nail and Rising Arc, 0.70 s ± 1 frame for Horizontal and Vertical, and goes out on the first damage frame.
344. [ ] **The guard holds through a block, and draws first from the back (D-419, D-420; replaces item 297(c)).** Setup A. Sword drawn, hold the right mouse button and let a kobold's Overhead land 5 times, then parry 5 times; log the Guard clip's weight. Then sheathe and press and hold guard 5 times standing and 5 walking, captured at 240 fps.
   (a) Pass: the Guard weight stays ≥ 0.99 on every frame while the button is held, GuardHit and Parry included.
   (b) Pass: sheathed, the tip never moves more than 1.3 studs in a 60 Hz frame (≤ 0.33 per 240 fps frame); the sword leaves the back about 0.22 s after the press and the guard is formed by about 0.7 s; the server blocks from the press at 0 and 0.1 s lag.
   (c) Pass: a parry while sheathed is still an instant draw-cut with its clash flash.
345. [ ] **A Draw on its own (D-466; replaces item 297).** Setup A, captured at 240 fps. In the Client command bar run C("draw", {}) (game.Players.LocalPlayer:WaitForChild("SkyspireDevAim", 5):Invoke("draw", {})) five times standing. Then, five times, run task.delay(3, function() C("draw", {}) end), click into the game view and hold Shift+W until the Draw plays.
   (a) Pass: every reply is ok and the Draw plays from the current pose with no swing; with no lock the sword goes back by itself.
   (b) Pass: the tip moves ≤ 1.3 studs per 60 Hz frame (≤ 0.33 per 240 Hz frame).
346. [ ] **A doomed Art placed on a wind-up (D-467; replaces item 302(b)).** Setup B at 0.15 s with setup C's S. The kobold attacks on its own AI. Run S("place", {position = a point outside the kobold's cone, onWindUp = koboldId, after = 0.95}) and press the Art when the axe goes up.
   (a) Pass: the reply is ok, the move comes 0.95 ± 1/60 s after the wind-up starts, and the body moves once; S("charge"), S("basic"), S("art") and S("walk", {wait = true}) answer busy while it waits, and S("hp") and the other quick commands still answer.
   (b) Pass: the stance lights about 0.5 s later at its hold pose, there is no Stagger, and releasing launches normally.
347. [ ] **A slam rests at the wall (D-431, D-437, D-438; replaces item 306).** Setup C. A boar 30 studs from a wall (S("part", …)), the player behind; S("charge"); again in the open; lag 0, 0.05, 0.1 and 0.25 s; at 60 and 144 fps.
   (a) Pass: the drawn snout is never more than a plain walk's + 0.07 past the wall face, and the drawn body steps ≤ 0.467 a frame at 60 (≤ 0.194 at 144) after its first drawn move.
   (b) Pass: at the slam stop the Charge pose's deepest point is 0.00 inside the wall and there is no back-snap on the next frame; the rest stays 0.23 off the face with 0 corrections.
   (c) Measure: the first frame the drawn root moves (Lune 0.70 at 60, 1.87 at 30, 0.37 at 144) and, at 60 fps and 0.1 s lag, the root's AssemblyLinearVelocity × dt against its true per-frame move: they should differ by ≤ 0.25 studs.
348. [ ] **A charge right after a hold, twice (D-433, D-438, D-442; replaces item 307).** Setup C. With a boar mid-wind-up run S("hold") then S("charge") at once; then two charges in a row against a wall; then hold a boar 0.35 s after a wall slam and send S("charge") every 0.5 s.
   (a) Pass: the second charge's drawn steps are ≤ 0.52 a frame.
   (b) Pass: after hand-back no red line piece is visible on any frame (if one shows, note the GPU and graphics level).
   (c) Pass: the charge is accepted within 3.0 s of the slam (Lune 1.93–2.65 s) and never answers Interrupted after that.
349. [ ] **The 40° slope (D-434; replaces item 308(a)).** Setup C. A 40° wedge slope, the boar charging uphill along it; then a vertical wall dead ahead.
   (a) Pass: the uphill charge ends Done at the full line length, never Jammed, with every drawn step ≤ 0.5 a frame.
   (b) Pass: the charge into the vertical wall still ends Jammed.
350. [ ] **Snouts by walls (D-435; replaces item 311).** Setup C with item 311's walls ({size = {1, 8, 40}, position = {4, 4, -20}} and {size = {16, 8, 1}, position = {-3.5, 4, -40.5}}). S("walk") the boar to a wall-side point; then run 311(b) and (c) as written.
   (a) Pass: every boar part is ≤ 0.05 inside a wall on every frame.
   (b) Pass: the walk ends within 3 s (Lune 2.55 s), never at the 30 s time-out.
351. [ ] **Wall-slam shake (D-359; replaces item 312).** Setup C, item 312's layout. Wait ≥ 1 s between slams. Log the camera position against the frame before contact.
   (a) Pass: at 10 and 22 studs the first shaken frame is the largest move and the same within 5% every take (Lune 0.423 studs); at 28 studs 0.74× of it (0.313), 29 studs 0.50× (0.211), 31 studs ≤ 0.08× (0.031), 34 studs 0.
   (b) Pass: three takes each at 22 and 28: every 28 take moves less than every 22 take.
352. [ ] **A kobold pack (D-443; replaces item 315).** Setup C. S("pack", {enemy = "KoboldAxeman", position = {0, 0, -20}, count = 3}), then count = 6; let them walk home; then place 3 kobolds 1 stud apart with S("enemy") and release them.
   (a) Pass: 3 (then 6) enemies spawn, each ≥ 12 studs from the others, with no anti-cheat correction in the Output.
   (b) Pass: no two enemies overlap on any frame while they walk.
353. [ ] **The rush blow, skid and hand-back (D-344, D-432, D-439, D-440, D-441; new).** Setup D, shot 6 (enemy-boar-charge), frame-tick square on, lag 0 then 0.05 s; then a free rush at 3 headings in setup C.
   (a) Pass: the boar's Torso moves about 0.47 studs a frame from the launch (about f60) with no step over 0.6; your white flash, impact moment and flinch's first pose first show on the first frame that draws the snout touching your body (about f72), never the frame before, and never after HitConfirmed.
   (b) Pass: level with you (about f85–100) the boar's Torso is ≥ 3 studs to its right and nothing crosses your torso; it is back on the line at rest (about f124).
   (c) Pass: 4 dust puffs at about f90, 95, 101 and 108, each first shown on the frame that draws the hind hooves past its spot.
   (d) Pass: from telegraph to HitConfirmed is 48 ± 1 frames; from the last rush frame to the rest no frame steps back and the rest is ≤ 0.05 off the line end with no slide over the next 10 frames.
354. [ ] **Fixed Behind and Rear views (D-444, D-445; new).** Setup D, shot 6 with the Behind view, then shot 11 (enemy-boar-charge-rear), U on, P.
   (a) Pass: from the end of the countdown the camera moves ≤ 0.001 studs and turns ≤ 0.01° a frame through the take (a slam or contact shake excepted), f60–130 and f162–198 included.
   (b) Pass: Behind keeps the boar whole in frame from crouch to the end of the turn; your body covers it beyond a sliver only on the contact frame (about f72).
   (c) Pass: Rear sits about 20° off the line behind the boar (32.8° with height), the red line shows on ≥ 28% of its length through the 0.6 s crouch, and the meet comes at about f68; the take ends at 2 s.
355. [ ] **The boar charge at 12 studs from a settled stage (D-447; replaces item 321).** Setup D. Stage enemy-boar-charge with U on, from about 25 studs off the spot.
   (a) Pass: on the staged frame the boar stands 12 ± 0.25 studs from your root.
   (b) Pass: the telegraph starts within 0.35 s of the take's start and the hit lands once at about 1.1 s.
356. [ ] **Walk into the ring (D-451, D-452, D-453, D-454, D-456; replaces item 316).** Setup D. Press P on shots 4, 7 and 9 from 8 bearings at about 25 studs, from below the ledge, at lag 0 and 0.1 s. Then put a wall across the last leg: S("part", {size = {16, 8, 1}, position = a point on the approach 4 studs short of the spot, height 4}) and press P from about 25 studs.
   (a) Pass: each take stages within 1 stud and 5° of the spot (Lune ≤ 0.92 studs, ≤ 4.6°) in at most 2 asks and 1 sprint, with the body never sprinting after the first let-go and ≤ 8 studs/s in a correction.
   (b) Pass: after the walk the body turns on the spot to the shot's facing; the staged facing is within 1.0° of it on frame 0.
   (c) Pass: with the wall, within 60 frames of the root stopping the sprint lets go and the root's flat speed is < 0.25 within 30 more frames; the panel reads "The walk is blocked N studs from the spot" (Lune 4.1). Walk round it into the ring and stand: it stages there, never outside the ring.
357. [ ] **Taking the walk over, J, and staging under lag (D-452, D-455, D-461; replaces items 317 and 324).** Setup D. Press P, tap W to take over, and stand outside the ring for 30 s; then walk in. Then shots 4, 7, 9 and parry-spark at Incoming Replication Lag 0.1 and 0.3 s from 4 bearings.
   (a) Pass: at 20 s and 30 s the ring and "Walk into the ring yourself" still show, with no "Walk failed"; walking in and standing still asks after 0.5 s; J ends it and gives the field back.
   (b) Pass: under lag each take stages within 1 stud and 5°; the staged kobold stands about 3.5 studs off on shots 4 and 9 and about 4.5 on shots 7 and 8, and never touches the body (nearest face ≥ 0.40 off the root box).
   (c) Pass: the parry-spark take parries (PARRY, not TAKEN) at both lags.
358. [ ] **The ask waits for rest (D-452; new).** Setup D, shot 4, P from about 25 studs at lag 0, 0.1 and 0.3 s, 3 takes each; then press P again 0.8 s into a walk.
   (a) Pass: in every take the ask shows ≥ 30 frames after the root's flat speed first stays under 0.25 studs/s.
   (b) Pass: the root moves < 0.05 between the ask frame and the staged frame; report any take that moves more with its lag and frame count.
   (c) Pass: P pressed mid-walk never stages the body outside the ring or while it moves (Lune before: 6.10 studs off, 168°).
359. [ ] **Field enemies moved off, and the ledge (D-449, D-457; new).** Setup D with the ledge built. Use S("enemy", …) to put held field enemies within 70 studs of shot 5's spot: one on the ramp's line, one on the ledge top, one beside the ramp. Press P on shot 5. Then restart Play, walk straight back about 40 studs to where the ledge goes, choose the locomotion shot and press P; repeat about 57 studs back, where the ramp goes.
   (a) Pass: every moved enemy lands about 70 studs from the spot, ≥ 3 studs off the ledge-and-ramp footprint, standing on the field floor; take 3 of shot 5 has no field enemy in frame and none falling or floating.
   (b) Pass: no ledge or ramp is built around you; the ring shows at the stage area; the parts appear clear of your body, you walk round and up, and no anti-cheat flag shows.
360. [ ] **The ThreeQuarter view, measured at the player (D-446; replaces item 320(a)).** Setup D, shot 7 (enemy-kobold-overhead), ThreeQuarter. Log the flat angle at your root between the camera and the line behind you through the kobold, and the kobold's facing against the kobold-to-player line.
   (a) Pass: the view reads 75 ± 2° at your root on every frame (from the kobold it reads 59° at 4.5 studs and 64° at 2.96; that is geometry).
   (b) Pass: the kobold faces you within 12 frames and holds it; report every frame below 55° off at the kobold.
361. [ ] **One attack on the staged shots (D-462; new).** Setup D, shot 7 (kobold-overhead) and shot 8 (parry-spark), three takes each.
   (a) Pass: the staged enemy begins exactly 1 attack per take; its stagger and recovery play out whole, then it holds still (0.00 studs a frame) to the take's end.
362. [ ] **Shot 1, the gate fight (D-458, D-459, D-460, D-461; replaces item 322).** Setup D. Shot 1 (fight-boar-kobold), U, P, record 20 s at 60 fps, at lag 0 and 0.1 s. Log the r frame of every parry spark, Art launch, basic hit, the boar's release and the kill.
   (a) Pass: 322(a)–(f) as written in section AE.
   (b) Pass: 10–13 basics land at lag 0; no basic lands during an Art; a held Art cut by a reaction cancels once and comes back on the next cycle; every overhead the take shows is guarded and no Art is pressed after 19 s.
   (c) Pass: the dodge's way up starts about 0.98 s into the boar's charge beat.
363. [ ] **Shot 10, the lock turn (D-416, D-421; replaces item 323).** Setup D, shot 10 as item 323, Open view, 60 fps; then stand drawn and sheathed and lock a target 90°, 135° and 180° off each way.
   (a) Pass: F at 10.2 s turns the standing body and plays exactly one Draw, starting after the turn ends (about 0.6 s after F), never a Draw that starts, stops and starts again; the same for F at 5 s after the skid.
   (b) Pass: on every lock turn the pivot foot turns on one sole corner and the other lifts and sets down once; no planted foot moves more than 0.02 a frame or 0.05 over the turn.
   (c) Pass: chest and head lead by up to 45°, nothing pops (≤ 20° a frame), and an attack right after starts from its own pose. Record item 323(e)'s video.
364. [ ] **The counters and the panel (D-463, D-464, D-465; replaces item 327).** Setup D, shot 9 (kill-shatter, 5 s), shot 11 (enemy-boar-charge-rear, 2 s) and shot 10 (locomotion, 14 s).
   (a) Pass: through the kill freeze f holds on exactly the frames heldShown is true (Normal 3, Final 6, Kill 10 at 60 fps) while r rises by 1 every frame.
   (b) Pass: the panel stays hidden through the last counted frame (about r300, r120 and r840 at the 60 cap) and shows on the next.
365. [ ] **Attacks out of the run, mashes and cancels (D-404, D-407, D-408, D-409; new).** Setup A, 0.25x capture where named. Run and sprint drawn and press each basic and Art mid-stride on both foot phases; mash the basic as fast as the game takes it; cut Basic1 at 0.1 s and 0.2 s with an Art, the guard and each dodge; cut the guard and an Art's start hold with a dodge. With two clients, watch the same cancels on the other player.
   (a) Pass: out of the run, legs and arms come into the first pose over 5–14 frames with no part turning more than 20° in a frame (Basic2 out of Run@0.5 may reach about 20.2°, 0.24° past the bar: report it).
   (b) Pass: each cancel is a snap of about 3 frames with no part turning back; a guard raised mid-basic shows at once; a cut lit Art's glow fades at the cut. On the other client no part pops over 20° after 3 frames.
   (c) Pass: mashed, Basic2 snaps out of Basic1 without a pop over 20°, Basic3's feet stay planted, and Basic2's pull is visible from the gameplay camera (still open: report it).
366. [ ] **Arts after the freeze, the Rising Arc rise, and the reach (D-405, D-415, D-424, D-425; new).** Setup D at the 3.5-stud staging; land each Art and Basic3 on a held kobold at 60 and 30 fps; Rising Arc also from behind.
   (a) Pass: the tip's first step after each freeze is ≤ 0.25 studs a 60 Hz frame (≤ 0.5 at 30).
   (b) Pass: on each freeze's first frame the blade stops at the kobold's surface (≤ 0.2 in) and no hand or arm is inside it; no root slide before a freeze exceeds 0.4 a frame. Basic3 may step 1.25 back: report it.
   (c) Pass: Rising Arc rises onto both toes; the head stands ≥ 0.22 over the drawn idle's from the snap's landing through the settle, and no foot floats or sinks more than 0.03.
367. [ ] **Player one-shots (D-373 to D-389; new).** Setup A at 1x and 0.25x from the gameplay camera, 60 and 144 Hz. Play GuardBreak from a held guard, Parry and GuardHit out of the guard, Skid, Land drawn and sheathed, Stagger, the four dodges sheathed and drawn, the four flinches over walking, the drawn stance and a held Art, and Jump.
   (a) Pass: no part turns more than 20° in a frame outside a strike's snap, including the first frame of a flinch or DodgeForward at 144 Hz.
   (b) Pass: planted feet slide ≤ 0.1 a frame and sink ≤ 0.1; GuardBreak's footsteps fall at 0.3 and 1.15 s, Stagger lands at 0.25 and 0.4 s, Skid's dust and sound at 0.09 s; dodges lift the feet and the head clears the sheathed hilt.
368. [ ] **Feet that hold the ground (D-411, D-417, D-418; replaces item 296).** Setup A. Log each foot's sole corners for 10 s of straight flat-ground walk (8), run (16) and sprint (24), sheathed and drawn, with the owner's avatar and once with a blank R15 avatar; also at the 0.25x capture scale; stand drawn 10 s; make a kobold start and stop walking 5 times (S("walk")).
   (a) Pass: a sole corner within 0.02 of the floor counts as planted; drawn walk at 8 is planted 63–75% of frames with step p90 < 0.02; run and sprint planted 20–26% with step median < 0.02.
   (b) Pass: standing drawn, no foot sinks at the 3 s weight shift and each moves ≤ 0.01; the rear heel stays up with its ball ≤ 0.05 over the floor.
   (c) Pass: the kobold's root drops ≤ 0.02 at each start and stop, and its planted foot stands within 0.03 of the floor.
369. [ ] **Enemy clips and the ClipLab (D-390 to D-397, D-412, D-413, D-414; new).** ClipLab place. Play enemy/Boar/Charge at 1x and 0.25x, enemy/Kobold/Overhead, Idle and Stagger at 0.25x, the 8 enemy flinches over the idle, and step through a strike's hit-stop; use the arrows and Space with the PlayerR15 pedestal; then in the Playground stand behind a charging boar and a chopping kobold.
   (a) Pass: the Charge crouch reads with all legs visible and planted hooves move ≤ 0.1 a frame at rush speed; the Overhead has no one-frame leg jump and the right leg stays attached; the kobold's feet stand on the field (≤ 0.03 off); the Stagger's right foot stays planted and the left comes down at home at 0.45 s.
   (b) Pass: the hit-stop preview pauses on the strike key, no frame is skipped after it, and no trail is left across a loop restart or scrub; the pedestal never walks or jumps and every lab key still works.
   (c) Report: whether the tell reads from behind each enemy (the pose is hidden from behind by design; the Telegraphs carry it).
370. [ ] **Dev keys, the smoke log and the hipHeight check (D-448, D-449, D-450; new).** File > Studio Settings: "Respect Studio shortcuts when game has focus" on. Setup D, Capture panel open. Then stop Play, close Roblox Studio and run tools/smoke.sh playground.
   (a) Pass: T four times reads 0.5x, 0.25x, 1x, 0.5x and the key line says "T time scale"; O changes nothing.
   (b) Pass: the smoke prints SMOKE-RESULT: PASS playground with no "[AntiCheat] userId=0 system line failed" line, and the stand-in is still kicked.
   (c) Pass: the kobold stands on the field, not 0.2 into it (report the depth; kobold hipHeight is an owner call).
371. [ ] **Gamepad, touch and audio (not run in AE; items 293, 295, 302 and 328(b)).** Setup A with a gamepad, then the device emulator's touch.
   (a) Pass: item 293 with the right stick: a flick that turns the look 4° or more ends the death's still shot; a smaller twitch does not.
   (b) Pass: item 328(b) as written in section AE: L3 or the touch Sprint button toggles sprint as before.
   (c) Report by ear: the whoosh on a struck stance (295) and the activation chime on a doomed press (302) do not play; the kill thud plays once.

## AG. Code leftovers after the fourth round (D-469 to D-493)

Run these on the round F build on the owner's PC. Setups A to D and the per-frame logger are item 329's. Report every pass line with its numbers.

372. [ ] **Switch between two players (D-470; new).** Test > Clients and Servers with 2 players. Player A lands Horizontal on a Frenzy Boar; within 0.8 s player B lands Horizontal on the same boar. Then repeat with B landing more than 0.8 s after A.
   (a) Pass: on both screens B's digit is cyan (Switch), ui.SwitchLand plays once, both blades flash white for 2 frames, and the SWITCH ring then reopens on the boar for B.
   (b) Pass: on B's own screen the land sound and both flashes come one round trip after B's own hit freeze, and the hit does not freeze, flash white or shake a second time.
   (c) Pass: with B more than 0.8 s late, B's digit is white or yellow and no land sound plays.
373. [ ] **A guard break freezes at Final (D-471; new).** Setup A. Hold guard facing a Kobold Axeman until its Overhead (GuardBreak telegraph) lands, then take a plain blocked hit.
   (a) Pass: the guard break freezes both bodies for 6 frames at 60 Hz (0.1 s, twice a block's 3), the camera shake is heavier than a block's, and one Final tick plays under the GuardBreak crack.
   (b) Pass: the plain blocked hit still freezes 3 frames with a Normal shake.
374. [ ] **A faster clip on a remote rig (D-469; new).** Test > Clients and Servers with 2 players, a boar held beside player A. In the Server command bar require CombatService and call beginArt(<player A's entity id>, "OneHandedSword.Horizontal", nil, 1.3). Then set Incoming Replication Lag to 0.25 s and repeat.
   (a) Pass: at lag 0, on client B the swing plays visibly faster and the boar is struck as the blade passes it, not after.
   (b) Report: at lag 0.25 the remote clip starts at most choreo catchUpMaxJump (0.25 clip-s) late, so at 1.3 it is expected to run 0.075 clip-s (about 0.058 s) behind the server. Report whether the strike reads late on B (Lune: 0 behind at lag 0 and 0.05 for 0.6, 1.15 and 1.4; at lag 0.25, 0.0375 clip-s behind at 1.15 and 0.100 at 1.4).
375. [ ] **No skid under a remote dodge (D-472; new).** Two clients. Client A sprints and taps dodge mid-sprint; then A sprints and lets go with no dodge.
   (a) Pass: on client B, A's dodge plays one whoosh with no skid scrape or LandSoft thud just before it.
   (b) Pass: the plain sprint stop still plays the Skid and its landing on B.
376. [ ] **A sheath-drawn opener's first ribbon under lag (D-473; new).** Two clients with Incoming Replication Lag 0.1 s, then 0.25 s. Client A, sword sheathed, opens with a basic attack; record B with the per-frame logger.
   (a) Pass: on B the first trail ribbon follows the hand's slash, with no streak from the back.
   (b) Report: log the frame the Weapon motor's Part0 changes from the back mount to the hand against the first frame the hand's pose is drawn there. Part0 is a property and shows on its step's frame, while the pose shows a frame later (impact.poseLagFrames 1), so the blade may show in the hand one frame before the arm reaches it.
377. [ ] **The stop with controls off (D-474; new).** Setup A.
   (a) Pass: walk, then open a menu or disable the controls mid-walk (require(Players.LocalPlayer.PlayerScripts.PlayerModule):GetControls():Disable()): the body stops within the two-step stop and does not keep walking.
   (b) Pass: a gamepad half tilt and a keyboard diagonal both walk and stop normally.
   (c) Pass: on a touch device the thumbstick and the dynamic thumbstick walk, let go and stand.
378. [ ] **Edge to edge on notched phones (D-475; new).** Device emulator: iPhone 14 Pro in landscape, and an Android phone with a punch-hole camera. Land a kill impact frame and sprint.
   (a) Pass: the black and white overlay and the speed lines reach every screen edge, past the notch and the home indicator.
   (b) Pass: the HUD bars and text stay inside the safe area.
379. [ ] **The Highlight budget in a wide kill (D-476; new).** Setup C. Spawn 45 or more boars around the player with the DevCombat pack hook and lock none; sweep-kill the far 10. Each frame, count the Highlights in the workspace with Enabled true.
   (a) Pass: never more than 31 are enabled on any frame.
   (b) Pass: each struck boar flashes white for 2 frames.
380. [ ] **No clone burst on a hit (D-477; new).** Setup C, MicroProfiler open. Spawn 4 large rigs near the camera and wait 1 s, then land a Final hit on all 4.
   (a) Pass: the hit frame shows no Clone burst; clones appear spread at most 6 per Heartbeat while the rigs come into range.
381. [ ] **Kills that land together (D-478; new).** Setup C.
   (a) Pass: 3 boars killed in one sweep make one crack and one bloom (no stacked loudness), and each body flashes at its own spot.
   (b) Pass: a boss killed with its adds in one hit keeps the boss's long bloom (where a boss can be staged; otherwise report not run).
   (c) Pass (Lune cannot check this): Emit on the moved shared flash part, called several times in one frame, spawns at each body's position.
382. [ ] **Clip cues on the drawn frame at 60 Hz (D-479; new).** Open the place with Workspace attribute DevCapture = true and start Test > Clients and Servers with 2 players (A and B), both swords drawn. On each client start a Capture take so the frame counter and the alternating square show, and record the screen at the display's refresh rate (or use Capture's time scale 0.25). On A cast Vertical and step through the recording frame by frame.
   (a) Pass: the blade light, the blade glow and the white weapon flash first show on the first frame that shows the wind-up pose (the hold), never on the frame before.
   (b) Pass: the white weapon flash shows on exactly 3 frames.
   (c) Pass: the light and glow go out on the first frame that shows the downswing, and the ribbon's first segment appears on that same frame.
   (d) Pass: on every frame of the stroke the ribbon's newest end touches the blade tip (0 px ahead).
   (e) Pass: no new ribbon segment appears after the frame that shows the stroke's end pose.
383. [ ] **The same at 30 and 144 Hz (D-479; new).** Item 382's setup. Run workspace:SetAttribute("DevFrameCap", 30) and repeat item 382; then clear the cap and repeat on a 144 Hz display.
   (a) Pass: 382 (a) to (e) hold at both rates.
384. [ ] **The same on a remote rig (D-479; new).** Item 382's setup. On client B record A casting Vertical (A's rig is remote there).
   (a) Pass: 382 (a) to (e) hold on B's recording.
385. [ ] **Footsteps on their pose (D-479; new).** Item 382's setup, recording audio. Run A straight on stone, then cast Vertical.
   (a) Pass: each footstep's sound starts after the frame where its foot touches down by the same amount (±1 frame) as the chime starts after the light's first frame. Both cues now share their pose's frame, so this holds whatever the engine's audio latency.
386. [ ] **A dodge cancels the light (D-479; new).** Item 382's setup. On A cast Vertical and dodge as early in the wind-up as the input allows.
   (a) Pass: the light fades out (fx.activationLight.cancelFadeSeconds) and never comes back on, and no second chime plays.
387. [ ] **A distant rig stepped on Heartbeat (D-479; new).** Item 382's setup. Keep B more than choreo quality nearRadius (High 80 studs) from A and inside 160 studs, and record A's Vertical on B.
   (a) Report: the frame offset between the light's first frame and the hold pose's first frame, and between the ribbon head and the tip. Expected 0 for both; ±1 means distant rigs need their own lag (owner call).
388. [ ] **Flashes under a kill (D-479; new).** Item 382's setup. Kill a kobold with a Final hit during a recorded take.
   (a) Pass: no more than 3 full-screen flashes in any 1 s window.
   (b) Pass: the activation's weapon flash still shows while the screen flashes play.
389. [ ] **A boar rush's first step under lag (D-480; new).** Setup B with Incoming Replication Lag 0, then 0.05, then 0.25 s. At each, stage a boar with the DevCombat charge hook on a 1-stud grid floor and record its launch at 30 (DevFrameCap), 60 and 144 Hz.
   (a) Pass: the boar's first move after the crouch is no larger than its steady per-frame move: ≤ 0.94 studs at 30, ≤ 0.47 at 60, ≤ 0.20 at 144.
   (b) Pass: the strike still lands on the same contact frame as before.
   (c) Report: in Studio's order with lag above 0, the frame the late root first moves may add at most one more steady step (item 347(c)).
390. [ ] **The kobold stands on the floor (D-483; replaces item 370(c)).** Setup C (the floor at y = 0), then S("hold", {}) so every enemy stands still. In the Server command bar run `for _, m in workspace.Enemies:GetChildren() do local h = m:FindFirstChildOfClass("Humanoid"); if m:FindFirstChild("LeftLeg") and h then local low = math.huge; for _, n in {"LeftLeg", "RightLeg"} do local p = m[n]; for _, x in {-0.5, 0.5} do for _, y in {-0.5, 0.5} do for _, z in {-0.5, 0.5} do low = math.min(low, (p.CFrame * Vector3.new(x * p.Size.X, y * p.Size.Y, z * p.Size.Z)).Y) end end end end; print(m.Name, h.HipHeight, m.HumanoidRootPart.Position.Y, low) end end`.
   (a) Pass: HipHeight prints 2.4.
   (b) Pass: HumanoidRootPart Y is 3.4 ± 0.05 over the floor under it.
   (c) Pass: the lowest leg corner is within 0.02 of the floor (−0.02 to +0.02 on the y = 0 floor).
   (d) Pass: on the client during Idle (the logger's column 4) each kobold foot's lowest corner stays within 0.02 of the floor on every frame for 5 s.
391. [ ] **Enemy Break, Stagger and Walk feet in the ClipLab (D-482; new).** ClipLab (item 8) at 60 Hz, then on a 144 Hz monitor, in the walk view that carries the root at the rig's walkSpeed (boar 14, kobold 10). Play enemy/Boar/Walk and enemy/Kobold/Walk for 5 s each, then enemy/Boar/Break, enemy/Boar/Stagger and enemy/Kobold/Break, at 1x and at 0.25x, logging each foot's lowest corner every frame.
   (a) Pass: after the first 0.15 s of a walk, a planted foot moves ≤ 0.1 studs along the ground per 60 Hz frame and ≤ 0.25 over one plant, and no hoof or foot goes below −0.1.
   (b) Pass: the boar walk sounds 2 footsteps per 0.30 s, the kobold 2 per 0.50 s.
   (c) Pass: Boar Stagger: the front hooves clear the floor by about 0.12 at the top of the rear (0.1–0.2 s) and land by 0.42 s with one footstep, and the back hooves move ≤ 0.02 over the clip.
   (d) Pass: Boar Break kneels on folded front legs by 0.4 s; the planted parts move ≤ 0.02 per frame from 0.45 to 2.35 s; it stands by 2.95 s; no part turns more than 20° in one 60 Hz frame at the hand-back to Idle.
   (e) Pass: Kobold Break slumps onto its right toe by 0.4 s with the axe's lowest corner at or above the floor; the left foot moves ≤ 0.02 over the clip; it is up by 2.92 s.
   (f) Report: fill fresh hand cells in docs/ANIMATION_REVIEW.md for the two walks and the three Break and Stagger clips at 0.25x (the old cells describe the old walks).
392. [ ] **The enemy walk start in game (D-482; new; Lune cannot measure it).** Setup C. Release one boar and one kobold so they walk toward the player from 15 studs, and log each foot's lowest corner from the frame the enemy starts moving through 0.5 s.
   (a) Report: the largest per-frame slide and the drift over the first plant.
   (b) Pass: no planted foot slides more than 0.1 in one frame after 0.15 s. Frames before 0.15 s are reported only (RigDriver blends Idle to Walk at weightBlendRate 8/s while the Humanoid accelerates).
393. [ ] **The drawn run's legs pass each other (D-481; new).** Setup A, sword drawn. Run drawn at 1x, then capture at 0.25x and step two strides frame by frame from the side and from the front.
   (a) Pass: on every frame the right shin and foot stay outside the left shin; the gap never goes below −0.1 (Lune: deepest 0.038).
   (b) Report: the avatar's leg part sizes, because Lune's blank avatar can read 0.1–0.3 deeper.
394. [ ] **The blade goes through and out (D-484 to D-491, D-493; new).** Setup C with a held kobold 3.5 studs in front, then 4.8 studs (where the Brute starts its overhead). Play Basic1, Basic3, Horizontal, Vertical, Sharp Nail and Rising Arc at 1x and at 0.25x (Capture time scale).
   (a) Pass: after each freeze the blade carries on out of the kobold within about 6 frames and does not rest inside it; Horizontal's sword hand no longer stands inside the kobold's torso after the cut.
   (b) Pass: at 4.8, Vertical's and Basic3's blade stays clear of the kobold's legs after the hold.
   (c) Report: Rising Arc's second cut at 60 fps: the blade rises and rolls out to the right past the kobold's left arm; note any sink in the first frames after the hold (the audit now finds none).
   (d) Report by eye: the point-blank hit-matrix cells of Basic3, Horizontal and Sharp Nail, whose windows' last frames (0.23–0.24, 0.43–0.48, 0.95–0.98) now start the follow-through.
395. [ ] **Basic2's wind-up (D-492, D-493; new).** Setup C with a held kobold 3.5 studs in front, default camera.
   (a) Pass: mash Basic1 into Basic2: the second basic's wind-up leaves the guard smoothly, without a jerk.
   (b) Report: whether that wind-up reads as hidden behind the player's own torso (the audit measures 50% hidden and 47% of the snap's speed for the mash, and 67% hidden out of a half-speed run).
   (c) Pass: run at about half speed and press Basic2: the off hand does not pop in the first frames.
   (d) Report: in the frame before the snap (0.083 s) the cocked blade sits 0.153 inside the kobold's near side at 3.5, and at 0.067 s it sits 0.170 inside the near leg at 4.8. Judge whether either reads as clipping (owner call).
396. [ ] **Basic3's step back (D-485; new).** Setup C with a held kobold 3.5 studs in front. Play Basic3.
   (a) Pass: the first strike's step back is visibly smaller (1.00 studs instead of 1.25), with the player's head clear of the kobold's axe.

## AH. Section AF re-test after the fixes (D-494 to D-507)

Run these on the build with rounds F and G (D-469 to D-507) on the owner's PC, after or beside section AG. Item 397 changes the logger and the frame names for every AH item; run item 398 first, because shots 1, 6 and 11 depend on it. Report every pass line with its numbers. The table after item 418 says what became of every AF line the PC failed on 48a846f.

397. [ ] **The logger at Last+2 and the frame names as logged (D-353, D-468; replaces item 329's frame names from AH on).** Every AH item reads item 329's logger with two changes. First, bind its render step (its reads and its frame timer) at Enum.RenderPriority.Last.Value + 2, after DevFrameCap's Last+1 (D-468): at Last+1 the two shared a priority, so from frame to frame the timer ran before or after the cap's wait (333(a)); nothing that draws the frame runs after the camera's late step at Last, so every other read is the same as at Last+1. Second, AF's frame names were one frame off: the logger reads isPaused at Enum.RenderPriority.Input.Value + 1, before the local character step (Character+1), and a pose is drawn one frame after its step (impact.poseLagFrames 1), so the frame the logger called F was AF's F+1. From AH on every frame name is the row the logger logs, with no conversion. F is the first row whose isPaused reads true for a hit you land, and that row draws the contact pose; heldShown is true from F+1. W is the row the word's number first shows. E is the first row your isPaused reads true for an enemy blow on you; an enemy blow is judged on Heartbeat (D-355), so that row already draws the blow's strike pose. r is the capture panel's row count and f its count of frames of motion. How AF's names map: anything drawn on AF's F+k (k ≥ 1: the contact pose, white, picture, number, heldShown, a still blade) is AH's F+(k−1), so AF's "contact pose on F+1, heldShown from F+2" is AH's "contact pose on F, heldShown from F+1"; AF's F is AH's F−1, a row whose isPaused still reads false; a flag run counts rows from the first true one and reads the same (a Normal F..F+2, a Kill F..F+9); W, E, r and f keep their meaning. Add the columns the items below ask for: each enemy's Humanoid state, root y and MoveDirection (398), the root's AssemblyLinearVelocity at PreSimulation (401), TrailLit beside TrailOwner (406) and the Weapon motor's Part0 (415).
   (a) Pass: on a still idle, the drawn body and the root before and after physics differ by ≤ 0.01 studs a row (329(a)'s feet line is item 417's).
   (b) Pass (corrects 333(a)): at the 30 cap (workspace:SetAttribute("DevFrameCap", 30)) every frame is ≥ 33.2 ms, frames the engine did not overrun are 33.3 ± 0.2 ms, and r rises 300 ± 3 over any 10 s of a take. Report frames over 34.3 ms as engine overruns; the cap lets them go at once.
398. [ ] **Enemies stay upright through a hold (D-494; the boar jam; run this first).** Setup D: shots 6, 11 and 1, 3 takes each, at lag 0 and 0.1 s. Each row, log every enemy's Humanoid:GetState(), root y, Humanoid.MoveDirection and the charge's end reason (the jam logger); on the staged frame also log Humanoid:GetStateEnabled(Enum.HumanoidStateType.FallingDown). Then in setup C: hold a boar; on its Humanoid h run, in the Server command bar, `h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true); h:ChangeState(Enum.HumanoidStateType.FallingDown)`; release it with S("hold", {ids = {boarId}, on = false}); then S("charge", {entityId = boarId}).
   (a) Pass: GetStateEnabled(FallingDown) reads false on the staged frame, and no enemy reads FallingDown or Ragdoll on any row of any take.
   (b) Pass: every enemy's root y stays within 0.05 of its standing height on every row (the boar's was 1.199).
   (c) Pass: every first charge of shots 1, 6 and 11 ends Done, never Jammed, with MoveDirection non-zero from the launch row. Shot 6's telegraph starts within 0.35 s of the take's start (Lune 0.30 s) and its hit lands once at about 1.1 s (Lune 1.10 s).
   (d) Pass: the forced-down boar reads GettingUp, then Running, within 0.05 s (3 rows) of the release, and its charge ends Done at 22.
   (e) Report: Lune assumes that SetStateEnabled on the frame the model is made keeps the body Running, as the PC's check J showed 3 of 3. If any row reads FallingDown, log the row and the state sequence.
399. [ ] **Shot 6 and the rush blow, again (D-494; item 353 as written, with 354(c) and 355).** Setup D: shot 6 (enemy-boar-charge) at lag 0 and 0.05 s; shot 11 (enemy-boar-charge-rear); then shot 6 staged from about 25 studs off the spot. Frame steps are row n minus row n−1; f numbers are the capture panel's (the launch at about f60).
   (a) Pass (353(a)): the boar's Torso steps ≤ 0.6 a row (Lune mean 0.491, max 0.544); your white flash and impact moment first show on the row that draws the snout touching your body, never the row before; HitConfirmed comes 14 rows after that row at lag 0 (17 at 0.05 s), so nothing shows after it.
   (b) Pass (353(b)): level with you the boar is ≥ 3 studs to the right (Lune 3.20) with nothing inside your torso, and it is back on the line at rest.
   (c) Pass (353(c)): 4 dust puffs at about f91, 96, 102 and 109 (launch +31, +36, +42 and +49 rows).
   (d) Pass (353(d)): 48 ± 1 rows from telegraph to HitConfirmed; rest at about f124 with no backward step and ≤ 0.05 of slide over the next 10 rows (Lune 0.0006).
   (e) Pass (354(c)): on shot 11 the meet comes at about f68, and the take ends at 2 s.
   (f) Pass (355): on the staged frame the boar stands 12 ± 0.25 studs from your root; the telegraph starts within 0.35 s of the take's start and the hit lands once at about 1.1 s.
400. [ ] **Shot 1, the gate fight, again (D-494; replaces item 362 and 322(a)).** Setup D. Shot 1 (fight-boar-kobold), U, P, 20 s at 60 fps, at lag 0, 0.05 and 0.1 s. Log the r row of every parry spark, Art launch, basic hit, the boar's release, the dodge and the kill.
   (a) Pass (replaces 322(a)): about 6 parries, at 2.2, 5.6, 8.9, 12.3, 15.6 and 18.9 s. Q at about 3.5 s and 2 at about 6.8 s; the third parry's Art is cut by the dodge and comes back on the next cycle (D-459): 4 at about 13.5 s and 3 at about 16.8 s; no Art after 19 s.
   (b) Pass: 322(b) to (f) as written in section AE: the boar let go at 8.6 s, the dodge at about 9.3 s with no hit taken, the kill at about 10.8 s, full HP.
   (c) Pass (replaces 362(b)): 10–13 hits land at lag 0 (Lune 12: 5 basics, the kill among them, and 7 Art hits; ≥ 10 at 0.05 and 0.1 s); no basic lands during an Art; a held Art cut by a reaction cancels once and comes back on the next cycle; every overhead the take shows is guarded. D-458's 10–13 counted hits, not basics.
   (d) Pass (replaces 362(c)): the dodge is pressed 0.3 s before the Charge clip's hit window, at about 9.3 s (0.7 s after the 8.6 s release), and you cross the line with no hit taken.
401. [ ] **A slam rests at the wall, corrected layout (D-438, D-494; replaces item 347).** Setup C. Place the boar, then S("part", {size = {16, 8, 1}, …}) square to the charge heading with its face 12 studs from the boar's root: the rush is 22 studs (14 reach + 8 overshoot), so no face beyond 27.6 studs is ever met, and item 347's wall 30 studs off never was. S("charge", {entityId = boarId, toward = a point past the wall}); then again in the open; at lag 0, 0.05, 0.1 and 0.25 s; at 60 and 144 fps. Each row, log dt, the root at PreSimulation and at PostSimulation, root.AssemblyLinearVelocity at PreSimulation and the drawn body (HumanoidRootPart.CFrame * DrawnBody.offset(model)); on the server, log the root's position 1 s after the slam.
   (a) Pass: after the row the late root first moves from rest, every drawn step is ≤ 28 × dt + 0.05 (0.517 at a steady 60, 0.244 at 144); on that row it may add the root's own move (≤ 28 × dt). Lune: 0.467 at 60 and 0.194 at 144 at every lag. The PC's 0.509 was 28 studs/s over an 18.2 ms frame.
   (b) Pass: on every row but that one the snout is ≤ 0.05 past the face (Lune 0.000); no backward drawn step is over 0.02 in the 10 rows after the stop; the server root rests within 0.05 of the told stop (Lune 0.000), so the rest pose is 0.23 off the face.
   (c) Measure (no pass): from 10 rows before the root's first move to 10 rows after its stop, log (velocity × dt) − (the PostSimulation minus PreSimulation move). Lune assumes 0 ± 0.01. About +0.47 for 1–2 rows before the start and −0.47 after the stop means the replicated velocity leads the drawn root; the proposed predictor fix waits for this number.
402. [ ] **A charge after a hold, and two in a row (D-500; replaces item 348).** Setup C. With a boar mid-wind-up run `task.spawn(function() print(S("charge", {entityId = boarId, toward = …})) end); task.wait(0.3); print(S("hold", {ids = {boarId}})); print(S("charge", {entityId = boarId, toward = …}))`. Then two charges in a row against a wall, sending the second only after the first has replied (the hook is single-flight and answers "busy" until then). Then hold a boar 0.35 s after a wall slam and send S("charge") every 0.5 s.
   (a) Pass: the first charge replies complete = false with endedBy "hold", and the second charge is accepted (was "busy: a charge is still waiting").
   (b) Pass: every drawn step of the second charge is ≤ 28 × dt + 0.05, except the row the late root first moves from rest (≤ 2 × 28 × dt, 0.98 at 60). Log which row the PC's 0.904 falls on.
   (c) Pass: 348(b) and (c) as written in section AF.
403. [ ] **The 40° slope, corrected (D-495; replaces item 349).** Setup C. A 40° wedge slope, the boar charging uphill along it from 4 studs down the line, at lag 0, 0.1 and 0.25 s; then a vertical wall dead ahead.
   (a) Pass: the uphill charge ends Done at 22.00, never Jammed. Every drawn step's horizontal part is ≤ 28 × dt + 0.05 and its rise ≤ horizontal × tan(slope) + 0.05, which in 3D is ≤ 0.66 at 40° (Lune 0.609); the root's first-move row is excepted as in item 401.
   (b) Pass (corrected): the charge into the vertical wall ends "Wall" (a slam, with its daze), never Done. "Jammed" is only for stops the cast misses.
404. [ ] **The root holds on held frames (D-496; replaces 330(a)'s creep and 331(a) and (c)'s root and tip).** Setup A, then setup B at 0.1 s. A held kobold at 1.5, 1.75 and 2 studs; Sharp Nail, Basic1 and Rising Arc at 60 and 144 Hz; then item 330(c)'s kill and item 332(b)'s Basic1 kill at 0.1 s. Log the root, the tip and heldShown every row.
   (a) Pass: on every row heldShown is true (F+1 to the last held row), the root moves ≤ 0.005 and the tip ≤ 0.01 (were 0.181 and 0.217 at 60, 0.058–0.095 at 144).
   (b) Pass: on the first row with heldShown false after a run, the root moves by one step's share only (Sharp Nail's keep-out ≤ 0.2 at 60); no row moves two steps' worth.
   (c) Pass (330(a)): the tip moves ≤ 0.005 from F+1 to one row after the freeze's last flagged row (the PC saw 0.009–0.022 two frames after the freeze's end); for the kill, F+1 to F+10.
   (d) Pass: 332(b)'s Basic1 kill at 0.1 s moves the blade 0 on the last Ink row (was 0.017).
405. [ ] **The kill's camera hand-over (D-497; replaces item 334(b)).** Setup B at 0, 0.05 and 0.1 s. A locked kobold: a Basic3 kill with its HP above Basic3's damage (unproven at the contact), then one at 1 HP (proven), then a Rising Arc kill.
   (a) Pass: on the row the still shot starts (W for an unproven kill, F for a proven one) and on every still row, the camera's move minus the root's move is ≤ 0.001 (was 0.016–0.026).
   (b) Pass (corrected): inside the Rising Arc kill's still shot the camera moves exactly with the root, |camera move − root move| ≤ 0.001. Rising Arc's root moves 0.09–0.13 a row after its kill freeze, and the still shot moves only with the body (D-323).
   (c) Pass: on release no row jumps beyond the shot's own ease-out: the first row moves ≤ 0.06.
406. [ ] **The ribbon's close, timed by TrailLit (D-498; replaces 341(a) and 342(a)).** Setup D. Shots 4 (Sharp Nail), 5 (Rising Arc) and 2 (Horizontal) with the Side camera, at 60, 30 and 144 fps. Each row, log the Beams lit on the ribbon whose TrailOwner is your character and its TrailLit, both read in the same step.
   (a) Pass: from the first row TrailLit reads false, the Beams show on exactly 2 rows at 60 (1 at 30, 5 at 144), then 0 until the next window lights.
   (b) Pass: at least one row with 0 Beams between Sharp Nail's three cuts and between Rising Arc's two.
   (c) Pass (corrects 342(a)): Horizontal at 1x shows about 10 unfrozen rows with TrailLit true, and the arc is gone 2 rows after TrailLit falls (D-360 replaced D-335's 8–9-frame tail). Lune from the first lit row: 5 lit, 6 held, 2 lit, 2 fading, gone.
407. [ ] **Hit, hold and shake lines as the code draws them (no code change; corrects 330(b), 331(b), 332(a), 332(b), 332(d), 333(b), 333(c), 335(a), 351(a), 365(b) and 366(a)).** Run those items again as written in section AF, with these pass lines in place of theirs, in item 397's frame names.
   (a) 330(b), Sharp Nail Final: with HitConfirmed before the contact, W = F: the number shows on F with the contact pose (the word waits for the strike key, D-267). Dark F and F+1, white F+2 and F+3.
   (b) 332(a): a word before the contact gives W = F, the contact pose's row (heldShown is false there and true from F+1). The flag runs F..F+2 for a Normal and F..F+5 for a Final.
   (c) 332(b): a kill the client proves at the contact (predicted damage ≥ HP, D-358) plays Black F and F+1, Dark F+2 and F+3, Ink F+4 and F+5, whatever W is, with the number on W. An unproven kill plays Black W–W+1, Dark W+2–W+3, Ink W+4–W+5. At 0.15 s on the boar, pictures from the contact and the number after the 12-frame cap are a pass.
   (d) 332(d), and 366(a) at 30 fps: the tip's first step after a run, measured in the root's frame, is ≤ 0.25 at 60 (≤ 0.5 at 30). Report the root's own step on that row apart; D-424 caps it at 0.4 a 60 Hz frame. Owner call: should the bar also cover that body step?
   (e) 333(b): at 30 fps a kill's run is F..max(F+4, W), capped at F+6 (wordHoldSeconds 0.2 s). 7 rows at 0.1 s each way is right; 5 only when W ≤ F+4 (lag 0).
   (f) 331(b) and 333(c): at 144 Hz a kill holds round(0.1667 / the mean of the 32 frames before it) rows (D-352). Log those frame times: 24 rows at 6.94 ms, 23 at 7.2 ms, 22 at 7.5 ms.
   (g) 335(a), as the code stands: E's row draws the axe's strike pose, your white flash first shows on E+1, and the axe is still from E+1; both flags stay up with no gap until W (capped at 0.2 s). Owner call: should the white land on E with the strike pose? That moves the enemy blow's judge from Heartbeat into the render step (a D-355 timing change).
   (h) 351(a): measure the distance 3-D from your root to the slam point (the dust's centre, where the snout meets the wall), and the camera's offset from the row before contact. Rows 1–3 at ≤ 26 studs: 0.423, 0.391, 0.367 (row to row 0.423, 0.747, 0.703); 28 studs 0.741× (0.313), 29 studs 0.500× (0.211), 31 studs 0.074× (0.031), 32 studs or more 0. Owner call: should "the first frame is the largest" mean the offset from rest (what the code does) or the row-to-row move (which needs a different shake shape)?
   (i) 365(b), a dodge cut: turns of any size are allowed in the 3 snap rows after the cut (D-408's ExpoOut puts about 90% of the turn in the first); from the 4th row no part turns more than 20° in a row and none turns back.
408. [ ] **Logs before any fix (not reproduced in Lune).** Item 397's logger, in the setup each item names.
   (a) 361, shot 8: from the parry to the take's end, log each row the kobold's server root (Server command bar, or a server attribute), its client-drawn root, Anchored and the Humanoid state. Lune holds the server root at 0.000. Pass: both move 0.00 a row.
   (b) 365(b): log the CharacterController state and InputController.guardChanged on the press row, for a guard pressed 0.1 and 0.2 s into Basic1. Lune: state Guard on the press row, the guard weight 0.33, 0.67 and 1.00 on the next 3 rows.
   (c) 366(a): log the clip id, clip time, root position and tip around the 6.6-stud jump (the basic chain at the 3.5-stud staging, 60 Hz).
   (d) 335(a) and (b): each row, log the kobold Overhead handle's time in the render step and the server clock when the blow is judged on Heartbeat; your sword's WeaponMount Part0 on frozen rows; the kobold's flag; and the axe and sword tips through the 1-HP kill's Black, Dark and Ink rows at 0.12 and 0.15 s (PC: the flag fell on W+4, the axe moved 1.35–1.41 on the 2nd Ink row, the sword 0.22–0.91 on a frozen row and a 0.01–0.035 creep).
   (e) 366(c): log the head's height over the drawn idle, with the Root joint's Transform Y, on your avatar.
409. [ ] **Hands and arms stay out of the enemy (D-501; replaces the hand lines of 331(a), 336(b) and 366(b)).** Setup A: walk drawn into a held kobold square on and a held side-on boar until the body shell stops you (the drawn rests, Lune root to root: kobold 3.27, boar side-on 3.40 and 3.55), then stand touching a kobold's front just left of its axe (item 336); then setup D at the 3.5-stud staging. The four Arts and the basic chain at 60 and 144 Hz, and at 30 fps at the staging. Each row, log the deepest point of each hand and arm (LeftHand, RightHand and the upper and lower arms) inside the enemy's parts, the root's step with the row's dt, and whether each hit's number showed.
   (a) Pass: no hand or arm is more than 0.05 inside the enemy on any row of any swing (Lune: kobold 0.007, boar 0.009 at 30–240 Hz; was 0.69–0.71 in the boar, 0.43 in the kobold at 144, and 0.04–0.55 on first freeze rows).
   (b) Pass: every cut still lands and every hit's number shows; log any hit with no number at 144 Hz, with its row and its HitConfirmed (336(b) lost one).
   (c) Pass (corrects 336(a) at 60 and 336(c)): the root's step back or aside is ≤ 12 studs/s × that row's dt on every row (0.200 at 1/60 s, 0.083 at 1/144 s); the PC's 0.209 and 0.090 were 17.4 ms and 7.5 ms frames.
   (d) Report (still open): the same swings at item 331's closer placement, a kobold put 1.75 studs away with S("place") (no walk reaches it). Lune still holds a hand there: Sharp Nail Final 0.61 deep, Basic2 0.39 on early frames; the 3.5 keep-out budget and the 12 studs/s cap cannot clear both the column and the hands from that close.
410. [ ] **The stand-off at a wall and a pillar, with the trace (D-502; replaces item 337).** Setup C with the DevCombat trace on. A held kobold in front; your back flush to a wall, then to a pillar; Basic1, then Sharp Nail 3 times. Each row, log the root position, the root box's depth into the wall or pillar, and whether UpperTorso, LowerTorso or Head overlaps it (workspace:GetPartsInPart).
   (a) Pass: the root moves ≤ 0.001 toward the kobold over Basic1 (was 0.313).
   (b) Pass: the root box is ≤ 0.05 inside the wall or pillar on every row (was 0.48 and 0.79; Lune −0.017), and no row steps more than 0.20.
   (c) Report: if the body still slides along the wall, the rows where UpperTorso overlaps it (Lune: Basic1 at clip 0.150 s, 0.44 in; Sharp Nail's wind-up at 0.333 s, 0.63 in).
   (d) Report (owner call): the slide off the pillar over the 4 swings against D-315's own aside (Lune: 0.166 on Basic1 + 0.205 on the first Sharp Nail = 0.37). The proposed line is "the slide beyond the keep-out's own aside is ≤ 0.2".
411. [ ] **Kobold packs at one point (D-499; replaces 352(a)).** Setup C, the player at {0, 3, 25}. S("pack", {enemy = "KoboldAxeman", position = {0, 0, -20}, count = 3}), then count = 6 twice more at the same point.
   (a) Pass: every member spawns ≥ 12 studs from every other enemy and from you, with no "took the roomiest" line and no anti-cheat correction in the Output (Lune closest pair 12.05; was 10.29, with 6 such lines).
412. [ ] **The ledge never goes up round a late body (D-503; replaces 359(b), with a log for 359(a)).** Setup D with shot 5's ledge not built. Restart Play, walk straight back about 40 studs to where the ledge goes, choose the locomotion shot and press P; then again about 57 studs back, where the ramp goes. Then item 359(a)'s set-up.
   (a) Pass: at 40 studs the reply reads "stand clear of where DevStageLedge goes first" and nothing is built (was built round the body, which ended on top at y 9.24); walk to the ring and it stages there.
   (b) Pass: at 57 studs no ledge or ramp goes up round you, the ring shows at the stage area, and no anti-cheat flag shows.
   (c) Log (359(a)): for each moved enemy, the flat distance to shot 5's spot, its gap to the ledge-and-ramp footprint and its root Y. Pass: about 70 studs, ≥ 3 off the footprint, standing on the field floor.
413. [ ] **Two lines the spec answers (no code change; corrects 344(a) and 346(b)).** Setup A for (a); setup B at 0.15 s with setup C's S for (b).
   (a) 344(a), corrected: the kobold's only attack, Overhead, is a GuardBreak (section 6: the axe breaks guards; section 9: the Brute's 1.0 s overhead with a yellow edge), and the boar's Charge is unblockable, so the Playground has no blockable blow that does not break a guard. Pass: each of the 5 Overheads breaks the held guard (GuardBreak, 34 damage), and the Guard weight stays ≥ 0.99 on every row while the button is held, Parry included. GuardHit on a blockable blow stays covered by Lune's GuardHeld spec.
   (b) 346(b), corrected action: run S("place", {position = …, onWindUp = koboldId, after = 0.95}) and press the Art 0.05–0.1 s before the axe lands (0.9–0.95 s after it goes up). Pressed when the axe goes up, its hold pose comes about 0.15 s after the press, long before any blow shows, so it lights at 0.13 s as designed (D-326). Pass: 346(b) as written.
414. [ ] **Logs for the stand-off, the walk-in and the anti-cheat flags (not reproduced in Lune).** Item 397's logger.
   (a) 336(a) at 144 Hz: split each row's root step into the code's move and the engine's push: read root.CFrame after stepStandOff (Character+1) and again at the next frame's First, with the row's dt. Pass: the code's step is ≤ 12 × dt (Lune 0.083 at 144; the PC's 0.686 back and 0.361 aside are larger than any code step).
   (b) 338(b): over the last 15 rows of each front walk-in at 8 and 24 studs/s, log hum.WalkSpeed, the shell share, AssemblyLinearVelocity and the root-to-root distance; this measures the Humanoid's stopping overshoot (rest 3.14 against Lune's 3.27; a hand 0.589 in at a sprint). Log the sheathed rests too (not run in AF).
   (c) 338(c): for the 45° walk, log which enemy and which flank, the shell share, the held direction and the root yaw each row. Lune slides on every flank and stalls only at the kobold's front toward the axe (an inner corner).
   (d) 350(b): at the walk's start, log the boar's position, yaw and phase, every enemy within 10 studs (id, kind, distance) and the walk's reply. Lune walks 34.40 studs in 2.55 s; the 4.9-wide blocker in the PC's note is the kobold's (4.89), not the boar's (2.74).
   (e) Anti-cheat: for each speed flag, log the sample time, distance, allowance and state (Art, Basic or idle), and the name in each "fell off the rim" line.
415. [ ] **A sheathed guard under a cover, and the Draw's tip speed (D-504; replaces 344(b) and 345(b)).** Setup A, 240 fps capture, sheathed. (i) Press and hold guard 5 times standing and 5 times walking. (ii) Five times, press guard on the row a jump lands and release it 0.5 s later. (iii) Five times, hold guard while a lock 135° off turns the body. Then item 345's Draws, standing and at a sprint. Log the Weapon motor's Part0 every row; on any row the tip moves more than 1 stud, also log SheathState's input (covered, cut, drawFirst, drawing, drawTime), the live FullBody clip ids and Locomotion's turnUnderWay.
   (a) Pass: the tip's step divided by that row's own dt stays ≤ 84 studs/s (choreo sheath.drawTipSpeed): ≤ 0.35 in a 4.17 ms row, ≤ 1.4 in a 16.7 ms row (was 5.7–6.6 in one 240 Hz frame; Lune 7.41 → 0.290). This replaces 344(b)'s and 345(b)'s fixed 1.3 per 60 Hz frame and 0.33 per 240 Hz frame, which read uneven 240 Hz frames as speed.
   (b) Pass: on the first row the Weapon motor's Part0 reads RightHand, the hand is within 0.3 of the hilt (the grip pose is drawn on the next row).
   (c) Pass: with a cover, Part0 changes ≥ 0.22 s after the cover clip's weight falls to 0.
   (d) Report: any Draw jump of 4.5 studs or more (345(b) had 2 of 6, and 1.2–6.1 at a sprint), with the log above. Lune does not reproduce them; its worst, 1.51, is a cover arriving after the grab.
416. [ ] **Lock turns: feet, chest and head (D-505, D-507; replaces 363(b) and (c)).** Setup D, 60 fps. Stand drawn and lock a target 90°, 135° and 180° off each way. Sheathed, turn with C("face") and no lock: a lock predicts the draw, so a sheathed lock is drawn at once; C("face") writes the root on Heartbeat and keeps a one-row lead, so report it apart. Then shot 10 as item 363(a).
   (a) Pass: a planted foot moves ≤ 0.02 a row and ≤ 0.05 over the turn (Lune ≤ 0.010 and ≤ 0.015; PC 0.13–0.32 a frame).
   (b) Pass: chest and head lead the hips by ≤ 46° (45 + 1; Lune 45.4 and 45.1; PC up to 100°).
   (c) Pass: the non-pivot foot lifts and sets down once.
   (d) Log (363(a)): at shot 10's F press at 10.2 s, the sword's place (back or hand), the lock and the Draw clip. The PC found the sword already out, so no Draw played.
417. [ ] **Feet on the avatar's floor, and the landing (D-506; replaces 329(a)'s feet, 367(a)'s Land and 368(a) and (b)).** Setup A at 60 and 144 Hz, with the owner's avatar and once with a blank R15 avatar. Print once: Humanoid.HipHeight, the root's Size.Y, and the distance from the root's centre to the lowest sole while standing.
   (a) Pass: standing drawn for 10 s, each foot's lowest sole corner is within ±0.02 of the floor on every row (was 0.22–0.26 below; Lune within 0.004).
   (b) Pass: the drawn walk at 8 is planted on 63–75% of rows (was 32–35%) with step p90 < 0.02.
   (c) Pass: landing drawn and sheathed, no leg part turns more than 20° per 60 Hz frame from the logged touch-down row on (was 31–48°; Lune 34.8 → 12.0).
   (d) Pass (368(b)): standing drawn, the rear heel stays up with its ball ≤ 0.05 over the floor.
   (e) Report (368(c)): the kobold's root drop at each walk start and stop (PC 0.055 at the first start; not looked into yet).
418. [ ] **ClipLab and Rising Arc lines, and the one-shots still open (corrects 369(a) and 366(c); reports for 365(a) and 367).**
   (a) 369(a), corrected: in the ClipLab the pedestal stands still, so a planted hoof moves back at the rush's travel, 0.467 a 60 Hz frame from 0.62 to 1.13 s, easing to 0 by 1.68 s. Pass: a planted hoof's row step minus that travel is ≤ 0.1 (the PC's 0.48–0.51 leaves 0.01–0.04); or measure it in the Playground, behind a charging boar.
   (b) Report (369(a)): the kobold's lowest foot point below the field in Idle, Stagger and Walk (Lune on hipHeight 2.4: Idle 0.032, Stagger 0.013–0.041, Walk 0.053; AG item 390(d) holds the Idle bar), and that the Stagger's left foot is down by 0.45 s and home by 1.0 s (the PC's 0.70 off home was before D-482).
   (c) 366(c), corrected window: Rising Arc's head stands ≥ 0.22 over the drawn idle from the first snap's landing (clip 0.383 s) through its settle (0.517 s); after that it drops for Snap 2 by design (Lune 0.230–0.276 on the owner-sized avatar). Owner call: should the window end at the settle?
   (d) Report (365(a)): out of a sprint, the largest turn per 60 Hz row of each arm and leg part in the first 5 rows of each basic and Art (Lune out of SprintDrawn: arms 20.4–21.9°, feet ≤ 18.0; PC feet 21.7–26.5°).
   (e) Report (367): Skid out of a sprint (Lune 22.4° sheathed and 24.0° drawn per 60 Hz frame; PC 39–41°), the guard raise's and Sheathe's largest turns (PC 33° and 37°), and each dodge's root and sole corners per row (PC slides 0.11–0.20; not measured in Lune).

**AF lines after the fixes.** Every lettered AF line the PC reported failing on 48a846f (part 1 and part 2), plus the marginal 330(a) and the rehearsal. "Corrected pass line" means the test asked for the wrong thing; the corrected line is quoted (in item 397's frame names) and runs in the AH item named.

| AF line | On 48a846f | After the fixes | AH item |
| --- | --- | --- | --- |
| 329(a) feet | lowest corners 0.22–0.26 below the floor | Fixed by D-506 (the IK measures against the Humanoid's floor; Lune within 0.004) | 417 |
| 330(a) creep (a marginal pass) | the tip crept 0.009–0.022 on the two frames after the freeze | Fixed by D-496 | 404 |
| 330(b) Sharp Nail Final "F = W+2" | the number showed with the contact pose; HitConfirmed came 4 frames before F | Corrected pass line: "W = F: the number shows on F with the contact pose; Dark F and F+1, white F+2 and F+3". The word waits for the strike key (D-267), so an early word shows with the contact. | 407(a) |
| 331(a) root and tip on held frames | root up to 0.181, tip 0.217 at 60; 0.058–0.095 at 144 | Fixed by D-496 | 404 |
| 331(a) hands | a hand 0.69–0.71 in the boar's torso (Horizontal, Sharp Nail Final); 0.14–0.24 (Sharp Nail Normals, Basic1) | Fixed by D-501 at the walk-in rests (Lune ≤ 0.009); a kobold placed 1.75 away, closer than a walk reaches, still leaves Sharp Nail Final's hand 0.61 deep in Lune (409(d)) | 409 |
| 331(b) kobold kill at 144 Hz | held 22 frames (24 asked) | Corrected pass line: "a kill holds round(0.1667 / the mean of the 32 frames before it) rows: 24 at 6.94 ms, 23 at 7.2 ms, 22 at 7.5 ms". The hold counts frames from the measured pace (D-352), and those frames ran 7.5–7.6 ms. | 407(f) |
| 331(c) | the root moved up to 0.181 on frozen frames | Fixed by D-496 | 404 |
| 332(a) word before the contact | the number showed on the first frame with heldShown false | Corrected pass line: "a word before the contact gives W = F, the contact pose's row (heldShown false there, true from F+1)". The number shows with the contact pose (D-267). | 407(b) |
| 332(b) Basic1 kill at 0.1 s | the blade moved 0.017 on the last Ink frame | Fixed by D-496 | 404 |
| 332(b) Sharp Nail kill, root | the root moved 0.167 on a held frame | Fixed by D-496 | 404 |
| 332(b) Sharp Nail kill, picture | the picture started one frame before W | Corrected pass line: "a kill proven at the contact plays Black F and F+1, Dark F+2 and F+3, Ink F+4 and F+5 whatever W is, the number on W". A proven kill does not wait for its word (D-358). | 407(c) |
| 332(b) boar at 0.15 s | the pictures played from the contact; the number came after the 12-frame cap | Corrected pass line: as the row above; a number after the cap is a pass | 407(c) |
| 332(d) | the blade's first move after a run 0.325–0.354 (0.25 asked) | Corrected pass line: "the tip's first step after a run, in the root's frame, ≤ 0.25 at 60 (≤ 0.5 at 30), the root's own step reported apart". D-405's bar is the clip's own tip step; the keep-out's step (≤ 0.4, D-424) comes on top. Owner call on whether the bar covers the body step. | 407(d) |
| 333(a) | frames 29.5–37.2 ms at the 30 cap (±1 ms asked) | Corrected pass line, with the logger at Last+2: "every frame ≥ 33.2 ms; frames the engine did not overrun 33.3 ± 0.2 ms; r rises 300 ± 3 per 10 s; frames over 34.3 ms reported as overruns". The logger shared the cap's Last+1, so its timer ran before or after the cap's wait. | 397(b) |
| 333(b) | a kill at 0.1 s froze 7 frames (5 asked) | Corrected pass line: "at 30 fps a kill runs F..max(F+4, W), capped at F+6". The hold waits up to wordHoldSeconds 0.2 s for the word, 6 frames at 30. | 407(e) |
| 333(c) kobold kill at 144 Hz | held 22–23 frames | Corrected pass line: as 331(b) | 407(f) |
| 334(b) Basic3 kills | the camera moved 0.016–0.026 at the hand-over to the still shot | Fixed by D-497 | 405 |
| 334(b) Rising Arc kills | the camera drifted 0.13–0.14 a frame inside the still shot | Corrected pass line: "inside the still shot the camera moves exactly with the root, \|camera move − root move\| ≤ 0.001". The still shot moves only with the body (D-323), and Rising Arc's root moves 0.09–0.13 a frame after its kill freeze. | 405(b) |
| 335(a) the axe's strike pose | the axe drew its strike pose on E, a frame early | Still open (owner call): an enemy blow is judged on Heartbeat (D-355), so E's row already draws the strike pose; moving the judge into the render step would put the white on that row. The line for the code as it stands is 407(g). | 407(g), 408(d) |
| 335(a) your sword | moved 0.22–0.91 on a frozen frame | Needs a log (not reproduced in Lune) | 408(d) |
| 335(b) at 1 HP, 0.12–0.15 s | the kobold's flag fell at W+4; the axe moved 1.35–1.41 on the 2nd Ink frame; the sword crept 0.01–0.035 | Needs a log (not reproduced; the creep may be D-496's case and is measured again) | 408(d) |
| 335(b) at 0.2 s | a second freeze at the word | Not a bug: it is the player's own 0.5 s death freeze (section 6, Death) | — |
| 336(a) at 60 Hz | the largest step 0.209 (0.20 asked) | Corrected pass line: "a step ≤ 12 studs/s × that frame's dt (0.200 at 1/60 s, 0.083 at 1/144 s)". The cap is a speed (D-426), and 0.209 is a 17.4 ms frame. | 409(c) |
| 336(a) at 144 Hz | 0.686 back, 0.361 aside | Needs a log: larger than any code step (Lune 0.083), so an engine push; the log splits the two | 414(a) |
| 336(b) hands | 0.055 in at 60, 0.426 at 144 | Fixed by D-501 | 409 |
| 336(b) a missing number | one hit showed no number at 144 | Needs a log (no report reproduced it) | 409(b) |
| 336(c) | 0.090 at 144 (0.083 asked) | Corrected pass line: as 336(a) at 60; 0.090 is 12 studs/s over a 7.5 ms frame | 409(c) |
| 337(a) | the root moved 0.313 toward the kobold on Basic1 at the wall | Fixed by D-502 | 410 |
| 337(b) the root box and steps | the root box 0.48 into the wall and 0.79 into the pillar, steps up to 0.40, the body squeezed 5.4 along the wall | Fixed by D-502 (Lune −0.017, steps ≤ 0.166) | 410 |
| 337(b) the torso at the wall | part of the squeeze | Still open: the posed UpperTorso twists behind the root box (Lune: Basic1 0.44, Sharp Nail's wind-up 0.63), which only the engine resolves at a wall; whether the clips or the plan take it out is an owner call | 410(c) |
| 337(b) the slide off the pillar | 2.8 off the pillar (≤ 0.2 asked) | Still open (owner call): D-315's own aside is 0.37 over the 4 swings; the proposed line is "the slide beyond the keep-out's own aside ≤ 0.2" | 410(d) |
| 338(b) the kobold's front rest, hands at a sprint | rest 3.14 (3.27 asked); a hand 0.589 in at a sprint, 0.059 at the boar's right | Needs a log: the Humanoid's overshoot after the shell cuts WalkSpeed (Lune rest 3.27) | 414(b) |
| 338(c) | the 45° walk stalled at the flank (8 → 1 → 0 studs/s) | Needs a log: not reproduced (Lune slides on every flank and stalls only at the kobold's front toward the axe) | 414(c) |
| 341(a) | the window's close could not be timed | Fixed by D-498 (TrailLit) | 406 |
| 342(a) | the ribbon went out 5 unfrozen frames after the freeze (8–9 asked) | Corrected pass line: "the arc is gone 2 rows after TrailLit falls". D-360 replaced D-335's 8–9-frame tail. | 406(c) |
| 344(a) | all 5 Overheads broke the guard | Corrected pass line: "each Overhead breaks the held guard (GuardBreak, 34 damage); the Guard weight stays ≥ 0.99 while held, Parry included". The kobold's only attack is a GuardBreak (sections 6 and 9), and the boar's is unblockable. | 413(a) |
| 344(b) | the tip jumped 5.7–6.6 in one 240 Hz frame on 4 of 5 presses | Fixed by D-504 (Lune 7.41 → 0.290) | 415 |
| 345(b) steady Draws | 0.37–0.59 per 240 Hz frame, 1.18–1.39 per 60 Hz frame | Corrected pass line: "the tip's step / that frame's dt ≤ 84 studs/s (sheath.drawTipSpeed)". A fixed per-frame bar reads uneven 240 Hz frames as speed, and 1.39 is inside the code's 1.4 per 60 Hz frame. | 415(a) |
| 345(b) jumps | 2 of 6 Draws jumped 4.5–6.6; 1.2–6.1 per 240 Hz frame at a sprint | Needs a log (not reproduced; Lune's worst, 1.51, is a cover arriving after the grab) | 415(d) |
| 346(b) | the stance lit 0.13 s after the press | Not a bug: an Art pressed when the axe goes up is not doomed (D-326); its hold pose comes 0.15 s after the press, before any blow shows. The press belongs 0.05–0.1 s before the axe lands. | 413(b) |
| 347(a) the drawn step | 0.509 at lag 0 (0.467 asked) | Corrected pass line: "after the row the late root first moves, every drawn step ≤ 28 × dt + 0.05". 0.509 is 28 studs/s over an 18.2 ms frame. Item 347's 30-stud wall is never met (the rush is 22 studs); AH puts the face 12 studs out. | 401(a) |
| 347(a)(b) the snout past the face, back-snaps | the snout 0.67/0.24/0.10/0.19 past at 0/0.05/0.1/0.25 s; back-snaps 0.05–0.17 | Needs a log: they match a replicated root velocity that leads the drawn root by 1–2 frames (Lune 0.000 past the face) | 401(c) |
| 347(b) the rest | 0.28–0.51 off the face (0.23 asked) | Needs a log: the server body rests 0.05–0.28 short of the told stop (Lune lands exactly) | 401(b) |
| 347(c) | the drawn body moved 1–2 frames before RushStarted arrived | Not a bug: the telegraph predicts the launch, and RushStarted arrives a latency later (D-171) | — |
| 348(a) hold, then charge | not runnable: the second charge answered "busy" | Fixed by D-500 | 402(a) |
| 348(a) two in a row | a 0.904 drawn step (0.52 asked) | Corrected pass line: "≤ 28 × dt + 0.05, except the row the late root first moves from rest (≤ 2 × 28 × dt, 0.98 at 60)". That row is D-438's open first move; owner call. | 402(b) |
| 349(a) | drawn steps up to 0.76 on 17 frames (0.5 asked) | Corrected pass line (D-495): "horizontal ≤ 28 × dt + 0.05, rise ≤ horizontal × tan(slope) + 0.05, ≤ 0.66 in 3D at 40°". Lune 0.609 at 40°. | 403(a) |
| 349(b) | the tall wall ended "Wall", not "Jammed" | Corrected pass line: "the vertical wall ends Wall (a slam with its daze), never Done". A wall the cast sees is a slam (D-202, D-205, D-208). | 403(b) |
| 350(b) | the walk along the wall returned arrived=false after 0.07 s | Needs a log: not reproduced (Lune 34.40 studs in 2.55 s); the 4.9-wide blocker is the kobold's | 414(d) |
| 351(a) | the second shaken frame was the largest (0.72–0.75); 28 studs 0.46×, 29 studs 0.23× | Corrected pass line: offsets from the row before contact, the distance 3-D to the slam point (407(h)). The code's first offset is the largest (0.423, then 0.391); 0.72–0.75 is a frame-to-frame move, and the PC's distances ran about 1.15 short. Owner call on which reading. | 407(h) |
| 352(a) | a pack of 6 put two 10.29 apart; "took the roomiest" 6 times | Fixed by D-499 | 411 |
| 352, anti-cheat | 5 speed flags; "fell off the rim" twice | Needs a log: the code-made squeeze is fixed by D-502, the rest are engine squeezes | 414(e) |
| 353(a) to (d) | every staged charge Jammed (r67 at lag 0, r73 at 0.05 s); no rush, no HitConfirmed | Fixed by D-494 | 398, 399 |
| 354(c) the meet | shot 11's charge jammed | Fixed by D-494 | 399(e) |
| 355(b) | no hit; the telegraph at 0.35 s | Fixed by D-494 (Lune: telegraph 0.30 s, hit 1.10 s) | 399(f) |
| 359(a) | failed, with no numbers | Needs a log | 412(c) |
| 359(b) | at 40 studs the ledge went up round the body (y 9.24) | Fixed by D-503 | 412 |
| 361, shot 8 | the kobold moved 0.08–0.16 a frame after its recovery | Needs a log (Lune holds the server body at 0.000) | 408(a) |
| 362(a) | 5 parries; no release, dodge, lock or kill; a hit taken for 16 | Fixed by D-494 (the boar jam), with 322(a)'s corrected line | 400 |
| 362(b) | 9–10 hits, 1–2 basics | Corrected pass line: "10–13 hits land at lag 0 (Lune 12: 5 basics with the kill, 7 Art hits)". D-458's 10–13 counted hits, not basics. | 400(c) |
| 362(c) | no dodge (the boar never charged) | Corrected pass line: "the dodge is pressed 0.3 s before the Charge clip's hit window, at about 9.3 s". The line's 0.98 s could not be traced to the perform. | 400(d) |
| 363(a) at 10.2 s | no Draw: the sword was already out | Needs a log (no report traced why) | 416(d) |
| 363(b) | the feet never lifted and slid 0.13–0.32 a frame | Fixed by D-505 (the slide) and D-506 (the sink that hid the lift) | 416 |
| 363(b) sheathed | not run: a sheathed lock draws at once | Not a bug: a lock predicts the draw; a sheathed turn uses C("face") | 416 |
| 363(c) | the chest led by up to 100° | Fixed by D-507 (Lune 57.5 → 45.4; 100 not reproduced) | 416 |
| 365(a) out of the sprint | the feet turned 21.7–26.5° at f2–3 | Still open: Lune's arms reach 20.4–21.9° out of SprintDrawn (feet ≤ 18.0); ClipAudit has no Sprint@ plans yet | 418(d) |
| 365(b) the guard | a guard pressed 0.1 or 0.2 s into a basic rose only after the basic | Needs a log (Lune: Guard on the press frame) | 408(b) |
| 365(b) the dodge cut | a part turned 26–32° in a frame | Not a bug: D-408's cancel snap puts about 90% of its turn in the first frame, and the 20° bar starts on the 4th | 407(i) |
| 365, Shift with 2, 3 and 4 | the keys never reached Studio | Still open: the PC's remote input could not send them; the owner checks by hand | — |
| 366(a) the jump | the tip jumped 6.6 after a 2-frame basic freeze at 60 | Needs a log (not reproduced) | 408(c) |
| 366(a) at 30 fps | the first step 0.51–0.62 | Corrected pass line: as 332(d) (≤ 0.5 at 30, in the root's frame) | 407(d) |
| 366(b) | hands 0.04–0.55 inside the kobold on first freeze frames | Fixed by D-501 | 409 |
| 366(c) | Rising Arc's head dropped back to the idle height | Corrected pass line: "≥ 0.22 over the drawn idle from the first snap's landing (0.383 s) through its settle (0.517 s)"; after that it drops for Snap 2 by design (Lune 0.230–0.276). Owner call on the window. | 418(c), 408(e) |
| 367(a) Land | 31–48° | Fixed by D-506 (Lune 34.8 → 12.0) | 417(c) |
| 367(a) Skid | 39–41° | Still open: Lune 22.4 sheathed and 24.0 drawn per 60 Hz frame, unchanged | 418(e) |
| 367(a) the guard raise, Sheathe | 33°, 37° | Needs a log (not reproduced) | 418(e) |
| 367(b) | dodges slid 0.11–0.20 | Needs a log (not measured in Lune) | 418(e) |
| 368(a) | the drawn walk planted only 32–35% (p90 0.05) | Fixed by D-506 | 417(b) |
| 368(b) | feet 0.16–0.26 into the floor standing; the rear heel not up | Fixed by D-506 (the sink); the rear heel is measured again | 417(a), 417(d) |
| 368(c) | a 0.055 drop at the kobold's first start | Still open: not looked into | 417(e) |
| 369(a) the Charge's hooves | planted hooves moved 0.48–0.51 a frame at 1x | Corrected pass line: "a planted hoof's step minus the rush's travel (0.467 a 60 Hz frame from 0.62 to 1.13 s) ≤ 0.1". The ClipLab pedestal stands still. | 418(a) |
| 369(a) the kobold's feet | 0.08 into the floor | Still open: D-483 (round F) stands the rest pose on the floor (0.200 below → 0.000), but Lune still reads Idle 0.032 and Walk 0.053 below the field (bar 0.03) | 418(b) |
| 369(a) the kobold's Stagger | the left foot landed 0.70 off home | Fixed by D-482 (round F's re-key: drift 0.007, home by 1.0 s) | 418(b) |
| Rehearsal | shots 1, 6 and 11 failed (Jammed); nothing was recorded | Fixed by D-494 | 398, 419 |

Not run on 48a846f; run them as written in AF with item 397's frame names: 333(d) (jitter), 338(b)'s sheathed rests (in 414(b)), 338(d) (inconclusive), 340(c) (two clients), 344(c), 347 at 144 fps (in 401), 348(b)'s red line (in 402(c)), 365(c) and 369(b) and (c). For the owner by eye, ear or hand: 341(b) and 354(b) (report by eye), 371 (gamepad, touch and the **(listen)** checks), and the Shift + 2, 3 and 4 keys of 365.

419. [ ] **Rehearse, then record, the 11 gate shots (once every AH re-test passes).** Setup D, 60 fps cap, lag 0, the frame-tick square on. Rehearse all 11 shots in dev.luau order: 1 fight-boar-kobold, 2 art-horizontal, 3 art-vertical, 4 art-sharp-nail, 5 art-rising-arc, 6 enemy-boar-charge, 7 enemy-kobold-overhead, 8 parry-spark, 9 kill-shatter, 10 locomotion, 11 enemy-boar-charge-rear. Check each take against its own pass lines (shot 1: item 400; shots 6 and 11: items 398 and 399; the others: the AF, AG and AH items that name them) and log every take that fails one, with its r rows. If all 11 pass, turn Game Bar capture on at 60 fps, High quality, Studio's window only, record each shot with **View > Stats** open during shot 1 for the fps reading, save each under its name in `docs/clips/phase-0/README.md`, and turn Game Bar capture back off.
   (a) Pass: every rehearsal take passes its own lines, and the frame-tick square repeats no colour except where a logger batch drops (report those rows).
   (b) Pass: 11 files at 60 fps, each as long as its take, handed over for the frame-by-frame review at 0.25x.

## AI. Section AH re-test after the fixes (D-508 to D-522)

Run these on the build with the section AH fixes (D-508 to D-522) on the owner's PC. Item 420 adds columns to item 397's logger that every later AI line reads; frame names stay exactly as item 397 defines them (F is the first row whose isPaused reads true for a hit you land, and it draws the contact pose; heldShown is true from F+1; W is the row the word's number first shows; E is the first row your isPaused reads true for an enemy blow on you; r and f are the capture panel's counts). Run item 420's checks first, then item 421 (shot 1). Report every pass line with its numbers. The table after item 437 says what became of every AH and AG line the PC failed on 0582a04, and lists the AG items still to run; item 438 is the rehearsal and the recording.

420. [ ] **The logger for section AI (D-510, D-514, D-519; adds to item 397, corrects 397(b)).** Item 397's logger at Enum.RenderPriority.Last.Value + 2, with its frame names and columns, plus these. Each later AI line names the column it reads.
   1. Frame time: the first statement of the Last+2 step reads os.clock(); the row's frame time is this read minus the last row's. Beside it, log the render step's dt (the step's argument) and r.
   2. The drawn body for rush lines: a second render step bound at Enum.RenderPriority.Input.Value + 1, before the rigs' step, logs HumanoidRootPart.CFrame * DrawnBody.offset(model) and the boar's Torso CFrame. That is the pose this row draws: the last step's pose on the root physics moved, drawn again after physics (D-514). The Last+2 read is the next row's pose against the root before physics (about drawn − velocity × dt): judge no rush step and no wall face on it. If the rush lines below fail on the Input+1 read by about item 401(c)'s error (−0.12 to −0.43 a row at 60 fps), the frame was drawn before PostSimulation and D-514's redraw changed nothing: report it.
   3. Physics: your root and each enemy root in a RunService.PreSimulation connection and in a PostSimulation connection of the same frame, with root.AssemblyLinearVelocity at PreSimulation.
   4. The server root (for items 422 and 423): a runtime-only server script logs, each Heartbeat from the boar's RushStarted to 1 s after its stop, the server clock, the boar root's position, AssemblyLinearVelocity, Humanoid.WalkSpeed and the told stop (RushEnded's contact for a slam, the line end for an open run). Mark three rows. land: the first Heartbeat whose WalkSpeed leaves the rush speed (28) for the landing pace (EnemyService's engine.land, once the flat distance left is ≤ 28 × min(dt, 1/30) + 0.001). landingUntil: land's clock plus the distance left on that row / 28. landed: the first Heartbeat at or after landingUntil, where the flat velocity reads 0 (engine.halt). Superseded by item 439.
   5. The sword's mount (D-519): character:GetAttribute("WeaponMount") ("Back" or "Hand") and character:GetAttribute("WeaponMountWhy") beside the Weapon motor's Part0 (the motor is character.Weapon.Weapon.Weapon). The logger's Drawn column is the server's combat tag; where this client hangs the blade is WeaponMount.
   6. Clip time and world tip: each row, the local rig's live clip id and clip time, and the weapon tip in world space, solve(Part0) * C0 * Transform * C1:Inverse() * TrailEnd (not Weapon.CFrame, which reads a frame stale). A row's tip step is |tip − the previous row's tip|.
   7. tipDrawn: the tip logged on the row before. The Last+2 read comes after this row's step has written the pose, which is drawn on the next row (D-342), so the logged tip runs one row ahead of the picture; tipDrawn is what this row draws.
   8. Shot 6's clocks (D-511): on the client, the go reply's receivedAt (DevStage stamps every reply), the Telegraph payload's serverTime, and workspace:GetServerTimeNow() on the row the Telegraph arrives.
   9. Gaps: judge only pairs of rows whose r values are consecutive. Report every r gap (the PC's relay drops batches of about 50 rows at 144 Hz) and any row whose dt is over twice the median; a jump across a gap or a stall is not a move.
   (a) Pass (397(b), corrected; D-510): setup A with Workspace DevCapture = true and workspace:SetAttribute("DevFrameCap", 30), one 10 s take. Every row's os.clock frame time is ≥ 33.30 ms; rows the engine did not overrun are 33.33–33.5 ms; rows over 34.3 ms are engine overruns (the work before the cap took longer than 33.3 ms), and the row after one is again ≥ 33.30 (the cap's releases are ≥ 33.333 ms apart and never catch up).
   (b) Report (397(b)): the dt column, not judged per row. Single rows can read 33.3 ± 2.5 ms (Lune 31.5–35.1; the PC 31.94–35.66 with 60 rows under 33.2), because dt carries the change in the work after the cap; its mean over any 30 rows is 33.3 ± 0.2 ms.
   (c) Pass: r rises 300 ± 3 over any 10 s (the PC 300).
   (d) Confirm: both frame-time columns side by side for the take. Expect no os.clock row under 33.30 where dt has some. If the os.clock column also has rows under 33.30, something that varies runs between Last+1 and Last+2: then also log os.clock at the end of the logger's step, and list what is bound at Last+1 to Last+2.
421. [ ] **Shot 1, the gate fight (D-512, D-513; replaces item 400).** Setup D. Shot 1 (fight-boar-kobold), U, P, 20 s at 60 fps, at Incoming Replication Lag 0, 0.05 and 0.1 s (setup B's menu). Log the r row and take time of every parry spark, Art launch, basic hit, the boar's release, the Charge clip's start on your client with the clip time it started at, the dodge press, every HitConfirmed on you and the kill; on the rows the perform runs, your root's flat speed.
   (a) Pass: about 6 parries, at about 2.2, 5.5, 8.9, 12.3, 15.6 and 18.9 s, at every lag (Lune).
   (b) Pass: the boar is let go at about 8.6 s (the PC 8.67). The dodge is pressed 0.3 s before the Charge clip's hit window, at about 9.3 s, also at 0.1 s, where the Charge clip starts past its 0.10 and 0.11 s events (D-513; the PC had no dodge there and was hit at 9.9 s). You cross the line with no hit taken.
   (c) Pass: the boar is killed at 10.7–11.2 s at every lag (Lune 10.70–11.15), so no second charge comes (the PC at lag 0: never killed, and its second charge at about 15.3 s hit you for 16–34).
   (d) Pass: 10–13 hits land (Lune 12), 0 are taken and HP is full (300) at the end; no basic lands during an Art; every overhead the take shows is guarded.
   (e) Pass (D-512): on the perform's run rows your root runs at the sprint speed (choreo sprintSpeed 24), as a held sprint key does, not at the walk (walkSpeed 8) the Lune probe found before D-512.
422. [ ] **Shot 6's rush blow, read on the drawn row (D-514; replaces 399(a) and (d)).** Setup D: shot 6 (enemy-boar-charge) at lag 0 and 0.05 s, 3 takes each. Read the drawn body at Input+1 (item 420 column 2) and the server root (column 4). Log the rows of (i) the first row whose drawn snout lies inside your body, (ii) the impact moment's first row (your white flash), (iii) HitConfirmed's arrival, and (iv) your CharacterController.state() on row (i).
   (a) Pass (399(a)): the boar's Torso steps ≤ 0.6 a row on the Input+1 read (Lune mean 0.491, max 0.544; the PC 0.75–0.82 on 2–4 rows, on the Last+2 read before D-514). Superseded by item 455.
   (b) Pass (399(a), corrected): row (ii) is row (i) or the row after it, never before (i). Report the gap from (i) to (iii), not judged: the old "HitConfirmed 14 rows later" was a loopback count from round G (the PC saw HitConfirmed 1 row after the closest snout, with the white on its row).
   (c) Pass (399(d)): 48 ± 1 rows from the Telegraph to HitConfirmed (the PC passed).
   (d) Report (399(d)): the rest at about f124; the backward slide after the line end; and the server root's rest distance short of the line end (22), with its land, landingUntil and landed rows. The slide equals the server root's rest error (the PC 0.58 over about 30 rows), not a client step: the client ends the body on its root. Superseded by item 441.
   (e) Report (399(c), not run on 0582a04): 4 dust puffs at about f91, 96, 102 and 109.
423. [ ] **A slam at the wall and the open run (D-514; replaces 401(a) and (b)).** Setup C with item 401's layout: S("part", {size = {16, 8, 1}, …}) square to the charge heading, its face 12 studs from the boar's root. S("charge", {entityId = boarId, toward = a point past the wall}); then again in the open; at lag 0, 0.05, 0.1 and 0.25 s; at 60 and 144 fps. Read the drawn body at Input+1, the physics columns and the server root (item 420 columns 2 to 4).
   (a) Pass (401(a), corrected): every drawn step ≤ 28 × dt + 0.05, dt that row's own, on every row, the late root's first-move row included (Lune 0.467 at 60 and 0.194 at 144 at every lag; the PC was over by up to 0.108 on 9 of 14 runs). Superseded by item 454.
   (b) Pass (401(b), corrected): the snout is ≤ 0.05 past the face on every row, with no first-move exception (Lune 0.000; the PC up to 0.34 on 1–7 rows in 7 of 9 runs), and no backward drawn step is over 0.02 in the 10 rows after the stop (Lune 0.000). Superseded by item 454.
   (c) Pass (server; expected still to fail at 60 fps until the server's landing is fixed): the server root rests within 0.05 of the told stop (the PC 0.126 past at 60 fps, 0.015–0.03 at 144). Report its land, landingUntil and landed rows and the root 1 s after the stop, for the slam and for the open run: the fix (land again for what is left, or end an overshoot a physics substep early) waits on these rows. Superseded by items 440 and 441.
   (d) Log (the jumps): on any row with a drawn step over 1 stud (the PC's 1.903 just before a launch at 0.1 s, and item 424(c)'s 7.77), log whether DrawnBody.offset(model) is nil, the offset's position part, the root's PreSimulation → PostSimulation move and its AssemblyLinearVelocity, the Humanoid state, and the rows since the Telegraph and since RushStarted. A jump with a nil or rotation-only offset is the root's own: before the launch (Armed) the crouch stands on its root (D-255).
424. [ ] **Two charges in a row, the 40° slope and the first launch step (D-514; replaces 402(b), 402(c), 403(a) and AG 389).** Setup C: item 402's two charges in a row against a wall, then a hold 0.35 s after a slam; item 403's 40° wedge at lag 0, 0.1 and 0.25 s; then setup B at lag 0, 0.05 and 0.25 s with item 389's staged launch at 30 (DevFrameCap), 60 and 144 Hz. Read the drawn body at Input+1.
   (a) Pass (402(b)): every drawn step of the second charge is ≤ 28 × dt + 0.05, with no exception for the first-move row. Superseded by item 458.
   (b) Pass (402(c), corrected): after the slam, hold the boar 0.35 s, then send S("charge", {entityId = boarId, toward = a point 15 studs back along the wall's normal, away from the face}) every 0.5 s. It is accepted within 3.0 s of the slam (the PC about 1.5 s), and once accepted no refusal "Interrupted (Stagger)" comes until that charge's own end. A charge toward a point past the same wall slams again by design ("Wall", then its daze ends it "Interrupted", D-205, D-208): not a fail.
   (c) Pass (403(a), corrected): the uphill charge ends Done at 22.00; on every row, the first move included, the horizontal step is ≤ 28 × dt + 0.05 (dt the row's own) and the 3D step ≤ horizontal / cos 40° + 0.05 (Lune 0.609 at 60 fps; the PC 0.682 at 0.1 s). Item 423(d)'s log on any step over 1 stud (the PC's 7.77 at 0.25 s). Superseded by item 458.
   (d) Pass (AG 389(a), corrected): the first launch step is ≤ 28 × dt + 0.01, dt that row's own: the PC's 0.490 at 60 fps and 0.25 s is 28 studs/s over a 17.5 ms row and passes on any row of 17.2 ms or more. With D-514 the first-move row adds nothing more. 389(b) and (c) as written. Superseded by item 458.
425. [ ] **Enemies upright on the client, and shot 6's beat (D-508, D-509, D-511; replaces 398(a), (c) and 399(f), with a log for 398(e)).** Setup D: shots 6, 11 and 1, 3 takes each, at lag 0 and 0.1 s; then shot 6 staged from about 25 studs off the spot at lag 0. Log item 420 column 8 (shot 6's clocks); each enemy's Humanoid:GetState() on server and client and its root's flat speed each row; and, on the first row each enemy model exists on the client, GetState() and GetStateEnabled(Enum.HumanoidStateType.FallingDown). The take's start is the row where the capture panel's r reads 0 (the countdown's last row, where the go is asked).
   (a) Pass (398(a)): on the client, GetStateEnabled(FallingDown) reads false on the first row the model exists (the staged row). The server's call does not replicate; the client now makes its own (D-508). Superseded by item 442.
   (b) Pass (398(a)): no enemy reads FallingDown or Ragdoll on any row of any take, server or client (the PC: the client copy on 183–196 rows a take, every held row). Report root y (2.784–2.85 on 0582a04): nothing on the client reads an enemy Humanoid's state, so nothing drawn is expected to change. Superseded by item 442.
   (c) Pass (398(c), corrected; D-511): every first charge ends Done (22 studs), never Jammed. From the launch row (RushStarted's launchedAt) to the line end the server root's flat step is non-zero on every row and its average flat speed is 28 ± 1 studs/s (AI.rushSpeed 28; the PC's 27.6 passes); the client's replicated root averages the same ± 1. MoveDirection is not judged: it reads 0 throughout, because the run walks the Humanoid with MoveTo.
   (d) Pass (shot 6; D-509): the Telegraph's serverTime is 0.30–0.35 s after the go's receivedAt, at both lags (Lune 0.300–0.351; 0582a04 up to 0.401).
   (e) Pass (shot 6): the Telegraph arrives ≤ 22 rows after the take's start at lag 0 (expect 20–22, 0.333–0.367 s) and ≤ 32 rows at 0.1 s (expect 28–32, 0.467–0.533 s): the PC's 23–25 and 31–35 rows less the late tick's 3. If clock (d) shows that the 0582a04 takes already ran under 0.35 s, judge by (d) plus the logged network ways instead.
   (f) Pass (shot 6): one HitConfirmed, its serverTime 0.80 ± 0.02 s after the Telegraph's, arriving 48 ± 1 rows after the Telegraph row: expect 68–70 rows (1.13–1.17 s) at lag 0 and 77–80 rows (1.28–1.33 s) at 0.1 s (the PC 71–73 and 80–83).
   (g) Pass (399(f), corrected; the take staged from 25 studs): on the staged row the boar stands 12 ± 0.25 studs from your root; the Telegraph's serverTime is 0.30–0.35 s after the go's receivedAt and it arrives ≤ 22 rows (0.367 s) after the take's start; the hit lands once, 48 ± 1 rows after the Telegraph row (≤ 70 rows, 1.17 s).
   (h) Report (398(e)): the client's GetState() and GetStateEnabled(FallingDown) on the first row the model exists. If that row already reads FallingDown, the engine stepped the copy before the tag's handler ran: log the row and the state sequence (the client then needs a stand-up too). Superseded by item 442.
   (i) Report: on 0582a04, lag 0.1 s added 8–10 rows over lag 0 (more than 0.1 s); say from the three clocks whether Incoming Replication Lag also delays the go.
426. [ ] **Held rows, read on the drawn row (no code change; replaces 404(a) to (d)).** Setup A, then setup B at 0.1 s, with item 404's swings: a held kobold at 1.5, 1.75 and 2 studs; Sharp Nail, Basic1 and Rising Arc at 60 and 144 Hz; item 330(c)'s kill and item 332(b)'s Basic1 kill at 0.1 s. Columns: r, dt, the root at PreSimulation and PostSimulation, the tip and tipDrawn (item 420 columns 1, 3, 6, 7), consecutive r pairs only (column 9).
   (a) Pass: on rows F+1 to the last heldShown row, tipDrawn moves ≤ 0.01 and the root ≤ 0.005. On the last heldShown row the logged tip (not tipDrawn) shows the next row's first free step: ≤ 0.12 at 60 Hz (Lune Sharp Nail 0.074, 0.114 and 0.020; Basic1 0.054; Rising Arc 0.032 and 0.054) and ≤ 0.02 at 144 Hz (0.013, 0.020 and 0.0035; 0.0093; 0.0057 and 0.0093). The PC's 0.013–0.0585 fit this.
   (b) Report (the 144 Hz jump): for a tip jump like the PC's 9.2 studs in a 2-row run, its r values and dt. No held run that short exists at 144 Hz (a Normal holds 7 rows), so a jump across an r gap or a stall's wake row (D-132) is not a held-row move.
   (c) Pass (404(b)): on the first row with heldShown false the root moves one step's share. Report that row's PreSimulation → PostSimulation move apart (the PC's 0.29 and 0.37 at 144 Hz): that is the engine's push-out or the keep-out (which runs at 1/60), not the step; at 144 Hz the clip's own root step there is ≤ 0.003.
   (d) Pass (404(c)): tipDrawn moves ≤ 0.005 from F+1 to one row after the last flagged row (for the kill, F+1 to F+10). The logged tip on that last row is the next free step (Lune 0.2158; the PC ≤ 0.22).
   (e) Pass (404(d)): in the Basic1 kill at 0.1 s, tipDrawn on the last Ink row moves ≤ 0.005. The logged tip there (the PC 0.0138) is the first free step.
   (f) Report: under the lock the keep-out holds the body 2.0–3.6 studs from the kobold whatever the 1.5–2.0 placement (the PC); the root is held on held rows and the pose does not depend on where it stands, so no held-row number changes.
427. [ ] **The kill camera under lag (D-515; replaces 405(a) to (c)).** Setup B at 0, 0.05 and 0.1 s with item 405's kills: a Basic3 kill unproven at the contact, one at 1 HP (proven), and a Rising Arc kill. In the logger require CameraController and log CameraController.lockLive() and CameraController.lockedOn(koboldModel) each row; a still row is one with lockedOn true and lockLive false. Also log a workspace:Spherecast from the root + (0, 1.5, 0) toward the camera (radius 0.6, your character excluded): its hit part's full name and distance.
   (a) Pass: on every still row, the first one included, |camera move − root move| ≤ 0.001 (D-515; Lune's first still row was 0.13 before it, and the PC's first 3–6 rows were 0.14–0.38 at 0.05 and 0.1 s).
   (b) Pass: on rows from F to the first still row (the freeze), a proven kill (1 HP) moves ≤ 0.001 apart, because it plays no shake or nudge (D-358). An unproven kill plays its contact's shake there by design (section 10's hold, D-357): report its per-row size apart (Final ≤ about 0.4).
   (c) Pass (405(b)): the Rising Arc kill as (a).
   (d) Pass (405(c)): the first released row moves ≤ 0.06 (Lune 0.054; the peak 0.18 a row on rows 5 to 7, below 0.01 within about 40 rows).
   (e) Pass: any row that moves more than 0.2 plus the root's move shows a new Spherecast hit on that row (a wall's reach snaps in at once by design). Report the hit and the row for jumps like the PC's 0.455 and 1.72; with no hit it is a failure: report that row's lockLive and target.
428. [ ] **Ribbon rows, kill holds, the enemy blow's white and the slam's shake (no code change; corrects 406(c), 407(d), (e), (g) and (h)).** Run items 406 and 407 as written in section AH, with these lines in place of theirs.
   (a) 406(c): Horizontal at 1x. From the first row TrailLit reads true, at 60 fps: 5 rows lit (the first shows 0 Beams), 6 rows lit with heldShown true, 2 rows lit, 2 rows with TrailLit false and Beams > 0, then 0. So 7 lit rows have heldShown false, 6 of them with Beams (the PC's 6 passes; the old "about 10" was wrong). At 30 fps: 3 lit, 3 lit and held, 1 fading. At 144 Hz: 8 lit, 14 lit and held, 6 lit, then 406(a)'s 5-row fade.
   (b) 407(d): the tip's first drawn step after a run (tipDrawn on the first row with heldShown false) is ≤ 0.25 at 60 Hz and ≤ 0.5 at 30 fps (Lune at 30: Basic1 0.216, Basic3 0.30, Sharp Nail ≤ 0.47, Rising Arc ≤ 0.22). The rows after it are the clip's own motion: Basic1's and Basic3's settles are item 437's lines (the PC's 3.99 and 4.94 at 30 fps were Basic1's old settle flick, fixed by D-522).
   (c) 407(e) (corrects 333(b)): at 30 fps, a kill; log W and the rows of each picture look. A kill the contact proved (picture F, F+1, F+2): isPaused runs F..F+4 and heldShown F+1..F+5, whatever W is up to F+5. An unproven kill whose word comes inside the wait (W ≤ F+5; wordHoldSeconds 0.2 s is 6 rows): Black W, Dark W+1, Ink W+2; isPaused runs F..max(F+4, W+1) and heldShown one row longer, so the Ink row is drawn held (D-350); Lune: W = F+2 or F+3 gives 5 rows, W = F+4 gives 6 (Ink F+6), W = F+5 gives 7 (Ink F+7). A word after F+5: isPaused F..F+5 (6 rows), no picture (D-348), the number on W. The PC's 6 rows at 0.1 s pass if its W was F+4.
   (d) 407(g): your white flash first shows on E, and the axe is drawn still from E (E's row draws the strike pose). Both flags stay up with no gap until W (the PC: W = E+3), capped at 0.2 s. The old line's E+1 was wrong (this is Lune's EnemyStrikeHold), so its owner call no longer applies.
   (e) 407(h): on the slam row, measure the distance from your HumanoidRootPart to workspace.WallSlamDust's emitter part Position, which sits on the contact point the code measures to; not to the boar's root, which stands up to 5.6 studs behind its snout. With that distance the old scales stand: ≤ 26 studs whole; 28 studs 0.741×; 29 studs 0.500×; 31 studs 0.074×; 32 or more 0.
429. [ ] **The guard press in a basic, the kobold's guard break and a wide sweep (no code change; replaces 408(b) and (c), corrects AG 373(a) and 379(b)).**
   (a) Log (408(b)): setup A, a guard pressed 0.1 and 0.2 s into Basic1. Each row: the row UserInputService.InputBegan fires MouseButton2, the row InputController.guardChanged fires true, and CharacterController.state() (require the module). Pass: the state reads "Guard" on the row guardChanged fires (Lune: the press row; in code setGuard sets Guard on the press, with no buffer or retry). If guardChanged itself comes about 4 rows after InputBegan (the PC: Guard 0.066 s late), report it as engine or input delivery; if only a server-replicated state lags, that is the round trip.
   (b) AG 373(a), corrected: setup A, the held guard against the kobold's Overhead. Your freeze is 6 rows at Final. The kobold's axe tip moves ≤ 0.01 on the 6 rows from the row it first draws its strike pose. Its flag runs 6 − k rows, k being the Overhead's authored hold rows shown before the word (Lune k = 2, so 4 rows: the PC's 4 passes, and the axe is still for 2 + 4 = 6, D-471). The shake per row is ≤ about 0.4 and heavier than a block's (Final 0.3 against Normal 0.15; the PC 0.17–0.37).
   (c) AG 379(b), corrected: one Horizontal window hits at most combat.maxTargetsPerWindow = 6 boars (D-010, D-049). Pass: exactly 6 of the 10 are struck (the 6 nearest along the blade's path), each flashing white 2 rows (the PC: 6 of 10, a pass). Whether a sweep should hit more is an owner call.
   (d) Report (408(c)): at 30 fps Basic1's tip moves 1 to 2.4 a row in its snap, the normal snap speed. For a row like the PC's 4.4 in a 144 Hz Sharp Nail, log its r values, dt and clip time: across an r gap it is the relay; otherwise report the clip time (Sharp Nail passes D-522's settle rule in Lune).
**Items 430 to 437 and 438.** The fails the PC found in 430 to 437 on 4b18b5c are being fixed separately; a second part of section AJ follows with their re-tests, and item 438 waits for it.

430. [ ] **Hands at the gate kobold, staged at 4.2 and turned (D-518; replaces 409(a) to (c)).** Setup D, shots 2–5 and 9 as staged: the kobold 4.2 studs ahead, turned 10.35° to its own right, so you stand off its axe on its left. At 60 and 144 Hz and at 30 fps. On the staged row, log once the flat root-to-root distance and the kobold's turn off the line to your root. Each row from the take's first to the swing's last, log the deepest point of LeftHand, RightHand and the upper and lower arms inside the kobold's body parts and inside its Weapon; your root read after stepStandOff (Character+1) and again at the next frame's First, with the row's dt; and, for every predicted contact, the swing number, window, HitConfirmed's arrival row, W and the DevCombat trace line. Then setup A at item 409's walk-in rests (not run on 0582a04).
   (a) Pass: the staged distance is 4.2 ± 0.25 and the turn −10.35 ± 1°.
   (b) Pass (409(a)): no hand or arm is more than 0.05 inside the Weapon or the body on any row (Lune deepest −0.001, Horizontal's LeftHand at clip 0.797 s; at the old 3.5 staging Rising Arc 0.430 and 0.124 standing; the PC 0.4–1.0 on Art rows and 0.46–0.83 standing). Report any row over 0.05 with the hand's offset from your root and the kobold's idle time on that row: at 3.5 the PC's avatar read deeper than Lune's (0.46–0.83 against 0.124), and the fallback is to stage farther (the drawn shell clears the idling axe square on at 4.85).
   (c) Pass (409(b)): every cut lands and every hit's number shows, at 30, 60 and 144: Horizontal 1, Vertical 1, Sharp Nail 3, Rising Arc 2, the kill 1 (the PC at 30 fps: 10 hits, 9 numbers; Lune draws every counted hit at all three rates).
   (d) Pass (409(c), with 414(a)'s split): the code's step (the root after stepStandOff minus the previous First read) is ≤ 12 × that row's dt (0.400 at 1/30 s, 0.200 at 1/60, 0.083 at 1/144). Report the engine's push (First to First, less the code's step) apart: the PC's rows over 12·dt (3, 10 and 3 rows) are larger than any code step.
   (e) Pass (the walk-in rests): no hand or arm more than 0.05 inside the kobold's Weapon (Lune 0.019 with the kobold idling) or its body (0.007–0.009). 409(d) as written.
431. [ ] **The stand-off at a wall and a pillar (D-517; replaces item 410).** Setup C with the DevCombat trace on and a held kobold in front. Walk backward drawn until the body stops at the wall, then at the pillar; Basic1, then Sharp Nail 3 times. Each row log: your root at Character+1 (after stepStandOff) and at the next First; the root box's depth into the wall or pillar; UpperTorso, LowerTorso and Head overlap and depth (workspace:GetPartsInPart); UpperTorso's offset from the root as read at Character+1, against the clip's pose at the handle's time.
   (a) Pass (410(a)): the root moves ≤ 0.001 toward the kobold over Basic1 (Lune; the PC +0.22 at the pillar, most likely the engine pushing a torso out of it, whose code share D-517 removes).
   (b) Pass (410(b)): on any row where a colliding part is within 0.05 of the wall or pillar, or in it, the code's step back (Character+1 minus the previous First) is 0.000 (Lune before D-517: 0.125 on Basic1, 0.442 on Sharp Nail).
   (c) Pass: the root box is ≤ 0.05 inside the wall or pillar on every row (the PC 0.48 into the wall, 1.74 past the pillar's face).
   (d) Pass: the code's step is ≤ 12 × dt (0.200 at 1/60 s), and the UpperTorso offset check agrees within 0.05 (Lune assumes a part's CFrame read at Character+1 already shows this frame's pose).
   (e) Report: the torso and head depth from the clip's own lean (Lune past the drawn idle's back line: Basic1 0.21 at clip 0.151 s, Sharp Nail 0.39 at 0.332 s); any row whose First-to-First step is over 12 × dt, as the engine's share (the PC's steps up to 2.50); and the total slide along the wall (the PC 3.1–3.4; the code's own aside is 0.37 over the 4 swings, D-315). 410(c) and (d) as written.
432. [ ] **The ledge's reply, and the guard after a break (D-516; replaces 412(a) and 413(a)).**
   (a) 412(a), corrected: setup D with the locomotion shot's ledge not built. Restart Play and stand about 40 studs back where the ledge goes. Do not press P: P runs the walk-in first, which takes the body to the ring before the stage is asked. In the Client command bar run `print(game:GetService("HttpService"):JSONEncode(game:GetService("ReplicatedStorage"):WaitForChild("DevStage"):InvokeServer("stage", "locomotion")))`. Pass: the reply is ok = false with "stand clear of where DevStageLedge goes first", and nothing is built.
   (b) Then press P. Pass: the walk-in takes the body to the ring, the take stages with the body on the ledge top at shot 10's own start (root y about 9.24, the y 48a846f's run read), and on no row is a ledge part built while the body overlaps its footprint. 412(b) and (c) as written (not run on 0582a04).
   (c) 413(a), corrected: setup A. Hold the guard button through the whole take against the kobold's 5 Overheads. Pass: each of the 5 breaks the held guard (GuardBreak, 34 damage; the PC: only the first, then Stagger 34 four times); after each break the state reads GuardBroken for 1.2 s, then Guard within 2 rows of the stagger's end at lag 0 with the button still held; no Parry comes from a resumed guard; the Guard weight is ≥ 0.99 on every row while held, except from each break's E row until 0.08 s (the Guard clip's blendIn, 5 rows at 60 fps) after its stagger ends.
   (d) Pass: once, release the button inside a stagger: the guard stays down after it. 413(b) as written (not run on 0582a04).
433. [ ] **Where the sword hangs, and the sheathed guard's tip (D-519; replaces item 415).** Setup C, 240 fps capture, sheathed, with item 420 columns 5 and 6. Item 415's presses: (i) guard pressed and held 5 times standing and 5 times walking; (ii) 5 times on the row a jump lands, released 0.5 s later; (iii) 5 times while a lock 135° off turns the body; then item 345's Draws, standing and at a sprint.
   (a) Pass: sheathed, before the first press, WeaponMount reads "Back", WeaponMountWhy is nil and Part0 is UpperTorso on every row (the PC: Part0 RightHand on every row, so the sword most likely never went to the back).
   (b) Pass (415(a)): on a guard press while sheathed, the tip's speed in the root's frame (column 6's tip through the root's PointToObjectSpace, divided by the row's dt) is ≤ 84 studs/s on every row (choreo sheath.drawTipSpeed; Lune 61.1 standing, 62.0 walking 16 → 8, 66.6 on a Land, 61.2 under the lock at 135, 68.4 the Draw; the PC 321 over 22 rows). Superseded by item 444.
   (c) Report: if WeaponMount reads "Hand", WeaponMountWhy's text and the row it first reads so.
   (d) Pass (415(b), (c), once (a) passes): as written in item 415. 415(d) as written. Superseded by item 445.
434. [ ] **Lock-turn feet (no code change; corrects 416(a) and (c)).** Setup D, 60 fps, as item 416: stand drawn and lock a target 90°, 135° and 180° off each way. Log each foot's four sole corners every row.
   (a) Pass (416(a), corrected): the pivot foot's least-moving grounded corner moves ≤ 0.01 a row (Lune 0.002–0.005; the PC's pivot ≤ 0.03). Superseded by item 446.
   (b) Report, not judged: the whole-foot slide (Lune 0.150–0.433; the PC 0.15–0.43), which is the pivot foot turning flat on its sole (D-416), and each foot's end-to-end move (Lune 0.80–1.96; the PC 1.8–3.3), which a turn in place has to make.
   (c) Pass (416(c), corrected): with a 0.05 lift bar (the lowest corner more than 0.05 over the floor), the non-pivot foot lifts at most once per turn clip and the pivot foot at most twice (Lune: the pivot twice, the other once). With a lower bar the drawn stance's rear ball, 0.037 up (D-417), counts as lifted. 416(b) passed; 416(d) as written.
435. [ ] **Feet on the floor, the landing on the move and the held-at-spawn kobold (D-520, D-521; replaces item 417 and AG 390(b) to (d)).** Setup C at 60 and 144 Hz with the owner's avatar, item 420 column 5. Draw first by locking a target (F) and check that WeaponMount reads "Hand": the logger's Drawn column is the server's combat tag, and on 0582a04 it read false at W 16 although the sword was in hand. For the kobolds, item 390's Server command bar print.
   (a) Pass (417(a), drawn): on a still drawn idle, each foot's lowest sole corner is within ±0.02 of the floor on every row (Lune −0.007). Superseded by item 447.
   (b) Report (417(a), sheathed): the corner reads about −0.061 to −0.068 (the sheathed Idle's Root y −0.05 with the ankles at 4–8°; a clip re-key, still open). The PC's 0.06–0.10 below was most likely this stance.
   (c) Pass (417(b), as written): the drawn walk at 8 is planted on 63–75% of rows with step p90 < 0.02 (not run on 0582a04: the take moved at 16, sheathed). Superseded by item 448.
   (d) Pass (417(c); D-521): landing at W 16 and 24 from 0.25 and 0.5 s falls, on the touch-down row and the 0.35 s after it, no foot turns more than max(20, the stride's own) + 1° a row (Lune 19.3–20.3 against the stride's own 19.6–22.8; the PC 25.3° and 27.2°). Superseded by item 449.
   (e) Pass (417(d), drawn): standing drawn, the rear heel stays up, its ball ≤ 0.05 over the floor (Lune's drawn stance 0.037).
   (f) Pass (417(e), AG 390(c); D-520): a held-at-spawn kobold released does not drop (Δ root y ≤ 0.005; the PC 0.066 at the first start).
   (g) Pass (AG 390(b), (c), corrected): item 390's print reads every kobold's HumanoidRootPart Y 3.400 over the floor, held at spawn or pack-spawned alike (the PC's held ones read 3.45), and its lowest leg corner 0.000 ± 0.005 on all four kobolds (the PC +0.050 on the held ones).
   (h) Report (AG 390(d)): on the client during Idle, each kobold foot's lowest corner. The + side (the PC +0.018 to +0.044) was the 0.05 spawn lift and should read 0; the − side (the PC −0.033 to −0.006) is the kobold Idle clip's 0.032 sink, still open. Superseded by item 443.
436. [ ] **One-shot bars and Basic3's step back (no code change; corrects 418(d), (e) and AG 396).** Setup C: item 418's moves for 418, and a held kobold 3.5 studs in front for 396.
   (a) Report (418(d)): out of a sprint, the arms against the Sprint@ hand-off (the PC 21.2°, Lune 20.4–21.9°; still open). The feet pass under popDegrees 20 (the PC 18.0). Superseded by item 450.
   (b) Pass (418(e), the Skid): each row's foot turn is within the sprint's own per-row foot turn + 1° (the sprint's feet turn 31.8–33.2° a frame by themselves; the PC's Skid 20.9 passes).
   (c) Pass (418(e), the guard raise): the snap ends within cancel.snapFrames, 3 rows (D-408: it is a hand-over snap), not judged against 20° (the PC 31.7). Superseded by item 451.
   (d) Pass (418(e)): F and the dodges turn under 20° a row (the PC 1.7–12.8 and ≤ 17.4). Superseded by item 452.
   (e) Pass (AG 396, corrected; Basic3 started with you exactly 3.5 away): the root's net move back from Basic3's first row, minus the clip's own root motion (0 to 0.10 s, then 0.50 toward the kobold by 0.15 and 0.60 by 0.25), reads the keep-out's step: 1.00 by the key at 0.15. The root's raw net move is +0.60 at 0.10, +0.50 at 0.15 and +0.40 at the end.
   (f) Pass (AG 396, the chain): with three presses from 3.5, Basic3 starts about 3.75 away; its raw net move is +0.35 at 0.10, +0.25 at the key and +0.15 at the end, with a 0.75 keep-out step (the PC's 0.178 is in this band). The old line read the root's travel as the keep-out's step.
   (g) Pass: your head stays clear of the axe tip (the PC ≥ 2.78).
437. [ ] **Basic1 and Basic3 settle slower than their snaps (D-522; replaces the settle numbers in 407(d) and 408(c)).** Setup C, drawn, with no enemy within reach (no hit-stop and no keep-out), and item 420 column 6 (clip time, world tip). Press attack once for Basic1; then press three times for the chain and judge the third swing (Basic3). 3 takes each at the 60 fps cap, the 30 cap and uncapped (144 Hz). Each row's step is |tip − the previous row's tip|.
   (a) Pass: on every row from the snap's last row (clip time 0.15, plus one row) to the clip's end, or to the next basic's first row, the tip's step is below the largest step on that take's snap rows (clip time 0.10 to 0.15, plus one row).
   (b) Pass: at 60 fps Basic1's settle rows peak at about 2.35 studs a row around clip time 0.267, against a snap row of 3.80 (before D-522: 5.13 at 0.25); Basic3's at about 2.80 around 0.333, against 4.81.
   (c) Pass: at 144 Hz Basic1 1.06 against 1.62 (was 3.01) and Basic3 1.45 against 2.08 (was 1.62); at 30 fps Basic1 3.11 against 5.53 (was 4.48; the PC logged 3.99 and 4.94) and Basic3 4.17 against 6.69.
   (d) For the owner, by eye: Basic1's blade now rolls flat out to the left after the cut, where it used to flick up past the head, then settles to the guard. Say whether that is the follow-through wanted (Open items in PROGRESS).
   (e) Pass: with a held kobold at 3.5 (setup C), the blade is out of the kobold by the row at clip time 0.267 and stays out (Lune at 60 Hz rows: 0.25 +0.21, 0.267 −0.01, 0.283 −0.13).

**AH and AG lines after the fixes.** Every lettered AH and AG line the PC reported failing on 0582a04. "Corrected pass line" means the test asked for the wrong thing; the corrected line is quoted (in item 397's frame names) and runs in the AI item named.

| AH or AG line | On 0582a04 | After the fixes | AI item |
| --- | --- | --- | --- |
| 397(b) the 30 cap's frame times | 60 rows under 33.2 ms (least 31.94), 42 at 33.5–34.3, 1 overrun (35.66); 300 rows per 10 s passed | Corrected pass line (D-510): "os.clock read first in the Last+2 step: every row ≥ 33.30 ms, rows not overrun 33.33–33.5; the render step's dt reported, its 30-row mean 33.3 ± 0.2". The cap's releases are ≥ 33.333 ms apart; the PC's column was most likely dt, which carries the work after the cap. | 420(a)–(d) |
| 398(a) the client copy | each held enemy's client Humanoid read FallingDown on 183–196 rows a take, GetStateEnabled true | Fixed by D-508 | 425(a), (b) |
| 398(c) MoveDirection | 0 from the launch row through the rush, server and client, with the root at 27.6 studs/s | Corrected pass line (D-511): "the server root's flat step non-zero on every row from the launch row, its average 28 ± 1 studs/s; MoveDirection not judged". The run walks the Humanoid with MoveTo, and MoveDirection reports Humanoid:Move. | 425(c) |
| 398(c), 399(f) shot 6's beat | the Telegraph arrived 23–25 rows after the take's start at lag 0 (0.38–0.42 s; 0.35 asked), 31–35 at 0.1 s; the hit at rows 71–73 and 80–83, 48 rows after it | Fixed by D-509 (the alert's late tick: go → Telegraph 0.366–0.399 → 0.316–0.349 s in Lune), with the line judged from the server's go and the network logged apart (D-511) | 425(d)–(g) |
| 398, RushEnded on the client | the client logger never received a RushEnded | Not a bug: the server sends none for a run that ran its time (Done; EnemyService's endedPayload is nil for it) | — |
| 399(a) the Torso's steps | 0.75–0.82 a row on 2–4 rows (≤ 0.6 asked) | Fixed by D-514 (Lune at the PC's velocity error: drawn steps up to 0.862 → ≤ 0.467), read at Input+1 | 422(a) |
| 399(a) the white against the snout | the white showed on the HitConfirmed row, 1 row after the closest snout | Needs a log: not reproduced (Lune draws the touch 14 rows before HitConfirmed at lag 0). Either the predicted rush blow did not fire (rushBlow's openToBlows and exposedStates for the capture's state, or the attack not marked as a rush by the Telegraph), or "closest" and "touching" are different rows | 422(b) |
| 399(a) "HitConfirmed 14 rows later" | HitConfirmed came at the contact | Corrected pass line: "the white on the first touching row or the row after, never before; the gap to HitConfirmed reported". The 14 rows were round G's loopback count, not a bound. | 422(b) |
| 399(d) the back-step after the line end | the torso slid back 0.58 over about 30 rows | Needs a log: the hand-back slides the body onto a server root that rests about 0.58 short of the line end (the client must end on its root); the server fix waits for the land, landingUntil and landed rows | 420 column 4, 422(d) |
| 400 at lag 0 | 5 parries, 8–9 hits, the boar never killed; its second charge (about 15.3 s) hit for 16–34 | Fixed by D-512 | 421 |
| 400 at 0.1 s | no dodge, hit at 9.9 s, 12–13 hits; the only kill the kobold's at 16.8 s | Fixed by D-513 | 421 |
| 401(a) the drawn steps | over 28·dt + 0.05 by up to 0.108 on 9 of 14 runs | Fixed by D-514; the line drops the first-move exception | 423(a) |
| 401(a) the 1.903 jump | one 1.903 step just before a launch at 0.1 s | Needs a log: not reproduced in Lune under any root model; a jump in Armed is the root's own (D-255) | 423(d) |
| 401(b) the snout past the face | over 0.05 past on 1–7 rows, up to 0.34, in 7 of 9 runs | Fixed by D-514 (Lune 0.308–0.338 → 0.000) | 423(b) |
| 401(b) the server rest | 0.126 past the told stop at 60 fps (0.015–0.03 at 144 passed) | Needs a log: the landing stops dead on the first server frame after landingUntil, so the rest depends on the Humanoid and the frame; the fix (land again for what is left, or end an overshoot a physics substep early) waits for the server root's land, landingUntil and landed rows | 420 column 4, 423(c) |
| 402(c) the charge after a slam | accepted after about 1.5 s, but it slammed the same wall again (Interrupted) | Corrected pass line: "a charge toward a point 15 studs back along the wall's normal, accepted within 3.0 s of the slam, and no refusal 'Interrupted (Stagger)' until its own end". A charge past the same wall slams again by design (D-205, D-208). | 424(b) |
| 403(a) at 0.1 s | a 3D step of 0.682 (0.66 asked) | Fixed by D-514 (the design's 0.609 plus the root error) | 424(c) |
| 403(a) at 0.25 s | a 7.77 jump | Needs a log (not reproduced) | 423(d), 424(c) |
| 404(a) the tip on held rows | up to 0.0585 (Sharp Nail's 2nd Normal), 0.013–0.036 (Basic1, Rising Arc, the kills) | Corrected pass line: "tipDrawn ≤ 0.01 on F+1 to the last heldShown row; the logged tip on that last row is the next row's first free step, ≤ 0.12 at 60 Hz and ≤ 0.02 at 144". The Last+2 read runs one row ahead of the picture (D-342); Lune's drawn tip is 0.0000 on every held row. | 426(a) |
| 404(a) the 144 Hz jump | a 9.2-stud tip jump in a 2-row run | Needs a log (r and dt): no held run that short exists at 144 Hz (a Normal holds 7 rows); most likely a relay gap or a stall's wake row (D-132) | 426(b) |
| 404(b) at 144 Hz | the first free row moved 0.29 and 0.37 | Needs a log (PreSimulation → PostSimulation): the clip's own root step there is ≤ 0.003, so it is the keep-out or the engine's push-out | 426(c) |
| 404(c) | the tip moved up to 0.22 (0.005 asked) | Corrected pass line: "tipDrawn ≤ 0.005 from F+1 to one row after the last flagged row; the logged tip there is the next free step" (Lune 0.2158) | 426(d) |
| 404(d) | the last Ink row's tip moved 0.0138 | Corrected pass line: "tipDrawn on the last Ink row ≤ 0.005; the logged tip there is the first free step" | 426(e) |
| 404, the keep-out under the lock | the body stood 2.0–3.6 studs from the kobold whatever the 1.5–2.0 placement | Not a bug: the keep-out holds the body out by design (D-424, D-501), and the root is held on held rows, so no held-row number changes | 426(f) |
| 405(a), (b) under lag | the camera moved 0.14–0.38 apart from the root on the first 3–6 still rows at 0.05 and 0.1 s | Fixed by D-515 (Lune's first still or freeze row 0.1295 → 0.0000); the line names the still rows by lockLive and lockedOn, and an unproven kill's freeze rows before W shake by design (D-357) | 427(a)–(c) |
| 405(c) the late jumps | 0.455 and 1.72 camera jumps a few rows after the release (≤ 0.038 on release passed) | Needs a log (the Spherecast): 2.5 and 10 times Lune's peak (0.177 a row); a wall's reach snaps in at once by design | 427(e) |
| 406(c) | 6 unfrozen lit rows (about 10 asked) | Corrected pass line: "7 lit rows with heldShown false, 6 of them with Beams". The first lit row shows 0 Beams, and the old count was wrong; the PC's 6 passes. | 428(a) |
| 407(d) at 30 fps | a kill jumped 3.99 and 4.94 | Fixed by D-522: the logger's second free step, inside Basic1's Spring settle flick (Lune 4.605); the first drawn step stays within 0.5 (Lune ≤ 0.47), and the line judges tipDrawn | 428(b), 437 |
| 407(e) at 0.1 s | 6 rows (5 asked) | Corrected pass line: "an unproven kill with W inside the wait: isPaused F..max(F+4, W+1), heldShown a row longer; W = F+4 gives 6". The old formula left out D-350's hold over the picture. | 428(c) |
| 407(g) | the enemy blow's white showed on E, not E+1; the axe still from E; the flags to W = E+3 | Corrected pass line: "the white first shows on E and the axe is drawn still from E; both flags up until W, capped at 0.2 s". This matches Lune; the old E+1 was wrong, so its owner call no longer applies. | 428(d) |
| 407(h) the slam shake by distance | 20 studs 0.420 / 0.387 / 0.365 (passed); 26 studs 0 and 0.155; 28 studs 0.012; 29–30.6 studs 0 | Corrected pass line: "the distance from your root to workspace.WallSlamDust's emitter part, the contact point the code measures to; the old scales stand". The PC's numbers fit a distance 3.4–6 studs longer, to the boar's root, which stands up to 5.6 behind its snout. | 428(e) |
| 408(b) | a right-mouse guard 0.08 and 0.2 s into Basic1 reached Guard 0.066 s late | Needs a log (InputBegan, guardChanged, CharacterController.state()): in code setGuard sets Guard on the press, with no buffer or retry | 429(a) |
| 408(c) at 30 fps | Basic1's tip moved 1–2.4 a row | Not a bug: that is the snap's normal speed at 30 fps | 429(d) |
| 408(c) at 144 Hz | one Sharp Nail row moved 4.4 | Needs a log (r, dt and clip time): most likely a relay gap; Sharp Nail passes D-522's settle rule | 429(d) |
| 409(a) hands at the staging | 0.4–1.0 inside the kobold on Art rows at 3.5; 0.46–0.83 inside its axe standing still | Fixed by D-518 (staged at 4.2, turned −10.35°: Lune's deepest 0.430 → −0.001) | 430(a), (b) |
| 409(b) at 30 fps | 10 hits, 9 numbers | Needs a log (swing, window, HitConfirmed row, W, trace line): not reproduced (Lune draws every counted hit at 30, 60 and 144) | 430(c) |
| 409(c) the root's steps | over 12·dt on 3, 10 and 3 rows | Needs a log (the code's move split from the engine's push, as 414(a)): Lune's step stays within 12·dt (0.400 / 0.200 / 0.083) | 430(d) |
| 410(a) at the pillar | +0.22 toward the kobold | Needs a log: Lune moves ≤ 0.001; most likely the engine pushing a torso out of the pillar, whose code share D-517 removes | 431(a) |
| 410(b) the root box | 0.48 into the wall, 1.74 past the pillar's face | Fixed by D-517 (the room counts the torsos and head: Sharp Nail's step into a touching wall 0.442 → 0) | 431(b), (c) |
| 410(b) the steps and the slide | steps up to 2.50; slid 3.1–3.4 sideways | Needs a log (First to First against the code's step): larger than any code step (0.2 a row at 60 fps), so the engine's | 431(d), (e) |
| 412(a) the reply | "stand clear" was not shown | Corrected pass line: "40 studs back, ask the stage from the Client command bar without pressing P: ok = false, 'stand clear of where DevStageLedge goes first', nothing built". P runs the walk-in first, which takes the body to the ring. | 432(a), (b) |
| 413(a) the guard after a break | only the first Overhead broke the held guard; it never came back, so 2–5 landed unguarded (Stagger, 34) | Fixed by D-516 | 432(c), (d) |
| 415(a) the sheathed guard's tip | up to 321 studs/s, 22 rows over the 84 bar | Needs a log (WeaponMount): Lune shows that pattern only when the sword is never sheathed (Part0 RightHand on every row, as the PC logged); D-519 retries a late category or torso and names the reason, but the PC's cause is not proven | 433(a)–(c) |
| 415(b), (c) | not measured (Part0 read RightHand on every row) | Needs a log: the same cause as 415(a); measured once WeaponMount reads "Back" | 433(d) |
| 416(a) the other foot | its planted corners slid 0.15–0.43 a row; each foot ended 1.8–3.3 from its start | Corrected pass line: "the pivot foot's least-moving grounded corner ≤ 0.01 a row; the whole-foot slide reported". 0.15–0.43 is the pivot foot turning flat on its sole (D-416; Lune 0.150–0.433, its least-moving corner 0.002–0.005). | 434(a), (b) |
| 416(c) the lifts | the non-pivot foot lifted 2–3 times | Corrected pass line: "with a 0.05 lift bar, the non-pivot foot lifts at most once per turn clip and the pivot at most twice". With a lower bar the drawn stance's rear ball (0.037 up) reads as a lift. | 434(c) |
| 417(a) the soles | 0.06–0.10 below the floor on every row | Still open: Lune's drawn stance stands within −0.007; the PC most likely stood sheathed (Drawn false), where the sheathed Idle sits −0.061 to −0.068 (its Root y −0.05, ankles at 4–8°), a clip re-key not done | 435(a), (b) |
| 417(b) the drawn walk | the take moved at 16 (planted 18–21%); the drawn walk at 8 was not produced (Drawn read false) | Corrected pass line: "draw by locking a target (F) first, with WeaponMount reading 'Hand'; the drawn walk at 8 planted on 63–75%, step p90 < 0.02". The logger's Drawn column is the server's combat tag, not where this client hangs the blade. | 435(c) |
| 417(c) the landing leg | turned 25.3° and 27.2° | Fixed by D-521 | 435(d) |
| 417(d) the heel | no heel up | Corrected pass line: "standing drawn (WeaponMount 'Hand'), the rear ball ≤ 0.05 over the floor". The line is for the drawn stance (368(b)); the PC most likely stood sheathed, as in 417(a). | 435(e) |
| 417(e) the start drop | 0.066 at the first start | Fixed by D-520 | 435(f) |
| 418(d) out of a sprint | arms 21.2°, feet 18.0° | Still open: arms over 20 are the known Sprint@ hand-off (ClipAudit has no Sprint@ plans yet); the feet pass popDegrees 20 | 436(a) |
| 418(e) the Skid | 20.9° (drawn) | Corrected pass line: "within the sprint's own per-row foot turn + 1°". The sprint's feet turn 31.8–33.2° a frame by themselves; owner call on that bar. | 436(b) |
| 418(e) the guard raise | 31.7° | Corrected pass line: "the snap ends within cancel.snapFrames, 3 rows (D-408)". It is a hand-over snap, not a pop. | 436(c) |
| AG 373(a) the kobold's flag | 4 rows (6 asked) | Corrected pass line: "the axe drawn still 6 rows from its strike pose; its flag 6 − k rows, k the authored hold rows shown before the word (k = 2: 4 rows)". The Overhead's own Hold shows 2 rows before the word, so the axe is still for 2 + 4 = 6 (D-471). | 429(b) |
| AG 379(b) the wide kill | 6 of 10 boars killed | Not a bug: one window hits at most combat.maxTargetsPerWindow = 6 targets (D-010, D-049); the 6 struck flash white together. Owner call on whether a sweep should hit more. | 429(c) |
| AG 389 the first launch step | 0.490 at 60 fps and 0.25 s (0.47 asked) | Corrected pass line: "≤ 28 × dt + 0.01, dt the row's own". 0.490 is 28 studs/s over a 17.5 ms row. | 424(d) |
| AG 390(c) the held kobolds | +0.05 over the floor (root 3.45) | Fixed by D-520 | 435(g) |
| AG 390(d) the + side | idle feet +0.018 to +0.044 | Fixed by D-520 (the spawn lift) | 435(h) |
| AG 390(d) the − side | idle feet −0.033 to −0.006 | Still open: the kobold Idle clip's 0.032 sink | 435(h) |
| AG 396 Basic3's step back | 0.178 (1.00 asked) | Corrected pass line: "the root's net move back minus the clip's own root motion reads the keep-out's 1.00 by the key at 0.15 (alone from 3.5); in the chain Basic3 starts about 3.75 away, raw +0.25 at the key with a 0.75 step". The line read the root's travel as the keep-out's step. | 436(e), (f) |

Counts: 61 lines, 17 fixed, 21 corrected pass lines, 4 not bugs, 16 that need a log, 3 still open. Not game issues: keys pressed with Shift held (Q, 2, 3, 4) never reached Studio, an input problem on the PC (the owner checks the Shift keys by hand), and the PC's relay drops batches of about 50 rows at 144 Hz (item 420 column 9 reports the gaps).

Not run on 0582a04; still to run, as written in AG with item 397's frame names: the two-client items 372, 374, 375, 376, 384 and 387 (Test > Clients and Servers); 383 (30 and 144 Hz recordings stepped frame by frame), 391 (ClipLab, with its hand cells in `docs/ANIMATION_REVIEW.md`) and 392 (the timed walk start). For the owner, by eye, ear, gamepad or phone: 377(b) with a gamepad (the keyboard half passed), 377(c) on a touch device, 378 on notched phones, 380 (the Clone burst in the MicroProfiler, by eye), 381 (one crack and one bloom, by ear and eye), 385 (footsteps against the chime, by ear), 386 (the light fading and no second chime), 388 (flashes in a 1 s window), 393 to 395 (legs, blade and wind-up by eye at 0.25x), 372's digit colours and land sound, and 375's whoosh with no skid. AH lines not run, to run as written: 399(c), 408(d) and (e), 409's walk-in rests and 409(d), 410(c), 412(b) and (c), 413(b), 414(a) to (d), 416(d) (not reported), 418(a) and (b) (ClipLab), and the AF lines listed as not run after item 418.

438. [ ] **Rehearse, then record, the 11 gate shots (once every AI re-test passes; replaces item 419).** Setup D, 60 fps cap, lag 0, the frame-tick square on. Rehearse all 11 shots in dev.luau order: 1 fight-boar-kobold, 2 art-horizontal, 3 art-vertical, 4 art-sharp-nail, 5 art-rising-arc, 6 enemy-boar-charge, 7 enemy-kobold-overhead, 8 parry-spark, 9 kill-shatter, 10 locomotion, 11 enemy-boar-charge-rear. Check each take against its own pass lines (shot 1: item 421; shots 6 and 11: items 422 and 425; shots 2–5 and 9: item 430's staging and hands; shot 10: items 432(b), 434 and 435; the others: the AF, AG, AH and AI items that name them) and log every take that fails one, with its r rows. If all 11 pass, turn Game Bar capture on at 60 fps, High quality, Studio's window only, record each shot with **View > Stats** open during shot 1 for the fps reading, save each under its name in `docs/clips/phase-0/README.md`, and turn Game Bar capture back off.
   (a) Pass: every rehearsal take passes its own lines, and the frame-tick square repeats no colour except where a logger batch drops (report those rows).
   (b) Pass: 11 files at 60 fps, each as long as its take, handed over for the frame-by-frame review at 0.25x.

## AJ. Section AI re-test after the fixes, first part (D-523 to D-526)

Run these on the build with the first part of the section AI fixes (D-523 to D-526) on the owner's PC. Frame names stay exactly as item 397 defines them (a row is the logger's at Last+2), and item 420's columns stand except column 4, which item 439 replaces. Report every pass line with its numbers. The render check, measured on 4b18b5c at 60 fps with rows at Last+2: a joint Transform written on PostSimulation never shows on screen (the boar's Root lifted 3 studs and the avatar's RightShoulder turned +80°: neither visible); written in the render step at Camera−1 it shows, steadily; written on PreSimulation it shows on the boar, while on the avatar's arm the game's own PreSimulation write replaces it. On every test the screen matched BasePart.CFrame, and BasePart.CFrame at Last+2 equals the previous row's joint-chain read (300 of 301 rows): the screen shows the pose as physics solved it, so D-514's PostSimulation redraw has no visible effect. Items 422(a), 423(b) and 424 stay open, keep their AI lines and are being re-worked, and the fails in 430 to 437 are being fixed separately; a second part of this section follows with both.

439. [ ] **The server root log, corrected marks (D-525; replaces item 420 column 4).** A runtime-only server script logs, each Heartbeat from the boar's RushStarted until 1 s after its stop, the server clock, the boar root's position, AssemblyLinearVelocity, Humanoid.WalkSpeed and the told stop (RushEnded's contact for a slam, the line end for an open run). "along" is the root's flat distance from the launch point along the run; times are from RushStarted. Mark these rows.
   1. land: for a slam, the first Heartbeat whose flat distance to the told stop is ≤ 28/30 + 0.001 = 0.934 (the rush speed times ai.movement.haltLeadSeconds, 1/30) or whose WalkSpeed is under 28, whichever comes first; for an open run, the Done row (the run's end stays on its timer).
   2. The landing rows: from land on, WalkSpeed reads about the distance left / (2 × that row's dt) (ai.movement.landFrames 2), capped at 28 (at 144 Hz it reads 28 until the body is about 0.39 from the stop), and shrinks each row.
   3. landingUntil: land + 0.25 (ai.movement.landMaxSeconds). It is now a bound, not the landing's end.
   4. landed: the first Heartbeat after land whose flat velocity reads 0 (Engine.halt).
   5. The rest: along on the landed row, and along 1 s after the stop.
440. [ ] **A slam's server rest, corrected (D-525, D-526; replaces 423(c) for the slam).** Setup C with item 401's layout: S("part", {size = {16, 8, 1}, …}) square to the charge heading, its face 12 studs from the boar's root; S("charge", {entityId = boarId, toward = a point past the wall}). At lag 0, 0.05, 0.1 and 0.25 s, at 60 and 144 fps, 3 takes each, with item 439's log.
   (a) Pass: RushEnded "Wall" tells a stop (Lune 6.169 along, sent at +0.116 s), and at 60 fps WalkSpeed first reads under 28 on the land row or the row after (the log and EnemyService both run on Heartbeat, in either order). Lune: land at +0.217 s, along 5.360, 0.809 left, WalkSpeed 24.25.
   (b) Pass: the landing's WalkSpeed shrinks each row (Lune 24.25, 12.12, 6.06, 3.03, 1.52, 0.76), and landed comes ≤ 0.25 s after land (Lune 6 rows, 0.100 s, at 60 fps; 7 rows at 144).
   (c) Pass: from land to 1 s after the stop, no row's along is more than 0.05 past the told stop (Lune rests at 6.156 at 60 fps and 6.159 at 144, landed at +0.254 s).
   (d) Pass: no row's along is more than 0.001 behind the row before.
   (e) Pass: the rest is within 0.05 of the told stop (Lune −0.013 at 60 fps; worst 0.020 with frame jitter at 60 and 144; the PC on 4b18b5c +0.126 at 60 and 0.015–0.03 at 144).
   (f) Pass: along 1 s after the stop equals the rest within 0.001.
   (g) Pass: RushEnded "Interrupted" (the daze) tells the stop (Lune 6.169), not a point past it (the PC on 4b18b5c 6.295).
   (h) Report: WalkSpeed is back at 28 on the next AI tick after landed, with no MoveTo, and the root stays still.
441. [ ] **The open run's rest and the slide back, corrected (D-525; replaces 422(d) and the open run in 423(c)).** Setup D: shot 6 (enemy-boar-charge) at lag 0 and 0.05 s, 3 takes each; then item 423's charge in the open (setup C, no wall) at 60 and 144 fps. Item 439's log, and on your client the boar's Torso CFrame on every row (what the screen shows; this section's intro).
   (a) Pass: Done comes on the run's timer, unchanged (the PC +0.80 s), and WalkSpeed first reads under 28 on the Done row or the row after. Lune at 60 fps: the Humanoid brakes on its own before Done (along 21.227 → 21.417); Done and the landing's first row come together at +0.817 s (along 21.456, WalkSpeed 16.31), then 8.16, 4.08, 2.04 and 1.02; landed at +0.900 s (along 21.983).
   (b) Pass: the server root rests within 0.05 of the line end, 22 (Lune −0.017; worst 0.020; the PC on 4b18b5c −0.533).
   (c) Pass: the server root takes no backward step over 0.001, and along 1 s later equals the rest within 0.001.
   (d) Pass (422(d)): the boar's backward slide on your client after the line end is ≤ 0.05 in all (the PC on 4b18b5c 0.58 over about 30 rows, the server root's rest error, since the client ends the body on its root).
   (e) Report: Done to landed (Lune 0.083 s at 60 fps; ≤ 0.25 s), and shot 6's rest at about f124 as 422(d) asked.
442. [ ] **Enemies upright on the client, with the client's own log (D-523, D-524; replaces 425(a), (b) and (h)).** Item 425's setup and takes (setup D: shots 6, 11 and 1, 3 takes each, at lag 0 and 0.1 s; then shot 6 staged from about 25 studs off the spot at lag 0), plus, on every row and for each enemy model: model:GetAttribute("UprightClient"), ("UprightClientWhy") and ("UprightClientTries") (ai.upright.client.attributes, written by this client only), the client Humanoid's GetState() and GetStateEnabled(Enum.HumanoidStateType.FallingDown), and the root's Anchored.
   (a) Pass (425(a)): on the first row each staged enemy exists on the client, GetStateEnabled(FallingDown) reads false, UprightClient "Off", UprightClientWhy nil and UprightClientTries 1 (Lune "Off", 1; the PC on 4b18b5c read true on rows 0–9 of all 6 takes). "Off" with tries 2 or 3 also passes: report the why on the rows before it. "StoodUp" fails (a): report its row and tries.
   (b) Pass (425(b)): no enemy reads FallingDown or Ragdoll on any row of any take, on the server or the client, through the hold and the 60 rows after the release, at lag 0 and 0.1 s (the PC on 4b18b5c: the client copy on every held row, 520 and 531, and 1–2 rows after the release at 0.1 s; Lune 196 → 0). UprightClient reads "Off" from the first row to the release. Report root y (2.784–2.85 on 4b18b5c; no change expected).
   (c) Report (425(h)): on the first row each enemy exists, GetState(), GetStateEnabled(FallingDown), Anchored and the three attributes; then, on every row until UprightClient first reads "Off" or "StoodUp", the three attributes. Reading them: 1. "Off" with tries 1: the states went off in the tag's handler, before the first physics step. 2. "Off" with tries 2 or more after "NotTaken" (or tries 2 with no row before): the engine dropped the first turn-off and the read-back caught it. 3. "Off" after "NoHumanoid" or "NotEnemy": the Humanoid or EntityKind arrived after the tag. 4. "StoodUp": the copy was already FallingDown when the client reached it (on that one row at most). 5. "Waiting" with tries climbing to 240: a client SetStateEnabled does not hold at all; log the why, and say whether the earlier probe's helper ran in the command bar or in a LocalScript. 6. The attributes nil on every row: Replication never watched the model; log EntityTracker.fromModel(model) ~= nil and EntityKind. 7. "Off" but GetStateEnabled true on a later row: something turns it back on; log the row it flips.
   (d) Report (the 1–2 FallingDown rows after the release at 0.1 s on 4b18b5c): from 10 rows before the release row to 10 after it, the client root's Anchored and ReceiveAge, the client GetState() and the root position; mark the first row Anchored reads false (from a GetPropertyChangedSignal("Anchored") connection) and the first row the position moves. With (b) passing, every row reads Running.
443. [ ] **The kobolds' client copies (D-523; replaces 435(h)).** Item 435's setup C with its kobolds, as 435(h): on the client during Idle, each kobold foot's lowest corner (440 rows a kobold, as the PC's K435 log), plus, on every row for every kobold, the client GetState(), GetStateEnabled(FallingDown), the root's Anchored and item 442's three attributes. Say how each kobold came: pack-spawned before the client joined, a respawn, held at spawn (placed with held = true, or hold-new), or held later by S("hold").
   (a) Pass: no kobold's client Humanoid reads FallingDown on any row (the PC on 4b18b5c: kobold #23 on 331 of 440 rows), and UprightClient reads "Off" on every row, "StoodUp" allowed on its first row only (Lune, 7 arrival orders: 0 rows in each, from 196 in the 6 late ones).
   (b) Report: each kobold's lowest leg corner range against 4b18b5c (#5 −0.033 to −0.006; #23 −0.057 to +0.024, 161 rows outside ±0.02). If #23 narrows to the Idle sink (about −0.033 to −0.006), its FallingDown copy was moving its drawn feet; the Idle clip's 0.032 sink itself is still open.

## AK. Section AI re-test after the fixes, second part (D-527 to D-529)

Run these on the build with the second part of the section AI fixes (D-527 to D-529) on the owner's PC, after section AJ. Frame names stay exactly as item 397 defines them (a row is the logger's at Last+2), and item 420's columns stand as item 439 left them. Judge every pose on the BasePart read at Last+2, which is what the screen shows (section AJ's intro); log the joint-chain read beside it for diagnosis. Report every pass line with its numbers. Section AI's lines that these replace are marked "Superseded by item …"; the rest of 433 to 437 stand.

444. [ ] **The sheathed guard's tip, presses judged only when sheathed (D-529; replaces 433(b)).** Setup C, 240 fps capture, sheathed, item 420 columns 1, 5, 6 and 7.
   1. Before each press wait until column 5 reads WeaponMount "Back" (about 7.2 s after the last guard release: the 6 s combat tag, sheatheDelay 0.3 and the Sheathe's 0.815 s), or space the presses 9 s apart.
   2. Each row, the screen tip in the root's frame: HumanoidRootPart.CFrame:PointToObjectSpace(the Weapon part's BasePart CFrame × TrailEnd), both read at Last+2; divide its step by the row's column-1 frame time. Log column 6's chain tip through the same root beside it.
   3. Count the PreSimulation callbacks between consecutive Last+2 rows (the row's physics substeps) and log the count.
   (a) Pass: on presses whose press row reads "Back", the screen tip is ≤ 84 studs/s on every row with exactly 1 substep (Lune 61.5 standing, 64.1 walking 16; the PC on 4b18b5c 301 at peak, 135 rows over 84, most of them on presses that were drawn).
   (b) Report: rows with 0 or 2 substeps, apart, with their tip step. If a 0-substep row shows no tip step and the next row shows two rows' worth, the PC's 301 is frame pacing, not the clip.
   (c) Report: presses whose press row reads "Hand", apart. A drawn guard is now a snap (D-527): Lune 340–358 studs/s on 1 row at 60 Hz, 914–1070 on 4 rows at 240 Hz; not judged.
   (d) Report (433(c)): the first row column 5 reads "Hand" after a sheathed press, and WeaponMountWhy (Lune: at the Draw's WeaponDraw, 0.22 s after the press, about 53 rows at 240 fps; Why nil).
445. [ ] **The Draw's tip with the substep count (replaces the PC's 433(d) Draw reading).** Item 345's Draws, standing and at a sprint, 240 fps, with item 444's screen tip and substep count (444 steps 2 and 3).
   (a) Pass: ≤ 84 studs/s on rows with exactly 1 substep (Lune 73–75 at 240 Hz, 68.4 standing, ≤ 73.8 over a sprint's cycle; the PC on 4b18b5c 171 at peak, 63 rows over 84).
   (b) Report: 0- and 2-substep rows apart, with the root's PreSimulation-to-PostSimulation move on that row (column 3; at 24 studs/s 0, 0.1 or 0.2 studs).
446. [ ] **The lock turn's pivot foot against the yaw physics applied (replaces 434(a)).** Setup C, lock a target 90°, 135° and 179° off each way, 60 fps.
   1. Each row log the pivot foot's grounded corners from the foot's BasePart at Last+2 (the screen) and from the chain beside, and the root's yaw at PreSimulation before the lock write, after it (pendingLockYaw flushed), and at PostSimulation (column 3).
   (a) Pass: the pivot foot's least-moving grounded corner moves ≤ 0.01 a row on the BasePart read through the turn (Lune 0.003–0.005; the PC on 4b18b5c 0.097 at +90, 0.010–0.025 elsewhere).
   (b) Report if (a) fails: each row's yaw physics applied (PostSimulation minus PreSimulation after the write) minus the yawAhead the pose was built with. A gap that is not zero means the turn the body shows is not the turn the pose expected.
   (c) Report: the lifts (Lune and the PC: L2 and R1 on + turns, L1 and R2 on − turns).
447. [ ] **The drawn idle's feet (D-529; replaces 435(a)).** The drawn idle, 60 fps, 300 rows.
   (a) Pass: on the BasePart read, every foot's lowest corner is within ±0.02 of the floor on every row, except the drawn stance's rear (right) foot, which D-417 sets heel-up (Lune LeftFoot −0.003 to 0.000).
   (b) Pass (435(e), as written): the rear foot's ball ≤ 0.05 over the floor with its heel up (Lune ball +0.033 to +0.038, heel about 0.13; the PC 0.033–0.038).
448. [ ] **The drawn walk's plants (D-529; replaces 435(c)).** The drawn walk at 8, 60 and 144 fps, 10 s each.
   (a) Pass: each foot is planted (a grounded corner within 0.02 and the least-moving corner ≤ 0.02 a row) on 55–65% of rows (Lune 60% and 60% at 60 fps, 61% and 59% at 144; the PC 58–61%).
   (b) Pass: at 60 fps the step p90 of the least-moving grounded corner is < 0.02 on the BasePart read (Lune 0.0187 and 0.0191; log the chain beside).
   (c) Report: at 144 fps the p90 (Lune's screen model 0.0504, chain 0.0200; the PC 0.050–0.052) with each row's PreSimulation count. Lune expects 1 or 2 substeps alternating (1 on about a third of the rows) and the large steps on the rows whose count differs from the row before. Not judged until the gait builds its pose for the frame's own physics travel (Open items in PROGRESS).
449. [ ] **The landing on the move at W 24 (D-529; replaces 435(d)).** The landing at W 24 from 0.25 s and 0.5 s falls, 60 and 144 fps.
   (a) Pass: each row's foot turn ≤ max(20, the sprint's own per-row foot turn) + 1° (Lune sprint's own 31.3 drawn, 31.1 sheathed; the PC's sprint 33–35.3 gives a bar of 34.3–36.3, so its 33.22 and 31.13 pass).
   (b) Report: the sprint's own foot turn over one cycle before the jump, on the same take.
450. [ ] **Out of a drawn sprint into an attack (D-529; replaces 436(a)).** Out of a drawn sprint at 24 into Basic1 and into Horizontal, 60 fps.
   (a) Pass: each row's foot turn ≤ the sprint's own per-row foot turn + 1° on the rows the sprint still shows (Lune feet 26.7 and 26.1 into Basic1, 26.4 and 24.9 into Horizontal; the sprint's own 31.3; the PC 26.9 and 26.0).
   (b) Report: the arms (Lune 21.2 and 20.9, up to 21.8; the PC under 20; still open).
451. [ ] **The drawn guard raise is a snap (D-527; replaces 436(c)).** The guard raised drawn, standing and walking at 8, with nothing to cut, 60 fps.
   (a) Pass: from the 4th row after the press (cancel.snapFrames 3) every upper-body part turns ≤ 8° a row (review.audit.reportDegrees) on the BasePart read (Lune after D-527: standing 89.3 / 8.9 / 0.9 / 0.1 / 0.1, walking 115.7 / 11.6 / 1.5 / 0.8 / 0.5; the PC on 4b18b5c 9.5 / 29.6 / 29.8 / 25.6 / 7.7).
   (b) Report: the first rows (the snap itself; not judged against 20°).
   (c) A guard pressed sheathed: item 444 instead (D-420's Draw over it, unchanged).
452. [ ] **A dodge takes the body without a pop (D-528; replaces 436(d)).** The four dodges from the drawn and the sheathed stance, standing, walking at 8 and running at 16 (stick held), 60 fps; mark the press row and the row State first reads Dodge.
   (a) Pass: from the press row until the dodge clip lets go, every body part turns ≤ 20° a row on the BasePart read (Lune after D-528: arms ≤ 19.6, legs ≤ 18.9, torso and head ≤ 8.4; the PC on 4b18b5c 30.9–60.3 on the arms).
   (b) Report: the rows between the press and the Dodge state (Lune: the clip plays from the press row).
   (c) Report: the dodge reaches its pose by 0.18 s (arms) and 0.12 s (legs, spine and root); its move and i-frames are unchanged. A dodge out of a basic is a cancel (the snap, D-408): report it apart.

## AL. Section AI re-test after the fixes, third part (D-530 to D-533)

Run these on the build with the third part of the section AI fixes (D-530 to D-533) on the owner's PC, after section AK. Rows are the logger's at Last+2 and every pose is judged on the BasePart read (the screen, section AJ's intro), with the joint-chain read logged beside it for diagnosis. The rush's Torso is now drawn off its root joint on this client while the rush is away from its root (D-531), so the joint chain no longer shows the body during a rush: read the Torso, Snout and feet BasePart CFrames. If item 453 fails, set choreo.luau enemy.rush.detachBody = false, rebuild, report the failure and run 454 to 458 again on that build (the body then draws through the joint as on 4b18b5c). Section AI's lines that these replace are marked "Superseded by item …"; 423(d) and the rest of 422 and 424 stand. The server root still rests short of or past its stop at 60 fps until section AJ's landing fails are fixed; the snout bar below is measured beyond the root's own rest.

453. [ ] **The detached Torso, engine checks (D-531).** Play with Server and Client, setup C, while a FrenzyBoar charges (S("charge", …) in the open, then into item 401's wall), at 60 fps.
   1. Each row on the client log the boar's Torso.Root.Enabled, Torso.Anchored, the Humanoid's GetState() and the Torso BasePart position; on the server log the same two properties each Heartbeat.
   (a) Pass: on the client Enabled reads false and Anchored true from the first row the rush is drawn away from its root (Run) until Done, and true and false on every row after; on the server they read true and false on every row (the client's writes never replicate).
   (b) Pass: on the row the Torso goes back on its joint there is no fling or pop: the Torso step is ≤ 28 × dt + 0.05 (item 456) and the Humanoid's client state is the same as the row before.
   (c) Report: whether the Head, Snout and legs follow the drawn Torso on the same row or one row late (the clip pose lagging the Torso by a row is the assumed worst case).
454. [ ] **The wall runs on the screen (D-531; replaces 423(a) and (b)).** Item 423's slam at the wall: 60 fps at lag 0, 0.05 and 0.25 s, and 144 fps at lag 0, 3 takes each (the PC's x423 runs). Per row the Snout BasePart's distance past the wall face, the drawn step of the Torso BasePart, and the server root (item 439).
   (a) Pass: while the boar is drawn away from its root the snout is ≤ 0.05 past the face on every row, the late root's catch-up row included (Lune replays of the PC's x423 rows 0.000; the PC on 4b18b5c 0.372 / 0.367 / 1.607 / 0.027). At rest it may sit past the face by no more than the server root's own rest past the told stop (item 440).
   (b) Pass: every drawn step ≤ 28 × dt + 0.05, dt that row's own (Lune ≤ 0.467 at 60 and ≤ 0.194 at 144 on every replay; the PC up to 1.248 over the run's travel), and no backward step over 0.02 in the 10 rows after the stop.
455. [ ] **The rush's Torso step on the screen (D-530; replaces 422(a)).** Shot 6 at lag 0 and 0.05 s, 3 takes each, and item 454's runs. Per row the Torso BasePart's step and the drawn root's step (DrawnBody.position's step).
   (a) Pass: on every row not crossing the Charge clip's launch snap the Torso steps ≤ 0.6 at 60 fps (Lune ≤ 0.484; ≤ 0.208 at 144).
   (b) Pass: on the launch row and the 2 rows after it the Torso steps ≤ the drawn root's step + 0.42 (Lune 0.737–0.853 = 0.466 + the clip's 0.308–0.431; the PC's chain 0.758–0.834).
   (c) Pass: run, skid and slam rows ≤ the drawn root's step + 0.12 (Lune ≤ + 0.109); crouch rows ≤ + 0.2 (Lune + 0.173).
456. [ ] **The hand-back's end (D-531).** Items 454 and 455's takes. Mark the row Torso.Root.Enabled first reads true again.
   (a) Pass: the Torso BasePart's step on that row and the row after is ≤ 28 × dt + 0.05 (Lune: the root's own move in that row, 0 on every PC run because the root is at rest by then).
457. [ ] **The nameplate over a charging boar (D-533).** Items 454 and 455's takes. Per row the nameplate BillboardGui's Adornee, its StudsOffsetWorldSpace, and the plate's place (the Adornee's BasePart position + StudsOffsetWorldSpace) against the drawn body (DrawnBody.position) plus the plate's lift.
   (a) Pass: the Adornee is the Torso on every row Torso.Root.Enabled reads false, and the root part again from the row it reads true.
   (b) Pass: the plate's place is within 0.05 of the drawn body plus its lift on every detached row (Lune 0.000; before the fix 0.491 / 0.487 / 0.487 at 60 fps and 0.216 at 144, the root's predicted move), and by eye it shows no lag or jump on the run, the stop or the re-attach.
   (c) Report: the SWITCH prompt over a charging boar, the same way, if one shows.
458. [ ] **Two charges, the slope and the first launch step on the screen (D-531; replaces the reads in 424(a), (c) and (d)).** Item 424's setups and takes as written, read on the Torso and Snout BasePart instead of at Input+1.
   (a) Pass (424(a)): every drawn step of the second charge ≤ 28 × dt + 0.05, the first-move row included.
   (b) Pass (424(c)): the uphill charge ends Done at 22.00; every horizontal step ≤ 28 × dt + 0.05 and every 3D step ≤ horizontal / cos 40° + 0.05 (Lune 0.609 at 60 fps).
   (c) Pass (424(d)): the first launch step ≤ 28 × dt + 0.01, dt that row's own.
   (d) 424(b) as written.
