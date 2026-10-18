#!/usr/bin/env bash
# Runs the run-in-roblox smoke scripts (tests/smoke/*.smoke.luau) against the Playground place.
#
#   tools/smoke.sh            build the place, run every smoke script
#   tools/smoke.sh --list     only print which smoke scripts exist
#   tools/smoke.sh combat     run the scripts whose file name contains "combat"
#
# Needs Roblox Studio installed and logged in on this machine. run-in-roblox opens Studio with
# the place and runs its script inside a plugin in Edit mode, where no server script runs, so
# each smoke script is first wrapped by tools/smoke-wrap.luau (tools/smoke/SmokeRunner.luau):
# the runner installs the smoke script as a server Script, starts a Run session (Main and the
# smoke script run as on a server, without a player), and prints "SMOKE-RESULT: PASS <name>" or
# "SMOKE-RESULT: FAIL <name>: <reason>". A script passes only when its log holds exactly one
# result line for it and that line is PASS; run-in-roblox's own exit code also turns red on
# errors Studio's built-in plugins print, so it is reported but not trusted. Each run's output
# is kept in build/smoke/<name>.log.
#
# Close Roblox Studio first: run-in-roblox drops its plugin into Studio's shared plugins folder,
# and an open Studio could load it and run the smoke script inside your own place. The script
# refuses to start while Studio is running (Windows only; set SMOKE_ALLOW_OPEN_STUDIO=1 to skip
# the check). Each run is killed after RUN_LIMIT seconds (run-in-roblox itself never times out
# once Studio is up, so a crashed or frozen Studio would otherwise hang here).
# It cannot run in CI or on Linux; the Lune suite (lune run tests/run.luau) covers the pure
# modules, these cover the parts that need the engine.
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
for tool in rojo lune; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "$tool is not installed: run 'aftman install' (or 'rokit install')." >&2
		exit 2
	fi
done

if [[ "${SMOKE_ALLOW_OPEN_STUDIO:-0}" != "1" ]] && command -v tasklist.exe >/dev/null 2>&1; then
	if tasklist.exe //FI "IMAGENAME eq RobloxStudioBeta.exe" 2>/dev/null | grep -qi "RobloxStudioBeta"; then
		echo "Roblox Studio is running. Close every Studio window, then run tools/smoke.sh again." >&2
		echo "(run-in-roblox's plugin would also load in an open Studio; SMOKE_ALLOW_OPEN_STUDIO=1 skips this check.)" >&2
		exit 2
	fi
fi

# The runner's own budget (tools/smoke/SmokeRunner.luau defaultTimeoutSeconds, 240 s) plus time
# for Studio to start, load the place and shut down.
RUN_LIMIT=420
limit=()
if timeout --version >/dev/null 2>&1; then
	limit=(timeout "$RUN_LIMIT")
else
	echo "note: GNU timeout not found; a frozen Studio will hang this script (Ctrl+C ends it)."
fi

place="places/Playground.rbxl"
echo "== rojo build places/Playground.project.json -> $place"
rojo build places/Playground.project.json -o "$place" || exit 1

mkdir -p build/smoke
status=0
passed=0
failed=0
for script in "${scripts[@]}"; do
	name="$(basename "$script" .luau)"
	runner="build/smoke/$name.runner.luau"
	log="build/smoke/$name.log"
	echo
	if ! lune run tools/smoke-wrap.luau "$script" "$runner"; then
		echo "   FAIL $script (could not write the runner)"
		failed=$((failed + 1))
		status=1
		continue
	fi
	echo "== run-in-roblox --place $place --script $runner"
	NO_COLOR=1 ${limit[@]+"${limit[@]}"} run-in-roblox --place "$place" --script "$runner" 2>&1 | tee "$log"
	exit_code=${PIPESTATUS[0]}
	name_re="${name//./\\.}"
	results=$(grep -cE "^SMOKE-RESULT: (PASS|FAIL) $name_re(:|\s*$)" "$log" || true)
	if [[ $exit_code -eq 124 ]]; then
		echo "   FAIL $script (killed after $RUN_LIMIT s: Studio hung or never finished; output in $log)"
		# run-in-roblox closes Studio only when it exits normally; close the one it left (no other
		# Studio was open when this script started, see the check above).
		if command -v taskkill.exe >/dev/null 2>&1; then
			taskkill.exe //IM RobloxStudioBeta.exe //F >/dev/null 2>&1 || true
		fi
		failed=$((failed + 1))
		status=1
	elif [[ "$results" == "1" ]] && grep -qE "^SMOKE-RESULT: PASS $name_re\s*$" "$log"; then
		echo "   PASS $script (run-in-roblox exit $exit_code)"
		passed=$((passed + 1))
	else
		if [[ "$results" != "1" ]]; then
			echo "   ($results result lines for $name; expected exactly one)"
		fi
		echo "   FAIL $script (run-in-roblox exit $exit_code; output in $log)"
		failed=$((failed + 1))
		status=1
	fi
done

echo
echo "smoke: $passed passed, $failed failed"
if [[ $status -ne 0 ]]; then
	echo "A failed script's SMOKE-RESULT line names the assertion or error that stopped it (full"
	echo "output in build/smoke/<name>.log). Studio must be installed and logged in; if no"
	echo "SMOKE-RESULT line appeared at all, Studio did not finish loading the place or the Run"
	echo "session did not start (docs/STUDIO_TASKS.md, section D)."
fi
exit $status
