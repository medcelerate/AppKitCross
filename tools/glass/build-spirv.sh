#!/bin/bash
# Compiles the Liquid Glass GLSL compute shaders to SPIR-V in the Linux container (which has
# glslang-tools) and re-embeds every shader into GlassShaders.swift (ADR-0052 stage 2):
#   bash tools/glass/build-spirv.sh
set -e
cd "$(dirname "$0")/../.."
OUT=.build-linux/glass-spirv
mkdir -p "$OUT"
docker run --rm -v "$PWD":/src -w /src ${APPKITWIN_LINUX_IMAGE:-appkitcross-linux:latest} bash -c "
  set -e
  for s in glass_box glass_saturate glass_luminance glass_lens; do
    glslangValidator -V --target-env vulkan1.3 -o $OUT/\$s.spv Sources/AppKit/Platform/Shaders/\$s.comp
  done"
python3 tools/glass/embed-shaders.py --spirv-dir "$OUT"
