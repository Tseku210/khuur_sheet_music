#!/usr/bin/env bash
# Runs the checks that CONTRIBUTING.md lists, each from its own directory.
# Every check runs even when one before it failed, and the script exits
# with code 1 at the end when any check failed.
#
#   tool/check.sh          the formatter, the analyzer, every test suite and
#                          every order of up to 7 steps on ScorePlayer
#   tool/check.sh --full   also the six benchmarks and the web tests, which
#                          need Chrome
set -uo pipefail
cd "$(dirname "$0")/.."

full=false
case "${1:-}" in
  '') ;;
  --full) full=true ;;
  *)
    echo "Usage: tool/check.sh [--full]" >&2
    exit 2
    ;;
esac

failed=''

# run <name> <directory> <command> [<argument> ...]
run() {
  local name=$1 dir=$2
  shift 2
  echo "== $name ($dir)"
  if ! (cd "$dir" && "$@"); then
    failed="$failed  $name"$'\n'
  fi
}

# benchmark <directory> <name> compiles benchmark/<name>.dart and runs it.
benchmark() {
  run "$2" "$1" sh -c "mkdir -p build &&
    dart compile exe benchmark/$2.dart -o build/$2 && build/$2"
}

run 'Format' . dart format --output=none --set-exit-if-changed .
run 'Analyze' . flutter analyze
run 'Score model tests' packages/khuur_score_model dart test
run 'Layout engine tests' packages/khuur_score_layout dart test
run 'Library tests' . flutter test
run 'Example tests' example flutter test
run 'Player orders' . flutter test verification/score_player/orders_test.dart

if $full; then
  for name in playback_benchmark erase_benchmark erase_growth_benchmark \
    musicxml_export_benchmark edit_growth_benchmark; do
    benchmark packages/khuur_score_model "$name"
  done
  benchmark packages/khuur_score_layout layout_benchmark
  run 'Web tests' . flutter test --platform chrome test/web
fi

if [ -n "$failed" ]; then
  printf 'These checks failed after %s s:\n%s' "$SECONDS" "$failed"
  exit 1
fi
echo "Every check passed in $SECONDS s."
