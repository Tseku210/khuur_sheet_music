#!/usr/bin/env bash
# Scores one package of the workspace with pana, as pub.dev will.
#
# pana resolves dependencies from pub.dev. In a release pull request a
# package may already depend on the new version of another package of this
# repository, which is published only once the release is tagged. Such a
# package cannot resolve yet, so it is skipped with a notice, and it is
# scored on the next run after that version is out.
set -euo pipefail
cd "$(dirname "$0")/../.."

dir=$1
for sibling in khuur_score_model khuur_score_layout; do
  if grep -q "^  $sibling:" "$dir/pubspec.yaml"; then
    version=$(sed -n 's/^version: *//p' "packages/$sibling/pubspec.yaml")
    if ! curl -fsS "https://pub.dev/api/packages/$sibling" |
      jq -e --arg v "$version" '.versions | map(.version) | index($v)' >/dev/null; then
      echo "::notice::$dir waits for $sibling $version on pub.dev, so pana skips it."
      exit 0
    fi
  fi
done

dart pub global run pana --no-warning --exit-code-threshold 20 "$dir"
