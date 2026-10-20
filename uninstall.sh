#!/bin/zsh
# Removes DevBoard. Your settings in ~/.config/devboard are kept unless you pass --all.
set -euo pipefail
APP=~/Applications/DevBoard.app

pkill -x DevBoard 2>/dev/null || true
if [[ -d $APP ]]; then
  pluginkit -r "$APP/Contents/PlugIns/DevBoardWidget.appex" 2>/dev/null || true
  rm -rf "$APP"
  echo "✓ Removed $APP"
fi
killall chronod 2>/dev/null || true

if [[ ${1:-} == --all ]]; then
  rm -rf ~/.config/devboard
  echo "✓ Removed ~/.config/devboard (config, Gemini key, profile)"
else
  echo "Settings kept in ~/.config/devboard (run ./uninstall.sh --all to delete them too)."
fi
echo "Your notes in Apple Notes are untouched."
