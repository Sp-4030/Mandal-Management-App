# Hindvi Swarajya Mandal Management

A Flutter app for recording and managing mandal collections, donations, and expenses. The interface and annual reports support Marathi/Devanagari text.

## Features

- Track annual vargani (membership contributions) and previous balances.
- Record prasad donations, prasad supplies, and aarti contributions.
- Track regular and mahaprasad market expenses.
- Generate, preview, and print annual PDF reports.
- Back up and restore the local database, review recovery data, and transfer records between phones using QR-based workflows.
- Scan QR codes for data transfer.

## Requirements

- Flutter SDK with Dart 3.13.4 or later, as allowed by `pubspec.yaml`.
- Android Studio or another configured Flutter target for running the app.

## Run Locally

```sh
flutter pub get
flutter run
```

To run the test suite:

```sh
flutter test
```

To build an Android APK:

```sh
flutter build apk
```

## Data and Backups

The app uses SQLite for local data storage. On Android, the active database is stored at `/storage/emulated/0/हिंदवी/hindvi_latest.db`; older or recovery database files are kept in the `Old` subfolder. Use **Settings** to create a backup, restore a backup, manage recovery data, or transfer mandal data to another phone. Keep a separate backup before restoring or moving data.

## Project Layout

- `lib/screens/`: collection, expense, settings, backup, restore, and transfer screens.
- `lib/database/`: SQLite database access and data models.
- `lib/pdf/`: annual report PDF generation.
- `assets/fonts/` and `assets/images/`: Devanagari font and app logo.
- `test/`: Flutter tests.
