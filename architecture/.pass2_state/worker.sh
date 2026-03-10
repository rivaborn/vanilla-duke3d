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
PROMPT_FILE_P2="${13}"
CLAUDE_CONFIG_DIR="${14}"
MAX_RETRIES="${15}"
RETRY_DELAY="${16}"
DEFAULT_FENCE="${17}"
ARCH_CONTEXT_FILE="${18}"
XREF_CONTEXT_FILE="${19}"
HASH_DB="${20}"

bump_count() {
  flock "$LOCK" bash -c "
    awk -F= 'BEGIN{OFS=FS} \$1==\"$1\"{ \$2=\$2+1 } {print}' '$COUNT_FILE' > '${COUNT_FILE}.tmp' \
      && mv '${COUNT_FILE}.tmp' '$COUNT_FILE'
  " 2>/dev/null || true
}

is_rate_limit() {
  local first3; first3="$(echo "$1" | head -3)"
  echo "$first3" | grep -qE '^#' && return 1
  echo "$first3" | grep -qiE '(^|[^0-9])429([^0-9]|$)|rate.?limit|usage.?limit|too many requests' && return 0
  return 1
}

ext_to_fence() {
  case "${1##*.}" in
    c|h|inc) echo "c" ;; cpp|cc|cxx|hpp|hh|hxx|inl) echo "cpp" ;;
    cs) echo "csharp" ;; java) echo "java" ;; py) echo "python" ;;
    rs) echo "rust" ;; lua) echo "lua" ;; gd|gdscript) echo "gdscript" ;;
    swift) echo "swift" ;; m|mm) echo "objectivec" ;;
    *) echo "$DEFAULT_FENCE" ;;
  esac
}

if [[ -f "$FATAL_FLAG" ]]; then exit 1; fi

# Debug log file — one per worker
DBGLOG="$STATE_DIR/debug_${rel//\//_}.log"

echo "[$(date)] START: $rel" >> "$DBGLOG"

src="$REPO_ROOT/$rel"
out="$ARCH_DIR/$rel.pass2.md"
pass1="$ARCH_DIR/$rel.md"
mkdir -p "$(dirname "$out")"

fence="$(ext_to_fence "$rel")"
echo "[$(date)] fence=$fence src=$src" >> "$DBGLOG"

# Build enriched payload
# For pass 2, truncate very large source files — Claude has the pass-1 doc
# which already summarizes the entire file. We send the first 500 lines
# of source as a reference, plus the full pass-1 analysis.
pass1_content=""
if [[ -f "$pass1" ]]; then
  pass1_content="$(cat "$pass1")"
  echo "[$(date)] pass1 loaded: $(echo "$pass1_content" | wc -c) bytes" >> "$DBGLOG"
else
  echo "[$(date)] WARNING: no pass1 doc at $pass1" >> "$DBGLOG"
fi

src_lines="$(wc -l < "$src")"
echo "[$(date)] src_lines=$src_lines" >> "$DBGLOG"

if [[ "$src_lines" -gt 500 ]]; then
  src_content="$(head -500 "$src")

... [truncated at 500/$src_lines lines — see first-pass analysis for full coverage] ..."
  echo "[$(date)] source truncated to 500 lines" >> "$DBGLOG"
else
  src_content="$(cat "$src")"
fi

arch_ctx_size="$(wc -c < "$ARCH_CONTEXT_FILE" 2>/dev/null || echo 0)"
xref_ctx_size="$(wc -c < "$XREF_CONTEXT_FILE" 2>/dev/null || echo 0)"
echo "[$(date)] context sizes: arch=${arch_ctx_size}B xref=${xref_ctx_size}B" >> "$DBGLOG"

payload="FILE PATH (relative): ${rel}

FILE CONTENT (${src_lines} lines total):
\`\`\`${fence}
${src_content}
\`\`\`

FIRST-PASS ANALYSIS:
${pass1_content}

ARCHITECTURE CONTEXT:
$(cat "$ARCH_CONTEXT_FILE")

CROSS-REFERENCE CONTEXT (excerpt):
$(cat "$XREF_CONTEXT_FILE")"

payload_size="${#payload}"
echo "[$(date)] payload built: ${payload_size} chars" >> "$DBGLOG"
echo "[$(date)] calling claude -p --model $MODEL ..." >> "$DBGLOG"

attempt=0
while true; do
  if [[ -f "$FATAL_FLAG" ]]; then echo "[$(date)] FATAL_FLAG detected, exiting" >> "$DBGLOG"; exit 1; fi
  set +e
  echo "[$(date)] attempt $((attempt+1)): sending to claude..." >> "$DBGLOG"
  resp="$(printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" claude -p \
    --model "$MODEL" --max-turns "$MAX_TURNS" --output-format "$OUTPUT_FORMAT" \
    --append-system-prompt-file "$PROMPT_FILE_P2" 2>&1)"
  code=$?; set -e
  echo "[$(date)] claude returned: exit=$code resp_size=${#resp}" >> "$DBGLOG"

  if [[ $code -eq 0 ]]; then
    if is_rate_limit "$resp"; then
      echo "[$(date)] rate limit detected in response" >> "$DBGLOG"
      code=429
    else
      echo "[$(date)] success" >> "$DBGLOG"
      break
    fi
  fi
  if is_rate_limit "$resp"; then
    bump_count fail
    echo "Rate limit hit processing: $rel" > "$FATAL_MSG"; : > "$FATAL_FLAG"; exit 1
  fi
  attempt=$((attempt + 1))
  if [[ $attempt -le $MAX_RETRIES ]]; then
    bump_count retries
    echo "  [retry $attempt/$MAX_RETRIES] exit=$code on: $rel" >&2
    echo "[$(date)] retry $attempt/$MAX_RETRIES" >> "$DBGLOG"
    sleep "$RETRY_DELAY"; continue
  fi
  echo "[$(date)] FAILED after $attempt attempts" >> "$DBGLOG"
  bump_count fail
  echo "Failed (exit=$code) after $attempt attempts on: $rel" > "$FATAL_MSG"; : > "$FATAL_FLAG"; exit 1
done

tmp="$(mktemp "$STATE_DIR/tmp.XXXXXX")"
printf '%s\n' "$resp" > "$tmp"
mv -f "$tmp" "$out"

# Immediately record hash so interrupted runs skip this file
file_sha="$(sha1sum "$src" | awk '{print $1}')"
(
  flock 9
  printf '%s\t%s\n' "$file_sha" "$rel" >> "$HASH_DB"
) 9>>"$LOCK"

bump_count done
