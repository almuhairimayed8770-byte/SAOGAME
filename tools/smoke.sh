#!/usr/bin/env bash
# Runs the run-in-roblox smoke scripts (tests/smoke/*.smoke.luau) against the Playground place.
#
#   tools/smoke.sh            build the place, run every smoke script
#   tools/smoke.sh --list     only print which smoke scripts exist
#   tools/smoke.sh combat     run the scripts whose file name contains "combat"
#
# Needs Roblox Studio installed and logged in on this machine: run-in-roblox opens Studio with
# the place, runs the script as a server Script, pipes its output here and exits with the
# script's status. It cannot run in CI or on Linux; the Lune suite (lune run tests/run.luau)
# covers the pure modules, these cover the parts that need the engine.
set -uo pipefail
cd "$(dirname "$0")/.."

filter=""
list_only=0
for arg in "$@"; do
	case "$arg" in
	--list) list_only=1 ;;
	*) filter="$arg" ;;
	esac
done

scripts=()
for script in tests/smoke/*.smoke.luau; do
	[[ -e "$script" ]] || continue
	if [[ -n "$filter" && "$script" != *"$filter"* ]]; then
		continue
	fi
	scripts+=("$script")
done

echo "== smoke scripts (${#scripts[@]})"
for script in "${scripts[@]}"; do
	echo "   $script"
done
if [[ ${#scripts[@]} -eq 0 ]]; then
	echo "no smoke scripts under tests/smoke/ (expected *.smoke.luau)"
	exit 1
fi
if [[ $list_only -eq 1 ]]; then
	exit 0
fi

if ! command -v run-in-roblox >/dev/null 2>&1; then
	echo "run-in-roblox is not installed: run 'aftman install' (or 'rokit install') in the repo root." >&2
	echo "It also needs Roblox Studio installed and logged in on this machine (Windows or macOS)." >&2
	exit 2
fi
if ! command -v rojo >/dev/null 2>&1; then
	echo "rojo is not installed: run 'aftman install' (or 'rokit install')." >&2
	exit 2
fi

place="places/Playground.rbxl"
echo "== rojo build places/Playground.project.json -> $place"
rojo build places/Playground.project.json -o "$place" || exit 1

status=0
passed=0
failed=0
for script in "${scripts[@]}"; do
	echo
	echo "== run-in-roblox --place $place --script $script"
	if run-in-roblox --place "$place" --script "$script"; then
		echo "   PASS $script"
		passed=$((passed + 1))
	else
		echo "   FAIL $script"
		failed=$((failed + 1))
		status=1
	fi
done

echo
echo "smoke: $passed passed, $failed failed"
if [[ $status -ne 0 ]]; then
	echo "A failed script prints the assertion that stopped it above. Studio must be installed and"
	echo "logged in; if Studio opened and closed at once, check that the place built and that"
	echo "Game Settings > Security > Enable Studio Access to API Services is on (docs/STUDIO_TASKS.md)."
fi
exit $status
