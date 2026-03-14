<div align="center">

<img src="web/icons/Icon-192.png" alt="PreConnect icon" width="96" height="96" />

# PreConnect

Fast, Calm Academic Companion App.
An initiative run by [BRAC University](https://bracu.ac.bd) students.

![GitHub Release](https://img.shields.io/github/v/release/sabbirba/preconnect?label=latest%20version&&color=dark-green) ![License](https://img.shields.io/badge/license-GPL3.0-blue) ![Contributors](https://img.shields.io/github/contributors/sabbirba/preconnect?color=red&link=https%3A%2F%2Fgithub.com%2Fsabbirba%2Fpreconnect%2Fblob%2Fmain%2FCONTRIBUTING.md)

</div>

## Overview

A Flutter app for BRAC University students with SSO login and Connect API integration.

### Key features

- Simple, predictable navigation
- Class schedules and exam tracking
- Smart alarms and reminders
- QR-based friend sharing
- Offline-friendly, cache-first experience

## Screenshots
<div>
<img src="screenshots/Apple iPhone 16 Pro Max Screenshot 1.png" alt="Apple iPhone 16 Pro Max Screenshot 1" width="240" />
<img src="screenshots/Apple iPhone 16 Pro Max Screenshot 2.png" alt="Apple iPhone 16 Pro Max Screenshot 2" width="240" />
<img src="screenshots/Apple iPhone 16 Pro Max Screenshot 3.png" alt="Apple iPhone 16 Pro Max Screenshot 3" width="240" />
</div>

## Design System

### Colors

- Primary: `#1E6BE3`
- Accent: `#22B573`
- Light background: `#EAF4FF` to `#F3FFF4`
- Dark background: `#000000`

### Typography

- Titles: 16–18 px, semibold
- Body: 11–14 px, regular

### Layout

- Card-first UI
- Padding: 14–16 px
- Radius: 18–22 px

## Project Structure

```
lib/
  main.dart          Entry point
  app.dart           App shell & routing
  api/               Auth & API client
  model/             Data models
  pages/             UI screens & sections
  tools/             Utilities (caching, helpers, etc.)
android/             Android configuration (Kotlin)
ios/                 iOS configuration (Swift)
macos/               macOS shell
web/                 Web shell
assets/              Icons & SVGs
```

## Getting Started

### Requirements

- Flutter stable
- Android Studio with Android SDK
- Java 17

Check your setup:

```bash
flutter doctor -v
```

Install packages:

```bash
flutter pub get
```

### Environment setup

Copy the example env file:

```bash
cp .env.example .env
```

Update [`.env.example`](.env.example) values in your local [`.env`](.env):

- `storeFile`
- `storePassword`
- `keyAlias`
- `keyPassword`
- `DEVELOPMENT_TEAM`

### Android signing setup

Release builds require `android/key.properties`.

Create `android/key.properties` manually with:

```bash
cat > android/key.properties <<'EOF'
storeFile=preconnect-release-key.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=preconnect
keyPassword=YOUR_KEY_PASSWORD
EOF
```

Update the values to match your keystore. The Android release build will fail if `android/key.properties` is missing.

### Run the app

```bash
flutter run
```

### Build Android APK

Release APK:

```bash
flutter build apk --release
```

Output:

```bash
build/app/outputs/flutter-apk/app-release.apk
```

### Build Android AAB

Release AAB:

```bash
flutter build appbundle --release
```

Output:

```bash
build/app/outputs/bundle/release/app-release.aab
```

Local release builds in this repo are Android ARM64 only. Desktop release builds are not part of the local release flow.

## Seat Status Proxy

The app does not call BRACU Connect seat-status endpoints directly. It uses the hosted proxy API:

- `GET /seat-status`
- `GET /sections/:sectionId/details`
- `GET /staff/:initial`
- `GET /seat-status/stream` (real-time trigger)
- `GET /course-prerequisites`

Current client flow:

- Load full section data from `/sections/details`
- Cache locally on device
- Listen to `/seat-status/stream` and refresh details on updates

Why this reduces Connect API calls:

- Server-side cache for seat, details, and staff data
- Shared upstream fetches across all users
- CDN/cache-friendly response headers
- No repeated per-device direct Connect seat-status polling

## Documentation & Policies

- Code of Conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security: [SECURITY.md](SECURITY.md)
- Environment Example: [.env.example](.env.example)
- Workflows: [.github/workflows/release.yml](.github/workflows/release.yml)

## Developer Credit
- NaiveInvestigator — GitHub: [@NaiveInvestigator](https://github.com/NaiveInvestigator)
- Sabbir Bin Abbas — GitHub: [@sabbirba](https://github.com/sabbirba)

## Licenses
This project is licensed under GPL-3.0 (see [LICENSE](LICENSE)).

Third-party packages follow their own license (see package pages on [pub.dev](https://pub.dev)).
