#!/usr/bin/env bash
# Fails when the docs disagree with the pubspecs or the export list:
# - each package's CHANGELOG.md must open with its pubspec version,
# - the site's tutorial must install the root package's version,
# - the site's Packages page must name the version of all three packages,
# - the site's Platforms and limits page must name each package's version,
# - the export table on the Packages page must name every name that a `show`
#   list in lib/khuur_sheet_music.dart exports, and no other name of the
#   packages it shows them from,
# - each full program that a README or the tutorial shows must be a dart
#   block that equals the region of its file in example/doc_snippets/.
set -euo pipefail
cd "$(dirname "$0")/../.."

status=0

version_of() {
  sed -n 's/^version: *//p' "$1/pubspec.yaml"
}

for dir in . packages/khuur_score_model packages/khuur_score_layout; do
  version=$(version_of "$dir")
  heading=$(grep -m1 '^## ' "$dir/CHANGELOG.md" | sed 's/^## *//')
  if [ "$heading" != "$version" ]; then
    echo "$dir/CHANGELOG.md opens with $heading, but $dir/pubspec.yaml says $version."
    status=1
  fi
done

version=$(version_of .)
tutorial=site/src/content/docs/tutorial/first-sheet.mdx
constraint=$(sed -n 's/^ *khuur_sheet_music: *//p' "$tutorial")
if [ "${constraint#^}" != "${version%.*}.0" ] && [ "${constraint#^}" != "$version" ]; then
  echo "$tutorial installs khuur_sheet_music $constraint, but pubspec.yaml says $version."
  status=1
fi

packages=site/src/content/docs/reference/packages.md
platforms=site/src/content/docs/reference/platforms-and-limits.md

named=$(sed -n 's/.*all at version \([0-9][^ ]*\)\. .*/\1/p' "$packages")
if [ -z "$named" ]; then
  echo "$packages no longer says \"all at version <version>.\", so this script cannot check it."
  status=1
fi

for entry in khuur_sheet_music:. \
  khuur_score_model:packages/khuur_score_model \
  khuur_score_layout:packages/khuur_score_layout; do
  name=${entry%%:*}
  dir=${entry#*:}
  version=$(version_of "$dir")

  if [ -n "$named" ] && [ "$named" != "$version" ]; then
    echo "$packages says all three packages are at $named, but $dir/pubspec.yaml says $version."
    status=1
  fi

  # The row of the version floors table: | `name` | version | Dart | Flutter |
  floor=$(sed -n "s/^| \`$name\` | \([0-9][^ ]*\) |.*/\1/p" "$platforms")
  if [ "$floor" != "$version" ]; then
    echo "$platforms gives $name the version ${floor:-<none>}, but $dir/pubspec.yaml says $version."
    status=1
  fi
done

# Each export with a `show` list, flattened to: <package> <name> <name> ...
exports=lib/khuur_sheet_music.dart
lists=$(tr '\n' ' ' < "$exports" |
  grep -oE "export 'package:[a-z_]+/[a-z_]+\.dart' +show [^;]*;" |
  sed -E "s/export 'package:([a-z_]+)\/[^']*' +show ([^;]*);/\1 \2/; s/,/ /g" || true)

if [ -z "$lists" ]; then
  echo "$exports has no export with a show list, so this script cannot check $packages."
  status=1
fi

while read -r package names; do
  [ -n "$package" ] || continue
  # The export table follows "The import exports the following names.", and
  # its rows read: | `package` | `Name`, `Name`, ... |
  row=$(awk '/^The import exports the following names\./ { on = 1 } on' "$packages" |
    grep -m1 "^| \`$package\` | " || true)
  if [ -z "$row" ]; then
    echo "$packages has no row for $package in its export table."
    status=1
    continue
  fi
  table=$(printf '%s\n' "${row#*| \`$package\` | }" |
    grep -oE '`[A-Za-z_][A-Za-z0-9_]*`' | tr -d '`' | sort)
  # shellcheck disable=SC2086 # split the names on spaces
  shown=$(printf '%s\n' $names | sort)
  for name in $(comm -23 <(printf '%s\n' "$shown") <(printf '%s\n' "$table")); do
    echo "$exports exports $name from $package, but the export table in $packages does not name it."
    status=1
  done
  for name in $(comm -13 <(printf '%s\n' "$shown") <(printf '%s\n' "$table")); do
    echo "The export table in $packages names $name from $package, but $exports does not export it."
    status=1
  done
done <<< "$lists"

# The library's own files export some names through a `show` list and the
# rest whole, so its row must name each shown name and may name more.
own=$(tr '\n' ' ' < "$exports" |
  grep -oE "export 'src/[a-z_]+\.dart' +show [^;]*;" |
  sed -E "s/export '[^']*' +show ([^;]*);/\1/; s/,/ /g" || true)
row=$(awk '/^The import exports the following names\./ { on = 1 } on' "$packages" |
  grep -m1 '^| The library itself | ' || true)
if [ -n "$own" ] && [ -z "$row" ]; then
  echo "$packages has no row for the library itself in its export table."
  status=1
fi
for name in $own; do
  if [ -n "$row" ] && ! printf '%s\n' "$row" | grep -q "\`$name\`"; then
    echo "$exports exports $name, but the export table in $packages does not name it."
    status=1
  fi
done


# Each full program on a page is a file in example/doc_snippets/, which
# flutter analyze checks. The page must show the lines between the file's
# `// #docregion` and `// #enddocregion` as one of its dart blocks.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
while read -r page snippet; do
  awk '/^\/\/ #enddocregion$/ { on = 0 } on; /^\/\/ #docregion$/ { on = 1 }' \
    "$snippet" > "$work/region"
  if [ ! -s "$work/region" ]; then
    echo "$snippet has no lines between // #docregion and // #enddocregion."
    status=1
    continue
  fi
  # Writes the body of each unindented dart block to block.1, block.2, ...
  rm -f "$work"/block.*
  awk -v out="$work/block." '
    on && /^```$/ { on = 0; close(file); next }
    on { print > file }
    /^```dart$/ { on = 1; file = out (++count); printf "" > file }
  ' "$page"
  closest='' fewest=''
  for block in "$work"/block.*; do
    [ -e "$block" ] || continue
    if cmp -s "$work/region" "$block"; then
      closest=match
      break
    fi
    differ=$(diff "$work/region" "$block" | grep -c '^[<>]' || true)
    if [ -z "$fewest" ] || [ "$differ" -lt "$fewest" ]; then
      fewest=$differ
      closest=$block
    fi
  done
  if [ "$closest" != match ]; then
    echo "$page shows no dart block that equals the region of $snippet."
    if [ -n "$closest" ]; then
      echo "Its closest block differs so, with < for $snippet and > for $page:"
      diff "$work/region" "$closest" || true
    fi
    status=1
  fi
done <<'EOF'
README.md example/doc_snippets/readme.dart
packages/khuur_score_model/README.md example/doc_snippets/score_model_readme.dart
packages/khuur_score_layout/README.md example/doc_snippets/score_layout_readme.dart
site/src/content/docs/tutorial/first-sheet.mdx example/doc_snippets/first_sheet_show_a_score.dart
site/src/content/docs/tutorial/first-sheet.mdx example/doc_snippets/first_sheet_finished.dart
EOF

exit $status
