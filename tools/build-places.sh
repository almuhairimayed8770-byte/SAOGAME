#!/usr/bin/env bash
# Builds every Rojo place project under places/ into a .rbxl next to it.
# Places are built artifacts (gitignored); world content lives in the project JSON and the
# server-side builders (src/server/world/), so a place can always be regenerated from git.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
for project in places/*.project.json; do
	name="$(basename "$project" .project.json)"
	echo "rojo build $project -> places/$name.rbxl"
	rojo build "$project" -o "places/$name.rbxl"
done
