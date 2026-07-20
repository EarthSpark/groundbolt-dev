#!/usr/bin/env bash
#
# Clone or update every component repo listed in the `repos` manifest.
#
# Each repo you can reach is cloned (or fast-forwarded if already present).
# Repos you can't access (private / unreachable) are skipped with a note;
# the run continues and exits 0.

set -u

# Resolve this script's own directory, then find the manifest next to it.
script_dir=$(cd "$(dirname "$0")" && pwd)
manifest="$script_dir/repos"

if [ ! -f "$manifest" ]; then
  echo "error: manifest not found at $manifest" >&2
  exit 1
fi

cd "$script_dir" || exit 1

cloned=0
updated=0
skipped=0

while IFS= read -r line; do
  # Skip blank lines.
  case "$line" in
    "") continue ;;
  esac
  # Skip comment lines (leading "#", allowing leading whitespace).
  case "$line" in
    \#*) continue ;;
    [[:space:]]*\#*)
      trimmed=$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//')
      case "$trimmed" in
        \#*) continue ;;
      esac
      ;;
  esac

  # Parse fields: name url [branch].
  name=$(printf '%s\n' "$line" | awk '{print $1}')
  url=$(printf '%s\n' "$line" | awk '{print $2}')
  branch=$(printf '%s\n' "$line" | awk '{print $3}')

  if [ -z "$name" ] || [ -z "$url" ]; then
    echo "skip: malformed line ($line)"
    skipped=$((skipped + 1))
    continue
  fi

  if [ -z "$branch" ]; then
    branch="main"
  fi

  if [ -d "$name/.git" ]; then
    # Already cloned: fetch and fast-forward the branch.
    if git -C "$name" fetch origin "$branch" >/dev/null 2>&1 \
       && git -C "$name" checkout "$branch" >/dev/null 2>&1 \
       && git -C "$name" merge --ff-only "origin/$branch" >/dev/null 2>&1; then
      echo "updated: $name ($branch)"
      updated=$((updated + 1))
    else
      echo "skip: $name (no access or unreachable)"
      skipped=$((skipped + 1))
    fi
  else
    # Not present: clone the branch.
    if git clone --branch "$branch" "$url" "$name" >/dev/null 2>&1; then
      echo "cloned: $name ($branch)"
      cloned=$((cloned + 1))
    else
      echo "skip: $name (no access or unreachable)"
      skipped=$((skipped + 1))
    fi
  fi
done < "$manifest"

# Seed the webapp env file from the tracked example on first run. Never
# overwrites an existing .env — local edits are preserved.
if [ ! -f "$script_dir/.env" ]; then
  cp "$script_dir/.env.example" "$script_dir/.env" || exit 1
  echo "created: .env (from .env.example)"
fi

echo ""
echo "summary: cloned=$cloned updated=$updated skipped=$skipped"
exit 0
