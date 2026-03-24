#!/usr/bin/env bash
# Skill management command for BashClaw

cmd_skill() {
  local subcommand="${1:-}"
  shift 2>/dev/null || true

  case "$subcommand" in
    list) _cmd_skill_list "$@" ;;
    load) _cmd_skill_load "$@" ;;
    import|import-clawhub) _cmd_skill_import "$@" ;;
    -h|--help|help|"") _cmd_skill_usage ;;
    *)
      log_error "Unknown skill subcommand: $subcommand"
      _cmd_skill_usage
      return 1
      ;;
  esac
}

_cmd_skill_usage() {
  printf 'Usage: bashclaw skill <subcommand> [options]\n\n'
  printf 'Subcommands:\n'
  printf '  %-22s %s\n' 'list AGENT' 'List installed skills for an agent as JSON'
  printf '  %-22s %s\n' 'load AGENT NAME' 'Print the SKILL.md content for a skill'
  printf '  %-22s %s\n' 'import AGENT SOURCE' 'Import a ClawHub-style skill directory'
  printf '\nOptions for import:\n'
  printf '  %-22s %s\n' '--name NAME' 'Override the imported skill name'
  printf '  %-22s %s\n' '--force' 'Replace an existing skill with the same name'
}

_cmd_skill_list() {
  local agent_id="${1:-}"
  if [[ -z "$agent_id" ]]; then
    log_error "Agent id is required"
    printf 'Usage: bashclaw skill list AGENT\n'
    return 1
  fi

  skills_list "$agent_id"
}

_cmd_skill_load() {
  local agent_id="${1:-}"
  local skill_name="${2:-}"
  local force="false"

  shift 2 2>/dev/null || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force="true"; shift ;;
      *) shift ;;
    esac
  done

  if [[ -z "$agent_id" || -z "$skill_name" ]]; then
    log_error "Agent id and skill name are required"
    printf 'Usage: bashclaw skill load AGENT NAME [--force]\n'
    return 1
  fi

  skills_load "$agent_id" "$skill_name" "$force"
}

_cmd_skill_import() {
  local agent_id="${1:-}"
  local source_dir="${2:-}"
  local requested_name=""
  local force="false"

  shift 2 2>/dev/null || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        requested_name="${2:-}"
        shift 2
        ;;
      --force)
        force="true"
        shift
        ;;
      *) shift ;;
    esac
  done

  if [[ -z "$agent_id" || -z "$source_dir" ]]; then
    log_error "Agent id and source directory are required"
    printf 'Usage: bashclaw skill import AGENT SOURCE [--name NAME] [--force]\n'
    return 1
  fi

  skill_import "$agent_id" "$source_dir" "$requested_name" "$force"
}
