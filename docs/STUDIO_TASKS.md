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
