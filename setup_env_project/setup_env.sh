#!/bin/bash
# --- Universal Arch Setup (Template-Driven) ---
# Version: 2026.05.09 - Public Candidate
# Author: Barry Kruyssen & Gemini AI
# Methodology: User-Independent, Verbose, Template-Driven.
# Contribution: Chris Titus - rich .bashrc configurization.

# --- COLOR PALETTE ---
RED='\033[0;31m'
YELLOW='\033[1;33m' 
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- MESSAGING HELPERS ---
msg_status() { echo -e "${BLUE}[STATUS]${NC} $1"; }
msg_action() { echo -e "${GREEN}[ACTION]${NC} $1"; }
msg_warn()   { echo -e "${YELLOW}[WARNING]${NC} $1"; }
msg_error()  { echo -e "${RED}[ERROR]${NC} $1"; }

# --- HELP FUNCTION ---
show_help() {
  echo -e "${BLUE}Usage:${NC} ./setup_env.sh [OPTION]"
  echo -e ""
  echo -e "A modular, rerunnable environment deployment suite for Arch-based Linux."
  echo -e ""
  echo -e "${BLUE}OPTIONS:${NC}"
  echo -e "  -h, --help    Show this detailed color-coded help message and exit."
  echo -e ""
  echo -e "${BLUE}ARCHITECTURE & STAGES:${NC}"
  echo -e "  1-4:  ${GREEN}SYSTEM PERSISTENCE${NC} - Core binaries, SSHD tuning, NoMachine."
  echo -e "  5:    ${GREEN}STORAGE${NC} - Mounts backup hardware via LABEL."
  echo -e "  6-7:  ${GREEN}TEMPLATING${NC} - Injects variables into Tmux/Bash configs."
  echo -e "  8-9:  ${GREEN}AUTOMATION${NC} - UI helpers and Topgrade safety rules."
  echo -e "  10-11:${GREEN}STYLE & BACKUP${NC} - BIT policy and Starship styling."
  echo -e "  12:   ${GREEN}VERIFICATION${NC} - Final system health check."
}

# --- ARGUMENT PARSING ---
[[ "$1" == "-h" || "$1" == "--help" ]] && { show_help; exit 0; }

# --- CONFIGURATION ---
DATA_BACKUP_LABEL="BACKUP"
BASH_TEMP="bashrc_template"
STAR_TEMP="starship_template.toml"
TMUX_TEMP="tmux_template.conf"
BIT_TEMP="main_home_backup_bit_config_template"

# --- DETECTION ---
CURRENT_USER=$(whoami)
USER_HOME=$HOME
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

if command -v yay &> /dev/null; then AUR_HELPER="yay";
elif command -v paru &> /dev/null; then AUR_HELPER="paru";
else AUR_HELPER="NONE"; fi

[[ "$XDG_SESSION_TYPE" == "wayland" ]] && YANK_CMD="wl-copy" || YANK_CMD="xclip -sel clipboard -i"
BASE_MOUNT=$([ -d "/run/media/$CURRENT_USER" ] && echo "/run/media/$CURRENT_USER" || echo "/mnt")

echo -e "${BLUE}------------------------------------------------------${NC}"
echo -e "--- Initializing Setup for ${GREEN}$CURRENT_USER${NC} on ${GREEN}$(hostname)${NC} ---"
echo -e "--- Source Directory: ${YELLOW}$SCRIPT_DIR${NC} ---"
echo -e "${BLUE}------------------------------------------------------${NC}"

# 1. Core Packages
echo -n "[1/12] Verifying core system packages... "
sudo pacman -S --needed --noconfirm openssh tmux fuse3 networkmanager timeshift trash-cli xclip >/dev/null 2>&1
echo -e "${GREEN}Done.${NC}"

# 2. Network Identity
echo "[2/12] Checking Network Identity..."
CONN_NAME=$(nmcli -t -f NAME,TYPE connection show --active | grep -v "lo" | head -n1 | cut -d: -f1)
if [ -n "$CONN_NAME" ]; then
    CURRENT_IP=$(nmcli -g ip4.address connection show "$CONN_NAME" | cut -d/ -f1)
    msg_status "Active Interface: $CONN_NAME ($CURRENT_IP)"
    echo -n -e "    -> ${YELLOW}[PROMPT]${NC} Modify Static IP? (y/N) [5s timeout]: "
    read -t 5 MODIFY_CHOICE
    if [[ "$MODIFY_CHOICE" =~ ^[Yy]$ ]]; then
        echo -e "\n"
        read -p "       Enter new Static IP: " NEW_IP
        read -p "       Enter Gateway: " GATEWAY
        sudo nmcli connection modify "$CONN_NAME" ipv4.addresses "${NEW_IP}/24" ipv4.gateway "$GATEWAY" ipv4.dns "8.8.8.8,8.8.4.4" ipv4.method manual
        sudo nmcli connection up "$CONN_NAME"
        msg_action "Network updated."; else echo -e "\n    -> [SKIP] Keeping current settings."; fi
fi

# 3. SSHD Persistence
echo -n "[3/12] Configuring SSHD keep-alives... "
SSHD_CONFIG="/etc/ssh/sshd_config"
if ! grep -q "ClientAliveInterval 120" "$SSHD_CONFIG"; then
    sudo sed -i '/ClientAliveInterval/d; /ClientAliveCountMax/d' "$SSHD_CONFIG"
    echo -e "ClientAliveInterval 120\nClientAliveCountMax 3" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    sudo systemctl enable --now sshd >/dev/null 2>&1
    echo -e "${GREEN}Updated.${NC}"; else echo -e "${BLUE}Already configured.${NC}"; fi

# 4. NoMachine (NX)
echo -n "[4/12] Verifying NoMachine (NX) status... "
if command -v /usr/NX/bin/nxserver &> /dev/null; then
    sudo systemctl enable --now nxserver >/dev/null 2>&1
    echo -e "${GREEN}Active.${NC}"; else echo -e "${YELLOW}Not installed (Skipping).${NC}"; fi

# 5. Backup Hardware
echo "[5/12] Verifying Backup Hardware..."
DATA_DEV=$(lsblk -no NAME,LABEL | grep "$DATA_BACKUP_LABEL" | awk '{print $1}')
if [ -n "$DATA_DEV" ]; then
    MOUNT_PATH="$BASE_MOUNT/$DATA_BACKUP_LABEL"
    if ! mountpoint -q "$MOUNT_PATH"; then
        sudo mkdir -p "$MOUNT_PATH" && sudo mount /dev/"$DATA_DEV" "$MOUNT_PATH" 2>/dev/null
        msg_action "Mounted to $MOUNT_PATH."; else msg_status "Drive already mounted."; fi
else msg_warn "Label '$DATA_BACKUP_LABEL' not found. Check Samsung T7 connection."; fi

# 6. Tmux Configuration
echo -n "[6/12] Syncing Tmux configuration... "
if [ -f "$SCRIPT_DIR/$TMUX_TEMP" ]; then
    sed "s|\$YANK_CMD|$YANK_CMD|g" "$SCRIPT_DIR/$TMUX_TEMP" > "$USER_HOME/.tmux.conf"
    echo -e "${GREEN}Done.${NC}"; else echo -e "${RED}FAILED: Template missing.${NC}"; fi

# 7. Bash Environment Deployment
echo -n "[7/12] Deploying .bashrc from template... "
if [ -f "$SCRIPT_DIR/$BASH_TEMP" ]; then
    [ -f "$USER_HOME/.bashrc" ] && cp "$USER_HOME/.bashrc" "$USER_HOME/.bashrc.bak"
    cp "$SCRIPT_DIR/$BASH_TEMP" "$USER_HOME/.bashrc"
    echo -e "${GREEN}Done.${NC}"; else echo -e "${RED}FAILED: Template missing.${NC}"; fi

# 8. UI Tools (AUR)
echo -n "[8/12] Installing UI Tools via $AUR_HELPER... "
if [ "$AUR_HELPER" != "NONE" ]; then
    $AUR_HELPER -S --needed --noconfirm starship zoxide fzf fastfetch >/dev/null 2>&1
    echo -e "${GREEN}Done.${NC}"; else echo -e "${RED}FAILED: No AUR helper.${NC}"; fi

# 9. Topgrade
echo -n "[9/12] Configuring Topgrade automation... "
mkdir -p "$USER_HOME/.config"
[ ! -f "$USER_HOME/.config/topgrade.toml" ] && topgrade --dry-run > /dev/null 2>&1
if [ -f "$USER_HOME/.config/topgrade.toml" ]; then
    if ! grep -q "Timeshift pre-topgrade" "$USER_HOME/.config/topgrade.toml"; then
        sed -i '/\[pre_commands\]/a "Timeshift pre-topgrade" = "sudo timeshift --create --comments \\"pre-topgrade\\" --tags O"' "$USER_HOME/.config/topgrade.toml"
    fi
    sed -i 's/^# upgrade =.*/upgrade = false/; s/^# use_sudo =.*/use_sudo = true/' "$USER_HOME/.config/topgrade.toml"
    echo -e "${GREEN}Done.${NC}"; else echo -e "${YELLOW}Config missing (Skipping).${NC}"; fi

# 10. Back In Time
echo -n "[10/12] Main Home Backup - Scripting Back In Time profile... "
BIT_TARGET="$USER_HOME/.config/backintime/config"
mkdir -p "$(dirname "$BIT_TARGET")"
if [ -f "$SCRIPT_DIR/$BIT_TEMP" ]; then
    sed -e "s|BASE_MOUNT|$BASE_MOUNT|g" \
        -e "s|DATA_BACKUP_LABEL|$DATA_BACKUP_LABEL|g" \
        -e "s|USER_HOME|$USER_HOME|g" \
        "$SCRIPT_DIR/$BIT_TEMP" > "$BIT_TARGET"
    echo -e "${GREEN}Done.${NC}"; else echo -e "${RED}FAILED: Template missing.${NC}"; fi

# 11. Starship Style
echo -n "[11/12] Deploying Starship configuration... "
if [ -f "$SCRIPT_DIR/$STAR_TEMP" ]; then
    mkdir -p "$USER_HOME/.config"
    cp "$SCRIPT_DIR/$STAR_TEMP" "$USER_HOME/.config/starship.toml"
    echo -e "${GREEN}Done.${NC}"; else echo -e "${YELLOW}SKIPPED.${NC}"; fi

# 12. Final System Verification
echo -n "[12/12] Verifying environmental integrity... "
if [ -f "$USER_HOME/.bashrc" ] && [ -f "$USER_HOME/.tmux.conf" ]; then
    echo -e "${GREEN}System Ready.${NC}"; else msg_warn "Configuration files missing."; fi

echo -e "${BLUE}------------------------------------------------------${NC}"
echo -e "Setup Complete for ${GREEN}$CURRENT_USER${NC} on ${GREEN}$(hostname)${NC}."
echo -e "${BLUE}------------------------------------------------------${NC}"
echo -e "Next step: Run 'source ~/.bashrc' or restart terminal."
echo -e "${BLUE}------------------------------------------------------${NC}"
