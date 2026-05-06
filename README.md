# Chicken

Chicken is a macOS desktop reading app for PDFs, EPUBs, and personal book/document libraries. This repo was forked from Asterion to preserve the visual direction while rebuilding the product around local-first reading instead of hosted web novels.

## Product Scope

Chicken launches as a no-account, local-first reader.

- Import and read PDF, EPUB, and common ebook/document formats.
- Manage a local library with title, author, format, progress, bookmarks, and reading state.
- Provide a reader view with page, section, and chapter navigation depending on source format.
- Search inside books when the imported format exposes searchable text.
- Support bookmarks, highlights, annotations, and reading progress.
- Offer light, dark, and warm reading themes.
- Store library metadata and user reading state locally at launch.
- Keep cloud sync and accounts out of the initial product surface.

## Format Strategy

EPUB should be treated as a first-class format, not a later add-on. The importer and reader architecture should model each book as a local document with format-specific capabilities:

- PDF: page-based rendering, page thumbnails, text search where extractable, highlight/bookmark anchors by page and text range.
- EPUB: spine/section navigation, reflowable text, table of contents, theme-aware typography, text search, highlight/bookmark anchors by EPUB location.
- Other documents: import where the OS or chosen parser can safely extract previewable text, with read-only fallback states when deep features are not available.

## App Architecture Direction

The inherited Asterion UI should remain the visual baseline, but Chicken should remove network-first assumptions.

- Replace remote novels/chapters with local `Book` and `LibraryItem` models.
- Replace `APIClient`, Clerk auth, rankings, hosted profiles, and backend sync with local storage services.
- Use SwiftData or a small SQLite layer for library metadata, reading progress, bookmarks, and highlights.
- Store imported source files in Application Support with security-scoped access when needed.
- Keep parsing/rendering capability isolated behind format adapters such as `PDFBookAdapter` and `EPUBBookAdapter`.

## Packaging

Initial packaging target: signed macOS desktop app build suitable for local distribution, then notarized DMG when the app is ready for broader testing.

- Primary platform: macOS.
- Distribution artifact: `.app` and `.dmg`.
- No account required.
- No backend required for the first launch.
- Bundle identifier: `cyberverse.Chicken`.

## Current Fork State

The project folder and Xcode identity have been renamed from Asterion to Chicken. The codebase still contains inherited Asterion product surfaces that need to be replaced during the rebuild.
