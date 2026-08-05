#!/usr/bin/env bash
set -euo pipefail

# scanner.sh — wrapper for RealiTLScanner
# - Beautiful menu
# - EN/RU language switch
# - Auto dependency checks
# - Auto clone/build RealiTLScanner Docker image
# - Scan public IP or custom IP/CIDR
# - Parse and colorize output

SCRIPT_NAME="scanner.sh"
REPO_URL="https://github.com/XTLS/RealiTLScanner.git"
REPO_DIR="$HOME/realitlscanner"
IMAGE_NAME="realitlscanner"

# ---------- Colors ----------
if [ -t 1 ]; then
  RESET="\033[0m"
  BOLD="\033[1m"
  DIM="\033[2m"

  GREEN="\033[0;32m"
  BLUE="\033[0;36m"
  PURPLE="\033[0;35m"
  YELLOW="\033[0;33m"
  RED="\033[0;31m"
  WHITE="\033[1;37m"
else
  RESET=""; BOLD=""; DIM=""
  GREEN=""; BLUE=""; PURPLE=""; YELLOW=""; RED=""; WHITE=""
fi

# ---------- Emojis ----------
EMO_OK="🟢"
EMO_TLS="🔵"
EMO_PQ="🟣"
EMO_WARN="🟡"
EMO_ERR="🔴"
EMO_SCAN="🛰️"
EMO_MENU="📋"
EMO_LANG="🌐"
EMO_DOCKER="🐳"
EMO_GIT="🌿"
EMO_NET="🌍"
EMO_EXIT="👋"
EMO_TRASH="🗑️"

# ---------- Defaults ----------
LANG_MODE="en"
TARGET=""

# ---------- Texts ----------
declare -A T_EN=(
  [title]="RealiTLScanner Wrapper"
  [subtitle]="Beautiful Docker-based scanner"
  [menu1]="Scan this machine's public IP"
  [menu2]="Scan another IP/CIDR"
  [menu3]="Remove script"
  [menu_lang]="Language: English / Русский"
  [menu_exit]="Exit"
  [prompt_choice]="Choose an option"
  [prompt_target]="Enter IP or CIDR"
  [checking]="Checking prerequisites..."
  [need_sudo]="This operation may require sudo."
  [docker_install]="Docker not found. Installing with get.docker.com..."
  [docker_ok]="Docker is installed"
  [git_install]="Git not found. Installing..."
  [curl_install]="curl not found. Installing..."
  [wget_install]="wget not found. Installing..."
  [image_check]="Checking RealiTLScanner image..."
  [repo_clone]="Cloning RealiTLScanner repository..."
  [repo_use]="Using existing repository at"
  [image_build]="Building docker image..."
  [ready]="Ready."
  [get_ip]="Fetching public IP..."
  [scan_run]="Running scan..."
  [invalid]="Invalid option"
  [bye]="Exiting..."
  [remove_confirm]="Remove this script from disk? (y/N)"
  [removed]="Script removed."
  [not_removed]="Script not removed."
  [warn_no_docker]="Docker command is unavailable. Please install Docker first."
  [warn_no_repo]="Repository folder was not found and clone failed."
  [warn_empty_target]="Target cannot be empty."
  [scan_header]="Scan result"
)

declare -A T_RU=(
  [title]="Обёртка для RealiTLScanner"
  [subtitle]="Красивый сканер на Docker"
  [menu1]="Сканировать публичный IP этой машины"
  [menu2]="Сканировать другой IP/CIDR"
  [menu3]="Удалить скрипт"
  [menu_lang]="Язык: English / Русский"
  [menu_exit]="Выход"
  [prompt_choice]="Выберите пункт"
  [prompt_target]="Введите IP или CIDR"
  [checking]="Проверка зависимостей..."
  [need_sudo]="Для некоторых действий может понадобиться sudo."
  [docker_install]="Docker не найден. Устанавливаю через get.docker.com..."
  [docker_ok]="Docker установлен"
  [git_install]="Git не найден. Устанавливаю..."
  [curl_install]="curl не найден. Устанавливаю..."
  [wget_install]="wget не найден. Устанавливаю..."
  [image_check]="Проверка образа RealiTLScanner..."
  [repo_clone]="Клонирую репозиторий RealiTLScanner..."
  [repo_use]="Использую существующий репозиторий:"
  [image_build]="Собираю Docker-образ..."
  [ready]="Готово."
  [get_ip]="Получаю публичный IP..."
  [scan_run]="Запускаю сканирование..."
  [invalid]="Неверный пункт меню"
  [bye]="Выход..."
  [remove_confirm]="Удалить этот скрипт с диска? (y/N)"
  [removed]="Скрипт удалён."
  [not_removed]="Скрипт не удалён."
  [warn_no_docker]="Команда docker недоступна. Сначала установите Docker."
  [warn_no_repo]="Папка репозитория не найдена и клонирование не удалось."
  [warn_empty_target]="Цель не может быть пустой."
  [scan_header]="Результат сканирования"
)

t() {
  local key="$1"
  if [[ "$LANG_MODE" == "ru" ]]; then
    printf '%s' "${T_RU[$key]:-${T_EN[$key]:-$key}}"
  else
    printf '%s' "${T_EN[$key]:-$key}"
  fi
}

# ---------- UI ----------
clear_screen() {
  clear >/dev/null 2>&1 || printf '\033c'
}

pause() {
  printf "\n%s" "${DIM}Press Enter to continue...${RESET}"
  read -r _
}

hr() {
  printf "%b\n" "${DIM}────────────────────────────────────────────────────────────${RESET}"
}

banner() {
  clear_screen
  printf "%b\n" "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${RESET}"
  printf "%b\n" "${BOLD}${BLUE}║${RESET} ${BOLD}${WHITE}$(t title)${RESET}                                  ${BOLD}${BLUE}║${RESET}"
  printf "%b\n" "${BOLD}${BLUE}║${RESET} ${DIM}$(t subtitle)${RESET}                           ${BOLD}${BLUE}║${RESET}"
  printf "%b\n" "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${RESET}"
  printf "\n"
}

menu() {
  banner
  printf "%b\n" "${EMO_MENU} 1️⃣  $(t menu1)"
  printf "%b\n" "${EMO_MENU} 2️⃣  $(t menu2)"
  printf "%b\n" "${EMO_TRASH} 3️⃣  $(t menu3)"
  printf "%b\n" "${EMO_LANG} l   $(t menu_lang)"
  printf "%b\n" "${EMO_EXIT} 0️⃣  $(t menu_exit)"
  printf "\n"
}

msg_info() { printf "%b\n" "${BLUE}${1}${RESET}"; }
msg_ok()   { printf "%b\n" "${GREEN}${EMO_OK} ${1}${RESET}"; }
msg_warn() { printf "%b\n" "${YELLOW}${EMO_WARN} ${1}${RESET}"; }
msg_err()  { printf "%b\n" "${RED}${EMO_ERR} ${1}${RESET}"; }

# ---------- Dependency checks ----------
install_pkg_if_possible() {
  local pkg="$1"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null 2>&1 || true
    sudo apt-get install -y "$pkg"
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y "$pkg"
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "$pkg"
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm "$pkg"
  else
    msg_warn "No supported package manager found. Install $pkg manually."
  fi
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    msg_warn "$(t docker_install)"
    curl -fsSL https://get.docker.com | sh
  fi
  if command -v docker >/dev/null 2>&1; then
    msg_ok "$(t docker_ok)"
  else
    msg_err "$(t warn_no_docker)"
    exit 1
  fi
}

check_tools() {
  if ! command -v git >/dev/null 2>&1; then
    msg_warn "$(t git_install)"
    install_pkg_if_possible git
  fi
  if ! command -v curl >/dev/null 2>&1; then
    msg_warn "$(t curl_install)"
    install_pkg_if_possible curl
  fi
  if ! command -v wget >/dev/null 2>&1; then
    msg_warn "$(t wget_install)"
    install_pkg_if_possible wget
  fi
}

ensure_image() {
  msg_info "$(t image_check)"
  if [[ ! -d "$REPO_DIR" ]]; then
    msg_warn "$(t repo_clone)"
    git clone "$REPO_URL" "$REPO_DIR"
  else
    msg_ok "$(t repo_use) $REPO_DIR"
  fi

  if [[ ! -d "$REPO_DIR" ]]; then
    msg_err "$(t warn_no_repo)"
    exit 1
  fi

  msg_info "$(t image_build)"
  (cd "$REPO_DIR" && docker build -t "$IMAGE_NAME" .)
  msg_ok "$(t ready)"
}

# ---------- Scanning ----------
get_public_ip() {
  msg_info "$(t get_ip)"
  curl -fsSL https://api.ipify.org
  printf "\n"
}

run_scanner() {
  local target="$1"
  if [[ -z "$target" ]]; then
    msg_err "$(t warn_empty_target)"
    return 1
  fi

  if ! command -v docker >/dev/null 2>&1; then
    msg_err "$(t warn_no_docker)"
    return 1
  fi

  hr
  msg_info "$(t scan_run)"
  printf "%b\n" "${DIM}Target: ${target}${RESET}"
  hr

  local output
  if ! output="$(docker run --rm "$IMAGE_NAME" "$target" 2>&1)"; then
    printf "%b\n" "${RED}${output}${RESET}"
    return 1
  fi

  parse_output "$output"
}

parse_output() {
  local raw="$1"
  local current_ip=""
  local domain=""
  local tls=""
  local alpn=""
  local curve=""
  local issuer=""
  local geo=""

  while IFS= read -r line; do
    # Reset on new host line if output contains IP-like line
    if [[ "$line" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]+)?$ ]]; then
      current_ip="$line"
      domain=""
      tls=""
      alpn=""
      curve=""
      issuer=""
      geo=""
      printf "\n%b %s\n" "${GREEN}${EMO_OK}${RESET}" "$current_ip"
      continue
    fi

    # Generic fallback when scanner prints first line as IP or host
    if [[ -z "$current_ip" && "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
      current_ip="${line%% *}"
      printf "\n%b %s\n" "${GREEN}${EMO_OK}${RESET}" "$current_ip"
      continue
    fi

    if [[ "$line" =~ [Dd]omain[[:space:]]*[:=][[:space:]]*(.*)$ ]]; then
      domain="${BASH_REMATCH[1]}"
      printf "  %b Domain : %s\n" "${GREEN}${EMO_OK}${RESET}" "$domain"
      continue
    fi

    if [[ "$line" =~ [Tt][Ll][Ss][[:space:]]*[:=][[:space:]]*(.*)$ ]]; then
      tls="${BASH_REMATCH[1]}"
      printf "  %b %s    : %b%s%b\n" "${EMO_TLS}" "TLS" "${BLUE}" "$tls" "${RESET}"
      continue
    fi

    if [[ "$line" =~ [Aa][Ll][Pp][Nn][[:space:]]*[:=][[:space:]]*(.*)$ ]]; then
      alpn="${BASH_REMATCH[1]}"
      printf "  %b ALPN   : %s\n" "${EMO_TLS}" "$alpn"
      continue
    fi

    if [[ "$line" =~ [Cc]urve[[:space:]]*[:=][[:space:]]*(.*)$ ]]; then
      curve="${BASH_REMATCH[1]}"
      if [[ "$curve" == *"KEM"* || "$curve" == *"Post-Quantum"* ]]; then
        printf "  %b Curve  : %b%s%b\n" "${EMO_PQ}" "${PURPLE}" "$curve" "${RESET}"
      else
        printf "  %b Curve  : %s\n" "${EMO_PQ}" "$curve"
      fi
      continue
    fi

    if [[ "$line" =~ [Ii]ssuer[[:space:]]*[:=][[:space:]]*(.*)$ ]]; then
      issuer="${BASH_REMATCH[1]}"
      printf "  %b Issuer : %s\n" "${EMO_TLS}" "$issuer"
      continue
    fi

    if [[ "$line" =~ [Gg][Ee][Oo][[:space:]]*[:=][[:space:]]*(.*)$ ]]; then
      geo="${BASH_REMATCH[1]}"
      printf "  %b Geo    : %s\n" "${EMO_OK}" "$geo"
      continue
    fi

    # Warnings / errors
    if [[ "$line" =~ ([Ww]arn|[Ww]arning|[Ee]rror|[Ff]ail|[Ff]ailed) ]]; then
      printf "  %b %b%s%b\n" "${EMO_ERR}" "${RED}" "$line" "${RESET}"
      continue
    fi
  done <<< "$raw"

  # If no structured output was detected, print raw output nicely
  if [[ -z "$raw" ]]; then
    msg_warn "No output."
  fi
}

# ---------- Actions ----------
scan_this_machine() {
  local ip
  ip="$(get_public_ip)"
  if [[ -z "$ip" ]]; then
    msg_err "Could not fetch public IP."
    return 1
  fi
  run_scanner "$ip"
}

scan_other() {
  local target
  printf "%b " "$(t prompt_target):"
  read -r target
  run_scanner "$target"
}

toggle_lang() {
  if [[ "$LANG_MODE" == "en" ]]; then
    LANG_MODE="ru"
  else
    LANG_MODE="en"
  fi
}

remove_script() {
  printf "%b " "$(t remove_confirm)"
  read -r ans
  case "${ans,,}" in
    y|yes|д|да)
      msg_warn "Removing $0 ..."
      rm -f -- "$0"
      msg_ok "$(t removed)"
      exit 0
      ;;
    *)
      msg_info "$(t not_removed)"
      ;;
  esac
}

# ---------- Main ----------
main() {
  check_tools
  check_docker
  ensure_image

  while true; do
    menu
    printf "%b " "$(t prompt_choice):"
    read -r choice
    case "$choice" in
      1)
        scan_this_machine
        pause
        ;;
      2)
        scan_other
        pause
        ;;
      3)
        remove_script
        pause
        ;;
      l|L)
        toggle_lang
        ;;
      0)
        msg_info "$(t bye)"
        exit 0
        ;;
      *)
        msg_err "$(t invalid)"
        pause
        ;;
    esac
  done
}

main "$@"
