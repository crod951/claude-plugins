#!/usr/bin/env bash
# sync-versions.sh — Sync plugin versions from plugin.json (source of truth)
# into marketplace.json and README.md.
#
# Compatible with Bash 3.2 (macOS default) and BSD sed.
# Requires python3 for JSON parsing (ships with macOS).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
README="$REPO_ROOT/README.md"

# --- Collect plugin data from plugin.json files ---

plugin_names=()
plugin_versions=()
plugin_descriptions=()
plugin_authors=()
plugin_repositories=()
plugin_keywords_json=()

for plugin_dir in "$REPO_ROOT"/plugins/*/; do
  plugin_json="$plugin_dir.claude-plugin/plugin.json"
  if [ ! -f "$plugin_json" ]; then
    continue
  fi

  name=$(python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" < "$plugin_json")
  version=$(python3 -c "import json,sys; print(json.load(sys.stdin)['version'])" < "$plugin_json")
  description=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" < "$plugin_json")
  author=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('author',{}).get('name',''))" < "$plugin_json")
  repository=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('repository',''))" < "$plugin_json")
  keywords=$(python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('keywords',[])))" < "$plugin_json")

  plugin_names+=("$name")
  plugin_versions+=("$version")
  plugin_descriptions+=("$description")
  plugin_authors+=("$author")
  plugin_repositories+=("$repository")
  plugin_keywords_json+=("$keywords")
done

if [ ${#plugin_names[@]} -eq 0 ]; then
  echo "No plugins found in $REPO_ROOT/plugins/"
  exit 1
fi

changed=0

# --- Update marketplace.json ---

for i in "${!plugin_names[@]}"; do
  name="${plugin_names[$i]}"
  version="${plugin_versions[$i]}"
  description="${plugin_descriptions[$i]}"
  author="${plugin_authors[$i]}"
  repository="${plugin_repositories[$i]}"
  keywords="${plugin_keywords_json[$i]}"

  # Check if plugin exists in marketplace.json
  exists=$(SYNC_NAME="$name" python3 -c "
import json, sys, os
data = json.load(sys.stdin)
found = any(p['name'] == os.environ['SYNC_NAME'] for p in data.get('plugins', []))
print('yes' if found else 'no')
" < "$MARKETPLACE")

  if [ "$exists" = "no" ]; then
    echo "  Adding new plugin '$name' (v$version) to marketplace.json"
    SYNC_NAME="$name" \
    SYNC_VERSION="$version" \
    SYNC_DESC="$description" \
    SYNC_AUTHOR="$author" \
    SYNC_REPO="$repository" \
    SYNC_KEYWORDS="$keywords" \
    python3 -c "
import json, sys, os
data = json.load(sys.stdin)
new_entry = {
    'name': os.environ['SYNC_NAME'],
    'source': './plugins/' + os.environ['SYNC_NAME'],
    'description': os.environ['SYNC_DESC'],
    'version': os.environ['SYNC_VERSION'],
    'author': {'name': os.environ['SYNC_AUTHOR']},
    'repository': os.environ['SYNC_REPO'],
    'keywords': json.loads(os.environ['SYNC_KEYWORDS'])
}
data['plugins'].append(new_entry)
print(json.dumps(data, indent=2, ensure_ascii=False))
" < "$MARKETPLACE" > "$MARKETPLACE.tmp" && mv "$MARKETPLACE.tmp" "$MARKETPLACE"
    changed=1
    continue
  fi

  # Check current version in marketplace
  current=$(SYNC_NAME="$name" python3 -c "
import json, sys, os
data = json.load(sys.stdin)
for p in data.get('plugins', []):
    if p['name'] == os.environ['SYNC_NAME']:
        print(p.get('version', ''))
        break
" < "$MARKETPLACE")

  if [ "$current" = "$version" ]; then
    echo "  marketplace.json: $name already at v$version"
  else
    echo "  marketplace.json: $name v$current -> v$version"
    SYNC_NAME="$name" SYNC_VERSION="$version" python3 -c "
import json, sys, os
data = json.load(sys.stdin)
for p in data['plugins']:
    if p['name'] == os.environ['SYNC_NAME']:
        p['version'] = os.environ['SYNC_VERSION']
        break
print(json.dumps(data, indent=2, ensure_ascii=False))
" < "$MARKETPLACE" > "$MARKETPLACE.tmp" && mv "$MARKETPLACE.tmp" "$MARKETPLACE"
    changed=1
  fi
done

# --- Update README.md ---

for i in "${!plugin_names[@]}"; do
  name="${plugin_names[$i]}"
  version="${plugin_versions[$i]}"

  # Check if a header like "### <name> (v<version>)" exists
  if grep -q "^### $name (v$version)" "$README"; then
    echo "  README.md: $name already at v$version"
  elif grep -q "^### $name (v" "$README"; then
    echo "  README.md: $name -> v$version"
    sed -i '' "s/^### $name (v[^)]*)/### $name (v$version)/" "$README"
    changed=1
  else
    echo "  WARNING: README.md has no section header for '$name' — add it manually"
  fi
done

# --- Summary ---

if [ "$changed" -eq 0 ]; then
  echo "All versions already up to date."
else
  echo "Versions synced."
fi

exit 0
