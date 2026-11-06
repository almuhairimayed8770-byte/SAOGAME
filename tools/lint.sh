#!/usr/bin/env bash
# Runs the same checks as CI. Pass --offline when selene cannot download the Roblox API dump
# (it then lints src/ against tools/lint/roblox-lite.yml, which only knows global names).
set -uo pipefail
cd "$(dirname "$0")/.."
status=0

echo "== stylua --check"
stylua --check src tests tools || status=1

echo "== selene src"
if [[ "${1:-}" == "--offline" ]]; then
	(cd tools/lint && selene --config selene-local.toml ../../src) || status=1
else
	selene src || status=1
fi

echo "== selene tests"
(cd tests && selene .) || status=1
echo "== selene tools"
(cd tools && selene .) || status=1

echo "== lune tests"
lune run tests/run.luau || status=1

echo "== validators"
lune run tools/validate.luau || status=1

echo "== rojo build"
mkdir -p build
rojo build default.project.json -o build/Skyspire.rbxl || status=1
tools/build-places.sh || status=1

if [[ $status -ne 0 ]]; then
	echo "LINT FAILED"
else
	echo "ALL GREEN"
fi
exit $status
