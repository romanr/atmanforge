import Foundation

struct GenerationRequest {
    let prompt: String
    let model: AIModel
    let aspectRatio: AspectRatio
    let resolution: ImageResolution?
    let imageCount: Int
    let gptQuality: GPTQuality?
    let gptBackground: GPTBackground?
    let gptInputFidelity: GPTInputFidelity?
}

struct GenerationResult {
    let imageDataArray: [Data]
}

protocol AIProvider {
    func generateImage(request: GenerationRequest) async throws -> GenerationResult
}
