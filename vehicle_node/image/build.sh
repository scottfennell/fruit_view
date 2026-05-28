#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VEHICLE_NODE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$VEHICLE_NODE_DIR/.." && pwd)"

PROFILE_PATH=""
ALLOW_DIRTY=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--profile)
			PROFILE_PATH="$2"
			shift 2
			;;
		--allow-dirty)
			ALLOW_DIRTY=1
			shift
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

if [[ -z "$PROFILE_PATH" ]]; then
	echo "Usage: ./vehicle_node/image/build.sh --profile vehicle_node/profiles/local/<name>.toml [--allow-dirty]" >&2
	exit 1
fi

if [[ $ALLOW_DIRTY -ne 1 ]] && [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain)" ]]; then
	echo "Refusing to build from a dirty git tree. Re-run with --allow-dirty to override." >&2
	exit 1
fi

SOURCE_ID="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)"
PROFILE_BASENAME="$(basename "${PROFILE_PATH%.toml}")"
mkdir -p "$VEHICLE_NODE_DIR/.cache" "$VEHICLE_NODE_DIR/dist"

docker build -t fruit-view-vehicle-node-builder -f "$SCRIPT_DIR/Dockerfile" "$VEHICLE_NODE_DIR"

docker run --rm --privileged \
	-v "$PROJECT_ROOT:/workspace" \
	-w /workspace \
	fruit-view-vehicle-node-builder \
	bash -lc "export PYTHONPATH=/workspace && python3 vehicle_node/image/scripts/validate_profile.py --profile '$PROFILE_PATH' && python3 vehicle_node/image/scripts/fetch_artifacts.py --lock vehicle_node/image/artifacts.lock.toml --cache-dir vehicle_node/.cache && python3 vehicle_node/image/scripts/patch_image.py --profile '$PROFILE_PATH' --lock vehicle_node/image/artifacts.lock.toml --cache-dir vehicle_node/.cache --dist-dir vehicle_node/dist --source-id '$SOURCE_ID' && python3 vehicle_node/image/scripts/validate_image.py --image 'vehicle_node/dist/${PROFILE_BASENAME}-${SOURCE_ID}.img'"

echo "Built vehicle-node image artifacts in vehicle_node/dist/"
