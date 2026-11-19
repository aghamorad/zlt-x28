#!/bin/bash
# Compiles ZLT-X28.apk (Android 7.0+ / API 24+) using plain javac + d8 + aapt2 + apksigner.
set -euo pipefail

cd "$(dirname "$0")"
HERE="$PWD"
ROOT="$(cd .. && pwd)"

SDK_CACHE="$HOME/.cache/android-sdk"
AAPT2="$SDK_CACHE/android-14/aapt2"
D8="$SDK_CACHE/android-14/d8"
ZIPALIGN="$SDK_CACHE/android-14/zipalign"
APKSIGNER="$SDK_CACHE/android-14/apksigner"
ANDROID_JAR="$SDK_CACHE/android-34/android.jar"

BUILD="$HERE/.build"
rm -rf "$BUILD"
mkdir -p "$BUILD/gen" "$BUILD/classes" "$BUILD/dex" "$HERE/res/drawable"

cp "$ROOT/ZLTApp/icon-preview.png" "$HERE/res/drawable/ic_launcher.png"

"$AAPT2" compile --dir "$HERE/res" -o "$BUILD/res.zip"
"$AAPT2" link \
    -I "$ANDROID_JAR" \
    --manifest "$HERE/AndroidManifest.xml" \
    -A "$HERE/assets" \
    -o "$BUILD/unaligned.apk" \
    --java "$BUILD/gen" \
    "$BUILD/res.zip"

javac --release 11 \
    -cp "$ANDROID_JAR" \
    -d "$BUILD/classes" \
    "$HERE/src/com/morad/zltx28/MainActivity.java" \
    "$BUILD/gen/com/morad/zltx28/R.java"

jar cf "$BUILD/classes.jar" -C "$BUILD/classes" .
"$D8" --lib "$ANDROID_JAR" --min-api 24 --output "$BUILD/dex" "$BUILD/classes.jar"

(cd "$BUILD/dex" && zip -q "$BUILD/unaligned.apk" classes.dex)
"$ZIPALIGN" -f 4 "$BUILD/unaligned.apk" "$BUILD/aligned.apk"

KEYSTORE="$SDK_CACHE/mobox-release.jks"
OUT_APK="$HERE/ZLT-X28.apk"
"$APKSIGNER" sign \
    --ks "$KEYSTORE" \
    --ks-pass pass:mobox123 \
    --key-pass pass:mobox123 \
    --out "$OUT_APK" \
    "$BUILD/aligned.apk"

cp "$OUT_APK" "/Users/Morad/C3PO/Tools/mibox-fixer/docs/downloads/ZLT-X28.apk"
ls -lh "$OUT_APK" "/Users/Morad/C3PO/Tools/mibox-fixer/docs/downloads/ZLT-X28.apk"
