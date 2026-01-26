import Foundation

class ReplicateProvider: AIProvider {
    private let apiKey: String
    private let session = URLSession.shared
    private let baseURL = "https://api.replicate.com/v1"
    private let pollInterval: UInt64 = 1_500_000_000 // 1.5 seconds
    private let maxPollAttempts = 300

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func generateImage(request: GenerationRequest) async throws -> GenerationResult {
        let input = buildInput(for: request)

        // Gemini models produce 1 image per call; run multiple calls in parallel
        let callCount: Int
        switch request.model {
        case .gemini25, .gemini30:
            callCount = request.imageCount
        case .gptImage15:
            callCount = 1 // GPT handles multiple via number_of_images param
        }

        let allImageData: [Data]
        if callCount > 1 {
            allImageData = try await withThrowingTaskGroup(of: [Data].self) { group in
                for _ in 0..<callCount {
                    group.addTask {
                        let prediction = try await self.createPrediction(
                            model: request.model.replicateModelID,
                            input: input
                        )
                        let final = try await self.pollPrediction(prediction)
                        return try await self.downloadImages(from: final)
                    }
                }
                var results: [Data] = []
                for try await batch in group {
                    results.append(contentsOf: batch)
                }
                return results
            }
        } else {
            let prediction = try await createPrediction(
                model: request.model.replicateModelID,
                input: input
            )
            let finalPrediction = try await pollPrediction(prediction)
            allImageData = try await downloadImages(from: finalPrediction)
        }

        return GenerationResult(imageDataArray: allImageData)
    }

    // MARK: - Input Building

    private func buildInput(for request: GenerationRequest) -> [String: Any] {
        var input: [String: Any] = [
            "prompt": request.prompt,
            "aspect_ratio": request.aspectRatio.rawValue,
        ]

        // Add reference images as base64 data URIs
        if !request.referenceImages.isEmpty {
            let dataURIs = request.referenceImages.map { data in
                "data:image/png;base64,\(data.base64EncodedString())"
            }
            input["image_input"] = dataURIs
        }

        switch request.model {
        case .gemini25:
            break

        case .gemini30:
            if let resolution = request.resolution {
                input["resolution"] = resolution.rawValue
            }

        case .gptImage15:
            input["number_of_images"] = request.imageCount
            if let quality = request.gptQuality {
                input["quality"] = quality.rawValue
            }
            if let background = request.gptBackground {
                input["background"] = background.rawValue
            }
            if let fidelity = request.gptInputFidelity {
                input["input_fidelity"] = fidelity.rawValue
            }
        }

        return input
    }

    // MARK: - API Calls

    private func createPrediction(model: String, input: [String: Any]) async throws -> PredictionResponse {
        let url = URL(string: "\(baseURL)/models/\(model)/predictions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["input": input]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: data)

        return try JSONDecoder().decode(PredictionResponse.self, from: data)
    }

    private func pollPrediction(_ prediction: PredictionResponse) async throws -> PredictionResponse {
        guard let getURL = URL(string: prediction.urls.get) else {
            throw ReplicateError.invalidURL
        }

        var urlRequest = URLRequest(url: getURL)
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        for _ in 0..<maxPollAttempts {
            try await Task.sleep(nanoseconds: pollInterval)

            let (data, response) = try await session.data(for: urlRequest)
            try validateResponse(response, data: data)

            let current = try JSONDecoder().decode(PredictionResponse.self, from: data)

            switch current.status {
            case "succeeded":
                return current
            case "failed", "canceled":
                let errorMsg = current.error ?? "Prediction failed with status: \(current.status)"
                throw ReplicateError.generationFailed(errorMsg)
            default:
                continue
            }
        }

        throw ReplicateError.generationFailed("Generation timed out after \(maxPollAttempts) polling attempts.")
    }

    private func downloadImages(from prediction: PredictionResponse) async throws -> [Data] {
        guard let output = prediction.output else {
            throw ReplicateError.noOutput
        }

        let urls = output.urls
        guard !urls.isEmpty else {
            throw ReplicateError.noOutput
        }

        var imageDataArray: [Data] = []
        for urlString in urls {
            guard let url = URL(string: urlString) else {
                throw ReplicateError.invalidURL
            }
            let (data, response) = try await session.data(from: url)
            try validateResponse(response, data: data)
            imageDataArray.append(data)
        }

        return imageDataArray
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ReplicateError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}

// MARK: - Response Types

private struct PredictionResponse: Codable {
    let id: String
    let status: String
    let urls: PredictionURLs
    let output: PredictionOutput?
    let error: String?
}

private struct PredictionURLs: Codable {
    let get: String
    let cancel: String
}

private enum PredictionOutput: Codable {
    case single(String)
    case array([String])

    var urls: [String] {
        switch self {
        case .single(let url): return [url]
        case .array(let urls): return urls
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            self = .array(array)
        } else if let single = try? container.decode(String.self) {
            self = .single(single)
        } else {
            throw DecodingError.typeMismatch(
                PredictionOutput.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected String or [String] for prediction output"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let url):
            try container.encode(url)
        case .array(let urls):
            try container.encode(urls)
        }
    }
}

// MARK: - Errors

enum ReplicateError: LocalizedError {
    case httpError(statusCode: Int, body: String)
    case noOutput
    case generationFailed(String)
    case invalidURL
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .noOutput:
            return "No image output received from the API."
        case .generationFailed(let msg):
            return "Generation failed: \(msg)"
        case .invalidURL:
            return "Invalid image URL received."
        case .noAPIKey:
            return "No Replicate API key configured. Add it in Settings."
        }
    }
}
