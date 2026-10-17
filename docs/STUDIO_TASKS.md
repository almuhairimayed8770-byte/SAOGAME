# Studio tasks

Everything that needs Roblox Studio (or a machine with it) by hand, in the order to do it. Menu paths are for Studio
as of 2026; a path marked **(verify)** was written without Studio at hand and may have moved a tab. Nothing on this
list has been done yet from the repository side; tick the box and note the date when you do one.

## A. First-time setup

1. [ ] **Install the command-line tools.** Install [Aftman](https://github.com/LPGhatguy/aftman) (or Rokit), then in the
   repo root run `aftman install` (or `rokit install`). This gives you `rojo`, `wally`, `selene`, `stylua`, `lune` and
   `run-in-roblox` at the versions in `aftman.toml`.
2. [ ] **Install the Rojo Studio plugin.** In a terminal: `rojo plugin install`. Then in Studio: **Plugins tab > Manage
   Plugins** and confirm "Rojo" is listed and enabled. (Alternative: Creator Store > search "Rojo" > Install.)
3. [ ] **Install the PoseEditor plugin.** `tools/build-plugin.sh` writes `build/SkyspirePoseEditor.rbxm`. In Studio:
   **Plugins tab > Plugins Folder** (opens your local plugins directory); copy the `.rbxm` there; restart Studio or
   **Plugins tab > Manage Plugins > (the plugin) > reload**. A "Skyspire" toolbar with a "PoseEditor" button appears.
   `tools/build-plugin.sh --install` does the copy on macOS and Windows (verify the folder it picks).
4. [ ] **Allow HTTP requests** so the PoseEditor can post to the pose server: **Home tab > Game Settings > Security >
   Allow HTTP Requests: On** (verify the exact label). This is per place file; do it in the Playground and the ClipLab.
5. [ ] **Enable Studio access to API services** (needed by run-in-roblox smoke scripts that touch DataStores later;
   harmless now): **Home tab > Game Settings > Security > Enable Studio Access to API Services: On** (verify).

## B. Open and sync the dev places

6. [ ] **Build the places.** `tools/build-places.sh` writes `places/Playground.rbxl` and `places/ClipLab.rbxl` (gitignored,
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
    (verify) that `Motor6D.Transform` moves the rig in edit mode on your Studio build; if it does not, scrub in Play mode
    with the ClipLab instead and use the editor for the numbers.
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

14. [ ] **Run the smoke scripts** on this machine (Studio installed and logged in): `tools/smoke.sh` builds the Playground
    and runs every `tests/smoke/*.smoke.luau` through `run-in-roblox`; `tools/smoke.sh --list` only lists them. A failed
    assertion prints the line that stopped it.
15. [ ] **Measure section 16 numbers in the Playground** and paste them into the table in `docs/PROGRESS.md`: **View tab >
    Stats > Summary / Render / Memory** for fps, part count and memory; **MicroProfiler** (Ctrl+F6, or **View tab >
    MicroProfiler**) for draw calls and frame time (verify); **Developer Console** (F9) **> Server > ServerJobs** for the
    heartbeat time (verify). Do it with the spawn tables filled (8 players is a test server; note what you had).

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

24. [ ] **Ship an empty `Animate` script.** The engine's default character animations write
    `Motor6D.Transform` too and would fight Choreo. In Studio: **Explorer > StarterPlayer > StarterCharacterScripts
    > + > LocalScript**, name it exactly `Animate`, leave it empty (verify the default `Animate` no longer appears
    under your character in Play mode; Choreo also destroys one it finds). Keep the Humanoid's `Animator`.
25. [ ] **Confirm the Motor6D names and the `Rig` attribute.** With the Playground in Play mode, select your
    character and each enemy in the Explorer: the Motor6Ds must be named as `src/shared/data/rigs.luau` lists them
    (player: the 15 R15 joints plus `Weapon` on `RightHand`; Boar: `Root`, `Neck`, `Jaw`, `TuskLeft`, `TuskRight`,
    the four `..Hip`s, `TailJoint`; Kobold: `Root`, `Neck`, the two `Shoulder`s and `Hip`s, `Weapon`) and every
    enemy Model must carry the `Rig` attribute (**Properties > Attributes**) the server sets, or Choreo poses it as a
    player. A rig whose joints are misnamed shows in its rest pose instead of its idle.
26. [ ] **Watch the write order.** In Play mode open **View tab > Script Performance** (verify) and confirm the
    Choreo RenderStepped step is the last thing that touches `Transform` each frame: a rig that snaps to rest for a
    frame means something else (an `AnimationTrack`, a plugin) writes after it.
