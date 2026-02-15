import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var showStats = false
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var cardHeights: [UUID: CGFloat] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .overlay(alignment: .bottom) {
            if let message = appState.toastMessage {
                ToastView(message: message)
                    .padding(.bottom, 40)
                    .animation(.easeInOut(duration: 0.2), value: appState.toastMessage)
            }
        }
        .task {
            // Initial rescanAll is done in PIQApp.task to ensure
            // ActivityStore is set up before first scan.
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "eyes")
                .foregroundStyle(.secondary)
            Text("PIQ")
                .font(.headline)
            Spacer()
            Text("\(appState.projects.count) projects")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                showStats.toggle()
            } label: {
                Image(systemName: showStats ? "list.bullet" : "chart.bar")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(showStats ? "Show projects" : "Show stats")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if showStats {
            StatsView()
        } else if appState.projects.isEmpty {
            emptyState
        } else {
            projectList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No projects")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Add a scan root via config")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var projectList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Array(appState.projects.enumerated()), id: \.element.id) { index, project in
                    let isDragging = draggingID == project.id
                    ProjectCardView(project: project, index: index, total: appState.projects.count)
                        .background(GeometryReader { geo in
                            Color.clear.onAppear {
                                cardHeights[project.id] = geo.size.height + 8
                            }
                        })
                        .offset(y: isDragging ? dragOffset : shiftOffset(for: index))
                        .zIndex(isDragging ? 1 : 0)
                        .opacity(isDragging ? 0.85 : 1)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if draggingID == nil {
                                        draggingID = project.id
                                    }
                                    guard draggingID == project.id else { return }
                                    dragOffset = value.translation.height
                                }
                                .onEnded { _ in
                                    guard draggingID == project.id else { return }
                                    let newIndex = targetIndex(from: index)
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        draggingID = nil
                                        dragOffset = 0
                                    }
                                    if newIndex != index {
                                        appState.moveProjectByIndex(from: index, to: newIndex)
                                    }
                                }
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// Calculate how far to shift a non-dragged card to make room.
    private func shiftOffset(for index: Int) -> CGFloat {
        guard let dragID = draggingID,
              let dragIndex = appState.projects.firstIndex(where: { $0.id == dragID }),
              index != dragIndex else { return 0 }

        let h = cardHeights[dragID] ?? 70
        let steps = stepsFromDrag(dragIndex: dragIndex)

        if dragOffset > 0 {
            // Dragging down: shift items between dragIndex+1..dragIndex+steps up
            if index > dragIndex && index <= dragIndex + steps {
                return -h
            }
        } else {
            // Dragging up: shift items between dragIndex+steps..dragIndex-1 down
            if index < dragIndex && index >= dragIndex + steps {
                return h
            }
        }
        return 0
    }

    /// How many positions the dragged card has moved past.
    private func stepsFromDrag(dragIndex: Int) -> Int {
        let avgH = cardHeights.values.isEmpty ? 70.0 : cardHeights.values.reduce(0, +) / Double(cardHeights.values.count)
        let threshold = avgH * 0.5
        if dragOffset > threshold {
            return min(Int((dragOffset + threshold) / avgH), appState.projects.count - 1 - dragIndex)
        } else if dragOffset < -threshold {
            return max(Int((dragOffset - threshold) / avgH), -dragIndex)
        }
        return 0
    }

    /// Calculate the target index after drag ends.
    private func targetIndex(from currentIndex: Int) -> Int {
        let steps = stepsFromDrag(dragIndex: currentIndex)
        return currentIndex + steps
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                appState.rescanAll()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "sessions")
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Sessions")

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gear")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.footnote)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
