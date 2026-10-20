#!/bin/zsh
# DevBoard setup: asks for your usernames, an optional free Gemini key and an optional resume,
# saves them to ~/.config/devboard/ (never inside this repo), then builds and installs the widgets.
# Safe to re-run any time to change settings.
set -euo pipefail
cd "${0:A:h}"

CONFIG_DIR=~/.config/devboard
bold() { print -P "%B$1%b"; }
ask() { # ask "Prompt" default -> REPLY
  local prompt=$1 def=${2:-}
  if [[ -n $def ]]; then read "REPLY?$prompt [$def]: "; REPLY=${REPLY:-$def}; else read "REPLY?$prompt: "; fi
}

bold "DevBoard setup"
echo

# 1. Requirements
major=$(sw_vers -productVersion | cut -d. -f1)
if (( major < 14 )); then
  echo "DevBoard needs macOS 14 (Sonoma) or later. You have $(sw_vers -productVersion)."; exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo "DevBoard builds with Apple's free Command Line Tools (no Xcode needed)."
  echo "Run:  xcode-select --install   then run ./setup.sh again."; exit 1
fi
mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"

# 2. Usernames (existing values become defaults)
current() { [[ -f $CONFIG_DIR/config.json ]] && python3 -I -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]) or '')" "$CONFIG_DIR/config.json" "$1" 2>/dev/null || true; }
bold "1/3  Profiles"
echo "Used for the Activity heatmaps. Leave blank to hide a section."
ask "LeetCode username" "$(current leetcode_username)"; LC=$REPLY
ask "GitHub username" "$(current github_username)"; GH=$REPLY
ask "Apple Notes folder for your answers" "$(current notes_folder || true)"; NOTES=${REPLY:-Daily Problems}
python3 -I - "$CONFIG_DIR/config.json" "$LC" "$GH" "$NOTES" <<'PY'
import json, sys
path, lc, gh, notes = sys.argv[1:]
try:
    cfg = json.load(open(path))
except Exception:
    cfg = {}
cfg.update({"leetcode_username": lc, "github_username": gh, "notes_folder": notes or "Daily Problems"})
cfg.setdefault("resume_questions", True)
json.dump(cfg, open(path, "w"), indent=2)
PY
chmod 600 "$CONFIG_DIR/config.json"
echo

# 3. Gemini key
bold "2/3  Gemini API key (optional, free)"
echo "Writes the daily system design, OS, networks, DBMS and infra questions with hints."
echo "Get a free key (no card): https://aistudio.google.com/apikey"
check_key() {
  python3 -I - "$CONFIG_DIR/gemini_key" <<'PY'
import json, sys, urllib.request
key = open(sys.argv[1]).read().strip()
req = urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models?pageSize=1", headers={"x-goog-api-key": key})
try:
    urllib.request.urlopen(req, timeout=15)
    print("  ✓ Key works")
except Exception as e:
    print(f"  ✗ Gemini rejected the key ({e}). Re-run ./setup.sh to try another.")
PY
}
if [[ -s $CONFIG_DIR/gemini_key ]]; then
  ask "A key is already saved. Replace it? (y/N)" ""; replace=$REPLY
else
  replace=y
fi
if [[ $replace == [yY]* ]]; then
  read -s "KEY?Paste your key (hidden; Enter to skip): "; echo
  if [[ -n $KEY ]]; then
    print -rn -- "$KEY" > "$CONFIG_DIR/gemini_key" && chmod 600 "$CONFIG_DIR/gemini_key"
    check_key
  fi
fi
echo

# 4. Resume → anonymized profile
bold "3/3  Resume-based questions (optional)"
echo "Each day one question is asked about your own projects, like an interviewer would."
echo "Your resume is turned into a short profile with no name, contact details, employers or schools."
echo "Contact details are removed on your Mac first; the rest is sent once to Gemini to write the profile."
if [[ -s $CONFIG_DIR/profile.txt ]]; then echo "(A profile is already saved at $CONFIG_DIR/profile.txt.)"; fi
ask "Path to your resume (PDF, DOCX, TXT, MD or TeX; Enter to skip)" ""; RESUME=${REPLY/#\~/$HOME}
if [[ -n $RESUME ]]; then
  if [[ ! -s $CONFIG_DIR/gemini_key ]]; then
    echo "  Skipped: a Gemini key is needed to write the profile. You can also copy"
    echo "  profile.example.txt to $CONFIG_DIR/profile.txt and fill it in by hand."
  elif [[ ! -f $RESUME ]]; then
    echo "  Couldn't find $RESUME"
  else
    TMP=$(mktemp -d)
    case ${RESUME:l} in
      *.pdf) swift scripts/extract-text.swift "$RESUME" > "$TMP/resume.txt" ;;
      *.docx|*.doc|*.rtf|*.odt|*.pages) textutil -convert txt -stdout "$RESUME" > "$TMP/resume.txt" ;;
      *) cp "$RESUME" "$TMP/resume.txt" ;;
    esac
    echo "  Writing your profile…"
    if python3 -I scripts/resume_to_profile.py "$TMP/resume.txt" > "$TMP/profile.txt"; then
      echo; echo "──────── profile ────────"; cat "$TMP/profile.txt"; echo "─────────────────────────"; echo
      ask "Save this profile? (Y = save, e = edit first, n = discard)" "Y"
      case $REPLY in
        [eE]*) ${EDITOR:-nano} "$TMP/profile.txt"; cp "$TMP/profile.txt" "$CONFIG_DIR/profile.txt" ;;
        [nN]*) echo "  Discarded." ;;
        *) cp "$TMP/profile.txt" "$CONFIG_DIR/profile.txt" ;;
      esac
      [[ -f $CONFIG_DIR/profile.txt ]] && chmod 600 "$CONFIG_DIR/profile.txt"
    fi
    rm -rf "$TMP"
  fi
fi
echo

# 5. Build + install
bold "Building DevBoard…"
./build.sh
echo
bold "Done! Next:"
echo "  1. Click the date & time in the menu bar → Edit Widgets (or right-click the desktop)."
echo "  2. Search \"DevBoard\" and add Activity, Today, CS Fundamentals and Build Idea."
echo "  3. The first time you save an answer, macOS asks to let DevBoard use Notes. Click Allow."
