#if DEBUG
import AppKit
import Charts
import SwiftUI

// MARK: - Generator

@MainActor
enum ScreenshotGenerator {

    @discardableResult
    static func render<V: View>(
        _ view: V,
        size: CGSize,
        scale: CGFloat = 2.0,
        to fileURL: URL
    ) -> Bool {
        let hosted = view.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: hosted)
        renderer.scale = scale

        guard let nsImage = renderer.nsImage,
              let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:])
        else { return false }

        do {
            try pngData.write(to: fileURL, options: .atomic)
            return true
        } catch { return false }
    }

    static func generateAll(to directory: URL, scale: CGFloat = 2.0) -> [URL] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let scenes: [(view: AnyView, size: CGSize, name: String)] = [
            (
                AnyView(MenuBarShowcase()),
                CGSize(width: 440, height: 580),
                "screenshot-menubar.png"
            ),
            (
                AnyView(DetailShowcase()),
                CGSize(width: 780, height: 680),
                "screenshot-detail.png"
            ),
            (
                AnyView(StatsShowcase()),
                CGSize(width: 780, height: 840),
                "screenshot-stats.png"
            ),
        ]

        var results: [URL] = []
        for scene in scenes {
            let url = directory.appending(path: scene.name)
            if render(scene.view, size: scene.size, scale: scale, to: url) {
                results.append(url)
            }
        }
        return results
    }
}

// MARK: - Mock Data

@MainActor
enum ScreenshotMockData {

    static let now = Date()

    static func sessions() -> [SessionEntry] {
        [
            SessionEntry(
                id: "s1", sessionId: "s1",
                projectPath: "/Users/dev/claude-code",
                projectName: "claude-code",
                firstPrompt: "Add streaming support for tool call results in the CLI output",
                lastPrompt: "Also update the tests for the new streaming behavior",
                lastOutput: "Done. Updated `ToolCallRenderer.swift` with streaming support and added 12 test cases covering...",
                userTurnCount: 8, messageCount: 24,
                model: "claude-opus-4-6", gitBranch: "feat/streaming",
                slug: "add-streaming-support",
                createdAt: now.addingTimeInterval(-1800),
                lastActivityAt: now.addingTimeInterval(-120),
                jsonlURL: URL(filePath: "/tmp/s1.jsonl"),
                hasSubagents: true,
                inputTokens: 245_000, outputTokens: 89_000,
                cacheReadTokens: 180_000, cacheCreationTokens: 12_000,
                readableMessageCount: 42
            ),
            SessionEntry(
                id: "s2", sessionId: "s2",
                projectPath: "/Users/dev/piq",
                projectName: "piq",
                firstPrompt: "Fix the session detail view not updating when switching sessions",
                lastPrompt: "",
                lastOutput: "The issue was that `loadedSessionId` wasn't being cleared before loading...",
                userTurnCount: 3, messageCount: 10,
                model: "claude-sonnet-4-5-20250929", gitBranch: "bugfix/detail-reload",
                slug: "fix-session-detail",
                createdAt: now.addingTimeInterval(-7200),
                lastActivityAt: now.addingTimeInterval(-5400),
                jsonlURL: URL(filePath: "/tmp/s2.jsonl"),
                hasSubagents: false,
                inputTokens: 52_000, outputTokens: 18_000,
                cacheReadTokens: 38_000, cacheCreationTokens: 4_000,
                readableMessageCount: 15
            ),
            SessionEntry(
                id: "s3", sessionId: "s3",
                projectPath: "/Users/dev/web-app",
                projectName: "web-app",
                firstPrompt: "Refactor the authentication middleware to support OAuth2 PKCE flow",
                lastPrompt: "Run the integration tests",
                lastOutput: "All 47 tests passed. The OAuth2 PKCE flow is working correctly with...",
                userTurnCount: 12, messageCount: 38,
                model: "claude-opus-4-6", gitBranch: "feat/oauth-pkce",
                slug: "refactor-auth-middleware",
                createdAt: now.addingTimeInterval(-14400),
                lastActivityAt: now.addingTimeInterval(-10800),
                jsonlURL: URL(filePath: "/tmp/s3.jsonl"),
                hasSubagents: true,
                inputTokens: 420_000, outputTokens: 156_000,
                cacheReadTokens: 310_000, cacheCreationTokens: 22_000,
                readableMessageCount: 68
            ),
            SessionEntry(
                id: "s4", sessionId: "s4",
                projectPath: "/Users/dev/ios-app",
                projectName: "ios-app",
                firstPrompt: "Add dark mode support to the settings screen",
                lastPrompt: "",
                lastOutput: "Updated `SettingsView.swift` with dynamic color scheme support...",
                userTurnCount: 5, messageCount: 14,
                model: "claude-haiku-4-5-20251001", gitBranch: "main",
                slug: "dark-mode-settings",
                createdAt: now.addingTimeInterval(-86400),
                lastActivityAt: now.addingTimeInterval(-82800),
                jsonlURL: URL(filePath: "/tmp/s4.jsonl"),
                hasSubagents: false,
                inputTokens: 28_000, outputTokens: 12_000,
                cacheReadTokens: 20_000, cacheCreationTokens: 2_000,
                readableMessageCount: 22
            ),
            SessionEntry(
                id: "s5", sessionId: "s5",
                projectPath: "/Users/dev/claude-code",
                projectName: "claude-code",
                firstPrompt: "Optimize the JSONL parser for large session files (>50MB)",
                lastPrompt: "",
                lastOutput: "Replaced line-by-line parsing with memory-mapped I/O. Benchmark shows 3.2x...",
                userTurnCount: 6, messageCount: 18,
                model: "claude-opus-4-6", gitBranch: "perf/parser",
                slug: "optimize-jsonl-parser",
                createdAt: now.addingTimeInterval(-172800),
                lastActivityAt: now.addingTimeInterval(-169200),
                jsonlURL: URL(filePath: "/tmp/s5.jsonl"),
                hasSubagents: false,
                inputTokens: 185_000, outputTokens: 67_000,
                cacheReadTokens: 140_000, cacheCreationTokens: 9_000,
                readableMessageCount: 30
            ),
        ]
    }

    static func stats() -> ClaudeStats {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        let daily = (-30...0).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: now)!
            let count = [45, 82, 67, 120, 95, 110, 55, 30, 88, 145, 72, 60, 98, 130, 115,
                         42, 78, 105, 92, 68, 140, 85, 56, 125, 108, 75, 90, 63, 135, 100, 88]
            return DailyActivity(
                date: df.string(from: date),
                messageCount: count[offset + 30]
            )
        }

        var hourCounts: [Int: Int] = [:]
        for h in 0..<24 {
            hourCounts[h] = [5, 2, 1, 0, 0, 0, 3, 12, 25, 38, 45, 42,
                             35, 40, 48, 52, 45, 38, 30, 28, 22, 18, 15, 8][h]
        }

        return ClaudeStats(
            totalSessions: 847,
            totalMessages: 12_450,
            totalInputTokens: 45_200_000,
            totalOutputTokens: 18_600_000,
            totalCacheReadTokens: 32_100_000,
            totalCacheCreationTokens: 2_800_000,
            firstSessionDate: now.addingTimeInterval(-30 * 86400),
            longestSessionMessages: 156,
            longestSessionDuration: 7200,
            hourCounts: hourCounts,
            dailyActivity: daily,
            modelBreakdown: [
                ModelStats(model: "claude-opus-4-6", displayName: "Opus 4.6",
                           inputTokens: 28_500_000, outputTokens: 12_400_000,
                           cacheReadTokens: 22_000_000, cacheCreationTokens: 1_800_000),
                ModelStats(model: "claude-sonnet-4-5-20250929", displayName: "Sonnet 4.5",
                           inputTokens: 12_200_000, outputTokens: 4_800_000,
                           cacheReadTokens: 8_100_000, cacheCreationTokens: 720_000),
                ModelStats(model: "claude-haiku-4-5-20251001", displayName: "Haiku 4.5",
                           inputTokens: 4_500_000, outputTokens: 1_400_000,
                           cacheReadTokens: 2_000_000, cacheCreationTokens: 280_000),
            ],
            projectGroups: [
                ProjectGroup(name: "piq", path: "/Users/demo/Developer/piq", count: 120, tokens: 15_000_000),
                ProjectGroup(name: "website", path: "/Users/demo/Developer/website", count: 85, tokens: 8_500_000),
                ProjectGroup(name: "api-server", path: "/Users/demo/Developer/api-server", count: 60, tokens: 6_200_000),
            ],
            recentHourly: (0..<24).map { i in
                let hour = Calendar.current.dateInterval(of: .hour, for: now)!.start.addingTimeInterval(Double(i - 23) * 3600)
                return HourlyBucket(date: hour, count: hourCounts[Calendar.current.component(.hour, from: hour)] ?? 0)
            }
        )
    }

    static func statsCache() -> StatsCache {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        let daily = (-14...0).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: now)!
            let sc = [12, 8, 15, 10, 18, 14, 6, 11, 16, 9, 20, 13, 7, 17, 14]
            let tc = [245, 180, 312, 210, 380, 290, 120, 230, 340, 195, 420, 275, 150, 355, 290]
            return StatsCache.DailyActivityCached(
                date: df.string(from: date),
                sessionCount: sc[offset + 14],
                toolCallCount: tc[offset + 14]
            )
        }

        let modelTokens = (-14...0).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: now)!
            return StatsCache.DailyModelTokens(
                date: df.string(from: date),
                tokensByModel: [
                    "claude-opus-4-6": Int.random(in: 400_000...1_200_000),
                    "claude-sonnet-4-5-20250929": Int.random(in: 100_000...500_000),
                    "claude-haiku-4-5-20251001": Int.random(in: 30_000...150_000),
                ]
            )
        }

        return StatsCache(
            dailyActivity: daily,
            dailyModelTokens: modelTokens,
            totalToolCalls: daily.reduce(0) { $0 + $1.toolCallCount }
        )
    }
}

// MARK: - MenuBar Showcase

private struct MenuBarShowcase: View {
    var body: some View {
        VStack(spacing: 0) {
            menuBarContent
                .frame(width: 360, height: 500)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
        .padding(40)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var menuBarContent: some View {
        let sessions = ScreenshotMockData.sessions()
        return VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "eyes")
                    .foregroundStyle(.secondary)
                Text("PIQ")
                    .font(.headline)
                Spacer()
                Text("\(sessions.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Text("Search sessions...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            // Session list
            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    SessionRowView(entry: session)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    if session.id != sessions.last?.id {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }

            Spacer(minLength: 0)

            Divider()

            // Footer
            HStack(spacing: 8) {
                Text("12.4K msgs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("45.2M in")
                    .font(.caption2)
                    .foregroundStyle(.blue.opacity(0.8))
                Text("18.6M out")
                    .font(.caption2)
                    .foregroundStyle(.green.opacity(0.8))
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Quit")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Detail Showcase

private struct DetailShowcase: View {
    var body: some View {
        VStack(spacing: 0) {
            detailContent
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            conversationContent
        }
    }

    private var detailHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text("claude-code")
                    .font(.headline)
                Text("feat/streaming")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.1), in: Capsule())
                Text("Opus")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Spacer()
                Text("8 turns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("245K in")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                Text("89K out")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private var conversationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // User turn 1
            userBubble("Add streaming support for tool call results in the CLI output")

            // Assistant response with tool calls
            VStack(alignment: .leading, spacing: 8) {
                toolCallRow(
                    tool: "Read",
                    detail: "src/renderers/ToolCallRenderer.swift",
                    color: .blue,
                    icon: "doc.text"
                )

                toolCallRow(
                    tool: "Edit",
                    detail: "src/renderers/ToolCallRenderer.swift",
                    color: .orange,
                    icon: "pencil",
                    diff: true
                )

                toolCallRow(
                    tool: "Bash",
                    detail: "swift test --filter ToolCallRendererTests",
                    color: .green,
                    icon: "terminal"
                )

                assistantText("Updated `ToolCallRenderer.swift` with streaming support. The renderer now emits partial results as they arrive, with proper backpressure handling.")
            }

            // User turn 2
            userBubble("Also update the tests for the new streaming behavior")

            // Assistant response
            VStack(alignment: .leading, spacing: 8) {
                toolCallRow(
                    tool: "Write",
                    detail: "tests/ToolCallRendererTests.swift",
                    color: .orange,
                    icon: "doc.badge.plus"
                )

                toolCallRow(
                    tool: "Bash",
                    detail: "swift test --filter ToolCallRendererTests",
                    color: .green,
                    icon: "terminal",
                    output: "Test Suite 'ToolCallRendererTests' passed.\n  12 tests, 0 failures (0.847s)"
                )

                assistantText("Added 12 test cases covering streaming output, backpressure, error handling, and partial result assembly.")
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer()
            Text(text)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
    }

    private func assistantText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.primary)
            .padding(.leading, 4)
    }

    private func toolCallRow(
        tool: String,
        detail: String,
        color: Color,
        icon: String,
        diff: Bool = false,
        output: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(tool)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            if diff {
                VStack(alignment: .leading, spacing: 0) {
                    diffLine("−", "    func render(_ result: ToolResult) {", isRemoval: true)
                    diffLine("+", "    func render(_ result: ToolResult, streaming: Bool = false) {", isAddition: true)
                    diffLine(" ", "        let formatted = formatter.format(result)", isContext: true)
                    diffLine("−", "        output.write(formatted)", isRemoval: true)
                    diffLine("+", "        if streaming {", isAddition: true)
                    diffLine("+", "            output.stream(formatted, flush: true)", isAddition: true)
                    diffLine("+", "        } else {", isAddition: true)
                    diffLine("+", "            output.write(formatted)", isAddition: true)
                    diffLine("+", "        }", isAddition: true)
                }
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 10)
                .padding(.top, 2)
            }

            if let output {
                Text(output)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }
        }
    }

    private func diffLine(_ prefix: String, _ text: String, isRemoval: Bool = false, isAddition: Bool = false, isContext: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(prefix)
                .foregroundStyle(isRemoval ? .red : isAddition ? .green : .secondary)
                .frame(width: 14)
            Text(text)
                .foregroundStyle(isContext ? .secondary : .primary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isRemoval ? Color.red.opacity(0.1) :
            isAddition ? Color.green.opacity(0.1) :
            Color.clear
        )
    }
}

// MARK: - Stats Showcase (no ScrollView — ImageRenderer compatible)

private struct StatsShowcase: View {
    let stats = ScreenshotMockData.stats()
    let sessions = ScreenshotMockData.sessions()
    let cache = ScreenshotMockData.statsCache()

    private var projectGroups: [(name: String, count: Int, tokens: Int)] {
        var groups: [String: (name: String, count: Int, tokens: Int)] = [:]
        for s in sessions {
            let key = s.projectPath
            let existing = groups[key] ?? (name: s.projectName, count: 0, tokens: 0)
            groups[key] = (existing.name, existing.count + 1, existing.tokens + s.inputTokens + s.outputTokens)
        }
        return groups.values.sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            statsContent
                .frame(width: 732)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statsContent: some View {
        VStack(spacing: 20) {
            summaryCards
            dailyActivityChart
            modelUsageTable
            projectsList
        }
        .padding(24)
    }

    // MARK: Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            statCard(icon: "bubble.left.and.bubble.right", value: "\(stats.totalSessions)", label: "Sessions", color: .blue)
            statCard(icon: "folder", value: "\(projectGroups.count)", label: "Projects", color: .indigo)
            statCard(icon: "arrow.down.circle", value: stats.totalInputTokens.formattedCount, label: "Input Tokens", color: .cyan)
            statCard(icon: "arrow.up.circle", value: stats.totalOutputTokens.formattedCount, label: "Output Tokens", color: .green)
            statCard(icon: "book.pages", value: stats.totalCacheReadTokens.formattedCount, label: "Cache Read", color: .teal)
            statCard(icon: "wrench.and.screwdriver", value: cache.totalToolCalls.formattedCount, label: "Tool Calls", color: .purple)
            statCard(icon: "arrow.triangle.turn.up.right.diamond", value: "7.3", label: "Avg Turns", color: .pink)
            statCard(icon: "calendar", value: "30", label: "Days Active", color: .orange)
        }
    }

    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Daily Activity Chart

    private var dailyActivityChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Activity")
                .font(.headline)
                .foregroundStyle(.secondary)

            Chart(stats.dailyActivity) { day in
                BarMark(
                    x: .value("Date", parseDate(day.date) ?? Date()),
                    y: .value("Messages", day.messageCount)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXScale(range: .plotDimension(padding: 12))
            .frame(height: 160)
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Model Usage

    private var totalCost: Double {
        stats.modelBreakdown.reduce(0) { $0 + $1.estimatedCost }
    }

    private var modelUsageTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Model Usage")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Est. \(totalCost, format: .currency(code: "USD"))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 0) {
                Text("Model").frame(width: 80, alignment: .leading)
                Text("Input").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Output").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Cache Read").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Cache Write").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Cost").frame(width: 70, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            ForEach(stats.modelBreakdown) { model in
                HStack(spacing: 0) {
                    Text(model.displayName)
                        .fontWeight(.medium)
                        .foregroundStyle(colorForModel(model.displayName))
                        .frame(width: 80, alignment: .leading)
                    Text(model.inputTokens.formattedCount)
                        .foregroundStyle(.cyan)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(model.outputTokens.formattedCount)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(model.cacheReadTokens.formattedCount)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(model.cacheCreationTokens.formattedCount)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(model.estimatedCost, format: .currency(code: "USD"))
                        .foregroundStyle(.orange)
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.caption)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Projects

    private var projectsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(projectGroups.enumerated()), id: \.offset) { idx, project in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(project.name)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text("\(project.count) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(project.tokens.formattedCount + " tokens")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if idx < projectGroups.count - 1 {
                        Divider().padding(.leading, 32)
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Helpers

    private func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    private func colorForModel(_ name: String) -> Color {
        if name.contains("Opus") { return .blue }
        if name.contains("Sonnet") { return .green }
        if name.contains("Haiku") { return .orange }
        return .gray
    }
}
#endif
