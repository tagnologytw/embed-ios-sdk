#!/usr/bin/env bash
# Records the booted simulator around one interaction and checks it for black screens.
#
#   scripts/sim-record.sh start <name> [udid]   # start recording
#   ... perform the tap in the simulator ...
#   scripts/sim-record.sh stop <name>           # stop, build a contact sheet, run blackdetect
#
# Output goes to $SIM_RECORD_DIR (default: ${TMPDIR}/EmbedIOSSDKSimRecords/<name>/):
#   tap.mp4, sheet.png (10 fps contact sheet) and blackdetect.txt.
# Exit code of `stop` is 1 when a fully black stretch of 0.3 s or longer is found
# (pic_th=0.995: at least 99.5% of pixels black). Stretches that are only 99% black
# (dark UI with a few controls, e.g. a story header while its video buffers) are
# printed as warnings to review by eye.
set -euo pipefail

command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)" >&2; exit 2; }

action="${1:-}"
name="${2:-}"
[[ -n "$action" && -n "$name" ]] || { echo "usage: $0 start|stop <name> [udid]" >&2; exit 2; }

out_dir="${SIM_RECORD_DIR:-${TMPDIR:-/tmp}/EmbedIOSSDKSimRecords}/$name"
pid_file="$out_dir/record.pid"

case "$action" in
  start)
    device="${3:-booted}"
    mkdir -p "$out_dir"
    xcrun simctl io "$device" recordVideo --codec h264 --force "$out_dir/tap.mp4" > /dev/null 2>&1 &
    echo $! > "$pid_file"
    sleep 1.5
    echo "recording $name -> $out_dir/tap.mp4"
    ;;
  stop)
    [[ -f "$pid_file" ]] || { echo "no recording named $name" >&2; exit 2; }
    kill -INT "$(cat "$pid_file")" 2>/dev/null || true
    rm -f "$pid_file"
    sleep 2

    ffmpeg -loglevel error -i "$out_dir/tap.mp4" \
      -vf "fps=10,scale=120:-1,tile=10x5" -frames:v 1 "$out_dir/sheet.png" -y

    detect() {
      ffmpeg -hide_banner -i "$out_dir/tap.mp4" -vf "blackdetect=d=0.3:pic_th=$1:pix_th=0.12" -an -f null - 2>&1 \
        | grep -o 'black_start:[0-9.]* black_end:[0-9.]* black_duration:[0-9.]*' || true
    }
    full_black="$(detect 0.995)"
    near_black="$(detect 0.99)"
    {
      echo "fully black (pic_th=0.995):"; echo "${full_black:-none}"
      echo "near black (pic_th=0.99):"; echo "${near_black:-none}"
    } > "$out_dir/blackdetect.txt"

    echo "contact sheet: $out_dir/sheet.png"
    if [[ -n "$full_black" ]]; then
      echo "FAIL black screen: $full_black"
      exit 1
    fi
    [[ -n "$near_black" ]] && echo "WARN near-black stretch, check the sheet: $near_black"
    echo "OK no black screen"
    ;;
  *)
    echo "usage: $0 start|stop <name> [udid]" >&2
    exit 2
    ;;
esac
