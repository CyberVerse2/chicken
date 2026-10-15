# Design

## The idea

Chicken is where your books come home to roost: a private reading room on Mac, iPad, and iPhone. The brand starts from the app icon (a linen hen rising out of an open book on a soot ground, with an ochre ribbon bookmark) and takes three things from it:

1. **The palette**: soot, linen, cocoa, ochre.
2. **The voice of a farmhouse almanac**: sturdy Clarendon headlines, warm book-face text, plain words with a little wit.
3. **The ribbon**: the one accent. Ochre silk marks *your place*, and nothing else.

Reading stays the center. Chrome is quiet, and the brand shows up in a few deliberate places rather than everywhere.

## Signature: the ribbon

The ochre ribbon means "this is where you are". It is used only for that, so it keeps its meaning:

- A ribbon tail hangs out of the foot of every book cover you're partway through, on Home, in the Library grid, in book details, and in the widget. Finished and unread books have none.
- Progress meters and the reader's scrubber fill with ribbon ochre.
- A bookmarked page gets a ribbon draped over its top edge.
- The active chapter in Contents, the selected Library/Notebook filter, and the selected theme/typeface are marked with ribbon.

Don't use the ribbon for decoration, errors, or general emphasis.

`Ribbon`, `RibbonShape`, and `.coverRibbon(_:)` live in `Library/BookCover.swift`.

## Color

Three reading themes, applied to the whole app (`ReadingTheme.palette`, `Design/Theme.swift`). Ink is the icon's own colors.

| | Paper | Sepia | Ink |
|---|---|---|---|
| Background | `#F4EEE4` linen | `#EEDFC4` | `#171413` soot |
| Surface | `#FBF8F2` | `#F6EBD6` | `#211D1C` (icon ground) |
| Alt surface | `#EAE2D5` | `#E3D1B0` | `#2D2826` |
| Text | `#211D1C` soot | `#3B2A1A` | `#F2E6D6` linen (icon hen) |
| Muted | `#6E6259` | `#77593C` | `#A89B8C` |
| Faint | `#A89C90` | `#A68B6A` | `#6D6359` |
| Ribbon | `#B57631` | `#A9642A` | `#CB8D45` (icon ribbon) |

Borders and shadows are the text color at low opacity (black for Ink shadows). Primary buttons fill with the text color and use the background as their label color. Color is never the only signal of state: selected tabs are bold as well as underlined, and finished books say "Read".

Highlights keep four soft tints (amber, green, purple, coral). Wherever a highlight is shown outside the book (Notebook, Search, details, the reader's panel) it is drawn as highlighter across the words, the way it looks on the page, not as a colored bar.

## Typography

All three faces ship with both iOS and macOS, so nothing is bundled.

- **Display: Superclarendon** (`Font.chickenDisplay`). Greetings, page titles, the book you're in, shelf names, big figures, chapter headings inside EPUBs, the drop cap in text files, and titles on cloth covers. Use it with restraint, at most a few things per screen.
- **Book face: Iowan Old Style** (`Font.chickenSerif`). Book titles in lists (semibold), authors (italic), summaries, quotations, captions and footnotes (italic).
- **UI: SF Pro** (`Font.chickenUI`). Controls, labels, metadata. Eyebrows are 10.5pt semibold, tracked 1.6, uppercase. Figures use monospaced digits (`Font.chickenMono`), not a mono typeface.
- **Reading**: the reader chooses the body face: New York (default), Iowan, Charter, Athelas, or San Francisco (`ReaderTypeface`, saved per book). Body text defaults to 17pt at 1.78 line height in a 620pt column.

## Covers

Real cover art is shown as is. Books without one get a **cloth cover** (`ClothCover`): bookcloth in one of eight colors drawn from the palette (soot, cocoa, ochre, moss, oxblood, linen, slate, rust), a faint weave, and one of three bindings (framed, banded label, plain), with the title in Superclarendon and the author in Iowan italic. Subtitles after `:` or `;` are left off the cover. An egg outline at the foot is the house colophon.

Every cover, real or cloth, gets the same finish: a darker hinge at the spine edge, a soft fall of light, and a hairline edge, so it reads as a book rather than a picture.

## The egg

The egg is a secondary motif, used in three places:

- **The clutch**: the yearly books goal on Home is an egg carton, with one egg laid per finished book. Goals over 24 fall back to a meter.
- The colophon on cloth covers.
- The mark at the foot of Home.

## Layout

- **Home**: a Superclarendon greeting, then the book you're in, set out on the page rather than boxed in a card: a large cover with its ribbon, title, author, a progress line naming the current chapter, and one "Continue reading" button. After that come the goals row and the shelves (Also reading, Recently added, Waiting on the shelf). Copy is kept to what the screen doesn't already show.
- **Shelves and grid**: covers stand on a shelf ledge (a hairline over a soft shadow) that runs edge to edge. In the Library grid each tile's ledge reaches into the gutters, so every row reads as one shelf. On the Mac, shelves show no scrollbar: ‹ › page buttons appear at the ends on hover, and covers stop at the page edge.
- **Filters** (Library, Notebook) are quiet text tabs with a ribbon underline, not chips.
- **Pages** (Library, Notebook, Search) open with `PageHeader`, a display title alone. Secondary screens (Settings, Find Books) use `ChickenPage` and `ChickenSection`.
- **Sidebar**: on the Mac, `MacSidebar` holds the lockup, Home / Library / Notebook / Search, a Reading list (mini cover, title, ribbon meter), and today's reading at the foot, on the theme's own surface. On iPad the tab sidebar carries the same Reading list and meter. iPhone uses a tab bar and shows the lockup on Home.
- **Book details**: tapping or clicking a cover opens the book's card, never the book itself. Reading starts from the card (its cover or Continue reading).
  - *iPhone and iPad*: full-height cards over the dimmed library, each filled with its book's colour (`CoverTint`) and holding its own close button. The neighbouring books peek in at the edges, and tapping one brings it to the middle; the current card centres, the first and last sit against the edges, and a swipe moves one card. The card zooms out of the tapped cover, and the reader zooms out of the card's cover.
  - *Mac*: one large card (`MacBookCard`) over the blurred window, with the books before and after standing smaller at either side; clicking one slides it into the middle. Its header is a band of the cover's colour with the cover on the left, the title at its top, and an inset panel (format, progress, Continue reading, Mark as finished) at its foot; ••• sits top right. The rest of the details sit below on a plain surface. ← → step, Return reads, Escape closes.
- **Reader**: a Contents sidebar or sheet, a highlights inspector, and a floating glass progress capsule. Typography lives in a popover (a sheet on iPhone) with a live sample, the typeface picker, size and spacing steppers, layout, and theme. On iPhone and iPad, tapping the middle of the page shows or hides the controls (and leaves zen); the edges turn pages, and pages turn with a swipe in either direction.
- **Scrollbars** on the Mac are the thin overlay kind that show only while scrolling, whatever pointing device is attached.

## Liquid Glass

Glass is for controls that float above content: toolbars, the progress capsule, the highlight picker, steppers, and buttons. Pages, covers, cards, and panels stay solid theme surfaces.

## Motion

Subtle and state-driven. Covers lift a few points on hover. The hero cover turns slightly toward you. Filter underlines slide between tabs. A bookmark ribbon drops in with a short spring. Theme changes cross-fade over 0.4s. Reduce Motion is respected.

## Voice

Plain, warm, a little wry, and never cute at the expense of clarity. Name things by what people do: "Continue reading", "Find books", "Kept on this device". Brand words appear sparingly: "clutch" for the year's finished books, "roost" in the empty library, "on the go" for books in progress.

## Anti-references

Not a SaaS dashboard, a Kindle storefront, a loud AI reader, or a glassy toy demo. No gradients as decoration, no fake analytics, no merchandising, no gamified streaks or confetti. And no second accent color competing with the ribbon.
