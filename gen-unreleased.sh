#!/usr/bin/env bash
# gen-unreleased.sh — Generate "## Unreleased changes" via llm Option A
# Requirements: git, llm, repo2prompt
set -euo pipefail

MODEL="${LLM_MODEL:-venice/deepseek-r1-671b}"
CHANGELOG="${CHANGELOG_PATH:-CHANGELOG.md}"

# --- sanity checks
command -v git >/dev/null || { echo "git not found" >&2; exit 1; }
command -v llm >/dev/null || { echo "llm not found" >&2; exit 1; }
command -v repo2prompt >/dev/null || { echo "repo2prompt not found" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Not in a git repo" >&2; exit 1; }

# --- temp files + cleanup
REPO_TMP="$(mktemp)"
DIFF_TMP="$(mktemp)"
OUT_TMP="$(mktemp)"
trap 'rm -f "$REPO_TMP" "$DIFF_TMP" "$OUT_TMP"' EXIT

# --- build repo context
# Current directory as baseline
repo2prompt > "$REPO_TMP"

# --- compute diff since the most recent tag (fallback: initial commit)
if LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null)"; then
  BASE="$LAST_TAG"
else
  BASE="$(git rev-list --max-parents=0 HEAD)"
fi
git diff --no-color -U0 "${BASE}..HEAD" > "$DIFF_TMP"

# --- call llm (Option A: repo as fragment; diff via stdin). Return body only.
CHANGE_BODY="$(
  cat "$DIFF_TMP" | llm -m "$MODEL" -f "$REPO_TMP" -s '
You are a precise release-notes writer.
The fragment is the BASELINE REPOSITORY; STDIN is a UNIFIED DIFF against that baseline.
Produce ONLY the Markdown BODY for a section titled "## Unreleased changes" in Keep a Changelog style.
Subsections (include only if non-empty): Highlights, Added, Changed, Fixed, Removed, Deprecated, Security, Breaking.
Keep bullets terse and include file paths when useful.
Omit the "## Unreleased changes" header itself. If nothing user-facing changed, output: _No user-facing changes._'
)"

# Compose full section with the header
{
  echo "## Unreleased changes"
  echo
  # Trim leading blank lines from model output
  printf '%s\n' "$CHANGE_BODY" | sed '1{/^[[:space:]]*$/d;}'
  echo
} > "$OUT_TMP"

# --- write/replace section in CHANGELOG.md
if [[ ! -f "$CHANGELOG" ]]; then
  {
    echo "# Changelog"
    echo
    cat "$OUT_TMP"
  } > "$CHANGELOG"
  echo "Created $CHANGELOG with Unreleased section." >&2
  exit 0
fi

# Replace existing "## Unreleased changes" section up to (but not including) next level-2 heading.
# If it doesn't exist, append it at the end.
awk -v NEW="$OUT_TMP" '
  function print_file(f,  l){ while ((getline l < f) > 0) print l; close(f) }
  BEGIN { replaced=0; skipping=0 }
  {
    if (!replaced && $0 ~ /^##[[:space:]]+Unreleased[[:space:]]+changes[[:space:]]*$/) {
      print_file(NEW)
      replaced=1
      skipping=1
      next
    }
    if (skipping) {
      if ($0 ~ /^##[[:space:]]+/) { skipping=0; print $0 }
      next
    }
    print $0
  }
  END {
    if (!replaced) {
      print ""
      print_file(NEW)
    }
  }
' "$CHANGELOG" > "${CHANGELOG}.tmp" && mv "${CHANGELOG}.tmp" "$CHANGELOG"

echo "Updated $CHANGELOG: Unreleased section refreshed." >&2
