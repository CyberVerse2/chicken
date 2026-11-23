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
        let size = fontSize
        let serif = typeface.cssFamily
        let display = "ui-serif, 'New York', Georgia, serif"

        let layout: String
        switch mode {
        case .scroll:
            layout = """
            html { --chicken-page-width: \(Int(columnWidth))px; --chicken-column-gap: 0px; }
            body {
              max-width: \(Int(columnWidth))px;
              padding: calc(44px + env(safe-area-inset-top)) clamp(20px, 6vw, 56px) calc(124px + env(safe-area-inset-bottom)) !important;
              overflow-x: hidden !important;
            }
            """
        case .paged:
            layout = columnsCSS(count: 1, inset: "max(24px, calc((100vw - \(Int(columnWidth))px) / 2))")
        case .spread:
            layout = columnsCSS(count: 2, inset: "clamp(32px, 4vw, 80px)") + """
            .chicken-spine-section h1, .chicken-spine-section h2, .chicken-spine-section h3,
            .chicken-spine-section h4, .chicken-spine-section h5, .chicken-spine-section h6,
            .chicken-spine-section header, .chicken-spine-section figure, .chicken-spine-section table {
              break-inside: avoid-column;
            }
            """
        }

        return """
        :root {
          --ch-bg: \(background);
          --ch-text: \(text);
          --ch-muted: \(muted);
        }
        html { background: var(--ch-bg) !important; color: var(--ch-text) !important; -webkit-text-size-adjust: 100%; }
        body {
          box-sizing: border-box;
          margin: 0 auto !important;
          background: var(--ch-bg) !important;
          color: var(--ch-text) !important;
          font-family: \(serif) !important;
          font-size: \(size)px !important;
          line-height: \(lineHeight) !important;
          overflow-wrap: break-word;
        }
        body::-webkit-scrollbar { width: 0 !important; height: 0 !important; display: \(horizontal ? "none" : "initial"); }
        \(layout)
        .chicken-spine-section { box-sizing: border-box; \(horizontal ? "" : "contain: layout style;") }
        .chicken-spine-section p, .chicken-spine-section li, .chicken-spine-section blockquote,
        .chicken-spine-section dd, .chicken-spine-section dt, .chicken-spine-section figcaption {
          color: var(--ch-text) !important;
          font-size: \(size)px !important;
          line-height: \(lineHeight) !important;
        }
        .chicken-spine-section p, .chicken-spine-section li, .chicken-spine-section blockquote {
          text-align: \(horizontal ? "justify" : "start");
          hyphens: \(horizontal ? "auto" : "manual");
          -webkit-hyphens: \(horizontal ? "auto" : "manual");
          widows: 2;
          orphans: 2;
        }
        .chicken-spine-section h1, .chicken-spine-section h2, .chicken-spine-section h3,
        .chicken-spine-section h4, .chicken-spine-section h5, .chicken-spine-section h6 {
          color: var(--ch-text) !important;
          font-family: \(display) !important;
          font-weight: 600 !important;
          letter-spacing: -0.02em;
          line-height: 1.18 !important;
        }
        .chicken-spine-section hr {
          border: 0 !important; height: auto !important; margin: 1.8em auto !important;
          text-align: center !important; color: var(--ch-muted) !important; background: transparent !important;
          font-family: \(serif) !important; font-size: 0.9em !important; letter-spacing: 0.6em !important; line-height: 1 !important;
        }
        .chicken-spine-section hr::before { content: "* * *"; }
        .chicken-spine-section table {
          display: table !important; width: auto !important; max-width: 100% !important;
          border-collapse: collapse; font-size: max(13px, \(size - 2)px) !important; line-height: 1.45 !important;
        }
        .chicken-spine-section th, .chicken-spine-section td {
          color: var(--ch-text) !important; padding: 0.28em 0.7em 0.28em 0 !important; vertical-align: top !important;
        }
        .chicken-spine-section a { color: var(--ch-muted) !important; }
        .chicken-spine-section img, .chicken-spine-section svg, .chicken-spine-section video {
          max-width: 100% !important; height: auto !important; \(horizontal ? "max-height: calc(100dvh - 180px) !important; object-fit: contain;" : "")
        }
        mark.chicken-hl { border-radius: 2px; padding: 0 1px; }
        ::selection { background: rgba(196, 123, 43, 0.30); }
        .chicken-speaking {
          background: rgba(196, 123, 43, 0.14) !important; border-radius: 4px;
          box-shadow: 0 0 0 0.3em rgba(196, 123, 43, 0.14); -webkit-box-decoration-break: clone;
          scroll-margin-top: 18vh;
        }
        """
    }

    func hasSameLayout(as other: EPUBStyle) -> Bool {
        fontSize == other.fontSize
            && lineHeight == other.lineHeight
            && columnWidth == other.columnWidth
            && mode == other.mode
            && typeface == other.typeface
    }

    private static var pagedBottomPadding: Int {
        #if os(macOS)
        124
        #else
        96
        #endif
    }

    private static var columnOverflow: String {
        #if os(iOS)
        "overflow-x: auto !important; overflow-y: hidden !important;"
        #else
        "overflow: hidden !important;"
        #endif
    }

    private func columnsCSS(count: Int, inset: String) -> String {
        """
        html, body { width: 100vw !important; max-width: none !important; }
        body {
          height: 100dvh !important;
          margin: 0 !important;
          padding: calc(32px + env(safe-area-inset-top)) 0 calc(\(Self.pagedBottomPadding)px + env(safe-area-inset-bottom)) !important;
          \(count == 1 ? "column-width: 100vw !important; column-count: auto !important;" : "column-count: \(count) !important;")
          column-gap: 0 !important;
          column-fill: auto !important;
          \(Self.columnOverflow)
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
