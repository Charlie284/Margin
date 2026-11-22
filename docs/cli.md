# The `margin` command-line tool

`margin` is a small executable embedded in Margin.app at
`Contents/SharedSupport/bin/margin`. Install it somewhere on your `PATH` with
**Margin → Install Command Line Tool…**, or run the embedded copy directly:

```sh
Margin.app/Contents/SharedSupport/bin/margin --help
```

## Usage

```
margin <file>
margin <folder>
margin --read <file>
margin export <file> (--pdf | --html) [--output <path>] [--force]
cat README.md | margin
```

## Opening files and folders

- `margin <file>` opens the file in Margin, activating the app.
- `margin --read <file>` opens it straight into Read mode, skipping the editor.
- `margin <folder>` launches Margin with that folder as the shared workspace. The CLI hands the
  app a security-scoped bookmark for the folder so the workspace keeps its file access.
- `cat file.md | margin` reads Markdown from standard input when no path is given. The piped
  text is written to a temporary file under `Margin-CLI/` in the system temporary directory and
  opened as a document; files in that directory older than a day are deleted on each run.

`--` ends option parsing, so a file literally named `--read` can still be opened
(`margin -- --read`).

## Exporting

`margin export` converts a Markdown file without opening the app UI:

```sh
margin export notes.md --html
margin export notes.md --pdf --output notes-final.pdf
```

Exactly one of `--pdf` or `--html` is required. Without `--output`, the output lands next to the
input with a `.html` or `.pdf` extension. An existing output file is not overwritten unless you
pass `--force`, and the output may never be the input file itself. The command prints the written
path. Local images resolve relative to the input file and are embedded in the HTML; remote images
are not fetched.

## Other flags

- `margin --help` / `-h` prints usage.
- `margin --version` prints the version of the Margin.app the CLI would talk to.

## How it finds Margin.app

The CLI needs a Margin.app to open routes in. It looks, in order:

1. the path in the `MARGIN_APP_PATH` environment variable, if set and valid,
2. an enclosing `*.app` bundle around the `margin` executable (the embedded install),
3. a `Margin.app` next to the executable,
4. any installed app with bundle identifier `com.marginapp.Margin`.

If none exists it fails with a message telling you to install the CLI from Margin or set
`MARGIN_APP_PATH`.

## Inter-process protocol

Folder opens and `--read` do not just launch the app — the CLI sends a `margin:` URL to
Margin.app and waits up to five seconds for the app to acknowledge it over a distributed
notification before exiting. The routes are:

- `margin://read?path=<path>&request=<id>` — open the file in Read mode.
- `margin://workspace?path=<path>&bookmark=<base64>&request=<id>` — open the folder as the
  workspace; `bookmark` is optional security-scoped bookmark data.

You can invoke these URLs from scripts or other apps the same way, through
`NSWorkspace`/`open`. If the app launches but never acknowledges, the CLI reports a timeout and
asks you to retry.

## Exit behavior

The CLI exits `0` after the app acknowledges the route (or after an export writes its file) and
`1` with a `margin: …` error on stderr for usage errors, missing files, an unfound app, or an
unacknowledged request.
