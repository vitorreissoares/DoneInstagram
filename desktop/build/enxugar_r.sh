#!/usr/bin/env bash
# Remove do ambiente R o que o programa não usa (compiladores, documentação,
# cabeçalhos...), para o instalador ficar menor. Uso: enxugar_r.sh <pasta do ambiente>
set -euo pipefail
cd "$1"
rm -rf conda-meta pkgs include man share/doc share/man share/info share/gtk-doc share/locale share/gir-1.0 \
       ssl/misc *-conda-linux-gnu *-apple-darwin* libexec/gcc lib/gcc lib/openvino-* lib/cmake lib/pkgconfig
if [ -d lib ]; then find lib -maxdepth 1 -name "*.a" -delete; fi
if [ -d bin ]; then
  find bin -maxdepth 1 \( -name "*-conda-*" -o -name "pandoc*" -o -name "*gcc*" -o -name "*g++*" -o -name "*gfortran*" \
       -o -name "clang*" -o -name "ld" -o -name "ld.*" -o -name "x86_64-*" -o -name "arm64-*" \
       -o -name "ffprobe" -o -name "ffplay" \) -delete
fi
# Windows
if [ -d Library ]; then
  rm -rf Library/include Library/share/doc Library/share/man Library/share/locale Library/share/info \
         Library/mingw-w64/include Library/mingw-w64/share/doc Library/lib/cmake Library/lib/pkgconfig
  find Library -name "*.a" -delete
  if [ -d Library/bin ]; then
    find Library/bin -maxdepth 1 \( -name "pandoc*" -o -name "ffmpeg.exe" -o -name "ffprobe.exe" -o -name "ffplay.exe" \) -delete
  fi
fi
# Ajuda e documentação dos pacotes R (lib/R no Mac e no Linux, Lib/R no Windows)
for r in lib/R Lib/R; do
  [ -d "$r/library" ] || continue
  for p in "$r"/library/*/; do rm -rf "${p}doc" "${p}html" "${p}tests" "${p}examples" "${p}demo"; done
  rm -rf "$r/doc/manual" "$r/tests"
done
du -sh .
