# Libraries (SharedShelf) — Privacy Policy

Last updated: May 24, 2026

Libraries does not collect, store, or transmit any personal data to the developer or to any third-party server operated by the developer.

## What data the app handles

- **Your books, libraries, and borrow requests** are stored in your personal iCloud account using Apple's CloudKit framework. This data lives in your private iCloud database (and, if you share a library, in the shared database of the user you share with). It is not accessible to the developer.
- **iCloud user identifiers** are used by Apple's CloudKit service to authenticate you and to deliver share invitations. This is handled entirely by Apple.
- **ISBN lookups** are performed against the Open Library public API (https://openlibrary.org). When you scan or type an ISBN, the ISBN value is sent to Open Library to retrieve book metadata (title, author, cover image). Open Library's privacy practices are governed by their own privacy policy.
- **Camera** is used only to scan ISBN barcodes locally on your device. Camera images are not stored or transmitted.

## What the app does NOT do

- No analytics, telemetry, advertising identifiers, or tracking SDKs.
- No third-party SDKs of any kind.
- No data is sent to the developer.
- No account creation — your identity is your existing iCloud account.

## Sharing libraries

When you share a library with another user through Apple's standard sharing flow, that user receives read access to the library's contents (book titles, authors, notes, covers, requests). This data lives in CloudKit's shared database scope and is governed by Apple's iCloud privacy practices.

## Children

The app does not knowingly collect information from children. It does not require accounts, does not advertise, and stores all data in the user's own iCloud.

## Contact

For questions about this policy, please open an issue at https://github.com/ajsimon1/libraries-ios/issues.
