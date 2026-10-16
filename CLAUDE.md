Read docs/GAME_SPEC.md in full before any work. It is the single source of truth.
Track progress in docs/PROGRESS.md. Never ask design questions the spec already answers.
When the spec is silent, choose the option closest to the anime feel, write it into docs/DECISIONS.md, and continue.
Every number lives in src/shared/data/; every file is --!strict; the server owns HP, hits, loot and rolls.
Run `lune run tests/run.luau` and `lune run tools/validate.luau` before claiming anything works.
Anything that needs Roblox Studio by hand goes into docs/STUDIO_TASKS.md as a numbered checklist.
