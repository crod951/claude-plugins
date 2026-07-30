#!/usr/bin/env bash
# Scan plugin skills with NVIDIA SkillSpector and fail on any non-suppressed finding.
#
# Usage:
#   bin/scan-skills.sh [plugin ...]   # default: every plugin with a skills/ directory
#
# Environment:
#   SKILLSPECTOR_LLM=1   also run the LLM semantic stage (requires provider credentials,
#                        e.g. SKILLSPECTOR_PROVIDER=anthropic + ANTHROPIC_API_KEY)
#   REPORT_DIR=<dir>     write per-skill JSON and Markdown reports into <dir>
#
# Known false positives are suppressed via each plugin's .skillspector-baseline.yaml,
# with an auditable reason per suppression. Suppressed findings still appear in the
# JSON reports under "suppressed".
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! command -v skillspector >/dev/null 2>&1; then
  echo "skillspector not found. Install it with:" >&2
  echo "  uv tool install git+https://github.com/NVIDIA/skillspector.git" >&2
  exit 1
fi

plugins=("$@")
if [ ${#plugins[@]} -eq 0 ]; then
  for d in plugins/*/skills; do
    [ -d "$d" ] && plugins+=("$(basename "$(dirname "$d")")")
  done
fi
if [ ${#plugins[@]} -eq 0 ]; then
  echo "No plugins with a skills/ directory found." >&2
  exit 1
fi

scan_flags=()
if [ "${SKILLSPECTOR_LLM:-0}" != "1" ]; then
  scan_flags+=(--no-llm)
fi

[ -n "${REPORT_DIR:-}" ] && mkdir -p "$REPORT_DIR"

failures=0
for plugin in "${plugins[@]}"; do
  skills_dir="plugins/$plugin/skills"
  if [ ! -d "$skills_dir" ]; then
    echo "warning: $skills_dir does not exist, skipping" >&2
    continue
  fi

  baseline_flags=()
  baseline="plugins/$plugin/.skillspector-baseline.yaml"
  [ -f "$baseline" ] && baseline_flags=(--baseline "$baseline")

  for skill_dir in "$skills_dir"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    skill="$(basename "$skill_dir")"
    json="$(mktemp)"

    skillspector scan "$skill_dir" ${scan_flags[@]+"${scan_flags[@]}"} ${baseline_flags[@]+"${baseline_flags[@]}"} \
      --format json --output "$json" >/dev/null

    summary="$(python3 - "$json" "$plugin/$skill" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
risk = report["risk_assessment"]
active = report["issues"]
line = (
    f"{sys.argv[2]}: score {risk['score']}/100 ({risk['severity']}, "
    f"{risk['recommendation']}) | active {len(active)} | "
    f"suppressed {report['suppressed_count']}"
)
print(line)
for issue in active:
    loc = issue["location"]
    print(f"  {issue['id']} {issue['pattern']} [{issue['severity']}] "
          f"{loc['file']}:{loc['start_line']}")
sys.exit(1 if active else 0)
PY
)" && skill_ok=0 || skill_ok=1
    echo "$summary"

    if [ -n "${REPORT_DIR:-}" ]; then
      cp "$json" "$REPORT_DIR/$plugin-$skill.json"
      skillspector scan "$skill_dir" ${scan_flags[@]+"${scan_flags[@]}"} ${baseline_flags[@]+"${baseline_flags[@]}"} \
        --show-suppressed --format markdown \
        --output "$REPORT_DIR/$plugin-$skill.md" >/dev/null
    fi
    rm -f "$json"

    [ "$skill_ok" -ne 0 ] && failures=$((failures + 1))
  done
done

if [ "$failures" -gt 0 ]; then
  echo
  echo "FAIL: $failures skill(s) have non-suppressed findings." >&2
  echo "Fix the finding, or if it is a reviewed false positive, add a rule with a" >&2
  echo "reason to the plugin's .skillspector-baseline.yaml." >&2
  exit 1
fi

echo
echo "PASS: all scanned skills are clean (suppressions documented in baselines)."
