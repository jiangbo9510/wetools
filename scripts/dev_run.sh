#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DevDerivedData"
SCHEME="${SCHEME:-Wetools}"
CONFIGURATION="Debug"
APP_NAME="${APP_NAME:-Wetools}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

find_xcode_container() {
  local workspace="$ROOT_DIR/Wetools.xcworkspace"
  local project="$ROOT_DIR/Wetools.xcodeproj"

  if [[ -d "$workspace" ]]; then
    echo "-workspace::$workspace"
    return
  fi

  if [[ -d "$project" ]]; then
    echo "-project::$project"
    return
  fi

  echo "No Wetools.xcworkspace or Wetools.xcodeproj found in $ROOT_DIR" >&2
  exit 1
}

kill_running_app() {
  osascript -e 'tell application "Wetools" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application "Wetools Dev" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x "Wetools" >/dev/null 2>&1 || true
  pkill -x "Wetools Dev" >/dev/null 2>&1 || true
}

container="$(find_xcode_container)"
container_flag="${container%%::*}"
container_path="${container#*::}"

echo "Building $SCHEME ($CONFIGURATION)"
echo "Using $container_flag $container_path"

xcodebuild \
  "$container_flag" "$container_path" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  build

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found at expected path: $APP_BUNDLE" >&2
  exit 1
fi

echo "Ad-hoc signing $APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Stopping old app process if running"
kill_running_app

echo "Opening $APP_BUNDLE"
open "$APP_BUNDLE"

echo "App path: $APP_BUNDLE"
