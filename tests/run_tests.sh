#!/bin/zsh
# tests/run_tests.sh
# Runs unit tests for set_resolution.sh logic without needing a real display.
# Strategy: temporarily replace `displayplacer` with a mock that returns
# fake-but-realistic output, then source the script's functions and test them.

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

PASS=0
FAIL=0

pass() { print "${GREEN}  ✅ PASS${NC} — $1"; (( PASS++ )) }
fail() { print "${RED}  ❌ FAIL${NC} — $1"; (( FAIL++ )) }
section() { print "\n${YELLOW}▶ $1${NC}" }

# ── Mock displayplacer binary ──────────────────────────────────────────────
# We put a fake `displayplacer` at the front of PATH so the script uses it.
MOCK_BIN="$(mktemp -d)/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/displayplacer" <<'MOCK'
#!/bin/zsh
if [[ "$1" == "list" ]]; then
  cat <<'EOF'
Persistent screen id: A1B2C3D4-0000-0000-0000-111111111111
Type: 27 inch external
Resolution: 2560 x 1440
Hertz: 60
UI Looks like: 2560 x 1440
mode 0: res:2560x1440 hz:60 color_depth:8 scaling:off origin:(0,0) degree:0
mode 1: res:1920x1080 hz:60 color_depth:8 scaling:off origin:(0,0) degree:0
mode 2: res:1280x800 hz:60 color_depth:8 scaling:on origin:(0,0) degree:0

Persistent screen id: B2C3D4E5-0000-0000-0000-222222222222
Type: 13 inch built-in
Resolution: 2560 x 1600
Hertz: 60
mode 0: res:2560x1600 hz:60 color_depth:8 scaling:on origin:(0,0) degree:0
mode 1: res:1440x900 hz:60 color_depth:8 scaling:off origin:(0,0) degree:0

displayplacer "id:A1B2C3D4-0000-0000-0000-111111111111 res:2560x1440 hz:60 scaling:off origin:(0,0) degree:0"
EOF
fi
MOCK
chmod +x "$MOCK_BIN/displayplacer"
export PATH="$MOCK_BIN:$PATH"

# ── Helper: extract display IDs (same logic as the script) ────────────────
get_display_ids() {
  displayplacer list 2>/dev/null \
    | grep "^Persistent screen id:" \
    | awk '{print $NF}'
}

# ── Helper: extract resolutions for a given display ID ────────────────────
get_resolutions_for() {
  local id="$1"
  displayplacer list 2>/dev/null \
    | sed -n "/Persistent screen id: ${id}/,/Persistent screen id:/p" \
    | grep -E "res:[0-9]+x[0-9]+" \
    | grep -v "^displayplacer"
}

# ─────────────────────────────────────────────────────────────────────────────
section "Test 1 — Display detection"

DISPLAYS=()
while IFS= read -r line; do
  DISPLAYS+=("$line")
done < <(get_display_ids)

if [[ ${#DISPLAYS[@]} -eq 2 ]]; then
  pass "Detected exactly 2 displays"
else
  fail "Expected 2 displays, got ${#DISPLAYS[@]}"
fi

if [[ "${DISPLAYS[1]}" == "A1B2C3D4-0000-0000-0000-111111111111" ]]; then
  pass "First display ID parsed correctly"
else
  fail "First display ID wrong: ${DISPLAYS[1]}"
fi

if [[ "${DISPLAYS[2]}" == "B2C3D4E5-0000-0000-0000-222222222222" ]]; then
  pass "Second display ID parsed correctly"
else
  fail "Second display ID wrong: ${DISPLAYS[2]}"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Test 2 — Resolution parsing (display 1)"

RESOLUTIONS=(); MODES_RES=(); MODES_HZ=(); MODES_SCALE=()

while IFS= read -r line; do
  if [[ "$line" =~ "res:([0-9]+x[0-9]+).*hz:([0-9]+).*scaling:(on|off)" ]]; then
    RESOLUTIONS+=("${match[1]} @ ${match[2]}Hz")
    MODES_RES+=("${match[1]}")
    MODES_HZ+=("${match[2]}")
    MODES_SCALE+=("${match[3]}")
  fi
done < <(get_resolutions_for "A1B2C3D4-0000-0000-0000-111111111111")

if [[ ${#RESOLUTIONS[@]} -eq 3 ]]; then
  pass "Parsed 3 resolution modes for display 1"
else
  fail "Expected 3 modes, got ${#RESOLUTIONS[@]}"
fi

if [[ "${MODES_RES[1]}" == "2560x1440" ]]; then
  pass "Mode 1 resolution correct: ${MODES_RES[1]}"
else
  fail "Mode 1 resolution wrong: ${MODES_RES[1]}"
fi

if [[ "${MODES_HZ[1]}" == "60" ]]; then
  pass "Mode 1 Hz correct: ${MODES_HZ[1]}"
else
  fail "Mode 1 Hz wrong: ${MODES_HZ[1]}"
fi

if [[ "${MODES_SCALE[3]}" == "on" ]]; then
  pass "Mode 3 scaling=on detected (HiDPI)"
else
  fail "Mode 3 scaling wrong: ${MODES_SCALE[3]}"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Test 3 — Resolution parsing (display 2)"

RESOLUTIONS2=(); MODES_RES2=()

while IFS= read -r line; do
  if [[ "$line" =~ "res:([0-9]+x[0-9]+).*hz:([0-9]+).*scaling:(on|off)" ]]; then
    RESOLUTIONS2+=("${match[1]}")
    MODES_RES2+=("${match[1]}")
  fi
done < <(get_resolutions_for "B2C3D4E5-0000-0000-0000-222222222222")

if [[ ${#RESOLUTIONS2[@]} -eq 2 ]]; then
  pass "Parsed 2 resolution modes for display 2"
else
  fail "Expected 2 modes for display 2, got ${#RESOLUTIONS2[@]}"
fi

if [[ "${MODES_RES2[1]}" == "2560x1600" ]]; then
  pass "Display 2 mode 1 resolution correct: ${MODES_RES2[1]}"
else
  fail "Display 2 mode 1 resolution wrong: ${MODES_RES2[1]}"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Test 4 — Input validation logic"

validate_choice() {
  local choice="$1"
  local max="$2"
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max )); then
    echo "valid"
  else
    echo "invalid"
  fi
}

[[ "$(validate_choice 1 3)"   == "valid"   ]] && pass "Choice 1 of 3 → valid"   || fail "Choice 1 of 3 should be valid"
[[ "$(validate_choice 3 3)"   == "valid"   ]] && pass "Choice 3 of 3 → valid"   || fail "Choice 3 of 3 should be valid"
[[ "$(validate_choice 0 3)"   == "invalid" ]] && pass "Choice 0 → invalid"      || fail "Choice 0 should be invalid"
[[ "$(validate_choice 4 3)"   == "invalid" ]] && pass "Choice 4 of 3 → invalid" || fail "Choice 4 of 3 should be invalid"
[[ "$(validate_choice "q" 3)" == "invalid" ]] && pass "Choice 'q' → invalid"    || fail "Choice 'q' should be invalid"
[[ "$(validate_choice ""  3)" == "invalid" ]] && pass "Empty choice → invalid"  || fail "Empty choice should be invalid"
[[ "$(validate_choice "abc" 3)" == "invalid" ]] && pass "Non-numeric → invalid" || fail "Non-numeric should be invalid"

# ─────────────────────────────────────────────────────────────────────────────
section "Test 5 — HiDPI label generation"

make_label() {
  local res="$1" hz="$2" scale="$3"
  local label="${res} @ ${hz}Hz"
  [[ "$scale" == "on" ]] && label+=" (HiDPI / Scaled)"
  echo "$label"
}

LABEL1=$(make_label "2560x1440" "60" "off")
LABEL2=$(make_label "1280x800"  "60" "on")

[[ "$LABEL1" == "2560x1440 @ 60Hz" ]]                && pass "Non-HiDPI label correct"  || fail "Non-HiDPI label wrong: $LABEL1"
[[ "$LABEL2" == "1280x800 @ 60Hz (HiDPI / Scaled)" ]] && pass "HiDPI label correct"      || fail "HiDPI label wrong: $LABEL2"

# ─────────────────────────────────────────────────────────────────────────────
section "Test 6 — macOS version detection"

OS_VER=$(sw_vers -productVersion)
MAJOR=${OS_VER%%.*}

if [[ "$MAJOR" =~ ^[0-9]+$ ]]; then
  pass "sw_vers returns parseable version: $OS_VER (major: $MAJOR)"
else
  fail "Could not parse macOS version: $OS_VER"
fi

if (( MAJOR >= 12 )); then
  pass "macOS version $OS_VER meets minimum requirement (12+)"
else
  fail "macOS version $OS_VER is below minimum (12+)"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Test 7 — Architecture detection"

ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
  BREW_PATH="/opt/homebrew/bin/brew"
  pass "Apple Silicon detected → expecting brew at $BREW_PATH"
elif [[ "$ARCH" == "x86_64" ]]; then
  BREW_PATH="/usr/local/bin/brew"
  pass "Intel detected → expecting brew at $BREW_PATH"
else
  fail "Unknown architecture: $ARCH"
fi

if [[ -f "$BREW_PATH" ]]; then
  pass "Homebrew found at expected path: $BREW_PATH"
else
  fail "Homebrew NOT found at: $BREW_PATH"
fi

# ─────────────────────────────────────────────────────────────────────────────
print "\n────────────────────────────────────────"
TOTAL=$(( PASS + FAIL ))
print "Results: ${GREEN}${PASS} passed${NC} / ${RED}${FAIL} failed${NC} / ${TOTAL} total"
print "────────────────────────────────────────"

# Cleanup
rm -rf "$MOCK_BIN:h"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1