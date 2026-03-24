#!/usr/bin/env bash
# Skills system for BashClaw
# Skills are prompt-level capabilities: directories containing SKILL.md and skill.json.
# Compatible with bash 3.2+ (no associative arrays, no global declares, no mapfile)
# Supports frontmatter-based requirements checking (requires_bins, requires_env).

# Parse YAML-like frontmatter from SKILL.md.
# Frontmatter is delimited by --- at the top of the file.
# Returns key=value pairs on separate lines.
_skill_parse_frontmatter() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  local first_line
  first_line="$(head -n 1 "$file")"
  if [[ "$first_line" != "---" ]]; then
    return 0
  fi

  local in_frontmatter=false
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if [[ $line_num -eq 1 ]]; then
      in_frontmatter=true
      continue
    fi
    if [[ "$in_frontmatter" == "true" && "$line" == "---" ]]; then
      break
    fi
    if [[ "$in_frontmatter" == "true" ]]; then
      local key val
      key="$(printf '%s' "$line" | sed 's/:.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
      val="$(printf '%s' "$line" | sed 's/^[^:]*://' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
      if [[ -n "$key" ]]; then
        printf '%s=%s\n' "$key" "$val"
      fi
    fi
  done < "$file"
}

# Get a single frontmatter field value from SKILL.md
_skill_get_frontmatter_field() {
  local file="$1"
  local field="$2"

  local result
  result="$(_skill_parse_frontmatter "$file" | grep "^${field}=" | head -1 | sed "s/^${field}=//")"
  printf '%s' "$result"
}

_skill_first_heading() {
  local file="$1"

  [[ -f "$file" ]] || return 0

  awk '
    BEGIN { in_frontmatter = 0; first = 1 }
    first {
      if ($0 == "---") { in_frontmatter = 1; first = 0; next }
      first = 0
    }
    in_frontmatter {
      if ($0 == "---") { in_frontmatter = 0 }
      next
    }
    /^#[[:space:]]+/ {
      sub(/^#[[:space:]]+/, "", $0)
      print
      exit
    }
  ' "$file"
}

_skill_first_body_line() {
  local file="$1"

  [[ -f "$file" ]] || return 0

  awk '
    BEGIN { in_frontmatter = 0; first = 1 }
    first {
      if ($0 == "---") { in_frontmatter = 1; first = 0; next }
      first = 0
    }
    in_frontmatter {
      if ($0 == "---") { in_frontmatter = 0 }
      next
    }
    /^[[:space:]]*$/ { next }
    /^#[[:space:]]+/ { next }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      print line
      exit
    }
  ' "$file"
}

_skill_guess_description() {
  local skill_dir="$1"

  require_command jq "skill description parsing requires jq"

  local skill_md="${skill_dir}/SKILL.md"
  local skill_json="${skill_dir}/skill.json"
  local desc=""

  if [[ -f "$skill_json" ]] && jq empty < "$skill_json" 2>/dev/null; then
    desc="$(jq -r '.description // empty' < "$skill_json" 2>/dev/null)"
  fi

  if [[ -z "$desc" ]]; then
    desc="$(_skill_get_frontmatter_field "$skill_md" "description")"
  fi

  if [[ -z "$desc" ]]; then
    desc="$(_skill_first_body_line "$skill_md")"
  fi

  if [[ -z "$desc" ]]; then
    desc="$(_skill_first_heading "$skill_md")"
  fi

  if [[ -z "$desc" ]]; then
    desc="Imported skill"
  fi

  printf '%s' "$desc"
}

_skill_normalize_source_dir() {
  local source_dir="$1"

  if [[ ! -d "$source_dir" ]]; then
    return 1
  fi

  (
    cd "$source_dir" >/dev/null 2>&1 && pwd
  )
}

# Check if a skill's requirements are met.
# Returns 0 if all requirements are satisfied, 1 otherwise.
# Sets _SKILL_REQ_MISSING with a description of what's missing.
skill_check_requirements() {
  local skill_dir="${1:?skill_dir required}"

  local skill_md="${skill_dir}/SKILL.md"
  _SKILL_REQ_MISSING=""

  if [[ ! -f "$skill_md" ]]; then
    _SKILL_REQ_MISSING="SKILL.md not found"
    return 1
  fi

  local requires_bins
  requires_bins="$(_skill_get_frontmatter_field "$skill_md" "requires_bins")"
  if [[ -n "$requires_bins" ]]; then
    local old_ifs="$IFS"
    IFS=','
    local bin
    for bin in $requires_bins; do
      bin="$(printf '%s' "$bin" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
      if [[ -n "$bin" ]] && ! command -v "$bin" &>/dev/null; then
        _SKILL_REQ_MISSING="missing binary: $bin"
        IFS="$old_ifs"
        return 1
      fi
    done
    IFS="$old_ifs"
  fi

  local requires_env
  requires_env="$(_skill_get_frontmatter_field "$skill_md" "requires_env")"
  if [[ -n "$requires_env" ]]; then
    local old_ifs="$IFS"
    IFS=','
    local var
    for var in $requires_env; do
      var="$(printf '%s' "$var" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
      if [[ -n "$var" ]]; then
        local var_val
        eval "var_val="\${${var}:-}""
        if [[ -z "$var_val" ]]; then
          _SKILL_REQ_MISSING="missing env var: $var"
          IFS="$old_ifs"
          return 1
        fi
      fi
    done
    IFS="$old_ifs"
  fi

  return 0
}

# Import a skill directory into an agent's local skill store.
# Preserves the skill directory contents and generates BashClaw metadata.
skill_import() {
  local agent_id="${1:?agent_id required}"
  local source_dir="${2:?source_dir required}"
  local requested_name="${3:-}"
  local force="${4:-false}"

  require_command jq "skill import requires jq"

  local normalized_source
  normalized_source="$(_skill_normalize_source_dir "$source_dir")" || {
    log_error "Skill source directory not found: $source_dir"
    return 1
  }

  local source_skill_md="${normalized_source}/SKILL.md"
  if [[ ! -f "$source_skill_md" ]]; then
    log_error "Skill source is missing SKILL.md: $normalized_source"
    return 1
  fi

  local display_name="$requested_name"
  if [[ -z "$display_name" ]]; then
    display_name="$(_skill_first_heading "$source_skill_md")"
  fi
  if [[ -z "$display_name" ]]; then
    display_name="$(basename "$normalized_source")"
  fi

  local safe_name
  safe_name="$(sanitize_key "$display_name")"
  if [[ -z "$safe_name" ]]; then
    log_error "Unable to derive a valid skill name from: $display_name"
    return 1
  fi

  local skills_root="${BASHCLAW_STATE_DIR:?BASHCLAW_STATE_DIR not set}/agents/${agent_id}/skills"
  local dest_dir="${skills_root}/${safe_name}"
  local tmp_dir="${skills_root}/.${safe_name}.import.$$"

  ensure_dir "$skills_root"
  rm -rf "$tmp_dir"
  mkdir -p "$tmp_dir"

  cp -R "$normalized_source/." "$tmp_dir/" || {
    rm -rf "$tmp_dir"
    log_error "Failed to copy skill from: $normalized_source"
    return 1
  }

  if [[ "$force" != "true" && -e "$dest_dir" ]]; then
    rm -rf "$tmp_dir"
    log_error "Skill already exists for agent ${agent_id}: ${safe_name}"
    return 1
  fi

  local desc
  desc="$(_skill_guess_description "$tmp_dir")"

  local existing_meta='{}'
  if [[ -f "${tmp_dir}/skill.json" ]] && jq empty < "${tmp_dir}/skill.json" 2>/dev/null; then
    existing_meta="$(jq '.' < "${tmp_dir}/skill.json")"
  fi

  local imported_at
  imported_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  jq -nc \
    --argjson existing "$existing_meta" \
    --arg name "$safe_name" \
    --arg display_name "$display_name" \
    --arg description "$desc" \
    --arg source "clawhub" \
    --arg source_path "$normalized_source" \
    --arg adapted_for "bashclaw" \
    --arg imported_at "$imported_at" \
    '$existing + {
      name: $name,
      display_name: $display_name,
      description: $description,
      source: $source,
      source_path: $source_path,
      adapted_for: $adapted_for,
      imported_at: $imported_at
    }' > "${tmp_dir}/skill.json"

  if [[ -e "$dest_dir" ]]; then
    rm -rf "$dest_dir"
  fi
  mv "$tmp_dir" "$dest_dir"

  jq -nc \
    --arg agent "$agent_id" \
    --arg name "$safe_name" \
    --arg dir "$dest_dir" \
    --arg source_dir "$normalized_source" \
    '{agent: $agent, name: $name, dir: $dir, source_dir: $source_dir}'
}

# Discover available skills for an agent.
# Scans ${BASHCLAW_STATE_DIR}/agents/${agent_id}/skills/ for skill directories.
# Each valid skill directory contains at least a SKILL.md file.
# Returns JSON array of skill metadata.
skills_discover() {
  local agent_id="${1:?agent_id required}"

  require_command jq "skills_discover requires jq"

  local skills_dir="${BASHCLAW_STATE_DIR:?BASHCLAW_STATE_DIR not set}/agents/${agent_id}/skills"
  local ndjson=""

  if [[ ! -d "$skills_dir" ]]; then
    printf '[]'
    return 0
  fi

  local d
  for d in "${skills_dir}"/*/; do
    [[ -d "$d" ]] || continue

    local skill_md="${d}SKILL.md"
    if [[ ! -f "$skill_md" ]]; then
      continue
    fi

    local skill_name
    skill_name="$(basename "$d")"

    local meta='{}'
    local skill_json="${d}skill.json"
    if [[ -f "$skill_json" ]] && jq empty < "$skill_json" 2>/dev/null; then
      meta="$(jq '.' < "$skill_json")"
    fi

    ndjson="${ndjson}$(jq -nc \
      --arg name "$skill_name" \
      --arg dir "$d" \
      --argjson meta "$meta" \
      '{name: $name, dir: $dir, meta: $meta}')"$'\n'
  done

  if [[ -n "$ndjson" ]]; then
    printf '%s' "$ndjson" | jq -s '.'
  else
    printf '[]'
  fi
}

# List metadata for all available skills.
# Returns JSON array with name, description, tags, and requirements status.
skills_list() {
  local agent_id="${1:?agent_id required}"

  require_command jq "skills_list requires jq"

  local discovered
  discovered="$(skills_discover "$agent_id")"

  local count
  count="$(printf '%s' "$discovered" | jq 'length')"
  if [[ "$count" -eq 0 ]]; then
    printf '[]'
    return 0
  fi

  local ndjson=""
  local idx=0
  while [ "$idx" -lt "$count" ]; do
    local name display_name desc tags skill_dir
    name="$(printf '%s' "$discovered" | jq -r ".[$idx].name")"
    display_name="$(printf '%s' "$discovered" | jq -r ".[$idx].meta.display_name // empty")"
    desc="$(printf '%s' "$discovered" | jq -r ".[$idx].meta.description // \"No description\"")"
    tags="$(printf '%s' "$discovered" | jq ".[$idx].meta.tags // []")"
    skill_dir="$(printf '%s' "$discovered" | jq -r ".[$idx].dir")"

    local skill_md="${skill_dir}SKILL.md"
    local fm_desc
    fm_desc="$(_skill_get_frontmatter_field "$skill_md" "description")"
    if [[ -n "$fm_desc" && "$desc" == "No description" ]]; then
      desc="$fm_desc"
    fi

    local requirements_met="true"
    local requirements_missing=""
    if ! skill_check_requirements "$skill_dir"; then
      requirements_met="false"
      requirements_missing="$_SKILL_REQ_MISSING"
    fi

    local always_flag
    always_flag="$(_skill_get_frontmatter_field "$skill_md" "always")"

    ndjson="${ndjson}$(jq -nc \
      --arg n "$name" \
      --arg dn "$display_name" \
      --arg d "$desc" \
      --argjson t "$tags" \
      --arg rm "$requirements_met" \
      --arg rmsg "$requirements_missing" \
      --arg af "${always_flag:-false}" \
      '{name: $n, display_name: (if $dn == "" then $n else $dn end), description: $d, tags: $t, requirements_met: ($rm == "true"), requirements_missing: $rmsg, always: ($af == "true")}')"$'\n'
    idx=$((idx + 1))
  done

  if [[ -n "$ndjson" ]]; then
    printf '%s' "$ndjson" | jq -s '.'
  else
    printf '[]'
  fi
}

# Load the SKILL.md content for a specific skill.
# Returns the raw markdown text.
# Skips skills whose requirements are not met (unless force=true).
skills_load() {
  local agent_id="${1:?agent_id required}"
  local skill_name="${2:?skill_name required}"
  local force="${3:-false}"

  local safe_name
  safe_name="$(sanitize_key "$skill_name")"

  local skill_dir="${BASHCLAW_STATE_DIR:?BASHCLAW_STATE_DIR not set}/agents/${agent_id}/skills/${safe_name}"
  local skill_md="${skill_dir}/SKILL.md"

  if [[ ! -f "$skill_md" ]]; then
    log_error "Skill not found: $skill_name for agent $agent_id"
    return 1
  fi

  if [[ "$force" != "true" ]]; then
    if ! skill_check_requirements "$skill_dir"; then
      log_warn "Skill '$skill_name' requirements not met: $_SKILL_REQ_MISSING"
      return 1
    fi
  fi

  cat "$skill_md"
}

# Generate a skills availability section for injection into the system prompt.
# Lists available skills so the agent knows what it can request.
# Returns a formatted text block, or empty string if no skills exist.
skills_inject_prompt() {
  local agent_id="${1:?agent_id required}"

  require_command jq "skills_inject_prompt requires jq"

  local skills_json
  skills_json="$(skills_list "$agent_id")"

  local count
  count="$(printf '%s' "$skills_json" | jq 'length')"
  if [[ "$count" -eq 0 ]]; then
    return 0
  fi

  printf '## Available Skills\n'
  printf 'You have access to the following skills. To use a skill, read its SKILL.md for detailed instructions.\n\n'

  local idx=0
  while [ "$idx" -lt "$count" ]; do
    local name desc
    name="$(printf '%s' "$skills_json" | jq -r ".[$idx].display_name")"
    desc="$(printf '%s' "$skills_json" | jq -r ".[$idx].description")"
    printf '%s\n' "- **${name}**: ${desc}"
    idx=$((idx + 1))
  done

  printf '\nTo load a skill, use: skills_load("%s", "<skill_name>")\n' "$agent_id"
}
