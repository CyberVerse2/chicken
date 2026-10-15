import Foundation

/// Builds small EPUB archives on disk with the system `zip` tool. Tests run
/// on the macOS host, so this is fine even though the app itself never
/// shells out.
enum Fixtures {
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChickenKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `files` (archive path → contents) into a zip. `mimetype` is
    /// stored uncompressed and first, as the EPUB spec requires.
    static func zip(_ files: [String: Data], named name: String = "book.epub", storedFirst: String? = "mimetype") throws -> URL {
        let staging = try temporaryDirectory()
        for (path, data) in files {
            let url = staging.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let output = try temporaryDirectory().appendingPathComponent(name)

        func run(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = staging
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        }

        if let storedFirst, files[storedFirst] != nil {
            try run(["-q", "-X", "-0", output.path, storedFirst])
        }
        let rest = files.keys.filter { $0 != storedFirst }.sorted()
        if !rest.isEmpty {
            try run(["-q", "-X", "-9", output.path] + rest)
        }
        return output
    }

    static func sampleEPUB(extraFiles: [String: Data] = [:]) throws -> URL {
        var files: [String: Data] = [
            "mimetype": Data("application/epub+zip".utf8),
            "META-INF/container.xml": Data("""
            <?xml version="1.0"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """.utf8),
            "OEBPS/content.opf": Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>The Quiet Room</dc:title>
                <dc:creator>Ada Writer</dc:creator>
                <dc:publisher>Small &amp; Good Press</dc:publisher>
                <dc:language>en</dc:language>
                <dc:description>&lt;p&gt;A book about &lt;b&gt;reading&lt;/b&gt;.&lt;/p&gt;</dc:description>
                <meta name="cover" content="cover-img"/>
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="c1" href="Text/chapter%201.xhtml" media-type="application/xhtml+xml"/>
                <item id="c2" href="Text/chapter2.xhtml" media-type="application/xhtml+xml"/>
                <item id="css" href="Styles/book.css" media-type="text/css"/>
                <item id="cover-img" href="Images/front.jpg" media-type="image/jpeg"/>
              </manifest>
              <spine>
                <itemref idref="c1"/>
                <itemref idref="css"/>
                <itemref idref="c2"/>
              </spine>
            </package>
            """.utf8),
            "OEBPS/nav.xhtml": Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
            <body>
              <nav epub:type="toc"><ol>
                <li><a href="Text/chapter%201.xhtml">One&nbsp;<span>Beginning</span></a>
                  <ol><li><a href="Text/chapter2.xhtml#part">Two</a></li></ol>
                </li>
              </ol></nav>
            </body></html>
            """.utf8),
            "OEBPS/Text/chapter 1.xhtml": Data("""
            <html><head><link rel="stylesheet" href="../Styles/book.css"/></head>
            <body><h1>Chapter One</h1><p>See <a href="chapter2.xhtml#part">part two</a>.</p>
            <img src="../Images/front.jpg"/></body></html>
            """.utf8),
            "OEBPS/Text/chapter2.xhtml": Data("""
            <html><body><h2 id="part">Chapter Two</h2><p>The end.</p></body></html>
            """.utf8),
            "OEBPS/Styles/book.css": Data("p { margin: 0; }".utf8),
            "OEBPS/Images/front.jpg": Data([0xFF, 0xD8, 0xFF, 0xD9]),
        ]
        files.merge(extraFiles) { _, new in new }
        return try zip(files)
    }
}
