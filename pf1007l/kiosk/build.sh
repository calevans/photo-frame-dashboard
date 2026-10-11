#!/usr/bin/env bash
# Builds kiosk/build/frame-kiosk.apk with Ubuntu's Android tools (no Gradle, no SDK download).
set -euo pipefail
cd "$(dirname "$0")"

ANDROID_JAR=/usr/lib/android-sdk/platforms/android-23/android.jar
DX=$(command -v dx || command -v dalvik-exchange)
KEYSTORE=$HOME/.android/frame-kiosk.keystore

rm -rf build
mkdir -p build/classes

# Signing key lives outside the project so it never ends up in a commit.
if [ ! -f "$KEYSTORE" ]; then
    mkdir -p "$(dirname "$KEYSTORE")"
    keytool -genkeypair -keystore "$KEYSTORE" -storepass android -keypass android -alias frame \
        -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Frame Kiosk" >/dev/null
fi

aapt package -f -M AndroidManifest.xml -I "$ANDROID_JAR" -F build/unsigned.apk
javac --release 8 -classpath "$ANDROID_JAR" -d build/classes $(find src -name '*.java')
"$DX" --dex --output=build/classes.dex build/classes
(cd build && aapt add unsigned.apk classes.dex >/dev/null)
zipalign -f 4 build/unsigned.apk build/aligned.apk
apksigner sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android \
    --out build/frame-kiosk.apk build/aligned.apk
apksigner verify build/frame-kiosk.apk
echo "built kiosk/build/frame-kiosk.apk"
