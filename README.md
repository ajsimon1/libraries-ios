# Libraries

iOS app for cataloging your books and sharing your library with family.

Add books by scanning the ISBN barcode (or by manual entry). Browse your own library and any libraries shared to you over iCloud. Request to borrow a book from a shared library.

## Architecture

- **SwiftUI** UI, **Core Data** persistence, **CloudKit** sharing
- Two-store `NSPersistentCloudKitContainer` setup:
  - `private.sqlite` — your own libraries
  - `shared.sqlite` — libraries shared to you by other users
- ISBN lookup against the [Open Library API](https://openlibrary.org/developers/api)
- Barcode scanning via `AVFoundation`

## Project layout

```
SharedShelf/
├── SharedShelfApp.swift          # @main entry
├── AppDelegate.swift             # CloudKit share acceptance, lifecycle
├── SharedShelf.xcdatamodeld/     # Core Data model (Book, BookRequest)
├── SharedShelf.entitlements      # iCloud + push
├── Info.plist
├── Services/
│   ├── PersistenceController.swift  # Core Data + CloudKit container
│   └── ISBNLookupService.swift      # Open Library lookup
└── Views/
    ├── LibrariesListView.swift   # All libraries (yours + shared)
    ├── LibraryView.swift         # Single library
    ├── MyBooksView.swift         # Your books
    ├── AddBookView.swift         # Add a book (scan or manual)
    ├── BookDetailView.swift      # Book detail
    ├── BarcodeScannerView.swift  # ISBN scanner
    ├── RequestsView.swift        # Borrow requests
    └── CloudSharingView.swift    # Share a library
```

## Building

Requires Xcode 15+ and an Apple Developer account with iCloud + CloudKit configured for the bundle ID.

1. Open `SharedShelf.xcodeproj` in Xcode.
2. Sign with the Apple ID that owns the iCloud container `iCloud.com.ajsimon1.SharedShelf` (or change the container ID in `PersistenceController.swift` and the entitlements file to your own).
3. Build and run on a real device — CloudKit sharing does not work in the simulator.

## Bundle and team

- Bundle ID: `com.ajsimon1.SharedShelf`
- Display name: Libraries
- iCloud container: `iCloud.com.ajsimon1.SharedShelf`
