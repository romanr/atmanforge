import SwiftUI

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
    var selectedTool: CanvasTool = .select
    var canvasZoom: CGFloat = 1.0
    var canvasOffset: CGSize = .zero
    var imageVersion = 0
    var errorMessage: String?

    // MARK: - Image Inspector
    var selectedImageJob: GenerationJob?
    var selectedImageIndex: Int = 0

    // MARK: - AI Generation
    var prompt = ""
    var selectedModel: AIModel = .gemini25
    var selectedResolution: ImageResolution = .r2k
    var selectedAspectRatio: AspectRatio = .r1_1
    var imageCount: Int = 1
    var gptQuality: GPTQuality = .medium
    var gptBackground: GPTBackground = .auto
    var gptInputFidelity: GPTInputFidelity = .high

    // MARK: - Jobs
    var generationJobs: [GenerationJob] = []
    var activeJobID: UUID?

    // MARK: - Services
    let projectManager = ProjectManager.shared

    // MARK: - Computed

    var hasProjectsRoot: Bool

    init() {
        hasProjectsRoot = ProjectManager.shared.projectsRootURL != nil
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

    // MARK: - Model Changed

    func onModelChanged() {
        // Clamp image count to model max
        if imageCount > selectedModel.maxImageCount {
            imageCount = selectedModel.maxImageCount
        }

        // Reset aspect ratio if not supported by new model
        if !selectedModel.supportedAspectRatios.contains(selectedAspectRatio) {
            selectedAspectRatio = .r1_1
        }
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

    func generateImage() async {
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

        // Create job and switch to activity tab immediately
        let job = GenerationJob(
            model: selectedModel,
            prompt: trimmedPrompt,
            projectID: projectRoot.lastPathComponent,
            aspectRatio: selectedAspectRatio,
            resolution: selectedModel.supportsResolution ? selectedResolution : nil,
            imageCount: imageCount,
            gptQuality: selectedModel == .gptImage15 ? gptQuality : nil,
            gptBackground: selectedModel == .gptImage15 ? gptBackground : nil,
            gptInputFidelity: selectedModel == .gptImage15 ? gptInputFidelity : nil
        )
        generationJobs.insert(job, at: 0)
        activeJobID = job.id

        isGenerating = true
        errorMessage = nil
        statusMessage = "Generating with \(selectedModel.displayName)..."
        job.status = .running

        let request = GenerationRequest(
            prompt: trimmedPrompt,
            model: selectedModel,
            aspectRatio: selectedAspectRatio,
            resolution: selectedModel.supportsResolution ? selectedResolution : nil,
            imageCount: imageCount,
            gptQuality: selectedModel == .gptImage15 ? gptQuality : nil,
            gptBackground: selectedModel == .gptImage15 ? gptBackground : nil,
            gptInputFidelity: selectedModel == .gptImage15 ? gptInputFidelity : nil
        )

        let provider = ReplicateProvider(apiKey: apiKey)

        do {
            let result = try await provider.generateImage(request: request)

            guard !result.imageDataArray.isEmpty else {
                throw ReplicateError.noOutput
            }

            let saved = try projectManager.saveGeneratedImages(result.imageDataArray, toFolder: projectRoot)

            job.resultImageData = result.imageDataArray
            job.savedImagePaths = saved.imagePaths
            job.thumbnailPaths = saved.thumbnailPaths
            job.status = .completed
            imageVersion += 1
            statusMessage = "Saved \(saved.imagePaths.count) image\(saved.imagePaths.count == 1 ? "" : "s")"
            saveActivity()
        } catch {
            job.status = .failed
            job.errorMessage = error.localizedDescription
            errorMessage = error.localizedDescription
            statusMessage = "Generation failed."
            saveActivity()
        }

        isGenerating = false
        if activeJobID == job.id {
            activeJobID = nil
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
