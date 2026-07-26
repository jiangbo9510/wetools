#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DevDerivedData"
SCHEME="${SCHEME:-Wetools}"
CONFIGURATION="${1:-Debug}"
APP_NAME="${APP_NAME:-Wetools}"
# TODO: Replace com.yourname.Wetools with the real bundle identifier before release.
BUNDLE_ID="${BUNDLE_ID:-com.yourname.Wetools}"
SIGNING_SCENARIO="${SIGNING_SCENARIO:-local-dev}"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
INSTALL_APP="${INSTALL_APP:-/Applications/Wetools Dev.app}"
ENTITLEMENTS="$ROOT_DIR/Wetools/Resources/Wetools.entitlements"

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

resolve_sign_identity() {
  case "$SIGNING_SCENARIO" in
    local-dev)
      if [[ -n "${SIGN_IDENTITY:-}" ]]; then
        echo "$SIGN_IDENTITY"
        return
      fi

      security find-identity -v -p codesigning | awk -F '"' '/Apple Development/ { print $2; exit }'
      ;;
    github-release)
      echo "-"
      ;;
    *)
      echo "Unknown SIGNING_SCENARIO: $SIGNING_SCENARIO" >&2
      echo "Use local-dev for /Applications/Wetools Dev.app or github-release for ad-hoc DMG builds." >&2
      exit 1
      ;;
  esac
}

sign_app() {
  local app_path="$1"
  local identity="$2"

  if [[ "$SIGNING_SCENARIO" == "local-dev" ]]; then
    if [[ -z "$identity" ]]; then
      echo "No Apple Development signing identity found." >&2
      echo "Install an Apple Development certificate in Keychain, or set SIGN_IDENTITY explicitly." >&2
      exit 1
    fi

    if [[ "$identity" == "-" ]]; then
      echo "local-dev signing must use Apple Development, not ad-hoc." >&2
      exit 1
    fi
  fi

  if [[ "$identity" == "-" ]]; then
    echo "Ad-hoc signing $app_path"
    codesign --force --deep --sign - "$app_path"
  else
    echo "Apple Development signing $app_path"
    codesign --force --sign "$identity" --entitlements "$ENTITLEMENTS" --timestamp=none "$app_path"
  fi
}

case "$CONFIGURATION" in
  Debug|Release) ;;
  *)
    echo "Usage: $0 [Debug|Release]" >&2
    exit 1
    ;;
esac

container="$(find_xcode_container)"
container_flag="${container%%::*}"
container_path="${container#*::}"
sign_identity="$(resolve_sign_identity)"

echo "Building $SCHEME ($CONFIGURATION)"
echo "Using $container_flag $container_path"
echo "Bundle ID: $BUNDLE_ID"

xcodebuild \
  "$container_flag" "$container_path" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "App bundle not found at expected path: $BUILT_APP" >&2
  exit 1
fi

sign_app "$BUILT_APP" "$sign_identity"

echo "Stopping old app process if running"
kill_running_app

echo "Removing old $INSTALL_APP"
rm -rf "$INSTALL_APP"

echo "Copying new app to $INSTALL_APP"
cp -R "$BUILT_APP" "$INSTALL_APP"

echo "Removing quarantine from $INSTALL_APP"
xattr -dr com.apple.quarantine "$INSTALL_APP" >/dev/null 2>&1 || true

echo "Opening $INSTALL_APP"
open "$INSTALL_APP"

echo "Install path: $INSTALL_APP"
