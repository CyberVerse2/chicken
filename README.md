# Chicken

A reading app for the PDFs and EPUBs you already own, on Mac, iPad, and iPhone. Chicken finds books in folders you choose, keeps its own copy, and syncs your library, place, and highlights through your own iCloud account. No Chicken account, no tracking.

One SwiftUI app target builds natively for macOS 26, iPadOS 26, and iOS 26 (not Mac Catalyst).

## What it does

- **Reads** PDF (PDFKit), EPUB (WebKit, with a pure-Swift ZIP/OPF parser), plain text, Markdown, and RTF. Scroll, paged, and two-page spread layouts; on iPhone and iPad pages slide under your finger.
- **Remembers** your place to the exact page, plus highlights with notes, bookmarks, and per-book type settings.
- **Finds books** in folders you pick (security-scoped bookmarks), scores what it finds, and imports only what you choose.
- **Syncs** through iCloud: the library database via CloudKit, book files and covers via Chicken's iCloud container. Other devices download a book when it's opened, or ahead of time with Download / Keep on This Device.
- **Tracks goals:** daily reading minutes and books per year, counted only while a book is open in front of you, per device and summed. Your Reading shows the time read this week and year, the year's finished books, and the latest highlight.
- **Reaches beyond the app:** widgets (Continue Reading, Reading Goal), a Live Activity while reading, Siri and Shortcuts actions, a Control Center control, Spotlight for books and highlights, a Focus filter, read aloud with Now Playing, and a menu bar reading panel on the Mac.

## Project layout

```
App/                    App target (folder-synced)
  Resources/            Assets, ChickenReader.js (EPUB runtime), privacy manifest
  Sources/
    App/                Entry point, scenes, routing, menu commands
    Design/             Theme, type, shared components
    Intents/            App Intents, Focus filter, Spotlight entities
    Library/            Home, Library, Notebook, Search, covers, book details
    Models/             SwiftData models (CloudKit-compatible)
    Reader/             Reader shell; PDF, EPUB, and text engines; read aloud
    Services/           LibraryStore and its parts: import, iCloud, downloads,
                        reading time, widgets, Spotlight, Live Activity
    Settings/           Settings
Widget/                 Widgets, Live Activity, Control Center control
Packages/ChickenKit/    Platform-neutral core: ZIP, EPUB, PDF metadata, covers,
                        discovery, title casing, duplicate detection
Config/                 Info.plists and entitlements per platform
AppStore/               Store metadata and icon sources
```

`LibraryStore` owns the database and the files behind it. Views read with `@Query` and call the store to change anything. Readers implement a small `ReaderEngine` protocol driven by an observable `ReaderModel`, so the toolbar, progress bar, and panels work the same for every format.

## Building

Requires Xcode 26 or later. Open `Chicken.xcodeproj` and run the **Chicken** scheme on My Mac, an iPad, or an iPhone.

```sh
swift test --package-path Packages/ChickenKit
```

iCloud needs a signed build: the app and widget share the App Group `group.cyberverse.Chicken`, and the app uses the iCloud container `iCloud.cyberverse.Chicken`. An unsigned build runs without sync.

### Development builds

Debug builds keep a separate library (`Chicken Development`) and sync with CloudKit's development environment, keeping their files in a `Development` folder in the iCloud container. Running from Xcode never touches your real library.

| Environment variable | Effect (Debug builds) |
|---|---|
| `CHICKEN_LIBRARY_ROOT=<folder>` | Use this folder as the library. It never syncs. |
| `CHICKEN_DEBUG_SEED=<folder>` | Fill an empty library with the books in a folder, with sample progress and highlights. |
| `CHICKEN_DEBUG_OPEN=continue` or a book UUID | Open a reader at launch. |
| `CHICKEN_DEBUG_TAB=library\|notebook\|search\|reading` | Start on that tab (`reading` is Your Reading, in the sidebar on Mac and iPad). |
| `CHICKEN_DEBUG_PANEL=…` | Open a panel at launch: `discovery`, `settings`, `detail:<uuid>`, `contents`, `annotations`, `typography`, `search`, or `menubar` (Mac). |
| `CHICKEN_DEBUG_THEME=paper\|sepia\|ink` | Force a reading theme. |
| `CHICKEN_DEBUG_FURTHER=continue` | Pretend an iPad read the current book further, to see the reader's offer to jump there. |

`CHICKEN_REAL_LIBRARY=<library folder> swift test --package-path Packages/ChickenKit` also runs a read-only check that every EPUB in a library parses and every saved position still resolves.

## Data

- **Database:** SwiftData store `Library.store` in Application Support, mirrored to the user's private CloudKit database. Models avoid unique constraints and required relationships, as CloudKit requires; a model change needs the schema deployed to production (see [RELEASE.md](RELEASE.md)).
- **Book files and covers:** Chicken's iCloud container, outside Documents so iCloud Drive doesn't list them. Without iCloud they stay in local `Books` and `Covers` folders.
- **Per-device:** theme, goals, which books to keep downloaded, and "Download all books" (on by default on the Mac) live in UserDefaults.
- **Duplicates:** the same file added on two devices merges into one book, keeping the earlier import and the most recent reading position.
- **Chicken 1.x (Mac):** on first launch the old JSON catalog is converted into the new store; books keep their IDs and positions.

## More

- [RELEASE.md](RELEASE.md): versioning, App Store, and GitHub releases.
- [DESIGN.md](DESIGN.md): the visual system.
