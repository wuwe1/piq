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

    private enum CodingKeys: String, CodingKey {
        case scanRoots, manualProjects, discoveredProjects
    }

    init(
        scanRoots: [URL] = [],
        manualProjects: [ProjectEntry] = [],
        discoveredProjects: [ProjectEntry] = []
    ) {
        self.scanRoots = scanRoots
        self.manualProjects = manualProjects
        self.discoveredProjects = discoveredProjects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manualProjects = try container.decodeIfPresent([ProjectEntry].self, forKey: .manualProjects) ?? []
        discoveredProjects = try container.decodeIfPresent([ProjectEntry].self, forKey: .discoveredProjects) ?? []

        // Decode scanRoots as strings, converting plain paths to file URLs
        let rawRoots = try container.decodeIfPresent([String].self, forKey: .scanRoots) ?? []
        scanRoots = rawRoots.map { str in
            if str.hasPrefix("file://") {
                return URL(string: str) ?? URL(filePath: str)
            }
            return URL(filePath: str)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(manualProjects, forKey: .manualProjects)
        try container.encode(discoveredProjects, forKey: .discoveredProjects)

        // Encode scanRoots as plain path strings for human readability
        let pathStrings = scanRoots.map { $0.path(percentEncoded: false) }
        try container.encode(pathStrings, forKey: .scanRoots)
    }
}
