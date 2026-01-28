import SwiftUI

enum CenterTab: String, CaseIterable {
    case activity
    case library
}

enum LibrarySortOrder: String, CaseIterable {
    case name, model, resolution, size, dateAdded

    var label: String {
        switch self {
        case .name: return "Name"
        case .model: return "Model"
        case .resolution: return "Resolution"
        case .size: return "Size"
        case .dateAdded: return "Date Added"
        }
    }
}

enum LibraryViewMode: String, CaseIterable {
    case grid, list
}

struct GenerationParamsSnapshot: Equatable {
    let prompt: String
    let selectedModel: AIModel
    let selectedResolution: ImageResolution
    let selectedAspectRatio: AspectRatio
    let imageCount: Int
    let referenceImages: [Data]
    let gptQuality: GPTQuality
    let gptBackground: GPTBackground
    let gptInputFidelity: GPTInputFidelity
}

@MainActor
@Observable
class AppState {
    // MARK: - Data
    var projects: [Project] = []

    // MARK: - Selection
    var selectedProjectID: String?
    var selectedCanvasID: String?

    // MARK: - UI State
    var isGenerating = false
    var statusMessage = "Ready"
    var selectedCenterTab: CenterTab = .activity
    var activityThumbnailSize: CGFloat = 64
    var libraryThumbnailSize: CGFloat = 96
    var selectedTool: CanvasTool = .select
    var canvasZoom: CGFloat = 1.0
    var canvasOffset: CGSize = .zero
    var imageVersion = 0
    var errorMessage: String?
    var projectSizeText: String = ""
    var librarySortOrder: LibrarySortOrder = .dateAdded
    var librarySortAscending: Bool = false
    var libraryViewMode: LibraryViewMode = .grid

    // MARK: - Image Inspector
    var selectedImageJob: GenerationJob?
    var selectedImageIndex: Int = 0
    var isRemovingBackground = false
    var toasts: [AppToast] = []

    // MARK: - AI Generation
    var prompt = ""
    var selectedModel: AIModel = .gemini25
    var selectedResolution: ImageResolution = .r2k
    var selectedAspectRatio: AspectRatio = .r1_1
    var imageCount: Int = 1
    var referenceImages: [Data] = []
    var gptQuality: GPTQuality = .medium
    var gptBackground: GPTBackground = .auto
    var gptInputFidelity: GPTInputFidelity = .high

    // MARK: - Undo/Redo
    var undoStack: [GenerationParamsSnapshot] = []
    var redoStack: [GenerationParamsSnapshot] = []
    var lastCommittedSnapshot: GenerationParamsSnapshot?
    var isRestoringSnapshot = false

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Jobs
    var generationJobs: [GenerationJob] = []
    var activeJobID: UUID?

    // MARK: - Services
    let projectManager = ProjectManager.shared

    // MARK: - Computed

    var hasProjectsRoot: Bool

    init() {
        hasProjectsRoot = ProjectManager.shared.projectsRootURL != nil
        lastCommittedSnapshot = currentSnapshot()
    }

    var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    var selectedCanvas: Canvas? {
        guard let projectID = selectedProjectID,
              let canvasID = selectedCanvasID,
              let project = projects.first(where: { $0.id == projectID }) else {
            return nil
        }
        return project.canvases.first { $0.id == canvasID }
    }

    var projectName: String {
        projectManager.projectsRootURL?.lastPathComponent ?? "AtmanForge"
    }

    var runningJobCount: Int {
        generationJobs.filter { $0.status == .running || $0.status == .pending }.count
    }

    func estimatedDuration(for model: AIModel) -> TimeInterval? {
        let completed = generationJobs.filter {
            $0.model == model && $0.status == .completed &&
            $0.startedAt != nil && $0.completedAt != nil
        }
        guard !completed.isEmpty else { return nil }
        let total = completed.reduce(0.0) { sum, job in
            sum + job.completedAt!.timeIntervalSince(job.startedAt!)
        }
        return total / Double(completed.count)
    }

    // MARK: - Model Changed

    func onModelChanged() {
        // Clamp image count to model max
        if imageCount > selectedModel.maxImageCount {
            imageCount = selectedModel.maxImageCount
        }

        // Clamp reference images to model max
        if referenceImages.count > selectedModel.maxReferenceImages {
            referenceImages = Array(referenceImages.prefix(selectedModel.maxReferenceImages))
        }

        // Reset aspect ratio if not supported by new model
        if !selectedModel.supportedAspectRatios.contains(selectedAspectRatio) {
            selectedAspectRatio = .r1_1
        }
    }

    // MARK: - Undo/Redo

    func currentSnapshot() -> GenerationParamsSnapshot {
        GenerationParamsSnapshot(
            prompt: prompt,
            selectedModel: selectedModel,
            selectedResolution: selectedResolution,
            selectedAspectRatio: selectedAspectRatio,
            imageCount: imageCount,
            referenceImages: referenceImages,
            gptQuality: gptQuality,
            gptBackground: gptBackground,
            gptInputFidelity: gptInputFidelity
        )
    }

    func commitUndoCheckpoint() {
        guard !isRestoringSnapshot else { return }
        let current = currentSnapshot()
        guard let last = lastCommittedSnapshot, last != current else { return }
        undoStack.append(last)
        if undoStack.count > 30 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        lastCommittedSnapshot = current
    }

    func undo() {
        commitUndoCheckpoint()
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        restore(snapshot)
    }

    private func restore(_ snapshot: GenerationParamsSnapshot) {
        isRestoringSnapshot = true
        prompt = snapshot.prompt
        selectedModel = snapshot.selectedModel
        selectedResolution = snapshot.selectedResolution
        selectedAspectRatio = snapshot.selectedAspectRatio
        imageCount = snapshot.imageCount
        referenceImages = snapshot.referenceImages
        gptQuality = snapshot.gptQuality
        gptBackground = snapshot.gptBackground
        gptInputFidelity = snapshot.gptInputFidelity
        lastCommittedSnapshot = snapshot
        isRestoringSnapshot = false
    }

    func addReferenceImages(_ images: [Data]) {
        let remaining = selectedModel.maxReferenceImages - referenceImages.count
        guard remaining > 0 else { return }
        for imageData in images.prefix(remaining) {
            if let normalized = Self.normalizeImageData(imageData) {
                referenceImages.append(normalized)
            }
        }
        commitUndoCheckpoint()
    }

    func removeReferenceImage(at index: Int) {
        guard referenceImages.indices.contains(index) else { return }
        referenceImages.remove(at: index)
        commitUndoCheckpoint()
    }

    /// Convert arbitrary image data to PNG for consistent API handling
    private static func normalizeImageData(_ data: Data) -> Data? {
        #if os(macOS)
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
        #else
        guard let image = UIImage(data: data),
              let pngData = image.pngData() else {
            return nil
        }
        return pngData
        #endif
    }

    // MARK: - Image Inspector

    func selectImage(job: GenerationJob, index: Int) {
        selectedImageJob = job
        selectedImageIndex = index
    }

    func clearImageSelection() {
        selectedImageJob = nil
        selectedImageIndex = 0
    }

    // MARK: - Toasts

    func showToast(_ message: String, icon: String = "checkmark", style: AppToast.ToastStyle = .info) {
        let toast = AppToast(message: message, icon: icon, style: style)
        withAnimation { toasts.append(toast) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { toasts.removeAll { $0.id == toast.id } }
        }
    }

    // MARK: - Reuse Settings

    func loadSettings(from job: GenerationJob) {
        selectedModel = job.model
        prompt = job.prompt
        selectedAspectRatio = job.aspectRatio
        if let res = job.resolution {
            selectedResolution = res
        }
        imageCount = job.imageCount
        if let q = job.gptQuality {
            gptQuality = q
        }
        if let bg = job.gptBackground {
            gptBackground = bg
        }
        if let f = job.gptInputFidelity {
            gptInputFidelity = f
        }
        // Restore reference images from saved paths
        if let root = projectManager.projectsRootURL, !job.referenceImagePaths.isEmpty {
            referenceImages.removeAll()
            for path in job.referenceImagePaths {
                let url = root.appendingPathComponent(path)
                if let data = try? Data(contentsOf: url) {
                    referenceImages.append(data)
                }
            }
        }
        commitUndoCheckpoint()
    }

    // MARK: - Project Operations

    func loadProjects() {
        projectManager.startAccessing()
        do {
            projects = try projectManager.loadProjects()
            if selectedProjectID == nil, let first = projects.first {
                selectedProjectID = first.id
            }
        } catch {
            statusMessage = "Failed to load projects: \(error.localizedDescription)"
        }
        loadActivity()
        updateProjectSize()
    }

    func createProject(name: String) {
        do {
            let project = try projectManager.createProject(name: name)
            projects.insert(project, at: 0)
            selectedProjectID = project.id
            selectedCanvasID = nil
            statusMessage = "Created project: \(name)"
        } catch {
            statusMessage = "Failed to create project: \(error.localizedDescription)"
        }
    }

    func deleteProject(_ project: Project) {
        do {
            try projectManager.deleteProject(project)
            projects.removeAll { $0.id == project.id }
            if selectedProjectID == project.id {
                selectedProjectID = nil
                selectedCanvasID = nil
            }
            statusMessage = "Deleted project: \(project.name)"
        } catch {
            statusMessage = "Failed to delete project: \(error.localizedDescription)"
        }
    }

    func renameProject(_ project: Project, to newName: String) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        do {
            try projectManager.renameProject(&projects[index], to: newName)
        } catch {
            statusMessage = "Failed to rename project: \(error.localizedDescription)"
        }
    }

    // MARK: - Canvas Operations

    func createCanvas(inProjectID projectID: String, name: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        do {
            let canvas = try projectManager.createCanvas(
                inProject: &projects[index],
                name: name,
                width: selectedResolution.dimensions(for: selectedAspectRatio).width,
                height: selectedResolution.dimensions(for: selectedAspectRatio).height
            )
            selectedCanvasID = canvas.id
            statusMessage = "Created canvas: \(name)"
        } catch {
            statusMessage = "Failed to create canvas: \(error.localizedDescription)"
        }
    }

    func deleteCanvas(_ canvas: Canvas, fromProjectID projectID: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        do {
            try projectManager.deleteCanvas(canvas, fromProject: &projects[index])
            if selectedCanvasID == canvas.id {
                selectedCanvasID = nil
            }
            statusMessage = "Deleted canvas: \(canvas.name)"
        } catch {
            statusMessage = "Failed to delete canvas: \(error.localizedDescription)"
        }
    }

    // MARK: - AI Generation

    func generateImage() {
        guard let projectRoot = projectManager.projectsRootURL else {
            errorMessage = "No project folder open."
            statusMessage = "No project folder open."
            return
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "Enter a prompt first."
            statusMessage = "Enter a prompt first."
            return
        }

        guard let apiKey = KeychainManager.load(key: "replicate_api_key"), !apiKey.isEmpty else {
            errorMessage = "No Replicate API key configured. Add it in Settings."
            statusMessage = "API key missing."
            return
        }

        // Snapshot current settings before launching async work
        let currentModel = selectedModel
        let currentAspectRatio = selectedAspectRatio
        let currentResolution = selectedResolution
        let currentImageCount = imageCount
        let currentReferenceImages = referenceImages
        let currentGptQuality = gptQuality
        let currentGptBackground = gptBackground
        let currentGptInputFidelity = gptInputFidelity

        // Create job and switch to activity tab immediately
        let job = GenerationJob(
            model: currentModel,
            prompt: trimmedPrompt,
            projectID: projectRoot.lastPathComponent,
            aspectRatio: currentAspectRatio,
            resolution: currentModel.supportsResolution ? currentResolution : nil,
            imageCount: currentImageCount,
            gptQuality: currentModel == .gptImage15 ? currentGptQuality : nil,
            gptBackground: currentModel == .gptImage15 ? currentGptBackground : nil,
            gptInputFidelity: currentModel == .gptImage15 ? currentGptInputFidelity : nil
        )
        generationJobs.insert(job, at: 0)
        activeJobID = job.id

        // Save reference images to project folder
        var referenceHashes: [String] = []
        if !currentReferenceImages.isEmpty {
            let result = projectManager.saveReferenceImages(currentReferenceImages, toFolder: projectRoot)
            job.referenceImagePaths = result.paths
            referenceHashes = result.hashes
        }

        errorMessage = nil
        statusMessage = "Generating with \(currentModel.displayName)..."
        job.startedAt = Date()
        job.status = .running

        let request = GenerationRequest(
            prompt: trimmedPrompt,
            model: currentModel,
            aspectRatio: currentAspectRatio,
            resolution: currentModel.supportsResolution ? currentResolution : nil,
            imageCount: currentImageCount,
            referenceImages: currentReferenceImages,
            gptQuality: currentModel == .gptImage15 ? currentGptQuality : nil,
            gptBackground: currentModel == .gptImage15 ? currentGptBackground : nil,
            gptInputFidelity: currentModel == .gptImage15 ? currentGptInputFidelity : nil
        )

        let provider = ReplicateProvider(apiKey: apiKey)

        Task {
            do {
                let result = try await provider.generateImage(request: request) { [weak self] cancelURL in
                    Task { @MainActor in
                        guard let self else { return }
                        if job.startedAt == nil {
                            job.startedAt = Date()
                        }
                        job.cancelURLs.append(cancelURL)
                    }
                }

                guard !result.imageDataArray.isEmpty else {
                    throw ReplicateError.noOutput
                }

                let meta = ImageMeta(
                    prompt: trimmedPrompt,
                    model: currentModel,
                    aspectRatio: currentAspectRatio,
                    resolution: currentModel.supportsResolution ? currentResolution : nil,
                    imageCount: currentImageCount,
                    gptQuality: currentModel == .gptImage15 ? currentGptQuality : nil,
                    gptBackground: currentModel == .gptImage15 ? currentGptBackground : nil,
                    gptInputFidelity: currentModel == .gptImage15 ? currentGptInputFidelity : nil,
                    referenceHashes: referenceHashes,
                    createdAt: Date()
                )
                let saved = try projectManager.saveGeneratedImages(result.imageDataArray, toFolder: projectRoot, meta: meta)

                job.resultImageData = result.imageDataArray
                job.savedImagePaths = saved.imagePaths
                job.thumbnailPaths = saved.thumbnailPaths
                job.completedAt = Date()
                job.status = .completed
                imageVersion += 1
                statusMessage = "Saved \(saved.imagePaths.count) image\(saved.imagePaths.count == 1 ? "" : "s")"
                showToast("Image generated", icon: "checkmark.circle", style: .success)
                saveActivity()
            } catch {
                if job.status != .cancelled {
                    job.completedAt = Date()
                    job.status = .failed
                    job.errorMessage = error.localizedDescription
                    errorMessage = error.localizedDescription
                    statusMessage = "Generation failed."
                    showToast("Generation failed", icon: "xmark.circle", style: .error)
                }
                saveActivity()
            }
        }
    }

    func cancelJob(_ job: GenerationJob) {
        guard job.status == .running || job.status == .pending else { return }

        let cancelURLs = job.cancelURLs
        job.completedAt = Date()
        job.status = .cancelled
        statusMessage = "Cancelled"
        saveActivity()

        guard let apiKey = KeychainManager.load(key: "replicate_api_key"), !apiKey.isEmpty else { return }
        let provider = ReplicateProvider(apiKey: apiKey)

        Task.detached {
            for url in cancelURLs {
                try? await provider.cancelPrediction(url: url)
            }
        }
    }

    func removeBackground(job: GenerationJob, imageIndex: Int) {
        guard let projectRoot = projectManager.projectsRootURL else { return }
        guard imageIndex < job.savedImagePaths.count else { return }
        guard let apiKey = KeychainManager.load(key: "replicate_api_key"), !apiKey.isEmpty else {
            errorMessage = "No Replicate API key configured. Add it in Settings."
            return
        }

        let imagePath = job.savedImagePaths[imageIndex]
        let imageURL = projectRoot.appendingPathComponent(imagePath)
        guard let imageData = try? Data(contentsOf: imageURL) else {
            errorMessage = "Could not read image file."
            return
        }

        // Copy the source image to references so it persists independently
        let refResult = projectManager.saveReferenceImages([imageData], toFolder: projectRoot)

        // Create job upfront so it appears in the activity list immediately
        let bgJob = GenerationJob(
            model: .removeBackground,
            prompt: job.prompt,
            projectID: projectRoot.lastPathComponent,
            aspectRatio: job.aspectRatio,
            resolution: nil,
            imageCount: 1,
            gptQuality: nil,
            gptBackground: nil,
            gptInputFidelity: nil
        )
        bgJob.referenceImagePaths = refResult.paths
        bgJob.startedAt = Date()
        bgJob.status = .running
        generationJobs.insert(bgJob, at: 0)
        activeJobID = bgJob.id

        isRemovingBackground = true
        statusMessage = "Removing background..."

        let provider = ReplicateProvider(apiKey: apiKey)

        Task {
            do {
                let resultData = try await provider.removeBackground(imageData: imageData)
                let meta = ImageMeta(
                    prompt: bgJob.prompt,
                    model: .removeBackground,
                    aspectRatio: bgJob.aspectRatio,
                    resolution: nil,
                    imageCount: 1,
                    gptQuality: nil,
                    gptBackground: nil,
                    gptInputFidelity: nil,
                    referenceHashes: refResult.hashes,
                    createdAt: Date()
                )
                let saved = try projectManager.saveGeneratedImages([resultData], toFolder: projectRoot, meta: meta)

                bgJob.resultImageData = [resultData]
                bgJob.savedImagePaths = saved.imagePaths
                bgJob.thumbnailPaths = saved.thumbnailPaths
                bgJob.completedAt = Date()
                bgJob.status = .completed

                selectImage(job: bgJob, index: 0)
                imageVersion += 1
                statusMessage = "Background removed"
                isRemovingBackground = false
                showToast("Background removed", icon: "checkmark.circle", style: .success)
                saveActivity()
            } catch {
                bgJob.completedAt = Date()
                bgJob.status = .failed
                bgJob.errorMessage = error.localizedDescription
                errorMessage = error.localizedDescription
                statusMessage = "Background removal failed."
                isRemovingBackground = false
                showToast("Background removal failed", icon: "xmark.circle", style: .error)
                saveActivity()
            }
        }
    }

    func removeJob(_ job: GenerationJob) {
        generationJobs.removeAll { $0.id == job.id }
        if selectedImageJob?.id == job.id {
            clearImageSelection()
        }
        saveActivity()
    }

    // MARK: - Project Size

    func updateProjectSize() {
        guard let root = projectManager.projectsRootURL else {
            projectSizeText = ""
            return
        }
        let bytes = projectManager.projectSize(at: root)
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1000 {
            let gb = mb / 1024
            projectSizeText = String(format: "%.1f GB", gb)
        } else {
            projectSizeText = String(format: "%.1f MB", mb)
        }
    }

    // MARK: - Zoom

    func zoomIn() {
        canvasZoom = min(canvasZoom * 1.25, 10.0)
    }

    func zoomOut() {
        canvasZoom = max(canvasZoom / 1.25, 0.1)
    }

    func zoomToFit() {
        canvasZoom = 1.0
        canvasOffset = .zero
    }

    // MARK: - Root Folder

    func setProjectsRoot(_ url: URL) {
        projectManager.setProjectsRoot(url)
        hasProjectsRoot = true
        loadProjects()
        loadActivity()
    }

    func loadActivity() {
        guard let root = projectManager.projectsRootURL else { return }
        let loaded = projectManager.loadActivity(from: root)
        // Merge: keep any in-flight jobs, prepend loaded history
        let inFlight = generationJobs.filter { $0.status == .pending || $0.status == .running }
        generationJobs = inFlight + loaded
    }

    func saveActivity() {
        guard let root = projectManager.projectsRootURL else { return }
        projectManager.saveActivity(generationJobs, to: root)
        updateProjectSize()
    }

    func closeProject() {
        hasProjectsRoot = false
        selectedProjectID = nil
        selectedCanvasID = nil
        projects = []
        projectManager.stopAccessing()
    }

    func openProject(url: URL) {
        setProjectsRoot(url)
    }

    // MARK: - Menu State

    var showNewProjectAlert = false
    var showNewCanvasAlert = false
    var newItemName = ""
}
