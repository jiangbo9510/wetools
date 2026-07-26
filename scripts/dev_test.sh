#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/build/TestDerivedData}"
SCHEME="${SCHEME:-Wetools}"
CONFIGURATION="${CONFIGURATION:-Debug}"

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

has_test_target() {
  xcodebuild "$1" "$2" -list 2>/dev/null | grep -E "Tests$|UITests$" >/dev/null 2>&1
}

container="$(find_xcode_container)"
container_flag="${container%%::*}"
container_path="${container#*::}"

echo "Using $container_flag $container_path"

if has_test_target "$container_flag" "$container_path"; then
  echo "Test target detected. Running xcodebuild test."
  xcodebuild \
    "$container_flag" "$container_path" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    test
else
  echo "No test target detected yet. Falling back to xcodebuild build."
  xcodebuild \
    "$container_flag" "$container_path" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    build
fi
