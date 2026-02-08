import Foundation

struct ProjectEntry: Codable, Sendable, Equatable {
    let rootPath: URL
    var isManual: Bool
    var isHidden: Bool

    init(rootPath: URL, isManual: Bool = false, isHidden: Bool = false) {
        self.rootPath = rootPath
        self.isManual = isManual
        self.isHidden = isHidden
    }
}

struct ProjectConfig: Codable, Sendable {
    var scanRoots: [URL]
    var manualProjects: [ProjectEntry]
    var discoveredProjects: [ProjectEntry]

    init(
        scanRoots: [URL] = [],
        manualProjects: [ProjectEntry] = [],
        discoveredProjects: [ProjectEntry] = []
    ) {
        self.scanRoots = scanRoots
        self.manualProjects = manualProjects
        self.discoveredProjects = discoveredProjects
    }
}
