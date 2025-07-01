# 🧠 Earshot Cognitive Co-Pilot

> **High-Performance Real-time AI Assistant with stdin-Stream Architecture**

A breakthrough cognitive co-pilot system featuring custom `whisper-stream-stdin` technology for true real-time transcription. Provides intelligent, context-aware assistance during conversations, meetings, and presentations with zero file I/O latency. Built with a robust Python-native architecture that eliminates complex dependencies and Just Works™ on Windows.

[![Windows Native](https://img.shields.io/badge/Windows-Native-blue?logo=windows&logoColor=white)](#)
[![Python](https://img.shields.io/badge/Python-3.10+-blue?logo=python&logoColor=white)](#)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

## ✨ Features

- **⚡ High-Performance Streaming**: Custom `whisper-stream-stdin` tool for true real-time transcription
- **🎤 Zero-Latency Audio Processing**: Direct FFmpeg → Whisper pipeline eliminates file I/O bottlenecks
- **🧠 Intelligent Question Detection**: AI-powered regex patterns for instant question recognition
- **💡 Contextual Assistance**: LLM-powered responses using Ollama with conversation memory
- **🌐 WebSocket Integration**: Real-time communication with frontend HUD interface
- **🖥️ Windows Native**: Robust, simplified architecture with zero C++ networking issues
- **🔒 Privacy-First**: All processing happens locally - no cloud dependencies
- **🚫 No Temporary Files**: Pure in-memory streaming for maximum performance
- **📊 Production Ready**: Robust error handling, monitoring, and graceful shutdown

## 🚀 Quick Start

### Two-Part Launch Process

**Part 1: Start Backend (Headless Services)**
```powershell
# Terminal 1: Start the Python-native backend
.\start_simple.ps1
```

**Part 2: Start Frontend (Visual HUD)**
```powershell
# Terminal 2: Start the Tauri HUD (when backend is ready)
.\start_frontend.ps1
```

### One-Time Setup
```powershell
# 1. Clone and setup
git clone https://github.com/your-username/earshot-copilot.git
cd earshot-copilot
.\setup_windows.ps1

# 2. Install frontend dependencies
cd frontend
pnpm install
```

## 📋 Prerequisites

- **Windows 10/11** (64-bit)
- **Python 3.10+** (with PATH configuration)
- **Node.js LTS + pnpm** (for frontend)
- **Rust + Tauri CLI** (for HUD)
- **FFmpeg** (for audio capture)
- **Ollama** (for local LLM)
- **VB-Audio Virtual Cable** (for audio routing)

## 🏗️ stdin-Stream Architecture

```
Backend (Headless)          Frontend (Visual)
├── 🎤 Audio (ffmpeg)       ├── 🪟 Tauri HUD Window
├── 🗣️ whisper-stream-stdin ├── ⚡ React UI
├── 🤖 Chronicler           ├── 🔌 WebSocket Client
├── 💡 Advisor (Ollama)     └── 🎯 Overlay Display
├── 🌐 WebSocket Server
└── 📊 Process Management
```

### Direct Streaming Pipeline
```
FFmpeg → whisper-stream-stdin.exe → Python → WebSocket → Frontend
   ↓           ↓                      ↓         ↓          ↓
Audio      Real-time              Callback  Broadcast   HUD
Capture    Transcription         Processing  Response   Display
```

### Architecture Benefits

- **⚡ True Real-time**: Custom stdin tool eliminates file I/O bottleneck
- **🚫 ZERO C++ networking issues** - All handled in Python
- **🔧 Robust process management** - Python asyncio handles everything
- **🐛 Simpler debugging** - One backend log stream
- **🏗️ Modular design** - Backend/frontend completely separate
- **🪟 Windows native** - No cross-platform compatibility hell
- **🎯 Minimal C++ changes** - Maximum stability with new whisper tool

## 🔧 Configuration

The system uses sensible defaults. Optional customization via environment variables:

```env
COPILOT_ADVISOR_MODEL=llama3:8b
COPILOT_CHRONICLER_ENABLED=true
OLLAMA_HOST=127.0.0.1
OLLAMA_PORT=11434
```

## ⚡ Technical Breakthrough: stdin-Stream Architecture

### The Problem with Traditional Approaches
Previous implementations suffered from a fatal performance bottleneck: **temporary file processing**. Writing audio chunks to disk, processing them, and cleaning up created significant latency that made real-time conversation assistance impossible.

### Our Solution: Direct Memory Streaming
We created a custom `whisper-stream-stdin.exe` tool that:

1. **Eliminates File I/O**: Audio flows directly from FFmpeg → Whisper via stdin/stdout
2. **True Real-time Processing**: No disk writes = no latency spikes
3. **Maximum Stability**: Minimal C++ modifications, maximum Python control
4. **Zero SDL Dependencies**: Removed audio capture complexity

### Performance Impact
- **Before**: 2-5 second delays due to file operations
- **After**: Sub-second transcription with direct streaming
- **Architecture**: `FFmpeg | whisper-stream-stdin | Python` pipeline

This breakthrough makes Earshot the **fastest local real-time transcription system** available.

## 🎯 Usage

### Access Points
- **Frontend HUD**: Launched via `.\start_frontend.ps1`
- **WebSocket Server**: `ws://localhost:9082`
- **Backend Status**: Visible in Terminal 1 logs

### Daily Workflow
```powershell
# Terminal 1: Backend
.\start_simple.ps1
# Wait for: "frontend clients: 1"

# Terminal 2: Frontend
.\start_frontend.ps1
# HUD window appears and connects
```

### Audio Setup
1. Install **VB-Audio Virtual Cable** from [vb-audio.com](https://vb-audio.com/Cable/)
2. Route desired audio to "CABLE Input"
3. System automatically captures from "CABLE Output"

## 🔧 Development & Testing

### Backend Development
```powershell
# Test all components
cd backend
python test_native_setup.py

# Run backend only
python brain_native.py --debug
```

### Frontend Development
```powershell
cd frontend
pnpm tauri dev
```

## 🐛 Troubleshooting

### System Validation
```powershell
# Run comprehensive tests
cd backend
python test_native_setup.py
```

### Common Issues
- **Backend not starting**: Check Ollama is running (`ollama serve`)
- **No audio**: Verify VB-Audio Virtual Cable installation
- **Frontend won't connect**: Ensure backend started first
- **Model errors**: Pull required model (`ollama pull llama3:8b`)
- **Whisper tool missing**: Ensure `whisper-stream-stdin.exe` is built in `backend/whisper.cpp/build/bin/Release/`
- **Slow transcription**: Verify you're using the new streaming tool, not the old CLI version

### Performance Diagnostics
```powershell
# Check if streaming tool exists
ls backend/whisper.cpp/build/bin/Release/whisper-stream-stdin.exe

# Test streaming pipeline manually
cd backend
python brain_native.py --debug

# Look for: "Starting direct audio pipeline" in logs
```

## 📁 Project Structure

```
earshot/
├── backend/
│   ├── brain_native.py          # 🧠 Main Python-native engine
│   ├── test_native_setup.py     # 🧪 System validation
│   ├── whisper.cpp/             # 🗣️ CLI tools & models
│   │   └── build/bin/Release/
│   │       └── whisper-stream-stdin.exe  # ⚡ Custom streaming tool
│   └── requirements.txt         # 📦 Dependencies
├── frontend/                    # 🎨 Tauri/React HUD
├── start_simple.ps1            # 🚀 Backend launcher
├── start_frontend.ps1          # 🖥️ Frontend launcher
└── NATIVE_ARCHITECTURE_GUIDE.md # 📖 Detailed guide
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Test your changes: `python backend/test_native_setup.py`
4. Commit changes: `git commit -m 'Add amazing feature'`
5. Push to branch: `git push origin feature/amazing-feature`
6. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

## 🙏 Acknowledgments

- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) for the foundation of our custom `whisper-stream-stdin` tool
- [Ollama](https://ollama.ai/) for local LLM inference
- [Tauri](https://tauri.app/) for cross-platform desktop applications
- The original whisper stream example for inspiration for our stdin-streaming breakthrough

---

<div align="center">

**Ready to enhance your conversations with AI assistance?**

[📖 Architecture Guide](NATIVE_ARCHITECTURE_GUIDE.md) • [🚀 Quick Start](#quick-start) • [🧪 System Test](backend/test_native_setup.py)

*Built with ❤️ for a robust, Python-native experience*

</div>
