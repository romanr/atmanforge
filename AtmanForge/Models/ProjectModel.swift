import Foundation

struct ProjectManifest: Codable {
    var name: String
    var createdAt: Date
    var canvases: [String]

    init(name: String) {
        self.name = name
        self.createdAt = Date()
        self.canvases = []
    }
}

struct Project: Identifiable {
    let id: String
    var folderURL: URL
    var manifest: ProjectManifest
    var canvases: [Canvas]

    var name: String { manifest.name }
}
