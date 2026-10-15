import Foundation

/// Stylesheet applied on top of the publisher's CSS. Typography, theme colors
/// and column layout come from Chicken; images and tables stay contained.
struct EPUBStyle: Equatable {
    var palette: ReaderPalette
    var fontSize: Double
    var lineHeight: Double
    var columnWidth: Double
    var mode: ReadingMode
    var typeface: ReaderTypeface = .default

    var css: String {
        let background = ReaderPalette.css(palette.backgroundHex)
        let text = ReaderPalette.css(palette.textHex)
        let muted = ReaderPalette.css(palette.mutedHex)
        let horizontal = mode.isHorizontal
        let size = mode == .spread ? max(fontSize + 2, fontSize * 1.12) : fontSize
        let serif = typeface.cssFamily
        // Chapter headings in the house display face.
        let display = "'Superclarendon', 'Superclarendon-Regular', \(serif)"

        let layout: String
        switch mode {
        case .scroll:
            layout = """
            html { --chicken-page-width: \(Int(columnWidth))px; --chicken-column-gap: 0px; }
            body {
              max-width: \(Int(columnWidth))px;
              padding: calc(40px + env(safe-area-inset-top)) clamp(20px, 6vw, 56px) calc(96px + env(safe-area-inset-bottom)) !important;
              overflow-x: hidden !important;
            }
            """
        case .paged:
            // One full-width column per screen; the reading measure comes
            // from per-page padding so page turns are exactly one viewport.
            // (Sized by width: WebKit ignores `column-count: 1` entirely.)
            layout = columnsCSS(count: 1, inset: "max(24px, calc((100vw - \(Int(columnWidth))px) / 2))")
        case .spread:
            layout = columnsCSS(count: 2, inset: "clamp(28px, 4vw, 80px)") + """
            .chicken-spine-section h1, .chicken-spine-section h2, .chicken-spine-section h3,
            .chicken-spine-section h4, .chicken-spine-section h5, .chicken-spine-section h6,
            .chicken-spine-section header, .chicken-spine-section figure, .chicken-spine-section table {
              break-inside: avoid-column;
            }
            """
        }

        return """
        html { background: \(background) !important; color: \(text) !important; -webkit-text-size-adjust: 100%; }
        body {
          box-sizing: border-box;
          margin: 0 auto !important;
          background: \(background) !important;
          color: \(text) !important;
          font-family: \(serif) !important;
          font-size: \(size)px !important;
          line-height: \(lineHeight) !important;
          overflow-wrap: break-word;
        }
        body::-webkit-scrollbar { width: 0 !important; height: 0 !important; display: \(horizontal ? "none" : "initial"); }
        \(layout)
        .chicken-spine-section { box-sizing: border-box; }
        .chicken-spine-section p, .chicken-spine-section li, .chicken-spine-section blockquote,
        .chicken-spine-section dd, .chicken-spine-section dt, .chicken-spine-section figcaption {
          color: \(text) !important;
          font-size: \(size)px !important;
          line-height: \(lineHeight) !important;
        }
        /* Justified, hyphenated text gives paged modes a printed rag; widows
           and orphans keep single lines from dangling at column breaks. */
        .chicken-spine-section p, .chicken-spine-section li, .chicken-spine-section blockquote {
          text-align: \(horizontal ? "justify" : "start");
          hyphens: \(horizontal ? "auto" : "manual");
          -webkit-hyphens: \(horizontal ? "auto" : "manual");
          widows: 2;
          orphans: 2;
        }
        .chicken-spine-section h1, .chicken-spine-section h2, .chicken-spine-section h3,
        .chicken-spine-section h4, .chicken-spine-section h5, .chicken-spine-section h6 {
          color: \(text) !important;
          font-family: \(display) !important;
          font-weight: normal !important;
          letter-spacing: -0.01em;
          line-height: 1.2 !important;
        }
        /* Scene breaks render as a quiet asterism. */
        .chicken-spine-section hr {
          border: 0 !important; height: auto !important; margin: 1.6em auto !important;
          text-align: center !important; color: \(muted) !important; background: transparent !important;
          font-family: \(serif) !important; font-size: 0.9em !important; letter-spacing: 0.6em !important; line-height: 1 !important;
        }
        .chicken-spine-section hr::before { content: "* * *"; }
        .chicken-spine-section table {
          display: table !important; width: auto !important; max-width: 100% !important;
          border-collapse: collapse; font-size: max(13px, \(size - 2)px) !important; line-height: 1.45 !important;
        }
        .chicken-spine-section th, .chicken-spine-section td {
          color: \(text) !important; padding: 0.28em 0.7em 0.28em 0 !important; vertical-align: top !important;
        }
        .chicken-spine-section a { color: \(muted) !important; }
        .chicken-spine-section img, .chicken-spine-section svg, .chicken-spine-section video {
          max-width: 100% !important; height: auto !important; \(horizontal ? "max-height: calc(100vh - 160px) !important; object-fit: contain;" : "")
        }
        mark.chicken-hl { border-radius: 2px; padding: 0 1px; }
        ::selection { background: rgba(189, 153, 87, 0.36); }
        """
    }

    /// Room under each page for the floating progress bar. On the Mac the
    /// bar and the soft edge beneath it sit higher than the page's own
    /// safe area reports, and a smaller margin cut the last line in half.
    private static var pagedBottomPadding: Int {
        #if os(macOS)
        return 116
        #else
        return 76
        #endif
    }

    private func columnsCSS(count: Int, inset: String) -> String {
        """
        html, body { width: 100vw !important; max-width: none !important; }
        body {
          height: 100vh !important;
          margin: 0 !important;
          padding: calc(28px + env(safe-area-inset-top)) 0 calc(\(Self.pagedBottomPadding)px + env(safe-area-inset-bottom)) !important;
          \(count == 1 ? "column-width: 100vw !important; column-count: auto !important;" : "column-count: \(count) !important;")
          column-gap: 0 !important;
          column-fill: auto !important;
          overflow: hidden !important;
          overscroll-behavior: none !important;
        }
        .chicken-spine-section {
          padding-left: \(inset) !important;
          padding-right: \(inset) !important;
          margin: 0 !important;
          min-height: 0 !important;
          -webkit-box-decoration-break: clone;
          box-decoration-break: clone;
          break-before: column;
        }
        """
    }
}
