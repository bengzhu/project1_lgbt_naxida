#!/bin/sh
set -eu

# The deterministic checksum is executed through the same shared sampler that
# VisionOCRService now calls. The Xcode build in the full profile compiles the
# Vision caller itself; this focused runtime keeps the pixel oracle lightweight.
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec bash "$repo_root/scripts/test-v3264-koharu-vertical-quad-warp-runtime.sh"
