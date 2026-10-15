import Foundation

/// Stylesheet applied on top of the publisher's CSS. Typography, theme colors
/// and column layout come from Chicken; images and tables stay contained.
struct EPUBStyle: Equatable {
    var palette: ReaderPalette
    var fontSize: Double
    var lineHeight: Double
    var columnWidth: Double
    var mode: ReadingMode

    var css: String {
        let background = ReaderPalette.css(palette.backgroundHex)
        let text = ReaderPalette.css(palette.textHex)
        let muted = ReaderPalette.css(palette.mutedHex)
        let horizontal = mode.isHorizontal
        let size = mode == .spread ? max(fontSize + 2, fontSize * 1.12) : fontSize
        let serif = "ui-serif, 'New York', Georgia, 'Times New Roman', serif"

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
            layout = """
            html {
              --chicken-page-width: min(\(Int(columnWidth))px, calc(100vw - 48px));
              --chicken-column-gap: 48px;
              --chicken-page-inset: clamp(16px, 5vw, 84px);
            }
            """ + columnsCSS
        case .spread:
            layout = """
            html {
              --chicken-column-gap: clamp(72px, 7vw, 160px);
              --chicken-page-width: calc((100vw - var(--chicken-column-gap)) / 2);
              --chicken-page-inset: clamp(40px, 4.6vw, 104px);
            }
            .chicken-spine-section h1, .chicken-spine-section h2, .chicken-spine-section h3,
            .chicken-spine-section h4, .chicken-spine-section h5, .chicken-spine-section h6,
            .chicken-spine-section header, .chicken-spine-section figure, .chicken-spine-section table {
              break-inside: avoid-column;
            }
            """ + columnsCSS
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
          font-family: \(serif) !important;
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

    private var columnsCSS: String {
        """
        body {
          max-width: none !important;
          height: 100vh !important;
          padding: calc(28px + env(safe-area-inset-top)) 0 calc(72px + env(safe-area-inset-bottom)) !important;
          column-width: var(--chicken-page-width) !important;
          column-gap: var(--chicken-column-gap) !important;
          column-fill: auto !important;
          overflow: hidden !important;
          overscroll-behavior: none !important;
        }
        .chicken-spine-section {
          padding-left: var(--chicken-page-inset) !important;
          padding-right: var(--chicken-page-inset) !important;
          -webkit-box-decoration-break: clone;
          box-decoration-break: clone;
          break-before: column;
        }
        """
    }
}
