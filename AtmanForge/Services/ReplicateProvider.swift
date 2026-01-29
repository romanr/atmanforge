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

    func generateImage(request: GenerationRequest, onPredictionCreated: @Sendable @escaping (String) -> Void) async throws -> GenerationResult {
        let input = try await buildInput(for: request)

        let prediction = try await createPrediction(
            model: request.model.replicateModelID,
            input: input
        )
        onPredictionCreated(prediction.urls.cancel)
        let finalPrediction = try await waitForPrediction(prediction)
        let allImageData = try await downloadImages(from: finalPrediction)

        return GenerationResult(imageDataArray: allImageData)
    }

    func removeBackground(imageData: Data) async throws -> Data {
        let fileURL = try await uploadFile(imageData, filename: "bg_remove.png")

        let url = URL(string: "\(baseURL)/models/bria/remove-background/predictions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("wait", forHTTPHeaderField: "Prefer")
        urlRequest.timeoutInterval = 120

        let body: [String: Any] = [
            "input": [
                "image": fileURL,
                "content_moderation": false,
                "preserve_alpha": true
            ]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: data)

        let prediction = try JSONDecoder().decode(PredictionResponse.self, from: data)

        guard prediction.status == "succeeded" else {
            let raw = prediction.error
            let errorMsg = (raw == nil || raw!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ? "No reason given"
                : raw!
            throw ReplicateError.generationFailed(errorMsg)
        }

        let imageDataArray = try await downloadImages(from: prediction)
        guard let result = imageDataArray.first else {
            throw ReplicateError.noOutput
        }
        return result
    }

    func cancelPrediction(url: String) async throws {
        guard let cancelURL = URL(string: url) else {
            throw ReplicateError.invalidURL
        }
        var urlRequest = URLRequest(url: cancelURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: Data())
    }

    // MARK: - Input Building

    private func buildInput(for request: GenerationRequest) async throws -> [String: Any] {
        var input: [String: Any] = [
            "prompt": request.prompt,
            "aspect_ratio": request.aspectRatio.rawValue,
        ]

        if !request.referenceImages.isEmpty {
            let fileURLs = try await uploadReferenceImages(request.referenceImages)
            let key = request.model == .gptImage15 ? "input_images" : "image_input"
            input[key] = fileURLs
        }

        input["number_of_images"] = request.imageCount

        switch request.model {
        case .gemini25, .removeBackground:
            break

        case .gemini30:
            if let resolution = request.resolution {
                input["resolution"] = resolution.rawValue
            }

        case .gptImage15:
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

    // MARK: - File Upload

    private func uploadReferenceImages(_ images: [Data]) async throws -> [String] {
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, imageData) in images.enumerated() {
                group.addTask {
                    let url = try await self.uploadFile(imageData, filename: "reference_\(index).png")
                    return (index, url)
                }
            }
            var results: [(Int, String)] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func uploadFile(_ data: Data, filename: String) async throws -> String {
        let url = URL(string: "\(baseURL)/files")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"content\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        urlRequest.httpBody = body

        let (responseData, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: responseData)

        let fileResponse = try JSONDecoder().decode(FileUploadResponse.self, from: responseData)
        return fileResponse.urls.get
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

    private func waitForPrediction(_ prediction: PredictionResponse) async throws -> PredictionResponse {
        if let streamURL = prediction.urls.stream {
            return try await streamPrediction(prediction, streamURL: streamURL)
        } else {
            return try await pollPrediction(prediction)
        }
    }

    // MARK: - SSE Streaming

    private func streamPrediction(_ prediction: PredictionResponse, streamURL: String) async throws -> PredictionResponse {
        guard let url = URL(string: streamURL) else {
            throw ReplicateError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: urlRequest)
        try validateResponse(response, data: Data())

        var currentEvent = ""
        var currentData = ""

        for try await line in bytes.lines {
            if line.hasPrefix("event: ") {
                currentEvent = String(line.dropFirst(7))
            } else if line.hasPrefix("data: ") {
                currentData += String(line.dropFirst(6))
            } else if line.isEmpty && !currentEvent.isEmpty {
                switch currentEvent {
                case "done":
                    return try await fetchPrediction(url: prediction.urls.get)
                case "error":
                    let errorMsg = currentData.isEmpty ? "No reason given" : currentData
                    throw ReplicateError.generationFailed(errorMsg)
                default:
                    break
                }

                currentEvent = ""
                currentData = ""
            }
        }

        return try await fetchPrediction(url: prediction.urls.get)
    }

    private func fetchPrediction(url: String) async throws -> PredictionResponse {
        guard let getURL = URL(string: url) else {
            throw ReplicateError.invalidURL
        }

        var urlRequest = URLRequest(url: getURL)
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: data)

        let prediction = try JSONDecoder().decode(PredictionResponse.self, from: data)

        guard prediction.status == "succeeded" else {
            let raw = prediction.error
            let errorMsg = (raw == nil || raw!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ? "No reason given"
                : raw!
            throw ReplicateError.generationFailed(errorMsg)
        }

        return prediction
    }

    // MARK: - Polling (fallback)

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
                let raw = current.error
                let errorMsg = (raw == nil || raw!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ? "No reason given"
                    : raw!
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
    let stream: String?
}

private struct FileUploadResponse: Codable {
    let urls: FileURLs
}

private struct FileURLs: Codable {
    let get: String
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
