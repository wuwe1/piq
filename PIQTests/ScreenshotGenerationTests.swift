#if DEBUG

import Foundation
import Testing
@testable import PIQ

@Suite("Screenshot Generation")
struct ScreenshotGenerationTests {

    private var outputDirectory: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "piq-screenshots/output")
    }

    @Test("Generate all product page screenshots")
    @MainActor
    func generateAll() throws {
        // Clean previous output
        try? FileManager.default.removeItem(at: outputDirectory)

        let urls = ScreenshotGenerator.generateAll(to: outputDirectory, scale: 2.0)

        #expect(urls.count == 3, "Expected 3 screenshots, got \(urls.count)")

        for url in urls {
            #expect(
                FileManager.default.fileExists(
                    atPath: url.path(percentEncoded: false)
                ),
                "Screenshot should exist: \(url.lastPathComponent)"
            )
            let data = try Data(contentsOf: url)
            #expect(
                data.count > 1000,
                "\(url.lastPathComponent) should have meaningful image data"
            )
        }

        print("Screenshots saved to: \(outputDirectory.path(percentEncoded: false))")
    }

    @Test("Render menu bar screenshot at 1x")
    @MainActor
    func renderMenuBarAt1x() throws {
        try? FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true
        )

        let appState = ScreenshotMockData.createAppState()
        let url = outputDirectory.appending(path: "test-menubar-1x.png")

        let success = ScreenshotGenerator.render(
            MenuBarShowcase(appState: appState),
            size: CGSize(width: 440, height: 580),
            scale: 1.0,
            to: url
        )

        #expect(success, "1x render should succeed")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test("Render expanded detail screenshot")
    @MainActor
    func renderExpandedDetail() throws {
        try? FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true
        )

        let appState = ScreenshotMockData.createExpandedAppState()
        let url = outputDirectory.appending(path: "test-detail.png")

        let success = ScreenshotGenerator.render(
            MenuBarShowcase(appState: appState),
            size: CGSize(width: 440, height: 700),
            to: url
        )

        #expect(success, "Detail render should succeed")
    }

    @Test("Mock data produces expected project count")
    @MainActor
    func mockDataProjectCount() {
        let state = ScreenshotMockData.createAppState()
        #expect(state.projects.count == 3)
        #expect(state.projects[0].name == "piq")
        #expect(state.projects[0].epics.count == 3)
    }

    @Test("Mock data activity store has events")
    @MainActor
    func mockDataHasActivity() {
        let state = ScreenshotMockData.createAppState()
        #expect(state.activityStore != nil)
        let events = state.activityStore?.recentEvents(limit: 50) ?? []
        #expect(events.count > 0, "Should have mock activity events")
    }
}

#endif
