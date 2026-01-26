import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class ProjectManager {
    static let shared = ProjectManager()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Root Folder

    var projectsRootURL: URL? {
        guard let data = UserDefaults.standard.data(forKey: "projectsRootBookmark") else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            saveRootBookmark(for: url)
        }
        return url
    }

    func setProjectsRoot(_ url: URL) {
        saveRootBookmark(for: url)
    }

    private func saveRootBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        UserDefaults.standard.set(data, forKey: "projectsRootBookmark")
    }

    // MARK: - Security-Scoped Access

    @discardableResult
    func startAccessing() -> Bool {
        projectsRootURL?.startAccessingSecurityScopedResource() ?? false
    }

    func stopAccessing() {
        projectsRootURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Load Projects

    func loadProjects() throws -> [Project] {
        guard let root = projectsRootURL else { return [] }

        let contents = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        var projects: [Project] = []
        for folderURL in contents {
            guard (try? folderURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            let manifestURL = folderURL.appendingPathComponent("project.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try decoder.decode(ProjectManifest.self, from: data)
                let canvases = loadCanvases(in: folderURL, canvasNames: manifest.canvases)
                let project = Project(
                    id: folderURL.lastPathComponent,
                    folderURL: folderURL,
                    manifest: manifest,
                    canvases: canvases
                )
                projects.append(project)
            } catch {
                continue
            }
        }

        return projects.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
    }

    private func loadCanvases(in projectURL: URL, canvasNames: [String]) -> [Canvas] {
        let canvasesDir = projectURL.appendingPathComponent("canvases")
        guard fileManager.fileExists(atPath: canvasesDir.path) else { return [] }

        var canvases: [Canvas] = []
        for name in canvasNames {
            let canvasDir = canvasesDir.appendingPathComponent(name)
            let manifestURL = canvasDir.appendingPathComponent("canvas.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try decoder.decode(CanvasManifest.self, from: data)
                canvases.append(Canvas(id: name, folderURL: canvasDir, manifest: manifest))
            } catch {
                continue
            }
        }
        return canvases
    }

    // MARK: - Create Project

    func createProject(name: String) throws -> Project {
        guard let root = projectsRootURL else {
            throw ProjectError.noRootFolder
        }

        let folderName = uniqueFolderName(for: name, in: root)
        let folderURL = root.appendingPathComponent(folderName)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: folderURL.appendingPathComponent("canvases"),
            withIntermediateDirectories: true
        )

        let manifest = ProjectManifest(name: name)
        let data = try encoder.encode(manifest)
        try data.write(to: folderURL.appendingPathComponent("project.json"))

        return Project(id: folderName, folderURL: folderURL, manifest: manifest, canvases: [])
    }

    // MARK: - Delete Project

    func deleteProject(_ project: Project) throws {
        try fileManager.removeItem(at: project.folderURL)
    }

    // MARK: - Rename Project

    func renameProject(_ project: inout Project, to newName: String) throws {
        project.manifest.name = newName
        try saveProjectManifest(project)
    }

    // MARK: - Create Canvas

    func createCanvas(inProject project: inout Project, name: String, width: Int = 1024, height: Int = 1024) throws -> Canvas {
        let canvasesDir = project.folderURL.appendingPathComponent("canvases")
        let folderName = uniqueFolderName(for: name, in: canvasesDir)
        let canvasDir = canvasesDir.appendingPathComponent(folderName)
        try fileManager.createDirectory(at: canvasDir, withIntermediateDirectories: true)

        let manifest = CanvasManifest(name: name, width: width, height: height)
        let data = try encoder.encode(manifest)
        try data.write(to: canvasDir.appendingPathComponent("canvas.json"))

        project.manifest.canvases.append(folderName)
        try saveProjectManifest(project)

        return Canvas(id: folderName, folderURL: canvasDir, manifest: manifest)
    }

    // MARK: - Delete Canvas

    func deleteCanvas(_ canvas: Canvas, fromProject project: inout Project) throws {
        try fileManager.removeItem(at: canvas.folderURL)
        project.manifest.canvases.removeAll { $0 == canvas.id }
        project.canvases.removeAll { $0.id == canvas.id }
        try saveProjectManifest(project)
    }

    // MARK: - Save

    func saveProjectManifest(_ project: Project) throws {
        let data = try encoder.encode(project.manifest)
        try data.write(to: project.folderURL.appendingPathComponent("project.json"))
    }

    func saveCanvasManifest(_ canvas: Canvas) throws {
        let data = try encoder.encode(canvas.manifest)
        try data.write(to: canvas.folderURL.appendingPathComponent("canvas.json"))
    }

    func saveCanvasImage(_ canvas: Canvas, imageData: Data) throws {
        try imageData.write(to: canvas.imageURL)
    }

    func saveGeneratedImages(_ imageDataArray: [Data], toFolder folder: URL) throws -> (imagePaths: [String], thumbnailPaths: [String]) {
        let generationsDir = folder.appendingPathComponent("generations")
        let thumbnailsDir = folder.appendingPathComponent(".thumbnails")
        try fileManager.createDirectory(at: generationsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())

        var imagePaths: [String] = []
        var thumbnailPaths: [String] = []

        for (index, data) in imageDataArray.enumerated() {
            let suffix = imageDataArray.count > 1 ? "-\(index + 1)" : ""
            let filename = "\(timestamp)\(suffix).png"

            // Save full image
            let imagePath = "generations/\(filename)"
            let imageURL = folder.appendingPathComponent(imagePath)
            try data.write(to: imageURL)
            imagePaths.append(imagePath)

            // Generate and save thumbnail
            let thumbPath = ".thumbnails/\(filename)"
            let thumbURL = folder.appendingPathComponent(thumbPath)
            if let thumbnailData = generateThumbnail(from: data, maxSize: 256) {
                try thumbnailData.write(to: thumbURL)
                thumbnailPaths.append(thumbPath)
            }
        }

        return (imagePaths, thumbnailPaths)
    }

    // MARK: - Thumbnails

    private func generateThumbnail(from imageData: Data, maxSize: CGFloat) -> Data? {
        #if os(macOS)
        guard let image = NSImage(data: imageData),
              let rep = image.representations.first else { return nil }

        let srcWidth = CGFloat(rep.pixelsWide)
        let srcHeight = CGFloat(rep.pixelsHigh)
        guard srcWidth > 0 && srcHeight > 0 else { return nil }

        let scale: CGFloat
        if srcWidth >= srcHeight {
            scale = min(maxSize / srcWidth, 1.0)
        } else {
            scale = min(maxSize / srcHeight, 1.0)
        }
        let thumbWidth = Int(srcWidth * scale)
        let thumbHeight = Int(srcHeight * scale)

        let thumbImage = NSImage(size: NSSize(width: thumbWidth, height: thumbHeight))
        thumbImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))
        thumbImage.unlockFocus()

        guard let tiffData = thumbImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return nil }
        return pngData
        #else
        guard let image = UIImage(data: imageData) else { return nil }

        let srcWidth = image.size.width
        let srcHeight = image.size.height
        guard srcWidth > 0 && srcHeight > 0 else { return nil }

        let scale: CGFloat
        if srcWidth >= srcHeight {
            scale = min(maxSize / srcWidth, 1.0)
        } else {
            scale = min(maxSize / srcHeight, 1.0)
        }
        let thumbSize = CGSize(width: srcWidth * scale, height: srcHeight * scale)

        UIGraphicsBeginImageContextWithOptions(thumbSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: thumbSize))
        let thumbImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return thumbImage?.pngData()
        #endif
    }

    // MARK: - Activity Persistence

    func loadActivity(from folder: URL) -> [GenerationJob] {
        let activityURL = folder.appendingPathComponent(".activity.json")
        guard fileManager.fileExists(atPath: activityURL.path),
              let data = try? Data(contentsOf: activityURL),
              let records = try? decoder.decode([ActivityRecord].self, from: data) else {
            return []
        }
        return records.map { GenerationJob(from: $0) }
    }

    func saveActivity(_ jobs: [GenerationJob], to folder: URL) {
        let activityURL = folder.appendingPathComponent(".activity.json")
        let records = jobs
            .filter { $0.status == .completed || $0.status == .failed }
            .map { $0.toRecord() }
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: activityURL)
    }

    // MARK: - Helpers

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_ "))
        let filtered = name.unicodeScalars.filter { allowed.contains($0) }.map { Character($0) }
        let result = String(filtered).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "untitled" : result.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private func uniqueFolderName(for name: String, in parent: URL) -> String {
        let base = sanitize(name)
        var candidate = base
        var counter = 1
        while fileManager.fileExists(atPath: parent.appendingPathComponent(candidate).path) {
            counter += 1
            candidate = "\(base)-\(counter)"
        }
        return candidate
    }
}

enum ProjectError: LocalizedError {
    case noRootFolder

    var errorDescription: String? {
        switch self {
        case .noRootFolder: return "No projects folder selected. Please choose a folder in Settings."
        }
    }
}
