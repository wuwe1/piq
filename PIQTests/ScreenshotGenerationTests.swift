import XCTest
@testable import PIQ

final class ScreenshotGenerationTests: XCTestCase {

    @MainActor
    func testGenerateAll() throws {
        let projectRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()  // PIQTests/
            .deletingLastPathComponent()  // piq/
        let outputDir = projectRoot.appending(path: "assets")

        let urls = ScreenshotGenerator.generateAll(to: outputDir)

        XCTAssertEqual(urls.count, 3, "Should generate 3 screenshots")
        for url in urls {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path()),
                "Screenshot should exist: \(url.lastPathComponent)"
            )
            let data = try Data(contentsOf: url)
            XCTAssertGreaterThan(data.count, 1000, "Screenshot should not be empty: \(url.lastPathComponent)")
            print("Generated: \(url.lastPathComponent) (\(data.count / 1024) KB)")
        }
    }
}
