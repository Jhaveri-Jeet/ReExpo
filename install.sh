#!/bin/bash

##########################################
#         FINDBUG Toolkit Installer      #
#         Professional Setup | v3.5      #
#            Author: Jeet Jhaveri        #
##########################################

set -e

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"
TOOLS_DIR="$HOME/tools"
WORDLIST_DIR="$HOME/wordlists/SecLists"

banner() {
  cat <<"EOF"
███████╗██╗███╗   ██╗██████╗ ██████╗  ██████╗  ███████╗██╗   ██╗
██╔════╝██║████╗  ██║██╔══██╗██╔══██╗██╔═══██╗██╔════╝╚██╗ ██╔╝
█████╗  ██║██╔██╗ ██║██║  ██║██████╔╝██║   ██║███████╗ ╚████╔╝ 
██╔══╝  ██║██║╚██╗██║██║  ██║██╔══██╗██║   ██║╚════██║  ╚██╔╝  
██║     ██║██║ ╚████║██████╔╝██████╔╝╚██████╔╝███████║   ██║   
╚═╝     ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═════╝  ╚═════╝ ╚══════╝   ╚═╝   

             FINDBUG INSTALLER v3.5 | Jeet Jhaveri
EOF
}

header() { echo -e "\n${YELLOW}========== $1 ==========${RESET}"; }
success() { echo -e "${GREEN}[✔] $1${RESET}"; }
fail() { echo -e "${RED}[✖] $1${RESET}"; }

export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"

banner
header "Updating system packages"
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y git curl wget nmap jq python3 python3-venv python3-pip pipx php golang hydra whatweb wafw00f unzip || fail "Basic packages installation failed"
pipx ensurepath || true

mkdir -p "$TOOLS_DIR"
cd "$TOOLS_DIR"

install_go_tool() {
  TOOL_NAME=$(basename "$1")
  if command -v "$TOOL_NAME" &>/dev/null; then
    success "$TOOL_NAME already installed"
  else
    echo -e "${YELLOW}Installing: $TOOL_NAME${RESET}"
    go install "$1@latest" && success "$TOOL_NAME installed" || fail "$TOOL_NAME installation failed"
  fi
}

header "Installing Go-based tools"
install_go_tool github.com/projectdiscovery/subfinder/v2/cmd/subfinder
install_go_tool github.com/tomnomnom/assetfinder
install_go_tool github.com/owasp-amass/v3/cmd/amass
install_go_tool github.com/projectdiscovery/httpx/cmd/httpx
install_go_tool github.com/lc/gau/v2/cmd/gau
install_go_tool github.com/tomnomnom/waybackurls
install_go_tool github.com/projectdiscovery/nuclei/v3/cmd/nuclei
install_go_tool github.com/ffuf/ffuf/v2
install_go_tool github.com/sensepost/gowitness
install_go_tool github.com/projectdiscovery/subzy/cmd/subzy
install_go_tool github.com/hahwul/dalfox/v2
install_go_tool github.com/projectdiscovery/interactsh/cmd/interactsh-client
install_go_tool github.com/tomnomnom/gf
install_go_tool github.com/s0md3v/uro
install_go_tool github.com/projectdiscovery/notify/cmd/notify

header "Setting up GF patterns"
[ -d "$HOME/.gf" ] || mkdir -p "$HOME/.gf"
[ -d "$HOME/.gf-patterns" ] && success "Gf patterns already cloned" || git clone https://github.com/1ndianl33t/Gf-Patterns.git "$HOME/.gf-patterns"
cp -r "$HOME/.gf-patterns/"*.json "$HOME/.gf/" || true

header "Cloning additional tools"
clone_repo() {
  local repo=$1 dir=$2
  [ -d "$dir" ] && success "$dir already cloned" || git clone "$repo" "$dir"
}

clone_repo https://github.com/sqlmapproject/sqlmap.git sqlmap
clone_repo https://github.com/s0md3v/XSStrike.git XSStrike
clone_repo https://github.com/pwn0sec/PwnXSS.git PwnXSS
clone_repo https://github.com/maurosoria/dirsearch.git dirsearch
clone_repo https://github.com/xnl-h4ck3r/xnLinkFinder.git xnLinkFinder
clone_repo https://github.com/devanshbatham/ParamSpider.git ParamSpider
clone_repo https://github.com/initstring/cloud_enum.git cloud_enum

header "Installing Python dependencies for tools"

setup_python_tool() {
  local dir="$1"
  local req_file="$2"
  python3 -m venv "$dir/venv"
  source "$dir/venv/bin/activate"
  pip install --upgrade pip
  pip install -r "$req_file" --break-system-packages || fail "$dir dependencies failed"
  deactivate
}

setup_python_tool "$TOOLS_DIR/xnLinkFinder" "$TOOLS_DIR/xnLinkFinder/requirements.txt"
setup_python_tool "$TOOLS_DIR/cloud_enum" "$TOOLS_DIR/cloud_enum/requirements.txt"

# ParamSpider manual dependencies
python3 -m venv "$TOOLS_DIR/ParamSpider/venv"
source "$TOOLS_DIR/ParamSpider/venv/bin/activate"
pip install --upgrade pip
pip install requests urllib3 colorama tldextract beautifulsoup4 --break-system-packages || fail "ParamSpider dependencies failed"
deactivate

# LinkFinder manually (as some forks remove requirements.txt)
[ -d "$TOOLS_DIR/LinkFinder" ] && success "LinkFinder already cloned" || git clone https://github.com/GerbenJavado/LinkFinder.git "$TOOLS_DIR/LinkFinder"
python3 -m venv "$TOOLS_DIR/LinkFinder/venv"
source "$TOOLS_DIR/LinkFinder/venv/bin/activate"
pip install --upgrade pip
pip install -r "$TOOLS_DIR/LinkFinder/requirements.txt" --break-system-packages || fail "LinkFinder dependencies failed"
deactivate

header "Installing SecLists wordlists"
if [ -d "$WORDLIST_DIR" ]; then
  success "SecLists already cloned"
else
  until git clone https://github.com/danielmiessler/SecLists.git "$WORDLIST_DIR"; do
    echo -e "${RED}Retrying SecLists clone...${RESET}"
    sleep 3
  done
  success "SecLists successfully cloned"
fi

header "Updating nuclei templates"
nuclei -update-templates || fail "nuclei templates update failed"

header "Installing vulners NSE script for nmap"
sudo curl -o /usr/share/nmap/scripts/vulners.nse https://raw.githubusercontent.com/vulnersCom/nmap-vulners/master/vulners.nse || fail "Downloading vulners.nse failed"
sudo nmap --script-updatedb || fail "Updating nmap scripts database failed"

header "Installing trufflehog (via pipx)"
if pipx list | grep trufflehog >/dev/null 2>&1; then
  success "trufflehog already installed (via pipx)"
else
  pipx install trufflehog || fail "trufflehog installation failed"
fi

success "Installation complete. Ready to run ./findbug.sh"
