# Chicken

Chicken is a private, local-first reading app for PDFs and EPUBs on Mac, iPad, and iPhone. It finds the books you already have in folders you choose, keeps its own copy, and gives you a calm reader with highlights, bookmarks, themes, and reading goals. No account, no backend.

## Platforms

One SwiftUI app target builds natively for **macOS 26, iPadOS 26, and iOS 26** (not Mac Catalyst). Liquid Glass is used for controls that float over content — toolbars, the reader's progress bar, the highlight picker, popovers — while the reading surface itself stays paper, sepia, or ink.

| | Mac | iPad | iPhone |
|---|---|---|---|
| Opening a book | New window per book | Full-screen reader | Full-screen reader |
| Contents | Sidebar | Sidebar | Sheet |
| Highlights & bookmarks | Inspector | Inspector | Sheet |
| Default flow | Scroll | Scroll | Pages |
| Page turns | Arrow keys, space, trackpad swipe, edge click | Swipe, edge tap | Swipe, edge tap |

## Features

- **Formats:** PDF (PDFKit), EPUB (WebKit, via a pure-Swift ZIP/OPF parser), plain text, Markdown, and RTF.
- **Reading:** scroll, paged, and two-page spread layouts; adjustable size, spacing, and width; search; zen mode; position saved per book and restored exactly.
- **Highlights** in every format, with notes, plus bookmarks.
- **Discovery:** share folders once (security-scoped bookmarks); Chicken scores what it finds ("is this a book?") and imports only what you pick.
- **Goals:** daily reading time and books-per-year, counted only while a book is open in front of you.
- **Widget** and **Shortcuts** action for continuing the current book.

## Project layout

```
App/                  App target (folder-synced): SwiftUI views, SwiftData models, services
  Resources/          Assets, ChickenReader.js (EPUB runtime), container-migration.plist
  Sources/
    App/              Entry point, scenes, routing, menu commands
    Design/           Themes, type, glass components
    Library/          Library, covers, discovery
    Reader/           Reader shell, PDF / EPUB / text engines
    Models/           SwiftData models (CloudKit-compatible shape)
    Services/         LibraryStore: importing, discovery, reading time, migration, widget
Widget/               Widget extension
Packages/ChickenKit/  Platform-neutral core: ZIP, EPUB, PDF metadata, covers, discovery, legacy import
Config/               Info.plists and entitlements per platform
```

`LibraryStore` owns the database and files; views read with `@Query` and call the store to change anything. Readers implement a small `ReaderEngine` protocol driven by an observable `ReaderModel`, so the toolbar, progress bar, and panels work the same for every format.

## Building

Requires Xcode 26 or later.

```sh
open Chicken.xcodeproj            # run the "Chicken" scheme on My Mac, an iPad, or an iPhone
swift test --package-path Packages/ChickenKit
```

Debug builds use their own library folder (`Application Support/Chicken Development`), so running from Xcode never touches your real library. To develop against real data, point a debug build at an APFS clone instead:

```sh
cp -cR ~/Library/Application\ Support/Chicken /tmp/chicken-dev-library
# Xcode › Scheme › Run › Environment: CHICKEN_LIBRARY_ROOT=/tmp/chicken-dev-library
# Optional: CHICKEN_DEBUG_OPEN=continue (or a book UUID) opens a reader at launch.
```

`CHICKEN_REAL_LIBRARY=<folder> swift test --package-path Packages/ChickenKit` also runs a read-only check that every EPUB in a library parses and every saved position still resolves.

## Data and privacy

The SwiftData store `Library.store` lives in `Application Support/Chicken` and syncs through the user's private CloudKit database, so progress, highlights, bookmarks, and reading time follow them across Mac, iPad, and iPhone. The models avoid unique constraints and non-optional relationships, as CloudKit requires. Book copies and covers live in Chicken's iCloud container (`iCloud.cyberverse.Chicken`, outside its Documents folder so iCloud Drive doesn't list them); other devices download a book when it's opened (`LibraryStore+ICloud.swift`). The same file added on two devices is merged into one book.

Without iCloud (signed out, turned off for Chicken, or an unsigned build) nothing syncs: files stay in the local `Books` and `Covers` folders and everything else works the same. Debug builds sync with CloudKit's development environment and keep their files in a separate `Development` folder in the container; `CHICKEN_LIBRARY_ROOT` clones never sync.

### Upgrading from Chicken 1.x (Mac)

Chicken 1.x kept a JSON catalog outside the sandbox. On the first sandboxed launch, macOS moves that folder into the app container (`container-migration.plist`), then `LegacyMigrator` converts `library.json`, highlights, bookmarks, per-book settings, and the reading log into the new store. Books keep their IDs and saved positions; the JSON files are left untouched.

## Releases

See [RELEASE.md](RELEASE.md).
