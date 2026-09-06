# resolve-remux — batch-transcode camera clips (HEVC/H.264, often
# variable frame rate) into DNxHR .mov files the free DaVinci Resolve on
# Linux can edit (it can't decode AVC/HEVC; DNxHR is the editable codec).
# Per clip it picks the DNxHR profile from the source bit depth and maps
# audio only if present. The VFR->CFR target defaults to 29.97 fps;
# override with the 2nd argument for 24/25/60 fps footage.
#
# Usage: resolve-remux <input-dir> [fps]
# Output: a sibling 'remux/' dir next to the input (…/raw -> …/remux).
# Loaded as text into a writeShellApplication, which prepends the
# shebang and `set -euo pipefail`; do not add them here.

if [ "$#" -lt 1 ] || [ ! -d "${1:-}" ]; then
  echo "usage: resolve-remux <input-dir> [fps]   (fps default 29.97)" >&2
  exit 1
fi

in_dir="$1"
fps="${2:-30000/1001}" # 29.97
out_dir="$(dirname "$in_dir")/remux"
mkdir -p "$out_dir"

shopt -s nullglob nocaseglob
clips=("$in_dir"/*.mp4 "$in_dir"/*.mov "$in_dir"/*.mkv)
shopt -u nullglob nocaseglob

if [ "${#clips[@]}" -eq 0 ]; then
  echo "no .mp4/.mov/.mkv clips found in $in_dir" >&2
  exit 1
fi

for f in "${clips[@]}"; do
  base="$(basename "${f%.*}")"
  out="$out_dir/$base.mov"
  if [ -e "$out" ]; then
    echo "skip (exists): $base"
    continue
  fi

  # DNxHR profile from source bit depth: 10-bit -> HQX, else HQ.
  pixfmt="$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=pix_fmt -of csv=p=0 "$f")"
  case "$pixfmt" in
    *10le | *10be | p010*)
      profile="dnxhr_hqx"
      opix="yuv422p10le"
      ;;
    *)
      profile="dnxhr_hq"
      opix="yuv422p"
      ;;
  esac

  # Map audio only if the clip has an audio stream.
  audio_args=(-an)
  if ffprobe -v error -select_streams a:0 -show_entries stream=index \
    -of csv=p=0 "$f" | grep -q .; then
    audio_args=(-map 0:a:0 -c:a pcm_s16le)
  fi

  echo "=== $base  ($pixfmt -> $profile, ${fps} fps cfr) ==="
  ffmpeg -y -hide_banner -loglevel error -stats \
    -i "$f" \
    -map 0:v:0 "${audio_args[@]}" \
    -c:v dnxhd -profile:v "$profile" -pix_fmt "$opix" \
    -r "$fps" -fps_mode cfr \
    "$out"
done

echo "done -> $out_dir"
