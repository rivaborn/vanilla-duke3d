#!/usr/bin/env bash
set -euo pipefail

rel="$1"
REPO_ROOT="$2"
ARCH_DIR="$3"
STATE_DIR="$4"
LOCK="$5"
COUNT_FILE="$6"
ERROR_LOG="$7"
FATAL_FLAG="$8"
FATAL_MSG="$9"
MODEL="${10}"
MAX_TURNS="${11}"
OUTPUT_FORMAT="${12}"
PROMPT_FILE="${13}"
CLAUDE_CONFIG_DIR="${14}"
MAX_RETRIES="${15}"
RETRY_DELAY="${16}"
DEFAULT_FENCE="${17}"
BUNDLE_HEADERS="${18}"
MAX_BUNDLED_HEADERS="${19}"
HASH_DB="${20}"

bump_count() {
  local field="$1"
  flock "$LOCK" bash -c "
    awk -F= 'BEGIN{OFS=FS} \$1==\"$field\"{ \$2=\$2+1 } {print}' '$COUNT_FILE' > '${COUNT_FILE}.tmp' \
      && mv '${COUNT_FILE}.tmp' '$COUNT_FILE'
  " 2>/dev/null || true
}

is_rate_limit() {
  local text="$1"
  local first3
  first3="$(echo "$text" | head -3)"
  echo "$first3" | grep -qE '^#' && return 1
  echo "$first3" | grep -qiE '(^|[^0-9])429([^0-9]|$)' && return 0
  echo "$first3" | grep -qiE 'rate.?limit|usage.?limit|too many requests' && return 0
  echo "$first3" | grep -qiE '^error:.*overloaded|^error:.*quota' && return 0
  return 1
}

log_error() {
  local etype="$1" code="$2" attempt="$3" resp="$4"
  flock "$LOCK" bash -c "
    {
      echo '===================================================='
      echo \"Timestamp: \$(date)\"
      echo \"File: $rel\"
      echo \"Exit Code: $code\"
      echo \"Attempt: $attempt\"
      echo \"Type: $etype\"
      echo '----------------------------------------------------'
    } >> '$ERROR_LOG'
    cat >> '$ERROR_LOG' <<'RESPEOF'
$resp
RESPEOF
    echo >> '$ERROR_LOG'
  " 2>/dev/null || true
}

ext_to_fence() {
  local file="$1"
  case "${file##*.}" in
    c|h|inc)           echo "c" ;;
    cpp|cc|cxx|hpp|hh|hxx|inl) echo "cpp" ;;
    cs)                echo "csharp" ;;
    java)              echo "java" ;;
    py)                echo "python" ;;
    rs)                echo "rust" ;;
    lua)               echo "lua" ;;
    gd|gdscript)       echo "gdscript" ;;
    swift)             echo "swift" ;;
    m|mm)              echo "objectivec" ;;
    shader|cginc|hlsl|glsl|compute) echo "hlsl" ;;
    toml)              echo "toml" ;;
    tscn|tres)         echo "ini" ;;
    *)                 echo "$DEFAULT_FENCE" ;;
  esac
}

# ── Resolve local #include headers ──
# Extracts #include "..." directives, searches the source file's directory
# and the repo root for matching headers, returns up to MAX_BUNDLED_HEADERS.
resolve_local_headers() {
  local src_file="$1" repo_root="$2" max_headers="$3"
  local src_dir
  src_dir="$(dirname "$src_file")"

  # Extract #include "file.h" (not <file.h> — those are system headers)
  grep -oP '#\s*include\s+"\K[^"]+' "$src_file" 2>/dev/null | head -20 | while read -r inc; do
    # Search order: same directory, then repo root
    local found=""
    if [[ -f "$src_dir/$inc" ]]; then
      found="$src_dir/$inc"
    elif [[ -f "$repo_root/$inc" ]]; then
      found="$repo_root/$inc"
    else
      # Try find in repo (limited depth to avoid slowness)
      found="$(find "$repo_root" -maxdepth 4 -name "$(basename "$inc")" -type f 2>/dev/null | head -1)"
    fi
    if [[ -n "$found" && -f "$found" ]]; then
      echo "$found"
    fi
  done | head -"$max_headers"
}

if [[ -f "$FATAL_FLAG" ]]; then exit 1; fi

src="$REPO_ROOT/$rel"
out="$ARCH_DIR/$rel.md"
mkdir -p "$(dirname "$out")"

fence_lang="$(ext_to_fence "$rel")"

# ── Build payload with optional header bundling ──
header_section=""
if [[ "$BUNDLE_HEADERS" == "1" ]]; then
  mapfile -t headers < <(resolve_local_headers "$src" "$REPO_ROOT" "$MAX_BUNDLED_HEADERS")
  if [[ "${#headers[@]}" -gt 0 ]]; then
    header_section="
BUNDLED HEADERS (included for context — these are the local headers this file depends on):
"
    for hdr in "${headers[@]}"; do
      # Get path relative to repo root
      local_path="${hdr#$REPO_ROOT/}"
      hdr_fence="$(ext_to_fence "$local_path")"
      header_section+="
--- ${local_path} ---
\`\`\`${hdr_fence}
$(cat "$hdr")
\`\`\`
"
    done
  fi
fi

payload="FILE PATH (relative): ${rel}

FILE CONTENT:
\`\`\`${fence_lang}
$(cat "$src")
\`\`\`
${header_section}"

attempt=0
while true; do
  if [[ -f "$FATAL_FLAG" ]]; then exit 1; fi

  set +e
  resp="$(printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" claude -p \
    --model "$MODEL" \
    --max-turns "$MAX_TURNS" \
    --output-format "$OUTPUT_FORMAT" \
    --append-system-prompt-file "$PROMPT_FILE" \
    2>&1)"
  code=$?
  set -e

  if [[ $code -eq 0 ]]; then
    if is_rate_limit "$resp"; then
      code=429
    else
      break
    fi
  fi

  if is_rate_limit "$resp"; then
    log_error "RATE_LIMIT" "$code" "$((attempt+1))" "$resp"
    bump_count fail
    echo "Rate limit hit processing: $rel" > "$FATAL_MSG"
    : > "$FATAL_FLAG"
    exit 1
  fi

  attempt=$((attempt + 1))
  if [[ $attempt -le $MAX_RETRIES ]]; then
    bump_count retries
    echo "  [retry $attempt/$MAX_RETRIES] exit=$code on: $rel (waiting ${RETRY_DELAY}s)" >&2
    sleep "$RETRY_DELAY"
    continue
  fi

  log_error "PERSISTENT_FAILURE" "$code" "$attempt" "$resp"
  bump_count fail
  echo "Claude failed (exit=$code) after $attempt attempts on: $rel" > "$FATAL_MSG"
  : > "$FATAL_FLAG"
  exit 1
done

tmp="$(mktemp "$STATE_DIR/tmp.XXXXXX")"
printf '%s\n' "$resp" > "$tmp"
mv -f "$tmp" "$out"

# Immediately record this file's hash so interrupted runs skip it
file_sha="$(sha1sum "$src" | awk '{print $1}')"
(
  flock 9
  printf '%s\t%s\n' "$file_sha" "$rel" >> "$HASH_DB"
) 9>>"$LOCK"

bump_count done
