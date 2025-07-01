# 🧠 Earshot Cognitive Co-Pilot

> **Python-Native Real-time AI Assistant for Live Audio Streams**

A streamlined cognitive co-pilot system that provides intelligent, context-aware assistance during conversations, meetings, and presentations. Built with a robust Python-native architecture that eliminates complex dependencies and Just Works™ on Windows.

[![Windows Native](https://img.shields.io/badge/Windows-Native-blue?logo=windows&logoColor=white)](#)
[![Python](https://img.shields.io/badge/Python-3.10+-blue?logo=python&logoColor=white)](#)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

## ✨ Features

- **🎤 Real-time Audio Processing**: Live transcription using Whisper CLI with subprocess management
- **🧠 Intelligent Question Detection**: AI-powered regex patterns for instant question recognition
- **💡 Contextual Assistance**: LLM-powered responses using Ollama with conversation memory
- **🌐 WebSocket Integration**: Real-time communication with frontend HUD interface
- **🖥️ Windows Native**: Robust, simplified architecture with zero C++ networking issues
- **🔒 Privacy-First**: All processing happens locally - no cloud dependencies
- **⚡ Low Latency**: Sub-second response times with optimized Python pipeline
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

## 🏗️ Python-Native Architecture

```
Backend (Headless)          Frontend (Visual)
├── 🎤 Audio (ffmpeg)       ├── 🪟 Tauri HUD Window
├── 🗣️ Whisper CLI          ├── ⚡ React UI
├── 🤖 Chronicler           ├── 🔌 WebSocket Client
├── 💡 Advisor (Ollama)     └── 🎯 Overlay Display
├── 🌐 WebSocket Server
└── 📊 Process Management
```

### Strategic Pivot Benefits

- **🚫 ZERO C++ networking issues** - All handled in Python
- **🔧 Robust process management** - Python asyncio handles everything
- **🐛 Simpler debugging** - One backend log stream
- **🏗️ Modular design** - Backend/frontend completely separate
- **🪟 Windows native** - No cross-platform compatibility hell

## 🔧 Configuration

The system uses sensible defaults. Optional customization via environment variables:

```env
COPILOT_ADVISOR_MODEL=llama3:8b
COPILOT_CHRONICLER_ENABLED=true
OLLAMA_HOST=127.0.0.1
OLLAMA_PORT=11434
```

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

## 📁 Project Structure

```
earshot/
├── backend/
│   ├── brain_native.py          # 🧠 Main Python-native engine
│   ├── test_native_setup.py     # 🧪 System validation
│   ├── whisper.cpp/             # 🗣️ CLI tools & models
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

- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) for local speech recognition
- [Ollama](https://ollama.ai/) for local LLM inference
- [Tauri](https://tauri.app/) for cross-platform desktop applications

---

<div align="center">

**Ready to enhance your conversations with AI assistance?**

[📖 Architecture Guide](NATIVE_ARCHITECTURE_GUIDE.md) • [🚀 Quick Start](#quick-start) • [🧪 System Test](backend/test_native_setup.py)

*Built with ❤️ for a robust, Python-native experience*

</div>
