#!/usr/bin/env bash
# Alfredo Marquina Meseguer - MIT License
#
# gen_upload_wl.sh — generate custom wordlist with common upload-rename filename candidates for fuzzing.
#
# Usage:
# ./gen_upload_wl.sh [-h|--help] [-e|--ext <ext>] [-d|--date <date>] [-w|--window <seconds>] <upload_name> ...
#
#   -e|-ext <ext>
#       ext corresponds to the extension without the dot, e.g. png. This text is just appended to filenames given 
#       by positional parameters regardless of previously existing extensions. Otherwise the extensions are extracted 
#       from the filenames themselves.
#
#   -d|--date <date>
#       <date> corresponds to a date in HTTP format (RFC 7231) (usually when the file was uploaded). Optional, if provided 
#       it generates suggested names that assume <date> to be the date the file was uploaded to change the name of the file.
#           i.e. the Last-Modified / Date response header
#           e.g. "Thu, 25 Sep 2026 12:34:56 GMT"
#
#   -w|--window <seconds>
#       <seconds> +/- seconds around <date> for timestamp and date suggestions. Requires -d|--date option to also be filled
#       schemes (default 0 = just that exact second)
#
#   <upload_name> 
#       original filenames. By default it seeks the extension form each name specifically, if the file has no extension  
#
# The date is treated as GMT/UTC (the "GMT" in the header anchors it), so the
# epoch is correct regardless of the box's local timezone.
#
# SUGGESTED USE:
# Streams candidates to stdout so nothing lands on disk. Pipe into fuzzing tool like ffuf:
#   ./gen_upload_wl.sh -e png -date "Thu, 25 Sep 2026 12:34:56 GMT" -w 5 test image \
#     | ffuf -w - -u 'http://target/uploads/FUZZ' -mc 200
#
set -euo pipefail

if [ "$#" -lt 3 ]; then
    echo "usage: $0 [-h|--help] [-e|--ext <ext>] [-d|--date <date>] [-w|--window <seconds>] <name>" >&2
    exit 1
fi

# Results of parsing
ext=""
ext_flag=0
date_str=""
base=""
window=0
epoch=""
args=()

parse_args(){
    while getopts ":he:d:w:-:" flag; do
        # Translate long options (--name or --name=value) into their short form
        if [[ $flag == "-" ]]; then
            flag="${OPTARG%%=*}"
            case "$flag" in
                ext|date|window)
                    if [[ $OPTARG == *=* ]]; then
                        OPTARG="${OPTARG#*=}"          # --ext=jpg
                    else
                        OPTARG="${!OPTIND:-}"          # --ext jpg
                        OPTIND=$((OPTIND + 1))
                    fi
                    [[ -z $OPTARG ]] && { echo "$0: --$flag requires a value" >&2; exit 1; }
                    ;;
            esac
        fi

        case "$flag" in
            h|help)     usage; exit 0 ;;
            e|ext)      ext="$OPTARG"; ext_flag=1;;
            d|date)     date_str="$OPTARG" ;;
            w|window)   window="$OPTARG" ;;
            :)          echo "$0: -$OPTARG requires a value" >&2; exit 1 ;;
            \?)         echo "$0: unknown option -$OPTARG" >&2; exit 1 ;;
            *)          echo "$0: unknown option --$flag" >&2; exit 1 ;;
        esac
    done
    shift $((OPTIND - 1))   # make "$@" only for positional argument
    if [[ -n $window && -z $date_str ]]; then
        die "-w/--window requires -d/--date"
    fi
    args=("$@")
    # Parse the HTTP date (RFC 7231, e.g. "Thu, 24 Sep 2026 16:09:22 GMT") to epoch.
    if [[ -n $date_str ]]; then
        if ! epoch="$(date -u -d "$date_str" +%s 2>/dev/null)" ; then
            echo "error: could not parse HTTP date '$date_str'" >&2
            echo "       expected format: \"Thu, 24 Sep 2026 16:09:22 GMT\"" >&2
            exit 1
        fi
    fi
}

# --- hashing helpers ---
h_md5(){    printf '%s' "$1" | md5sum    | cut -d' ' -f1; }
h_sha1(){   printf '%s' "$1" | sha1sum   | cut -d' ' -f1; }
h_sha256(){ printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
h_b64(){    printf '%s' "$1" | base64; }


# ============================================================
# 1. Deterministic, name-based transforms (small, always emitted)
# ============================================================
deterministic()
{
    fullname="${base}.${ext}"
    # the plain names themselves
    printf '%s\n' "$fullname"
    printf '%s\n' "$base"

    # hashes of the bare base and the full name; keep ext, and also drop it
    for n in "$base" "$fullname"; do
        for fn in h_md5 h_sha1 h_sha256; do
            h="$("$fn" "$n")"
            printf '%s.%s\n' "$h" "$ext"     # <hash>.png
            printf '%s\n'    "$h"            # <hash> (ext stripped)
        done
    done

    # md5 of the full name, upper-hex (some stacks store it uppercase)
    up="$(h_md5 "$fullname" | tr 'a-f' 'A-F')"
    printf '%s.%s\n' "$up" "$ext"

    # base64 of the names, with and without padding
    for n in "$base" "$fullname"; do
        e="$(h_b64 "$n")"
        printf '%s.%s\n' "$e" "$ext"
        printf '%s.%s\n' "${e%%=*}" "$ext"  # padding stripped
        printf '%s\n' "$e"                  # No extension
    done
}

# ============================================================
# 2. Human-readable date formats embedded in the name.
#    All rendered from the exact epoch, in UTC. Note: use %m (month) and
#    %d (day) -- %M is minutes and %D expands to m/d/y with slashes.
# ============================================================
formats=(             # Examples
    '%Y%m%d'          # 20260924
    '%d%m%Y'          # 24092026
    '%m%d%Y'          # 09242026
    '%Y-%m-%d'        # 2026-09-24
    '%d-%m-%Y'        # 24-09-2026
    '%Y_%m_%d'        # 2026_09_24
    '%H%M%S'          # 160922
    '%Y%m%d%H%M%S'    # 20260924160922
    '%Y%m%d_%H%M%S'   # 20260924_160922
    '%d%m%Y%H%M%S'    # 24092026160922
    '%Y%m%d%H%M'      # 202609241609
)

human_readeable_date(){
    for fmt in "${formats[@]}"; do
        d="$(date -u -d "@$epoch" +"$fmt")"

        # the date string on its own
        printf '%s.%s\n' "$d" "$ext"

        # combined with the base name, common orders and separators
        printf '%s_%s.%s\n' "$base" "$d" "$ext"   # base_date.png
        printf '%s_%s.%s\n' "$d" "$base" "$ext"   # date_base.png
        printf '%s%s.%s\n'  "$base" "$d" "$ext"   # basedate.png

        # hashes of the date, and of base+date
        printf '%s.%s\n' "$(h_md5 "$d")"              "$ext"
        printf '%s.%s\n' "$(h_md5 "${base}${d}")"     "$ext"
        printf '%s.%s\n' "$(h_md5 "${fullname}${d}")" "$ext"

        # using common prefix upload
        printf 'upload_%s.%s\n' "$d" "$ext" # With base name
        for fn in h_md5 h_sha1 h_sha256 h_b64; do
            h="$("$fn" "$d")"
            printf 'upload_%s.%s\n' "$h" "$ext"     # <hash>.png
            printf 'upload_%s\n'    "$h"            # <hash> (ext stripped)
        done
    done
}

# ============================================================
# 3. Timestamp-based transforms, swept over [epoch-window, epoch+window]
#    (only .ext form, to keep a wide window from exploding)
# ============================================================
timestamp_based(){
    for (( t = epoch - window; t <= epoch + window; t++ )); do
        printf '%s.%s\n' "$t" "$ext"                          # raw epoch
        printf '%s.%s\n' "$(h_md5 "$t")"  "$ext"              # md5(epoch)
        printf '%s.%s\n' "$(h_sha1 "$t")" "$ext"              # sha1(epoch)
        printf '%s.%s\n' "$(h_md5 "${fullname}${t}")" "$ext"  # md5(name+epoch)
        printf '%s.%s\n' "$(h_md5 "${base}${t}")"     "$ext"  # md5(base+epoch)
        printf '%s_%s.%s\n' "$base" "$t" "$ext"              # base_epoch.png

        # add to common name upload_{date}.{ext}
        printf 'upload_%s.%s' "$t" "$ext"
    done
}

main(){
    parse_args "$@"

    for name in "${args[@]}"; do 
        echo "Name: $name"
        if [ $ext_flag -eq 0 ]; then 
            base="${name%.*}"
            ext="${name##*.}"
        else
            base="$name"
        fi

        deterministic

        if [[ -n $date_str ]]; then
            human_readeable_date
            timestamp_based
        fi
    done
}


main "$@"
