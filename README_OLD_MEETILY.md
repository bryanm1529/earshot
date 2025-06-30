# 🧠 Earshot Cognitive Co-Pilot

> **Real-time AI-powered conversational assistance for live audio streams**

A production-ready cognitive co-pilot system that provides intelligent, context-aware assistance during conversations, meetings, and presentations. Built with privacy-first local processing and designed for daily use.

[![Windows Support](https://img.shields.io/badge/Windows-Native-blue?logo=windows&logoColor=white)](WINDOWS_MIGRATION_GUIDE.md)
[![Linux Support](https://img.shields.io/badge/Linux-WSL-green?logo=linux&logoColor=white)](#)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)
[![Python](https://img.shields.io/badge/Python-3.10+-blue?logo=python&logoColor=white)](#)

## ✨ Features

- **🎤 Real-time Audio Processing**: Live transcription using Whisper.cpp with GPU acceleration
- **🧠 Intelligent Question Detection**: AI-powered regex patterns for instant question recognition
- **💡 Contextual Assistance**: LLM-powered responses using Ollama with conversation memory
- **🌐 WebSocket Integration**: Real-time communication with frontend HUD interface
- **🖥️ Cross-Platform**: Native Windows support + Linux/WSL compatibility
- **🔒 Privacy-First**: All processing happens locally - no cloud dependencies
- **⚡ Low Latency**: Sub-second response times with optimized pipeline
- **📊 Production Ready**: Robust error handling, monitoring, and graceful shutdown

## 🚀 Quick Start

### Windows (Native) - **Recommended**

```powershell
# 1. Clone the repository
git clone https://github.com/your-username/earshot-copilot.git
cd earshot-copilot

# 2. Run setup (one-time)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup_windows.ps1

# 3. Build components
cd backend
.\build_whisper.cmd tiny.en
cd ..

# 4. Start the system
.\start_native.ps1
```

### Linux/WSL

```bash
# 1. Clone the repository
git clone https://github.com/your-username/earshot-copilot.git
cd earshot-copilot

# 2. Start the system
./start_copilot.sh
```

## 📋 Prerequisites

### Windows
- Windows 10/11 (64-bit)
- Python 3.10+ (with PATH configuration)
- Node.js LTS + pnpm
- Rust toolchain + Tauri CLI
- Visual Studio Build Tools + CMake
- CUDA Toolkit (optional for GPU acceleration)
- websocat, FFmpeg, Ollama

### Linux/WSL
- Python 3.10+
- Node.js 18+
- FFmpeg
- Ollama
- Whisper.cpp build dependencies

📖 **Detailed installation guides:**
- [**Windows Migration Guide**](WINDOWS_MIGRATION_GUIDE.md) - Complete Windows setup
- [Backend README](backend/README.md) - Detailed backend configuration
- [Frontend README](frontend/README.md) - Frontend development setup

## 🏗️ System Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Audio Input   │───▶│  Whisper Server  │───▶│ Cognitive Engine│
│ (Microphone/    │    │  (Speech-to-Text)│    │   (brain.py)    │
│  System Audio)  │    └──────────────────┘    └─────────────────┘
└─────────────────┘                                      │
                                                         │
┌─────────────────┐    ┌──────────────────┐             │
│  Frontend HUD   │◄───│  WebSocket API   │◄────────────┘
│ (Next.js/Tauri) │    │   (Real-time)    │
└─────────────────┘    └──────────────────┘
                                 │
                                 ▼
                       ┌──────────────────┐
                       │  Ollama LLM      │
                       │ (Local Models)   │
                       └──────────────────┘
```

### Core Components

1. **Audio Pipeline**: FFmpeg → websocat → Whisper WebSocket
2. **Whisper Server**: Local speech-to-text with hot stream API
3. **Cognitive Engine**: Python-based AI orchestrator with WebSocket server
4. **Frontend**: Tauri desktop app with Next.js UI
5. **LLM Integration**: Ollama for local language model inference

## 🔧 Configuration

### Windows (.env file - Recommended)
```env
# Copy .env.example to .env and customize
COPILOT_ADVISOR_MODEL=llama3:8b
COPILOT_CHRONICLER_ENABLED=true
COPILOT_WHISPER_HOST=127.0.0.1
COPILOT_WHISPER_PORT=9080
COPILOT_OLLAMA_HOST=127.0.0.1
COPILOT_OLLAMA_PORT=11434
```

### Linux (.copilotrc file)
```bash
# Copy .copilotrc.example to .copilotrc and customize
export COPILOT_ADVISOR_MODEL="llama3:8b"
export COPILOT_CHRONICLER_ENABLED="true"
export COPILOT_WHISPER_HOST="127.0.0.1"
export COPILOT_WHISPER_PORT="9080"
```

## 🎯 Usage

### Access Points
- **HUD Interface**: http://localhost:3118/hud
- **Whisper Server**: http://127.0.0.1:9080
- **WebSocket Stream**: ws://127.0.0.1:10080/hot_stream
- **Cognitive Engine**: ws://127.0.0.1:9082

### Controls
- **Pause/Resume**: Caps Lock in HUD interface
- **Stop System**: Ctrl+C in terminal or run `.\stop_native.ps1`

### Audio Setup
1. **Direct Microphone**: Works immediately (captures all system audio)
2. **VB-Audio Virtual Cable**: Download from [vb-audio.com](https://vb-audio.com/Cable/) for selective audio routing

## 📊 Sprint History & Development

This project follows an agile development approach with documented sprint completions:

- **Sprint 1-2**: Core audio capture and transcription pipeline
- **Sprint 3-4**: Real-time streaming and performance optimization
- **Sprint 5-6**: Question detection and LLM integration
- **Sprint 7-8**: Context management and reliability improvements
- **Sprint 9**: WebSocket integration and production readiness
- **Windows Migration**: Native Windows support with enhanced reliability

📚 **Complete documentation**: [Sprint Reports](SPRINT_9_COMPLETION_REPORT.md)

## 🔧 Development

### Local Development
```bash
# Backend development
cd backend
python brain.py --debug

# Frontend development
cd frontend
pnpm dev

# Tauri development
pnpm tauri dev
```

### Testing
```bash
# Run system validation
python sprint_9_validation.py

# Performance testing
cd backend
./run_soak_test.sh
```

## 🐛 Troubleshooting

### Windows Issues
- **Execution Policy**: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`
- **Audio Pipeline**: Test manually with `ffmpeg ... | websocat ...`
- **Missing CMake**: Install via Chocolatey or cmake.org
- **Port Conflicts**: Check with `netstat -an | findstr ":9080"`

### General Issues
- **Model Download**: Ensure Ollama is running and models are pulled
- **WebSocket Errors**: Verify all services are started in correct order
- **Performance**: Use GPU acceleration with CUDA for Whisper

📖 **Complete troubleshooting**: [Windows Migration Guide](WINDOWS_MIGRATION_GUIDE.md#troubleshooting)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

## 🙏 Acknowledgments

- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) for local speech recognition
- [Ollama](https://ollama.ai/) for local LLM inference
- [Tauri](https://tauri.app/) for cross-platform desktop applications
- [websocat](https://github.com/vi/websocat) for WebSocket streaming

---

<div align="center">

**Ready to enhance your conversations with AI assistance?**

[📖 Read the Windows Guide](WINDOWS_MIGRATION_GUIDE.md) • [🚀 Quick Start](#quick-start) • [💬 Discussions](../../discussions)

*Built with ❤️ for privacy-conscious power users*

</div>
