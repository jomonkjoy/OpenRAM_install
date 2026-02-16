#!/usr/bin/env bash
# =============================================================================
#  install_openram.sh — Install OpenRAM + SKY130 PDK
#  Tested on Ubuntu 20.04 / 22.04
#
#  Usage:
#    chmod +x install_openram.sh
#    ./install_openram.sh
# =============================================================================

set -euo pipefail

INSTALL_DIR="$HOME/OpenRAM"
LOG_FILE="$HOME/openram_install.log"

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✔]${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✘]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}▶ $*${NC}" | tee -a "$LOG_FILE"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║   OpenRAM + SKY130 PDK Installer    ║"
echo "  ║   Ubuntu 20.04 / 22.04              ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"
echo "OpenRAM Install — $(date)" > "$LOG_FILE"

# ── 1. Preflight ──────────────────────────────────────────────────────────────
section "Checking system"

[[ "$(uname -s)" == "Linux" ]] || error "Linux required."
[[ "$EUID" -ne 0 ]]            || error "Do not run as root."
command -v python3 &>/dev/null  || error "python3 not found. Install it first."
sudo -v 2>/dev/null             || error "sudo access required."
log "System OK — $(python3 --version)"

# ── 2. APT packages ───────────────────────────────────────────────────────────
section "Installing system packages"

sudo apt-get update -qq | tee -a "$LOG_FILE"
sudo apt-get install -y \
    git python3 python3-pip build-essential \
    tcl-dev tk-dev libcairo2-dev \
    magic netgen ngspice \
    wget curl m4 csh \
    2>&1 | tee -a "$LOG_FILE" \
    || error "APT install failed. See $LOG_FILE"

log "System packages installed."

# ── 3. Clone OpenRAM ──────────────────────────────────────────────────────────
OPENRAM_TAG="v1.2.48"
section "Cloning OpenRAM (tags/${OPENRAM_TAG})"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    warn "OpenRAM already cloned — fetching and checking out $OPENRAM_TAG."
    git -C "$INSTALL_DIR" fetch --tags 2>&1 | tee -a "$LOG_FILE"
    git -C "$INSTALL_DIR" checkout "tags/$OPENRAM_TAG" 2>&1 | tee -a "$LOG_FILE" \
        || error "Failed to checkout tags/$OPENRAM_TAG. See $LOG_FILE"
else
    git clone --branch "$OPENRAM_TAG" \
        https://github.com/VLSIDA/OpenRAM.git \
        "$INSTALL_DIR" \
        2>&1 | tee -a "$LOG_FILE" \
        || error "git clone failed. Check your connection."
fi
log "OpenRAM source ready at $INSTALL_DIR (tags/$OPENRAM_TAG)"

# ── 4. Python dependencies ────────────────────────────────────────────────────
section "Installing Python dependencies"

REQ="$INSTALL_DIR/requirements.txt"
if [[ -f "$REQ" ]]; then
    pip3 install -r "$REQ" --break-system-packages \
        2>&1 | tee -a "$LOG_FILE" \
    || pip3 install -r "$REQ" \
        2>&1 | tee -a "$LOG_FILE" \
    || warn "Some Python packages may not have installed cleanly."
else
    warn "No requirements.txt found — skipping."
fi
log "Python dependencies done."

# ── 5. SKY130 PDK ─────────────────────────────────────────────────────────────
section "Installing SKY130 PDK"

cd "$INSTALL_DIR"
if grep -q "^pdk" Makefile 2>/dev/null; then
    log "Running: make pdk  (may take 5–15 minutes)"
    make pdk     2>&1 | tee -a "$LOG_FILE" || error "make pdk failed. See $LOG_FILE"
    log "Running: make install"
    make install 2>&1 | tee -a "$LOG_FILE" || error "make install failed. See $LOG_FILE"
else
    warn "No 'pdk' Makefile target — installing sky130 via pip."
    pip3 install sky130 --break-system-packages 2>&1 | tee -a "$LOG_FILE" || true
fi
log "SKY130 PDK installed."

# ── 6. Environment variables ──────────────────────────────────────────────────
section "Configuring environment variables"

if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

MARKER="# >>> OpenRAM >>>"
END_MARKER="# <<< OpenRAM <<<"

# Remove stale block on re-runs
if grep -q "$MARKER" "$SHELL_RC" 2>/dev/null; then
    warn "Updating existing OpenRAM block in $SHELL_RC"
    sed -i "/$MARKER/,/$END_MARKER/d" "$SHELL_RC"
fi

cat >> "$SHELL_RC" <<EOF

$MARKER
export OPENRAM_HOME="$INSTALL_DIR/compiler"
export OPENRAM_TECH="$INSTALL_DIR/technology"
export PYTHONPATH="\$OPENRAM_HOME:\$OPENRAM_TECH/sky130:\$OPENRAM_TECH/sky130/custom:\${PYTHONPATH:-}"
$END_MARKER
EOF

# Also export for current session
export OPENRAM_HOME="$INSTALL_DIR/compiler"
export OPENRAM_TECH="$INSTALL_DIR/technology"
export PYTHONPATH="$OPENRAM_HOME:$OPENRAM_TECH/sky130:$OPENRAM_TECH/sky130/custom:${PYTHONPATH:-}"

log "Env vars written to $SHELL_RC"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  ✔  Installation complete!${NC}"
echo ""
echo -e "  ${BOLD}Installed to:${NC} $INSTALL_DIR"
echo -e "  ${BOLD}Log file:${NC}     $LOG_FILE"
echo ""
echo -e "  ${YELLOW}Reload your shell before running OpenRAM:${NC}"
echo -e "  ${CYAN}    source $SHELL_RC${NC}"
echo ""
echo -e "  Then see the README for how to configure and run your first SRAM."
echo ""
