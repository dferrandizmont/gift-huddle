#!/bin/sh
# Compila la web como en producción (con nombres) y falla si alguna función
# de la app tiene un `unreachable` inesperado (ver check_wasm_unreachable.mjs).
#   cd app && sh tool/check_wasm_unreachable.sh [carpeta de salida]
set -eu
out="${1:-build/web_check}"
flutter build web --release --wasm --no-web-resources-cdn --pwa-strategy=none --no-strip-wasm -o "$out"
sdk="$(dirname "$(command -v flutter)")/cache/dart-sdk"
"$sdk/bin/utils/wasm-opt" "$out/main.dart.wasm" --all-features --print > "$out/main.wat"
node tool/check_wasm_unreachable.mjs "$out/main.wat"
