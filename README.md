# gen_upload_wl

A simple Bash tool to generate a custom wordlist of common upload-rename
filename candidates for fuzzing.

*Alfredo Marquina Meseguer — MIT License*

## Usage

```bash
./gen_upload_wl.sh [-h|--help] [-e|--ext <ext>] [-d|--date <date>] [-w|--window <seconds>] <upload_name> ...
```

## Options

- **`-h`, `--help`**
  Show usage information and exit.

- **`-e`, `--ext <ext>`**
  Extension *without* the dot, e.g. `png`. When given, it is appended to the
  names produced from the positional arguments. Otherwise the extension is
  extracted from each filename individually.

- **`-d`, `--date <date>`**
  A date in HTTP format (RFC 7231) — typically when the file was uploaded,
  i.e. the `Last-Modified` or `Date` response header. Optional; when provided,
  the tool also generates suggested names that use the upload's date.
  Example: `"Thu, 25 Sep 2026 12:34:56 GMT"`.

- **`-w`, `--window <seconds>`**
  Generate timestamp and date suggestions for ±`<seconds>` around `<date>`.
  Requires `-d`/`--date`. Default `0` (just that exact second).

- **`<upload_name> ...`**
  One or more original filenames. By default the extension is taken from each
  name individually; if a filename has no extension, none is added (unless
  `-e`/`--ext` is given).

## Notes

The date is treated as GMT/UTC (the "GMT" in the header anchors it), so the
epoch is correct regardless of the box's local timezone.

Patterns based on [offs.es](https://offs.es/) curriculum on File Upload attack.

## Suggested use

Candidates are streamed to `stdout`, so nothing lands on disk. Pipe the output
straight into a fuzzing tool like [`ffuf`](https://github.com/ffuf/ffuf):

```bash
./gen_upload_wl.sh -e png --date "Thu, 25 Sep 2026 12:34:56 GMT" -w 5 test image \
| ffuf -w - -u 'http://target/uploads/FUZZ' -mc 200
```
