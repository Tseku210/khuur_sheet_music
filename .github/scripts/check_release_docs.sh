#!/usr/bin/env bash
# Fails when the docs name a version other than the one in the pubspecs:
# - each package's CHANGELOG.md must open with its pubspec version,
# - the site's tutorial must install the root package's version.
set -euo pipefail
cd "$(dirname "$0")/../.."

status=0

for dir in . packages/khuur_score_model packages/khuur_score_layout; do
  version=$(sed -n 's/^version: *//p' "$dir/pubspec.yaml")
  heading=$(grep -m1 '^## ' "$dir/CHANGELOG.md" | sed 's/^## *//')
  if [ "$heading" != "$version" ]; then
    echo "$dir/CHANGELOG.md opens with $heading, but $dir/pubspec.yaml says $version."
    status=1
  fi
done

version=$(sed -n 's/^version: *//p' pubspec.yaml)
tutorial=site/src/content/docs/tutorial/first-sheet.mdx
constraint=$(sed -n 's/^ *khuur_sheet_music: *//p' "$tutorial")
if [ "${constraint#^}" != "${version%.*}.0" ] && [ "${constraint#^}" != "$version" ]; then
  echo "$tutorial installs khuur_sheet_music $constraint, but pubspec.yaml says $version."
  status=1
fi

exit $status
