<div align="center">

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
scripts/             Build & CI helpers
```

## Seat Status Proxy (Dev)

Seat Status doesn't calls Connect API directly. It goes through the hosted proxy API:

- `GET /api/v1/seat-status`
- `GET /api/v1/sections/:sectionId/details`
- `GET /api/v1/staff/:initial`
- `GET /api/v1/seat-status/stream` (realtime)

Why this reduces Connect API calls:

- server-side cache (seat map, details, staff)
- one shared upstream fetch for all users
- edge/cache headers for Cloudflare/CDN
- App reads from proxy instead of repeated direct Connect calls per device

Seat-status base URL:

- `http://34.144.247.162`

## Documentation & Policies

- Code of Conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security: [SECURITY.md](SECURITY.md)
- Environment Example: [.env.example](.env.example)
- Android Signing Example: [android/key.properties.example](android/key.properties.example)
- Workflows: [.github/workflows/release.yml](.github/workflows/release.yml)

## Developer Credit
- NaiveInvestigator — GitHub: [@NaiveInvestigator](https://github.com/NaiveInvestigator)
- Sabbir Bin Abbas — GitHub: [@sabbirba](https://github.com/sabbirba)

## Licenses
This project is licensed under GPL-3.0 (see [LICENSE](LICENSE)).

Third-party packages follow their own license (see package pages on [pub.dev](https://pub.dev)).
