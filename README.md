# AtmanForge

Hey, I'm the creator of AtmanForge. With most text being LLM generated these days I wanted a personal line to start off the read me with. I created this project as I noticed I really only use a few image models when creating assets so I wanted a cheap, fast and convenient way to access the models. And it was a ton of fun to build! All code in Claude Code, Opus 4.5. Hope you find it useful!

**Open source AI image generation app for macOS.**

Generate stunning images with state-of-the-art AI models. Bring your own API keys — no subscription, no backend, complete privacy.

![macOS](https://img.shields.io/badge/macOS-15.0+-blue?logo=apple)
![License](https://img.shields.io/badge/license-MIT-green)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)

## Features

- **Multiple AI Models** — Access Gemini, GPT-Image, and more. Switch between models instantly.
- **Bring Your Own Keys** — Use your own API keys stored securely in your Mac's Keychain.
- **Reference Images** — Guide AI generation with reference images. Sketch directly on them.
- **Background Removal** — One-click AI-powered background removal.
- **Project Organization** — Keep generations organized with full metadata and activity history.
- **Privacy First** — Everything runs locally. Your data never touches our servers.

## Requirements

- macOS 15.0 or later
- Xcode 16.0 or later (for building)
- A [Replicate](https://replicate.com) API key — currently the only supported provider for accessing AI models

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/Nixarn/atmanforge.git
cd atmanforge
```

### 2. Open in Xcode

```bash
open AtmanForge.xcodeproj
```

### 3. Build and run

Select your target device and press `⌘R` to build and run.

### 4. Add your API key

1. Open AtmanForge
2. Go to **Settings** (⌘,)
3. Enter your [Replicate API key](https://replicate.com/account/api-tokens)

## Supported Models

AtmanForge currently uses [Replicate](https://replicate.com) as its sole provider to access AI models. You'll need a Replicate API key to use the app.

| Model | Description |
|-------|-------------|
| Gemini 2.5 | Google's latest multimodal model |
| GPT-Image 1.5 | OpenAI's image generation model |
| Remove Background | AI-powered background removal |

*More models and providers coming soon!*

## Architecture

```
AtmanForge/
├── Models/           # Data models (Project, Canvas, GenerationJob)
├── ViewModels/       # App state and business logic
├── Views/            # SwiftUI views
│   ├── Canvas/       # Main canvas and library views
│   ├── Components/   # Reusable components
│   ├── Inspector/    # Side panel views
│   ├── Settings/     # Settings view
│   └── Sidebar/      # Generation sidebar
└── Services/         # API providers and managers
```

## Privacy

AtmanForge is designed with privacy in mind:

- **Local Storage** — All images and project data are stored locally on your Mac
- **Secure Keys** — API keys are stored in your Mac's Keychain, not in plain text
- **No Telemetry** — We don't collect any usage data or analytics
- **Direct API Calls** — Requests go directly to AI providers, no middleman servers

## Contributing

Contributions are welcome! Feel free to:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Credits

Built with ♥ by [Turbo Lynx Oy](https://github.com/Nixarn)

---

**AtmanForge** — Create with AI, on your terms.
