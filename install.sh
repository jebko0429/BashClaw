#!/usr/bin/env bash
# Bashclaw installer - standalone script, no project dependencies
# Usage: curl -fsSL https://raw.githubusercontent.com/shareAI-lab/bashclaw/main/install.sh | bash
set -euo pipefail

_DEFAULT_BASHCLAW_REPO="https://github.com/shareAI-lab/bashclaw.git"
_DEFAULT_BASHCLAW_REF="main"
_INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_INSTALL_SOURCE_REPO=""
_INSTALL_SOURCE_REF=""
_INSTALL_SOURCE_TARBALL=""

_INSTALL_DIR="${BASHCLAW_INSTALL_DIR:-${HOME}/.bashclaw/bin}"
_NO_PATH=false
_UNINSTALL=false
_PREFIX=""
_NEEDS_SHELL_RELOAD=false

# ---- Output helpers ----

_print() {
  printf '%s\n' "$*"
}

_info() {
  printf '[INFO] %s\n' "$*"
}

_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

_fatal() {
  _error "$@"
  exit 1
}

_banner() {
  cat <<'BANNER'
 ____            _       ____ _
| __ )  __ _ ___| |__   / ___| | __ ___      __
|  _ \ / _` / __| '_ \ | |   | |/ _` \ \ /\ / /
| |_) | (_| \__ \ | | | | |___| | (_| |\ V  V /
|____/ \__,_|___/_| |_| \____|_|\__,_| \_/\_/

 Bash is all you need.
BANNER
  _print ""
}

# ---- Platform detection ----

_detect_os() {
  if [[ -d "/data/data/com.termux" ]]; then
    printf 'termux'
    return
  fi
  case "$(uname -s)" in
    Darwin) printf 'darwin' ;;
    Linux)  printf 'linux' ;;
    *)      printf 'unknown' ;;
  esac
}

_detect_distro() {
  if [[ -f /etc/os-release ]]; then
    local id
    id="$(. /etc/os-release && printf '%s' "${ID:-}")"
    printf '%s' "$id"
  elif _is_command_available lsb_release; then
    lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]'
  else
    printf 'unknown'
  fi
}

_check_bash_version() {
  local major="${BASH_VERSINFO[0]:-0}"
  local minor="${BASH_VERSINFO[1]:-0}"
  if (( major < 3 || (major == 3 && minor < 2) )); then
    _fatal "Bash 3.2+ is required. Current: ${BASH_VERSION}"
  fi
  _info "Bash version: ${BASH_VERSION}"
}

_is_command_available() {
  command -v "$1" &>/dev/null
}

_installer_tmp_base() {
  local candidate
  for candidate in "${TMPDIR:-}" "${HOME}/.tmp" "${PREFIX:-}/tmp" "/data/local/tmp" "${PWD}/.tmp" "/tmp"; do
    [[ -z "$candidate" ]] && continue
    if mkdir -p "$candidate" 2>/dev/null; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

_installer_mktemp() {
  local prefix="${1:-bashclaw_install}"
  local suffix="${2:-}"
  local base
  base="$(_installer_tmp_base)" || return 1
  mktemp "${base}/${prefix}.XXXXXX${suffix}" 2>/dev/null
}

_normalize_github_repo_url() {
  local url="${1:-}"
  if [[ -z "$url" ]]; then
    printf '%s' ""
    return 0
  fi

  case "$url" in
    git@github.com:*)
      url="https://github.com/${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      url="https://github.com/${url#ssh://git@github.com/}"
      ;;
  esac

  printf '%s' "$url"
}

_derive_github_tarball_url() {
  local repo_url="${1:-}"
  local ref="${2:-${_DEFAULT_BASHCLAW_REF}}"

  repo_url="$(_normalize_github_repo_url "$repo_url")"
  if [[ "$repo_url" != https://github.com/* ]]; then
    printf '%s' ""
    return 0
  fi

  repo_url="${repo_url%.git}"
  printf '%s/archive/refs/heads/%s.tar.gz' "$repo_url" "$ref"
}

_resolve_install_source() {
  local source_dir="${BASHCLAW_INSTALL_SOURCE_DIR:-${_INSTALL_SCRIPT_DIR}}"
  local repo="${BASHCLAW_REPO:-}"
  local ref="${BASHCLAW_REF:-}"
  local tarball="${BASHCLAW_TARBALL:-}"

  if [[ -z "$repo" && -d "${source_dir}/.git" ]] && _is_command_available git; then
    repo="$(git -C "$source_dir" config --get remote.origin.url 2>/dev/null || true)"
    ref="$(git -C "$source_dir" branch --show-current 2>/dev/null || true)"
  fi

  repo="$(_normalize_github_repo_url "$repo")"
  if [[ -z "$repo" ]]; then
    repo="$_DEFAULT_BASHCLAW_REPO"
  fi
  if [[ -z "$ref" ]]; then
    ref="$_DEFAULT_BASHCLAW_REF"
  fi
  if [[ -z "$tarball" ]]; then
    tarball="$(_derive_github_tarball_url "$repo" "$ref")"
  fi
  if [[ -z "$tarball" ]]; then
    tarball="$(_derive_github_tarball_url "$_DEFAULT_BASHCLAW_REPO" "$_DEFAULT_BASHCLAW_REF")"
  fi

  _INSTALL_SOURCE_REPO="$repo"
  _INSTALL_SOURCE_REF="$ref"
  _INSTALL_SOURCE_TARBALL="$tarball"
}

# ---- Dependency checks ----

_check_curl() {
  if ! _is_command_available curl; then
    _fatal "curl is required but not found. Please install curl first."
  fi
  _info "curl: found"
}

_install_jq() {
  if _is_command_available jq; then
    _info "jq: found ($(jq --version 2>/dev/null || echo 'unknown'))"
    return 0
  fi

  _info "jq not found, attempting to install..."

  local os
  os="$(_detect_os)"

  case "$os" in
    darwin)
      if _is_command_available brew; then
        _info "Installing jq via Homebrew..."
        brew install jq
      else
        _info "Downloading jq binary..."
        _install_jq_binary "darwin"
      fi
      ;;
    linux)
      local distro
      distro="$(_detect_distro)"
      case "$distro" in
        ubuntu|debian|linuxmint|pop)
          _info "Installing jq via apt-get..."
          sudo apt-get update -qq && sudo apt-get install -y -qq jq
          ;;
        fedora|rhel|centos|rocky|alma)
          _info "Installing jq via yum..."
          sudo yum install -y jq
          ;;
        arch|manjaro)
          _info "Installing jq via pacman..."
          sudo pacman -S --noconfirm jq
          ;;
        alpine)
          _info "Installing jq via apk..."
          sudo apk add jq
          ;;
        opensuse*|sles)
          _info "Installing jq via zypper..."
          sudo zypper install -y jq
          ;;
        *)
          _info "Unknown distro, downloading jq binary..."
          _install_jq_binary "linux"
          ;;
      esac
      ;;
    termux)
      _info "Installing jq via pkg..."
      pkg install -y jq
      ;;
    *)
      _info "Downloading jq binary..."
      _install_jq_binary "linux"
      ;;
  esac

  if ! _is_command_available jq; then
    _fatal "Failed to install jq. Please install it manually."
  fi
  _info "jq: installed"
}

_install_jq_binary() {
  local platform="$1"
  local arch
  arch="$(uname -m)"
  local jq_url=""

  case "${platform}-${arch}" in
    darwin-x86_64)  jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-macos-amd64" ;;
    darwin-arm64)   jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-macos-arm64" ;;
    linux-x86_64)   jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64" ;;
    linux-aarch64)  jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-arm64" ;;
    linux-armv7l)   jq_url="https://github.com/jqlang/jq/releases/latest/download/jq-linux-armhf" ;;
    *)
      _fatal "No pre-built jq binary for ${platform}-${arch}"
      ;;
  esac

  local jq_dir="${HOME}/.local/bin"
  mkdir -p "$jq_dir"
  curl -fsSL "$jq_url" -o "${jq_dir}/jq"
  chmod +x "${jq_dir}/jq"

  if [[ ":$PATH:" != *":${jq_dir}:"* ]]; then
    export PATH="${jq_dir}:$PATH"
  fi
}

# ---- Installation ----

_download_bashclaw() {
  local install_dir="$1"
  local parent_dir
  parent_dir="$(dirname "$install_dir")"
  mkdir -p "$parent_dir"

  if _is_command_available git; then
    _info "Cloning bashclaw..."
    if [[ -d "$install_dir" ]]; then
      _info "Existing installation found, updating..."
      if [[ -d "$install_dir/.git" ]]; then
        git -C "$install_dir" remote set-url origin "$_INSTALL_SOURCE_REPO" 2>/dev/null || true
        (cd "$install_dir" && git fetch origin "$_INSTALL_SOURCE_REF" && git checkout "$_INSTALL_SOURCE_REF" && git pull --ff-only origin "$_INSTALL_SOURCE_REF" 2>/dev/null) || {
          _warn "Git update failed, performing fresh clone..."
          rm -rf "$install_dir"
          git clone --depth 1 --branch "$_INSTALL_SOURCE_REF" "$_INSTALL_SOURCE_REPO" "$install_dir"
        }
      else
        _warn "Git pull failed, performing fresh clone..."
        rm -rf "$install_dir"
        git clone --depth 1 --branch "$_INSTALL_SOURCE_REF" "$_INSTALL_SOURCE_REPO" "$install_dir"
      fi
    else
      git clone --depth 1 --branch "$_INSTALL_SOURCE_REF" "$_INSTALL_SOURCE_REPO" "$install_dir"
    fi
  else
    _info "Downloading bashclaw tarball..."
    local tmp_tar
    tmp_tar="$(_installer_mktemp "bashclaw_install" ".tar.gz")"
    curl -fsSL "$_INSTALL_SOURCE_TARBALL" -o "$tmp_tar"
    mkdir -p "$install_dir"
    tar xzf "$tmp_tar" -C "$install_dir" --strip-components=1
    rm -f "$tmp_tar"
  fi

  chmod +x "${install_dir}/bashclaw"
  _info "Installed to: $install_dir"
}

_install_command() {
  local install_dir="$1"
  local bashclaw_bin="${install_dir}/bashclaw"

  if [[ "$_NO_PATH" == "true" ]]; then
    _info "Skipping command installation (--no-path)"
    return 0
  fi

  # Already accessible
  if _is_command_available bashclaw; then
    local existing
    existing="$(command -v bashclaw)"
    if [[ -L "$existing" ]]; then
      # Update existing symlink
      ln -sf "$bashclaw_bin" "$existing"
      _info "Updated symlink: $existing"
    else
      _info "bashclaw already in PATH: $existing"
    fi
    return 0
  fi

  # Strategy 1: Symlink to /usr/local/bin (system-wide, always in PATH)
  if [[ -d "/usr/local/bin" ]] && [[ -w "/usr/local/bin" ]]; then
    ln -sf "$bashclaw_bin" /usr/local/bin/bashclaw
    _info "Symlinked to /usr/local/bin/bashclaw"
    return 0
  fi

  # Strategy 2: Symlink to ~/.local/bin (XDG standard)
  local local_bin="${HOME}/.local/bin"
  mkdir -p "$local_bin"
  ln -sf "$bashclaw_bin" "${local_bin}/bashclaw"
  _info "Symlinked to ${local_bin}/bashclaw"

  # If ~/.local/bin is already in PATH, done
  if [[ ":$PATH:" == *":${local_bin}:"* ]]; then
    return 0
  fi

  # Strategy 3: Add ~/.local/bin to shell configs
  _NEEDS_SHELL_RELOAD=true
  _add_path_to_shell_configs "$local_bin"
  export PATH="${local_bin}:$PATH"
}

_add_path_to_shell_configs() {
  local dir_to_add="$1"
  local path_line="export PATH=\"${dir_to_add}:\$PATH\""
  local shell_configs=()
  local os
  os="$(_detect_os)"

  if [[ "$os" == "darwin" ]]; then
    if [[ ! -f "$HOME/.zshrc" ]]; then
      touch "$HOME/.zshrc"
    fi
    shell_configs+=("$HOME/.zshrc")
  fi

  if [[ -f "$HOME/.bashrc" ]]; then
    shell_configs+=("$HOME/.bashrc")
  fi
  if [[ -f "$HOME/.bash_profile" ]]; then
    shell_configs+=("$HOME/.bash_profile")
  elif [[ -f "$HOME/.profile" ]]; then
    shell_configs+=("$HOME/.profile")
  fi
  if [[ "$os" != "darwin" && -f "$HOME/.zshrc" ]]; then
    shell_configs+=("$HOME/.zshrc")
  fi

  local added=false
  local rc
  for rc in "${shell_configs[@]}"; do
    if grep -qF "bashclaw" "$rc" 2>/dev/null; then
      _info "PATH entry already in $rc"
      continue
    fi
    printf '\n# bashclaw\n%s\n' "$path_line" >> "$rc"
    _info "Added to PATH in $rc"
    added=true
  done

  if [[ "$added" == "false" && ${#shell_configs[@]} -eq 0 ]]; then
    printf '# bashclaw\n%s\n' "$path_line" >> "$HOME/.bashrc"
    _info "Added to PATH in $HOME/.bashrc"
  fi
}

_create_default_config() {
  local install_dir="$1"
  local state_dir="${HOME}/.bashclaw"
  local config_file="${state_dir}/bashclaw.json"
  if [[ -f "$config_file" ]]; then
    _info "Config already exists: $config_file"
    return 0
  fi

  mkdir -p "$state_dir"
  BASHCLAW_STATE_DIR="$state_dir" "${install_dir}/bashclaw" config init >/dev/null 2>&1 || \
    _fatal "Failed to initialize default config via ${install_dir}/bashclaw config init"
  _info "Created default config from installed repo: $config_file"
}

_uninstall() {
  _banner
  _print "Uninstalling bashclaw..."

  local install_dir="$_INSTALL_DIR"

  # Remove symlinks
  local symlink_path
  for symlink_path in /usr/local/bin/bashclaw "${HOME}/.local/bin/bashclaw"; do
    if [[ -L "$symlink_path" ]]; then
      rm -f "$symlink_path"
      _info "Removed symlink: $symlink_path"
    fi
  done

  if [[ -d "$install_dir" ]]; then
    rm -rf "$install_dir"
    _info "Removed: $install_dir"
  fi

  # Remove PATH entries from shell configs (backward compatibility with old installs)
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f "$rc" ]] && grep -qF "# bashclaw" "$rc" 2>/dev/null; then
      local tmp
      tmp="$(_installer_mktemp "bashclaw_uninstall")"
      awk '/^# bashclaw$/{skip=1; next} skip && /^export PATH=.*bashclaw/{skip=0; next} skip{skip=0; print; next} {print}' "$rc" > "$tmp"
      mv "$tmp" "$rc"
      _info "Cleaned PATH from $rc"
    fi
  done

  _print ""
  _print "bashclaw has been uninstalled."
  _print "Your data in ~/.bashclaw has been preserved."
  _print "To remove all data: rm -rf ~/.bashclaw"
}

_verify_install() {
  local install_dir="$1"

  if [[ -x "${install_dir}/bashclaw" ]]; then
    local version
    version="$("${install_dir}/bashclaw" version 2>/dev/null)" || version="unknown"
    _info "Verified: ${version}"
    return 0
  else
    _warn "bashclaw binary not found or not executable at ${install_dir}/bashclaw"
    return 1
  fi
}

_print_instructions() {
  local needs_reload="${_NEEDS_SHELL_RELOAD:-false}"
  local os
  os="$(_detect_os)"

  cat <<'EOF'

  =============================================
    bashclaw installed successfully!
  =============================================

  Quick start:

    bashclaw gateway
    # Open http://localhost:18789 in your browser

  Or in CLI mode:

    bashclaw agent -m "hello"

  Engine options:

    # Claude Code CLI (recommended, reuses subscription):
    bashclaw config set '.agents.defaults.engine' '"claude"'

    # Builtin (direct API, 18 providers):
    export ANTHROPIC_API_KEY='sk-ant-...'

  Other commands:

    bashclaw onboard          # Interactive setup wizard
    bashclaw doctor           # Diagnose issues
    bashclaw daemon install   # Run as background service

  Documentation: https://github.com/shareAI-lab/bashclaw

EOF

  if [[ "$needs_reload" == "true" ]]; then
    local shell_rc="\$HOME/.bashrc"
    if [[ "$os" == "darwin" ]]; then
      shell_rc="\$HOME/.zshrc"
    fi
    _warn "PATH was added to shell config. Reload first:"
    _warn "  source ${shell_rc}  (or open a new terminal)"
  fi
}

# ---- Main ----

_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix)
        _PREFIX="$2"
        _INSTALL_DIR="$2"
        shift 2
        ;;
      --no-path)
        _NO_PATH=true
        shift
        ;;
      --uninstall)
        _UNINSTALL=true
        shift
        ;;
      --help|-h)
        _print "bashclaw installer"
        _print ""
        _print "Usage: install.sh [options]"
        _print ""
        _print "Options:"
        _print "  --prefix DIR    Install to DIR (default: ~/.bashclaw/bin)"
        _print "  --no-path       Don't modify shell PATH"
        _print "  --uninstall     Remove bashclaw"
        _print "  --help          Show this help"
        exit 0
        ;;
      *)
        _warn "Unknown option: $1"
        shift
        ;;
    esac
  done
}

main() {
  _parse_args "$@"

  if [[ "$_UNINSTALL" == "true" ]]; then
    _uninstall
    exit 0
  fi

  _banner

  _print "Installing bashclaw..."
  _print ""

  # System checks
  _check_bash_version
  _check_curl
  _install_jq
  _resolve_install_source
  _print ""

  # Download and install
  _download_bashclaw "$_INSTALL_DIR"
  _install_command "$_INSTALL_DIR"
  _create_default_config "$_INSTALL_DIR"
  _verify_install "$_INSTALL_DIR"

  _print_instructions
}

main "$@"
