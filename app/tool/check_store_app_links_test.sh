#!/bin/sh
# Prueba de la tarea Gradle checkStoreAppLinks (app/android/app/build.gradle.kts).
# Android solo mira assetlinks.json: falla con marcadores REEMPLAZAR_ o sin el
# fichero, y no le importa el Team ID pendiente de apple-app-site-association.
# Ejecutar desde app/: sh tool/check_store_app_links_test.sh
# (necesita android/local.properties, que crea cualquier `flutter build`).
set -u
cd "$(dirname "$0")/../android" || exit 1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gradle=./gradlew
[ -f gradlew.bat ] && [ "${OS:-}" = "Windows_NT" ] && gradle=./gradlew.bat

clean='[{"target":{"sha256_cert_fingerprints":["AA:BB"]}}]'
marked='[{"target":{"sha256_cert_fingerprints":["REEMPLAZAR_SHA256"]}}]'
aasa_marked='{"applinks":{"details":[{"appIDs":["REEMPLAZAR_TEAM_ID.es.gifthuddle.app"]}]}}'

fails=0
check() { # nombre, carpeta, resultado esperado (pass|fail)
  dir=$2; command -v cygpath >/dev/null 2>&1 && dir=$(cygpath -m "$2")
  if "$gradle" -q :app:checkStoreAppLinks -PappLinksDir="$dir" >"$tmp/out.txt" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado $3, salió $got)"; tail -20 "$tmp/out.txt"; fails=$((fails + 1)); fi
}

mkdir -p "$tmp/a" "$tmp/b" "$tmp/c" "$tmp/d"
printf '%s' "$clean" >"$tmp/a/assetlinks.json"; printf '%s' "$aasa_marked" >"$tmp/a/apple-app-site-association"
printf '%s' "$marked" >"$tmp/b/assetlinks.json"; printf '%s' "$aasa_marked" >"$tmp/b/apple-app-site-association"
printf '%s' "$aasa_marked" >"$tmp/c/apple-app-site-association"
printf '%s' "$clean" >"$tmp/d/assetlinks.json"

check "assetlinks limpio y AASA con Team ID pendiente: pasa" "$tmp/a" pass
check "assetlinks con REEMPLAZAR_: falla" "$tmp/b" fail
check "sin assetlinks.json: falla" "$tmp/c" fail
check "solo assetlinks limpio, sin AASA: pasa" "$tmp/d" pass

[ "$fails" -eq 0 ] && echo "checkStoreAppLinks: 4/4" || { echo "checkStoreAppLinks: $fails fallos"; exit 1; }
