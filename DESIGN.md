# Design

## Style

Chicken is a personal reading room rendered as a macOS app. The interface should feel composed and quiet — a literary surface, not a SaaS dashboard or a Kindle storefront. Typography carries the mood; chrome stays out of the way. Three reading themes — paper, sepia, ink — sit on equal footing and switch from inside the reader.

## Color

Color is restrained and neutral. There is no brand accent green; "accent" is just the highest-contrast text color of the active theme. Color must never be the only signal for state.

The three reading themes are first-class — they apply to the whole app, not only the reader.

### Paper (default)

- App background: `#F5F1E8` warm off-paper
- Surface (cards, hero): `#FFFFFF`
- Alt surface (panels, chips): `#EDE7D9`
- Text (primary, accent): `#1F1B16` deep ink
- Muted text: `#6B655B`
- Faint text / metadata: `#A8A095`
- Hairline border: `rgba(31, 27, 22, 0.10)`
- Strong border (active state): `rgba(31, 27, 22, 0.18)`
- Shadow: `rgba(31, 27, 22, 0.08)`

### Sepia

- Background: `#EFE3CC`
- Surface: `#F4EAD3`
- Alt surface: `#E5D6B8`
- Text: `#3A2A18`
- Muted: `#7A5A40`
- Faint: `#A89070`
- Hairline border: `rgba(58, 42, 24, 0.14)`
- Strong border: `rgba(58, 42, 24, 0.22)`
- Shadow: `rgba(58, 42, 24, 0.10)`

### Ink (dark)

- Background: `#0F0F10`
- Surface: `#1A1A1B`
- Alt surface: `#252527`
- Text: `#E8E6E1`
- Muted: `#9A968D`
- Faint: `#5A5851`
- Hairline border: `rgba(255, 255, 255, 0.08)`
- Strong border: `rgba(255, 255, 255, 0.14)`
- Shadow: `rgba(0, 0, 0, 0.40)`

### Highlight colors

Four soft tints for marginalia. Translucent fill on the running text, full-strength bar on highlight rails in the side panel.

- Amber — fill `rgba(239, 159, 39, 0.30)`, bar `#EF9F27`
- Green — fill `rgba(99, 153, 34, 0.28)`, bar `#97C459`
- Purple — fill `rgba(127, 119, 221, 0.28)`, bar `#AFA9EC`
- Coral — fill `rgba(216, 90, 48, 0.25)`, bar `#F0997B`

## Typography

A literary serif for reading and titles, a clean sans for chrome and metadata.

- Reading body, titles, drop caps: `New York` / system serif via `Font.serif`. Body sits at 17pt by default with a 1.78 line height; column width defaults to ~620pt and is user-adjustable (480–820).
- UI chrome (toolbars, buttons, side panel labels): system sans.
- Section labels and metadata accents: small caps style — sans, 11pt, weight 500, letter-spacing ~0.14em, uppercase, in muted color.
- Brand lockup: app icon mark plus serif "Chicken" title. Keep it compact and stable in the library header.
- Drop cap on the first paragraph of a chapter: serif, ~3.4× body size, sits flush left, paragraph wraps around it.

## Layout

The app is a single window with two surfaces:

1. **Library** — sticky header (wordmark, search, theme switch, settings), then a "Continue reading" hero card for the most recently opened book, then a grid of book covers in `auto-fill, minmax(180pt, 1fr)`. Footer carries quiet counts.
2. **Reader** — three columns: a chapter sidebar on the left (~220pt), a centered reading column with `maxWidth = columnWidth`, a highlights panel on the right (~280pt). A slim top bar carries the back button, book title, and tool toggles. A 2pt progress bar lives at the bottom.

Both side panels are toggleable from the top bar. The typography popover floats over the reader column and never pushes content. Reduce-motion is respected — transitions on theme, panel show/hide, and column width changes use short opacity/position fades only.

## Components

- **Book cover** — 2:3 ratio, solid background tint, accent ink, a thin rule above the title block, an optional motif in the background at low opacity (lines, frame, tree, flourish, crack, pattern). Title in serif 500, author in serif italic.
- **Library card (hero)** — rounded surface, cover on the left at 200pt, chapter eyebrow + serif title + italic author + slim progress bar + "Continue reading" primary button + meta line (time-left, highlights count).
- **Reading goal card** — sits between the Continue card and the grid. Small-caps eyebrow `Reading goal · YYYY` on the left, large serif `n` of `m` on the right (tabular numerals). Hairline meter underneath. Italic caption beneath the meter ("3 books to go", "Goal met. Read on for the joy of it."). Below, a horizontal row of finished-this-year books at 78pt cover width with a `MMM` month tag — quiet, scannable, never celebratory. Goal is set by a stepper in the Settings popover and persists in UserDefaults.
- **Library tile** — cover, title (serif 500, 15pt), author (serif italic 13pt), then a hairline progress meter or "Read"/"Unread" tag and a highlight count.
- **Reader top bar** — back button, centered book/chapter label, icon toggles for chapters / typography / theme / highlights, a time-left readout.
- **Chapter list item** — small caps "Chapter N" eyebrow, serif title, page range. Active item has a 2pt accent bar on the leading edge.
- **Highlight rail item** — left bar in the highlight color, the quoted text in serif at 13pt, optional italic note underneath, footer with "Ch. N · timestamp" and a remove icon.
- **Highlight selection popover** — small dark pill that floats above the selection with four 24×24pt color swatches.
- **Typography popover** — surface card with three steppers (size 13–24, line height 1.4–2.2, column width 480–820), a three-up theme picker, and a "Reset to defaults" tonal button.
- **Buttons** — primary uses the active theme's text color as fill with the background as label color. Secondary is a hairline border on a transparent surface. Both at 8pt radius.

## Motion

Motion is subtle and state-driven. Theme transitions: 0.4s ease on background and primary text. Side-panel show/hide and popovers: 0.15s ease. Continue-reading button hover: 0.2s opacity. No parallax, no decorative animation.

## Anti-references

Do not make Chicken feel like a SaaS dashboard, a Kindle storefront, a loud AI reader, or a glassy toy macOS demo. No green or saturated brand accent. No nested cards. No gradients, no fake analytics, no merchandising shelves, no decorative effects competing with text.
