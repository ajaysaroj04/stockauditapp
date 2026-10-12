#!/usr/bin/env bash
# Generates the Android platform folder and applies the settings the app needs
# (camera permission, minSdk 23, app name). Safe to run more than once.
#
# Usage (from the project root):   bash tools/setup_android.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter is not installed or not on PATH. See README.md." >&2
  exit 1
fi

if [ ! -d android ]; then
  echo "==> Generating Android project (flutter create)"
  # flutter create must not clobber our own sources, so stash them first.
  BACKUP="$(mktemp -d)"
  cp -r lib test pubspec.yaml analysis_options.yaml "$BACKUP"/
  flutter create --platforms=android --org com.example --project-name vehicle_scanner .
  rm -rf lib test
  cp -r "$BACKUP"/lib "$BACKUP"/test .
  cp "$BACKUP"/pubspec.yaml "$BACKUP"/analysis_options.yaml .
  rm -rf "$BACKUP"
else
  echo "==> android/ already exists, only patching"
fi

echo "==> Patching AndroidManifest.xml and Gradle"
python3 - <<'PY'
import re, pathlib, sys

manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
m = manifest.read_text()
if "android.permission.CAMERA" not in m:
    perms = (
        '    <uses-permission android:name="android.permission.CAMERA"/>\n'
        '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
        '    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false"/>\n'
    )
    m = m.replace("<application", perms + "    <application", 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="Vehicle Scanner"', m, count=1)
manifest.write_text(m)

patched = False
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    f = pathlib.Path(name)
    if not f.exists():
        continue
    s = f.read_text()
    new = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", s)
    new = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", new)
    # ML Kit text recognition breaks R8 in release builds (missing optional
    # language classes), so switch code/resource shrinking off explicitly.
    if "isMinifyEnabled" not in new and "minifyEnabled" not in new:
        if name.endswith(".kts"):
            new = re.sub(
                r"(buildTypes\s*\{\s*release\s*\{)",
                r"\1\n            isMinifyEnabled = false\n            isShrinkResources = false",
                new, count=1)
        else:
            new = re.sub(
                r"(buildTypes\s*\{\s*release\s*\{)",
                r"\1\n            minifyEnabled false\n            shrinkResources false",
                new, count=1)
    f.write_text(new)
    patched = True
if not patched:
    sys.exit("Could not find android/app/build.gradle(.kts)")
PY

echo "==> flutter pub get"
flutter pub get

echo
echo "Done. Next:"
echo "  flutter run                  # run on a connected phone"
echo "  flutter build apk --release  # build an installable APK"
