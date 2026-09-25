Alfredo Marquina Meseguer - MIT License
# gen_upload_wl
A simple bash tool to generate custom wordlist with common upload-rename filename candidates for fuzzing.
Usage: `./gen_upload_wl.sh [-h|--help] [-e|--ext <ext>] [-d|--date <date>] [-w|--window <seconds>] <upload_name> ...`
* -e|-ext <ext>:
  * ext corresponds to the extension without the dot, e.g. png. This text is appended to the names given by positional argument. Otherwise the extensions are extracted from the filenames themselves.
* -d|--date <date>
  * <date> corresponds to a date in HTTP format (RFC 7231) (usually when the file was uploaded). Optional, if provided generate suggested name that use the upload's date to change the name of the file.
  * i.e. the Last-Modified / Date response header
  * e.g. `"Thu, 25 Sep 2026 12:34:56 GMT"`
* -w|--window <seconds>
  * <seconds> +/- seconds around <date> for timestamp and date suggestions. Requires -d|--date option to also be filled
  * <schemes (default 0 = just that exact second)
* <upload_name>
  * original filenames. By default it seeks the extension form each name specifically, if the file has no extension  
  
The date is treated as GMT/UTC (the "GMT" in the header anchors it), so the
epoch is correct regardless of the box's local timezone.

SUGGESTED USE: Streams candidates to `stdout` so nothing lands on disk. Pipe into fuzzing tool like `ffuf`:
```bash
./gen_upload_wl.sh -e png -date "Thu, 25 Sep 2026 12:34:56 GMT" -w 5 test image \
| ffuf -w - -u 'http://target/uploads/FUZZ' -mc 200
```
