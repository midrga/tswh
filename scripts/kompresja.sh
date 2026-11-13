#!/usr/bin/env bash
# Kompresuje film do ok. 90 MB (H.264 + AAC, MP4), zeby zmiescil sie w limicie 100 MB na plik w repo.
# Uzycie: scripts/kompresja.sh <plik_wejsciowy>
# Wypisuje sciezke pliku wynikowego (zawsze .mp4). Oryginal usuwa, gdy nazwa sie zmienia.
set -euo pipefail

src="$1"
dir=$(dirname "$src")
base=$(basename "${src%.*}")
out="$dir/$base.mp4"
work=$(mktemp -d)

command -v ffmpeg >/dev/null || { sudo apt-get update -qq && sudo apt-get install -y -qq ffmpeg >/dev/null; }

dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src")
[[ "$dur" =~ ^[0-9.]+$ ]] || { echo "nie odczytam dlugosci filmu: $src" >&2; exit 1; }

# Cel 90 MB razem z dzwiekiem 128 kb/s.
vb=$(python3 -c "print(int(90e6*8/float('$dur')/1000 - 128))")
# Ponizej 1000 kb/s (film dluzszy niz ok. 12 min) obraz bylby za slaby na reklame.
[ "$vb" -ge 1000 ] || { echo "film za dlugi na kompresje do 90 MB ($dur s, $vb kb/s): $src" >&2; exit 1; }

# Krotszy bok najwyzej 1080 px (4K -> 1080p daje lepsza jakosc przy tej samej wadze).
scale="scale=w='if(lte(iw,ih),min(1080,iw),-2)':h='if(lte(iw,ih),-2,min(1080,ih))'"
common=(-c:v libx264 -preset medium -b:v "${vb}k" -maxrate "$((vb * 3 / 2))k" -bufsize "$((vb * 2))k" -vf "$scale" -pix_fmt yuv420p)

ffmpeg -nostdin -loglevel error -y -i "$src" "${common[@]}" -pass 1 -passlogfile "$work/p" -an -f null /dev/null
ffmpeg -nostdin -loglevel error -y -i "$src" "${common[@]}" -pass 2 -passlogfile "$work/p" \
  -c:a aac -b:a 128k -movflags +faststart "$work/out.mp4"

[ "$src" != "$out" ] && rm -f "$src"
mv "$work/out.mp4" "$out"
rm -rf "$work"
echo "$out"
