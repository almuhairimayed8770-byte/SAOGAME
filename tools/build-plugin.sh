#!/usr/bin/env bash
# Builds the PoseEditor Studio plugin (tools/PoseEditor) into build/SkyspirePoseEditor.rbxm and
# lints its source against the offline Roblox globals list.
#
#   tools/build-plugin.sh              build + lint
#   tools/build-plugin.sh --install    also copy the .rbxm into the local Studio plugins folder
#
# Install by hand: Roblox Studio > Plugins tab > Plugins Folder, drop the .rbxm in and restart
# Studio (docs/STUDIO_TASKS.md). CI runs this script's build step so a broken plugin fails the
# build like any other Rojo project.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

out="build/SkyspirePoseEditor.rbxm"
echo "== rojo build tools/PoseEditor/PoseEditor.project.json -> $out"
rojo build tools/PoseEditor/PoseEditor.project.json -o "$out"

echo "== stylua --check tools/PoseEditor"
stylua --check tools/PoseEditor

echo "== selene tools/PoseEditor/src (roblox-lite: the plugin uses Roblox globals, tools/ lints as Lune)"
(cd tools/lint && selene --config selene-local.toml ../PoseEditor/src)

if [[ "${1:-}" == "--install" ]]; then
	# Studio's local plugins folder. (verify) the path on your machine: Studio > Plugins > Plugins Folder opens it.
	case "$(uname -s)" in
	Darwin) folder="$HOME/Documents/Roblox/Plugins" ;;
	MINGW* | MSYS* | CYGWIN*) folder="${LOCALAPPDATA:-$HOME/AppData/Local}/Roblox/Plugins" ;;
	*)
		echo "No Studio on this platform; copy $out into Studio's Plugins Folder by hand."
		exit 0
		;;
	esac
	mkdir -p "$folder"
	cp "$out" "$folder/"
	echo "installed to $folder/$(basename "$out"); restart Studio or Plugins > Manage Plugins > reload"
fi

echo "plugin built: $out"
