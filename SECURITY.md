# Security policy

## Supported versions

The project is before 1.0. Security fixes go into the newest release only.

## Report a vulnerability

Do not open a public issue for a security problem. Report it privately:

1. Go to the [Security tab](https://github.com/Tseku210/khuur_sheet_music/security) of the repository.
2. Select **Report a vulnerability**.
3. Describe the problem, the version or commit, and the steps or the file that shows it.

Only the maintainer can read the report. The maintainer answers in the advisory, agrees a fix with you, and publishes the advisory when a release has the fix. You are credited in the advisory unless you ask not to be.

## Scope

The library reads MusicXML files, plain and compressed (`.mxl`), and scores in its own JSON. It writes MusicXML, JSON and MIDI. A file that it reads can come from people that an app does not trust. A file that makes a reader or the layout engine crash, hang or use memory without limit is in scope. So is any problem in the code of this repository that an attacker can use.

Problems in dependencies, for example FluidSynth in `khuur_synth`, belong to those projects. Report them there.
