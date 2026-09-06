#!/bin/bash
#
# Print (and optionally write) the next marketing version from Info.plist.
# usage: bump-version.sh current|patch|minor|major [--write]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
BUMP="${1:-}"
WRITE=0

if [[ $# -lt 1 ]]; then
  echo "usage: $0 current|patch|minor|major [--write]" >&2
  exit 1
fi
shift
for arg in "$@"; do
  case "$arg" in
    --write) WRITE=1 ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

current="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
if [[ ! "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "invalid CFBundleShortVersionString in Info.plist: $current" >&2
  exit 1
fi

IFS=. read -r major minor patch <<< "$current"
case "$BUMP" in
  current) version="$current" ;;
  patch) version="$major.$minor.$((patch + 1))" ;;
  minor) version="$major.$((minor + 1)).0" ;;
  major) version="$((major + 1)).0.0" ;;
  *)
    echo "usage: $0 current|patch|minor|major [--write]" >&2
    exit 1
    ;;
esac

if [[ "$WRITE" == "1" ]]; then
  existing_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
  if [[ "$version" != "$current" || "$existing_build" != "$version" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$PLIST"
  fi
fi

printf '%s\n' "$version"
