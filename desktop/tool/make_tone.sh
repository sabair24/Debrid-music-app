#!/usr/bin/env bash
# A short, quiet FLAC used by the live speaker test. Regenerate with:
#   bash tool/make_tone.sh
set -euo pipefail
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=8:sample_rate=44100" \
  -af "volume=0.05" -c:a flac -sample_fmt s16 \
  -metadata title="DebridMusic testtoon" -metadata artist="Verificatie" \
  "$(dirname "$0")/../test/fixtures/tone.flac"
