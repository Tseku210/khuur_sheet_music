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
| `packages/khuur_score_model` | The score model, MusicXML and MIDI, and the playback script. Pure Dart. | `xml` |
| `packages/khuur_score_layout` | The layout engine. Pure Dart. | `khuur_score_model` |
| the root | `SheetView`, the painter and `ScorePlayer`. Flutter. | both, and `khuur_synth` |

Keep Flutter out of `packages/`. The compiler enforces it, because neither package depends on Flutter.

## Run the checks

Run these from the repository root before you push. `flutter test` at the root does not run the tests of the two packages or of the example, so run all of them.

```bash
flutter analyze
flutter test
(cd packages/khuur_score_model && dart test)
(cd packages/khuur_score_layout && dart test)
(cd example && flutter test)
flutter test --platform chrome test/web
```

The last line runs the web tests in Chrome, so it needs Chrome installed. `flutter analyze` must report no issues. The lints come from `pedantic_mono`.

After a change to the layout engine, also run the layout benchmark. It exits with code 1 when a layout is over its budget.

```bash
cd packages/khuur_score_layout
mkdir -p build
dart compile exe benchmark/layout_benchmark.dart -o build/layout_benchmark
build/layout_benchmark
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

## How a release goes out

The maintainer releases each package on its own. A pushed tag publishes it to pub.dev through `.github/workflows/publish.yml`.

1. In a pull request, raise the `version` in the package's `pubspec.yaml` and add its entry to the package's `CHANGELOG.md`. If the package needs a new version of another package of this repository, release that one first and raise the dependency.
2. Merge the pull request.
3. Tag the merge commit on `main` and push the tag. The tag names the package and the new version.

   | Package | Tag |
   | --- | --- |
   | `khuur_sheet_music` | `v0.4.0` |
   | `khuur_score_model` | `khuur_score_model-v0.4.0` |
   | `khuur_score_layout` | `khuur_score_layout-v0.4.0` |

   ```bash
   git tag v0.4.0
   git push origin v0.4.0
   ```

4. The workflow runs the package's tests and publishes it. pub.dev refuses the upload when the tag's version is not the one in the pubspec.

## Code of conduct

Everyone who takes part follows the [code of conduct](CODE_OF_CONDUCT.md).

## Licence

By contributing, you agree that your contribution is licensed under the [MIT licence](LICENSE) of this repository.
