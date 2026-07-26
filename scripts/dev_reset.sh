#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DevDerivedData"
# TODO: Replace com.yourname.Wetools with the real bundle identifier before release.
BUNDLE_ID="${BUNDLE_ID:-com.yourname.Wetools}"
APP_SUPPORT_DIR="$HOME/Library/Application Support/Wetools"

kill_running_app() {
  osascript -e 'tell application "Wetools" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application "Wetools Dev" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x "Wetools" >/dev/null 2>&1 || true
  pkill -x "Wetools Dev" >/dev/null 2>&1 || true
}

confirm() {
  local prompt="$1"
  local answer
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

echo "Stopping Wetools processes"
kill_running_app

if [[ -d "$DERIVED_DATA" ]]; then
  echo "Removing $DERIVED_DATA"
  rm -rf "$DERIVED_DATA"
else
  echo "No local derived data at $DERIVED_DATA"
fi

if [[ -d "$APP_SUPPORT_DIR" ]]; then
  if confirm "Delete local Application Support data at '$APP_SUPPORT_DIR'?"; then
    rm -rf "$APP_SUPPORT_DIR"
    echo "Deleted $APP_SUPPORT_DIR"
  else
    echo "Kept $APP_SUPPORT_DIR"
  fi
fi

if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
  if confirm "Delete UserDefaults for '$BUNDLE_ID'?"; then
    defaults delete "$BUNDLE_ID"
    echo "Deleted UserDefaults for $BUNDLE_ID"
  else
    echo "Kept UserDefaults for $BUNDLE_ID"
  fi
else
  echo "No UserDefaults found for $BUNDLE_ID"
fi

echo "Reset complete"
