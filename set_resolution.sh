#!/bin/zsh

# 1. Shell Environment Safety
unsetopt BASH_REMATCH 2>/dev/null

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { print "${GREEN}[INFO]${NC}  $*" }
warn()  { print "${YELLOW}[WARN]${NC}  $*" }
error() { print "${RED}[ERROR]${NC} $*"; exit 1 }

[[ "$(uname)" != "Darwin" ]] && error "Run this inside macOS."

# 2. Dependency Check
for cmd in curl awk grep; do
    if ! command -v "$cmd" &>/dev/null; then
        error "Required command '$cmd' is missing."
    fi
done

# 3. Hardware Architecture Compatibility
if ! command -v brew &>/dev/null; then
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    else
        warn "Homebrew is missing."
        info "To install manually (prevents SSH/headless hangs), run:"
        echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
fi

if ! command -v displayplacer &>/dev/null; then
    info "Installing displayplacer..."
    brew tap jakehilborn/jakehilborn || error "Failed to tap Homebrew."
    brew install displayplacer || error "Failed to install displayplacer."
fi

# 4. Multi-Monitor Handling
info "Detecting displays..."
DISPLAYS=()
while IFS= read -r line; do
    DISPLAYS+=("$line")
done < <(displayplacer list 2>/dev/null | grep "^Persistent screen id:" | awk '{print $NF}')

[[ ${#DISPLAYS[@]} -eq 0 ]] && error "Could not detect any displays."

DISPLAY_ID="${DISPLAYS[1]}"
if [[ ${#DISPLAYS[@]} -gt 1 ]]; then
    info "Multiple displays detected:"
    for i in {1..${#DISPLAYS[@]}}; do
        echo "  $i) ${DISPLAYS[$i]}"
    done
    read "D_CHOICE?Select target display (1-${#DISPLAYS[@]}): "
    if [[ "$D_CHOICE" =~ ^[0-9]+$ ]] && (( D_CHOICE >= 1 && D_CHOICE <= ${#DISPLAYS[@]} )); then
        DISPLAY_ID="${DISPLAYS[$D_CHOICE]}"
    else
        error "Invalid display selection."
    fi
fi
info "Targeting Display: $DISPLAY_ID"

RESOLUTIONS=()
MODES_RES=()
MODES_HZ=()
MODES_SCALE=()

# 5. Scaled (Retina) Resolutions Fix
while IFS= read -r line; do
    if [[ "$line" =~ "res:([0-9]+x[0-9]+).*hz:([0-9]+).*scaling:(on|off)" ]]; then
        res="${match[1]}"
        hz="${match[2]}"
        scale="${match[3]}"
        
        label="${res} @ ${hz}Hz"
        [[ "$scale" == "on" ]] && label+=" (HiDPI / Scaled)"
        
        RESOLUTIONS+=("$label")
        MODES_RES+=("$res")
        MODES_HZ+=("$hz")
        MODES_SCALE+=("$scale")
    fi
done < <(displayplacer list 2>/dev/null | sed -n "/Persistent screen id: ${DISPLAY_ID}/,/Persistent screen id:/p" | grep -E "res:[0-9]+x[0-9]+" | grep -v "^displayplacer")

[[ ${#RESOLUTIONS[@]} -eq 0 ]] && error "No resolutions found for this display."

echo ""
info "Available resolutions:"
printf "  %-4s  %-30s\n" "#" "Resolution @ Hz (Type)"
echo "  ──────────────────────────────────────────"
for i in {1..${#RESOLUTIONS[@]}}; do
    printf "  %-4s  %s\n" "$i" "${RESOLUTIONS[$i]}"
done
echo ""

read "CHOICE?Enter number (or q to quit): "
[[ "$CHOICE" == "q" || -z "$CHOICE" ]] && exit 0

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#RESOLUTIONS[@]} )); then
    error "Invalid selection."
fi

RES="${MODES_RES[$CHOICE]}"
HZ="${MODES_HZ[$CHOICE]}"
SCALE="${MODES_SCALE[$CHOICE]}"

info "Applying ${RES} @ ${HZ}Hz (scaling:${SCALE})..."
displayplacer "id:${DISPLAY_ID} res:${RES} hz:${HZ} scaling:${SCALE} origin:(0,0) degree:0"
info "Done! Resolution updated."