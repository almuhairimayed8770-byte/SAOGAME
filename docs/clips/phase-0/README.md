# Phase 0 gate recordings

The clips the Phase 0 gate needs (`GAME_SPEC.md` section 20, section 21 line 3), one file per shot (ten in all), named exactly as
the Capture panel shows them. The list and the lengths come from `src/shared/data/dev.luau` (`capture.shots`); the
panel (`src/client/dev/Capture.client.luau`) runs in the Playground place because its Workspace carries the
`DevCapture` attribute, and it prompts each shot with a 3-2-1 countdown, hides itself, and shows a frame counter
bottom-left while you record.

| File | Length | What the reviewer must be able to see |
| --- | --- | --- |
| `fight-boar-kobold.mp4` | 20 s | the gate clip: one boar and one kobold; every attack shows the six beats; a parry spark; a kill shatter; the server registered every hit (a digit per hit) |
| `art-horizontal.mp4` | 5 s | start pose, activation glow, anticipation, snap, smear, hold, settle, post-motion |
| `art-vertical.mp4` | 5 s | the overhead cut; gauge-heavy hit; same six beats |
| `art-sharp-nail.mp4` | 5 s | three hits, three hit-stops, the trail on only in the windows |
| `art-rising-arc.mp4` | 5 s | the sunken start pose, the rise onto the toes, two hits with Normal then Final hit-stop, the trail on only in the windows |
| `enemy-boar-charge.mp4` | 5 s | 0.6 s crouch with the red line, the launch, the skid, readable from behind |
| `enemy-kobold-overhead.mp4` | 5 s | 1.0 s wind-up with the yellow edge, the chop, the recovery |
| `parry-spark.mp4` | 5 s | guard tapped inside the window against the kobold's overhead (the boar's charge is unblockable); spark and ring; the enemy staggers |
| `kill-shatter.mp4` | 5 s | the 10-frame kill hit-stop, the 0.5 s freeze and silence, the shards rising |
| `locomotion.mp4` | 14 s | walk, run, sprint sheathed then drawn (lock on to draw), turn in place, skid stop, fall off a ledge and land (no jump); no T-pose, no sliding foot |

None of these files exists yet.

## Recording

1. Build and open the Playground (`docs/STUDIO_TASKS.md` B.6 to B.9), press Play.
2. Start your recorder (Studio **View > Video Record** on Windows, or OBS / QuickTime), then on the panel pick the
   shot with `[` / `]`, press `P`; after the countdown the panel hides and the counter shows the shot id, the frame
   number and the elapsed seconds against the target. `O` cycles the time scale (1x / 0.5x / 0.25x) for a slow pass;
   `H` hides or shows the panel; `K` marks the shot done and the panel comes back with the shot checked.
3. Stop the recorder, trim to the counter, save the file here under the name above (mp4, 60 fps if the recorder can).
4. Watch it at 0.25x (the ClipLab for single clips, or the recorder's slow playback) and fill the hand columns of
   `docs/ANIMATION_REVIEW.md`; write the result on the gate checklist in `docs/PROGRESS.md`.

## Committing

`.gitattributes` routes `docs/clips/**/*.mp4` (and `.mov`, `.gif`) through Git LFS; run `git lfs install` once per
machine before the first commit (Git for Windows ships Git LFS). Re-recordings replace the file under the same name; the
review table is keyed by clip id, not by recording, so nothing else changes.
