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
| `packages/score_model` | The score model, MusicXML and MIDI, and the playback script. Pure Dart. | `xml` |
| `packages/score_layout` | The layout engine. Pure Dart. | `score_model` |
| the root | `SheetView`, the painter and `ScorePlayer`. Flutter. | both, and `khuur_synth` |

Keep Flutter out of `packages/`. The compiler enforces it, because neither package depends on Flutter.

## Run the checks

Run these from the repository root before you push. `flutter test` at the root does not run the tests of the two packages or of the example, so run all of them.

```bash
flutter analyze
flutter test
(cd packages/score_model && dart test)
(cd packages/score_layout && dart test)
(cd example && flutter test)
```

`flutter analyze` must report no issues. The lints come from `pedantic_mono`.

After a change to the layout engine, also run the layout benchmark. It exits with code 1 when a layout is over its budget.

```bash
cd packages/score_layout
mkdir -p build
dart compile exe benchmark/layout_benchmark.dart -o build/layout_benchmark
build/layout_benchmark
```

The glyph table `packages/score_layout/lib/src/bravura.g.dart` is generated. Do not edit it by hand. Change `tool/bravura_metadata.json` or the generator, then run `dart run tool/generate_bravura.dart` in `packages/score_layout`.

## Write the change

- Add or change tests for every change in behaviour. Test what a user of the API can observe, not the internals. The tests use hand-written fakes from `test/mock/`, not a mocking package.
- Document every new public member with a `///` comment.
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
3. CI runs the checks on the oldest supported Flutter and on the newest stable Flutter. Both jobs must pass.
4. The maintainer reviews the change. Push more commits to the same branch to answer the review.
5. The maintainer merges the pull request with a merge commit.

`main` is protected. Nobody pushes to it directly, and nothing merges before CI passes.

## Code of conduct

Everyone who takes part follows the [code of conduct](CODE_OF_CONDUCT.md).

## Licence

By contributing, you agree that your contribution is licensed under the [MIT licence](LICENSE) of this repository.
