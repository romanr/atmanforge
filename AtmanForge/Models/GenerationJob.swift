import SwiftUI

@Observable
class GenerationJob: Identifiable {
    let id: UUID
    let model: AIModel
    let prompt: String
    let projectID: String
    let createdAt: Date

    // All generation settings
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let gptQuality: GPTQuality?
    let gptBackground: GPTBackground?
    let gptInputFidelity: GPTInputFidelity?

    var status: Status = .pending
    var resultImageData: [Data] = []
    var savedImagePaths: [String] = []
    var thumbnailPaths: [String] = []
    var errorMessage: String?

    enum Status: String, Codable {
        case pending
        case running
        case completed
        case failed
    }

    init(model: AIModel, prompt: String, projectID: String,
         aspectRatio: AspectRatio, resolution: ImageResolution?,
         imageCount: Int, gptQuality: GPTQuality?,
         gptBackground: GPTBackground?, gptInputFidelity: GPTInputFidelity?) {
        self.id = UUID()
        self.model = model
        self.prompt = prompt
        self.projectID = projectID
        self.createdAt = Date()
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.imageCount = imageCount
        self.gptQuality = gptQuality
        self.gptBackground = gptBackground
        self.gptInputFidelity = gptInputFidelity
    }

    init(from record: ActivityRecord) {
        self.id = record.id
        self.model = record.model
        self.prompt = record.prompt
        self.projectID = record.projectID
        self.createdAt = record.createdAt
        self.aspectRatio = record.aspectRatio
        self.resolution = record.resolution
        self.imageCount = record.imageCount
        self.gptQuality = record.gptQuality
        self.gptBackground = record.gptBackground
        self.gptInputFidelity = record.gptInputFidelity
        self.status = record.status
        self.savedImagePaths = record.savedImagePaths
        self.thumbnailPaths = record.thumbnailPaths
        self.errorMessage = record.errorMessage
    }

    func toRecord() -> ActivityRecord {
        ActivityRecord(
            id: id, model: model, prompt: prompt, projectID: projectID,
            createdAt: createdAt, aspectRatio: aspectRatio, resolution: resolution,
            imageCount: imageCount, gptQuality: gptQuality,
            gptBackground: gptBackground, gptInputFidelity: gptInputFidelity,
            status: status, savedImagePaths: savedImagePaths,
            thumbnailPaths: thumbnailPaths, errorMessage: errorMessage
        )
    }

    var settingsSummary: String {
        var parts: [String] = [aspectRatio.displayName]
        if let res = resolution { parts.append(res.displayName) }
        if imageCount > 1 { parts.append("\(imageCount) images") }
        if let q = gptQuality { parts.append("Q:\(q.displayName)") }
        if let bg = gptBackground, bg != .auto { parts.append("BG:\(bg.displayName)") }
        if let f = gptInputFidelity { parts.append("Fidelity:\(f.displayName)") }
        return parts.joined(separator: " · ")
    }

    var progressText: String {
        switch status {
        case .pending: return "Queued"
        case .running: return "Generating..."
        case .completed: return "Completed"
        case .failed: return errorMessage ?? "Failed"
        }
    }

    var statusIcon: String {
        switch status {
        case .pending: return "clock"
        case .running: return "arrow.trianglehead.2.counterclockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var statusColor: Color {
        switch status {
        case .pending: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

struct ActivityRecord: Codable {
    let id: UUID
    let model: AIModel
    let prompt: String
    let projectID: String
    let createdAt: Date
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let gptQuality: GPTQuality?
    let gptBackground: GPTBackground?
    let gptInputFidelity: GPTInputFidelity?
    let status: GenerationJob.Status
    let savedImagePaths: [String]
    let thumbnailPaths: [String]
    let errorMessage: String?
}
