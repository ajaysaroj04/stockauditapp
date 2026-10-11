# Vehicle Scanner (Android, Flutter)

Scan vehicle window-label barcodes (VIN, spec code, fuel type), review/correct the
parsed data, store it on the phone, see a live dashboard, search the history and
export everything to CSV.

## Features

| Screen | What it does |
|---|---|
| **Dashboard** | Total vehicles scanned, bars per fuel type (Petrol / Diesel / CNG / EV + any extras), recent scans, big **START SCAN** button |
| **Scanner** | Live camera (Google ML Kit via `mobile_scanner`), reads 1D and 2D codes, torch + camera switch, "not reading?" hint after 12 s, **Enter manually** fallback, camera-permission-denied screen with *Open settings* |
| **Review / Edit** | Editable VIN (validated: 17 chars, no I/O/Q), spec code, fuel type, raw data. Duplicate-VIN warning. Save writes to SQLite |
| **History** | Search by VIN / spec / raw data, fuel filter chips, tap to edit, swipe left to delete, **share icon exports CSV** (respects current filter) |

Saved fields: raw barcode string, VIN, spec/model code, fuel type, scan timestamp.

## Project structure

```
vehicle_scanner/
├── pubspec.yaml
├── analysis_options.yaml
├── .gitignore
├── README.md
├── .github/workflows/build-apk.yml     # CI: analyze, test, build APK
├── tools/setup_android.sh              # generates android/ + camera permission + minSdk
├── lib/
│   ├── main.dart
│   ├── theme.dart                      # large touch targets, fuel colours
│   ├── models/vehicle_scan.dart
│   ├── services/
│   │   ├── barcode_parser.dart         # raw string -> VIN / spec / fuel
│   │   ├── database_service.dart       # sqflite
│   │   └── export_service.dart         # CSV + share sheet
│   └── screens/
│       ├── dashboard_screen.dart
│       ├── scanner_screen.dart
│       ├── review_screen.dart
│       └── history_screen.dart
└── test/barcode_parser_test.dart
```

The `android/` folder is **not** committed on purpose: `tools/setup_android.sh`
generates it with your own Flutter version, so there are no stale Gradle files.

## Option A: get an APK from GitHub (no local setup)

1. Create an empty repository on GitHub (e.g. `vehicle-scanner`, no README).
2. In this folder:
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/<your-username>/vehicle-scanner.git
   git push -u origin main
   ```
3. Open the repo's **Actions** tab. The *Build Android APK* workflow starts on its own (about 5-8 minutes).
4. When it is green, open the run and download the **vehicle-scanner-apk** artifact (a zip containing `app-release.apk`).
5. Copy the APK to the phone and install it (allow "Install unknown apps" for your file manager or browser).

If the run fails, open the failed step; the log shows the exact error. Paste it back and it can be fixed quickly.

## Option B: run locally

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (3.27 or newer), Android Studio (for the SDK) and run `flutter doctor` until Android is green.
2. In the project folder:
   ```bash
   bash tools/setup_android.sh      # on Windows use Git Bash or WSL
   flutter test                     # parser unit tests
   flutter run                      # phone connected with USB debugging on
   flutter build apk --release      # APK at build/app/outputs/flutter-apk/app-release.apk
   ```

## Important: check the barcode format on your labels

The photographed Hyundai labels print the VIN as text (`MALPC813LTM` + `429642`) and
carry two barcodes. **What those barcodes actually encode has not been verified** (it
could be the VIN, the PIO number, or a combined string), so the parser is tolerant:

* VIN: a `VIN:` value, or any 17-character VIN-shaped run, including a VIN split across two tokens.
* Spec: the text after `SPEC`, otherwise a pattern like `1.5UGLS M6`.
* Fuel: `PETROL`, `DIESEL`, `CNG`, `EV`, `HYBRID`, `LPG` anywhere in the string. If both `PETROL` and `CNG` appear (bi-fuel labels) it picks `CNG`.

Anything the parser cannot find is left blank and highlighted on the Review screen, so
nothing is saved unchecked. **Scan a few real labels first**, look at the *Raw barcode
data* field, and if the content is in a different layout, adjust `lib/services/barcode_parser.dart`
(the tests in `test/barcode_parser_test.dart` show how). If the barcodes only contain
the VIN, the spec and fuel can be typed in once per batch on the Review screen.

## Troubleshooting

* **Camera permission denied:** the scanner shows a message with an *Open settings* button.
* **Barcode will not read:** move closer/further, avoid glare on the windscreen glass, use the torch, or use *Enter manually*.
* **Min SDK errors:** re-run `bash tools/setup_android.sh` (it sets minSdk 23).
* **Release signing:** the CI APK is signed with the debug key, which is fine for in-house use. For Play Store publishing, add your own keystore.
