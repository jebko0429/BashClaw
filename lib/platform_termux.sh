#!/usr/bin/env bash
# Termux platform helpers

platform_is_termux() {
  [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux/files" ]] || [[ "${PREFIX:-}" == *"/com.termux/files/usr" ]]
}

platform_termux_prefix() {
  if [[ -n "${PREFIX:-}" ]]; then
    printf '%s' "$PREFIX"
  elif [[ -d "/data/data/com.termux/files/usr" ]]; then
    printf '%s' "/data/data/com.termux/files/usr"
  else
    printf '%s' "${HOME}/../usr"
  fi
}

platform_termux_home() {
  if [[ -n "${HOME:-}" ]]; then
    printf '%s' "$HOME"
  else
    printf '%s' "/data/data/com.termux/files/home"
  fi
}

platform_temp_base() {
  local candidate

  for candidate in "${TMPDIR:-}" "${BASHCLAW_STATE_DIR:-}/tmp"; do
    [[ -z "$candidate" ]] && continue
    if mkdir -p "$candidate" 2>/dev/null; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  if platform_is_termux; then
    for candidate in \
      "$(platform_termux_home)/.tmp" \
      "$(platform_termux_prefix)/tmp" \
      "/data/local/tmp"; do
      if mkdir -p "$candidate" 2>/dev/null; then
        printf '%s' "$candidate"
        return 0
      fi
    done
  fi

  for candidate in "${PWD}/.tmp" "${HOME:-}/.tmp" "/tmp"; do
    [[ -z "$candidate" ]] && continue
    if mkdir -p "$candidate" 2>/dev/null; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

platform_termux_shared_storage() {
  local home
  home="$(platform_termux_home)"
  printf '%s' "${home}/storage/shared"
}

platform_termux_downloads_dir() {
  local home
  home="$(platform_termux_home)"
  printf '%s' "${home}/storage/downloads"
}

platform_termux_boot_dir() {
  local home
  home="$(platform_termux_home)"
  printf '%s' "${home}/.termux/boot"
}

platform_termux_api_available() {
  is_command_available "$1"
}
