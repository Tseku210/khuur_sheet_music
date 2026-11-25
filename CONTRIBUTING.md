# Contributing

Thanks for helping with khuur_sheet_music. This page explains how to set up the repository, which checks a change must pass, and how a pull request lands.

## Before you start

- For a bug, open an issue with the bug form. Include the smallest score that shows it.
- For a new feature or a change to the public API, open an issue with the feature form first. Agree on the shape there before you write the code.
- For a question, start a discussion in [Discussions](https://github.com/Tseku210/khuur_sheet_music/discussions).
- For a security problem, do not open an issue. Follow [SECURITY.md](SECURITY.md).

The library is general. Khuur is its first app, not its target, so instruments, marks and examples stay general. A change that only one app needs belongs in that app.

## Set up

You need Flutter 3.47.5 or later, with the Dart SDK that it includes.

```bash
git clone https://github.com/Tseku210/khuur_sheet_music.git
cd khuur_sheet_music
flutter pub get
```

The repository is a pub workspace of three packages:

| Folder | Package | Depends on |
|---|---|---|
| `packages/khuur_score_model` | The score model, MusicXML and MIDI, and the playback script. Pure Dart. | `archive` and `xml` |
| `packages/khuur_score_layout` | The layout engine. Pure Dart. | `khuur_score_model` |
| the root | `SheetView`, the painter and `ScorePlayer`. Flutter. | both, `khuur_synth` and `material_ui` |

Keep Flutter out of `packages/`. The compiler enforces it, because neither package depends on Flutter.

## Run the checks

Run `tool/check.sh` from the repository root before you push. It runs every check even when one fails, and it exits with code 1 when any check failed.

```bash
tool/check.sh
```

The script runs these commands, each from its own directory. `flutter test` at the root runs only the tests in `test/`, so the script also runs the two packages' tests, the example's tests and the check in `verification/`.

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
.github/scripts/check_release_docs.sh
(cd packages/khuur_score_model && dart test)
(cd packages/khuur_score_layout && dart test)
flutter test
(cd example && flutter test)
flutter test verification/score_player/orders_test.dart
```

`flutter analyze` must report no issues. The lints come from `pedantic_mono`. `check_release_docs.sh` checks that the docs name the pubspecs' versions and the library's exports, and that each code sample in `example/doc_snippets/` matches its page. The last line replays every order of up to 7 steps on `ScorePlayer` and checks each order against the player's promises.

`tool/check.sh --full` also runs the six benchmarks that follow and the web tests. The web tests run in Chrome, so they need Chrome installed.

```bash
flutter test --platform chrome test/web
```

After a change to the layout engine, also run the layout benchmark. It exits with code 1 when a layout is over its budget.

```bash
cd packages/khuur_score_layout
mkdir -p build
dart compile exe benchmark/layout_benchmark.dart -o build/layout_benchmark
build/layout_benchmark
```

After a change to the playback compile, also run the playback benchmark. It exits with code 1 when a score four times as long costs more than eight times as much to compile.

```bash
cd packages/khuur_score_model
mkdir -p build
dart compile exe benchmark/playback_benchmark.dart -o build/playback_benchmark
build/playback_benchmark
```

After a change to how an edit settles the spanners, also run the erase benchmark. It exits with code 1 when erasing the chords that glissandi end on, so that every line loses its note, costs more than three times as much as erasing the chords after them, where no line does.

```bash
cd packages/khuur_score_model
mkdir -p build
dart compile exe benchmark/erase_benchmark.dart -o build/erase_benchmark
build/erase_benchmark
```

After a change to `Erase` or to a ripple edit, also run the erase growth benchmark. It erases a chord in every bar of a score and of one four times as long. It exits with code 1 when the plain erase, the rippled erase, or the rippled erase of a score with a rehearsal mark every eight bars costs more than eight times as much on the longer score.

```bash
cd packages/khuur_score_model
mkdir -p build
dart compile exe benchmark/erase_growth_benchmark.dart -o build/erase_growth_benchmark
build/erase_growth_benchmark
```

After a change to the MusicXML export, also run the export benchmark. It exports scores of note spanners, direction lines, glissandi and measure-repeat signs, each at two lengths. It exits with code 1 when a score four times as long costs more than eight times as much to export.

```bash
cd packages/khuur_score_model
mkdir -p build
dart compile exe benchmark/musicxml_export_benchmark.dart -o build/musicxml_export_benchmark
build/musicxml_export_benchmark
```

After a change to an edit or to the edit session, also run the edit benchmark. It enters one note in scores of two lengths, overwriting and rippling. It exits with code 1 when a score four times as long costs more than eight times as much.

```bash
cd packages/khuur_score_model
mkdir -p build
dart compile exe benchmark/edit_growth_benchmark.dart -o build/edit_growth_benchmark
build/edit_growth_benchmark
```

The glyph table `packages/khuur_score_layout/lib/src/bravura.g.dart` is generated. Do not edit it by hand. Change `tool/bravura_metadata.json` or the generator, then run `dart run tool/generate_bravura.dart` in `packages/khuur_score_layout`.

The pictures of sheets on the docs site and in the README are generated too. After a change to what the sheet draws, or to the sample code on a page with a picture, draw them again and commit the files that change.

```bash
cd example
flutter test tool/render_docs_images.dart
```

The script builds each picture's score as the code on its page does. It writes the site's pictures, a light and a dark one each, to `site/src/assets/sheets/`, and the README's to `doc/`. A second run on the same machine writes the same bytes.

## Write the change

- Add or change tests for every change in behaviour. Test what a user of the API can observe, not the internals. The tests use hand-written fakes from `test/mock/`, not a mocking package.
- Document every new public member with a `///` comment.
- A full program that a README or the tutorial shows is also a file in `example/doc_snippets/`, where `flutter analyze` checks it. Change the page's block and the code between the file's `// #docregion` and `// #enddocregion` together. `.github/scripts/check_release_docs.sh` fails when they differ and prints the lines that differ.
- Asset paths that code loads at runtime start with `packages/khuur_sheet_music/`. A bare `fonts/...` path works only inside this repository.
- For a change that users of the package can notice, add a bullet to the top section of `CHANGELOG.md`. Mark a breaking change with `**Breaking:**` and show how to migrate.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <description>
```

The types are `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf` and `ci`. Common scopes are `model`, `layout`, `view`, `playback` and `example`. For example, `fix(layout): keep a tie inside its system`.

## How a pull request lands

1. Fork the repository and make a branch from `main`.
2. Open a pull request into `main`. Fill in the template.
3. CI runs the tests on the oldest supported Flutter and on the newest stable Flutter. It also runs the web tests, the scaling gates, an Android build of the example app and the package checks. Every job must pass.
4. The maintainer reviews the change. Push more commits to the same branch to answer the review.
5. The maintainer merges the pull request with a merge commit.

`main` is protected. Nobody pushes to it directly, and nothing merges before CI passes.

## How a release goes out

The maintainer releases each package on its own. A pushed tag publishes it to pub.dev through `.github/workflows/publish.yml`.

1. In a pull request, raise the `version` in the package's `pubspec.yaml` and add its entry to the package's `CHANGELOG.md`. If the package needs a new version of another package of this repository, release that one first and raise the dependency.
2. In the same pull request, update the site in `site/src/content/docs/` for every change in the CHANGELOG entry that a user of the package would notice, such as a new or changed edit, widget or option, or a change in how a score sounds or is drawn. For a new minor version, raise the `khuur_sheet_music` version that the tutorial installs. Raise the versions on the Packages and Platforms and limits pages under `reference/` too. CI checks that each CHANGELOG, the tutorial and those two pages name the pubspec's version, with `.github/scripts/check_release_docs.sh`.
3. Merge the pull request.
4. Tag the merge commit on `main` and push the tag. The tag names the package and the new version.

   | Package | Tag |
   | --- | --- |
   | `khuur_sheet_music` | `v0.4.0` |
   | `khuur_score_model` | `khuur_score_model-v0.4.0` |
   | `khuur_score_layout` | `khuur_score_layout-v0.4.0` |

   ```bash
   git tag v0.4.0
   git push origin v0.4.0
   ```

5. The workflow runs the package's tests and publishes it. pub.dev refuses the upload when the tag's version is not the one in the pubspec.

## Code of conduct

Everyone who takes part follows the [code of conduct](CODE_OF_CONDUCT.md).

## Licence

By contributing, you agree that your contribution is licensed under the [MIT licence](LICENSE) of this repository.
