# Windows Migration Guide
# Earshot Cognitive Co-Pilot - Native Windows Implementation

## Overview

This guide provides comprehensive instructions for migrating the Earshot Cognitive Co-Pilot to a native Windows environment. This migration eliminates WSL dependencies and provides a fully native Windows experience with improved performance and stability.

## Phase 1: Clean Windows Setup

### Prerequisites
- Windows 10/11 (64-bit)
- Administrative privileges for initial setup
- Internet connection for downloads

### Fresh Repository Clone
1. Open **Git Bash** or **PowerShell**
2. Navigate to your desired project directory:
   ```bash
   cd C:\Users\%USERNAME%\Documents
   ```
3. Clone the repository:
   ```bash
   git clone https://github.com/your-fork/earshot-copilot.git
   cd earshot-copilot
   ```

## Phase 2: Complete Toolchain Installation

### Core Development Tools

#### 1. Git for Windows
- Download from: https://git-scm.com/download/win
- Provides `git` command and Git Bash terminal
- ✅ **Required**

#### 2. Python 3.10+
- Download from: https://python.org/downloads/
- ⚠️ **Important**: Check "Add Python to PATH" during installation
- ✅ **Required**

#### 3. Node.js LTS & Package Manager
- Download Node.js from: https://nodejs.org/
- Install pnpm globally: `npm install -g pnpm`
- ✅ **Required**
- **Note**: If you prefer npm or yarn: `npm install && npm run tauri build` works too

### Specialized Toolchains

#### 4. Rust Toolchain (for Tauri Desktop App)
```powershell
# Install rustup from https://rustup.rs/
# Or run in PowerShell:
Invoke-WebRequest -Uri "https://win.rustup.rs/" -OutFile "rustup-init.exe"
.\rustup-init.exe
rustup default stable

# Install Tauri CLI
cargo install tauri-cli
```
- ✅ **Required for Tauri builds**
- **Note**: Some Tauri plugins may require nightly toolchain. See [Tauri Quick Start](https://tauri.app/v1/guides/getting-started/prerequisites/) for details.

#### 5. C++ Build Tools (for Whisper.cpp)
- Download "Build Tools for Visual Studio" installer
- Select "Desktop development with C++" workload
- **Verify CMake is on your PATH**: `cmake --version`
  - If not available: `choco install cmake` or download from https://cmake.org/
- Provides MSVC compiler for CMake builds
- ✅ **Required**

#### 6. CUDA Toolkit (for GPU Acceleration)
- Download from: https://developer.nvidia.com/cuda-downloads
- Installer sets `CUDA_PATH` environment variables
- 🔧 **Optional but recommended for performance**

#### 7. WebSocket Streaming Tool (websocat)
```powershell
# Download websocat.x86_64-pc-windows-msvc.exe
# From: https://github.com/vi/websocat/releases

# Create tools directory
mkdir C:\Users\$env:USERNAME\tools
# Place websocat.exe in tools directory
# Add tools directory to System PATH
```
- ✅ **Required for audio streaming**

#### 8. FFmpeg (for Audio Processing)
- Download from: https://ffmpeg.org/download.html
- Add to System PATH
- ✅ **Required**

#### 9. Ollama (for LLM Processing)
- Download from: https://ollama.ai/
- ✅ **Required**

## Phase 3: Native Build Process

### Step 1: Environment Setup
```powershell
# Run initial setup
.\setup_windows.ps1
```

The `setup_windows.ps1` script performs these steps:
- **Dependency Verification**: Checks Python 3.10+, Node.js, Git, Rust, CUDA (optional)
- **Python Environment**: Creates `.venv` virtual environment
- **Package Installation**: Runs `pip install -r backend\requirements.txt`
- **Frontend Dependencies**: Runs `pnpm install` in frontend directory
- **Tool Validation**: Verifies websocat, ffmpeg, Ollama availability
- **Configuration Setup**: Creates `.copilotrc` from example if needed

You can also run these steps manually if preferred:
```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r backend\requirements.txt
cd frontend && pnpm install && cd ..
```

### Step 2: Build Native Components

#### Build Whisper.cpp with CUDA Support
```powershell
# Open "Developer PowerShell for VS" from Start Menu
cd backend\whisper.cpp

# Clean previous builds
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue

# Configure with CUDA (or without: -DWHISPER_CUDA=OFF)
cmake -B build -DWHISPER_CUDA=ON

# Build release version
cmake --build build --config Release
```

#### Download Whisper Model
```powershell
cd backend
.\download-ggml-model.cmd tiny.en
```

The `download-ggml-model.cmd` script:
- Downloads from HuggingFace model repositories
- Supports multiple model sizes (tiny, base, small, medium, large)
- Uses PowerShell BitsTransfer for reliable downloads
- Creates `whisper.cpp\models\ggml-[model].bin`

#### Build Tauri Desktop Application
```powershell
cd frontend
pnpm tauri build
```

### Step 3: Ollama Setup
```powershell
# Start Ollama service
ollama serve

# In another terminal, pull required models
ollama pull llama3:8b
```

## Phase 4: Running the System

### Launch the Complete System
```powershell
# From project root, run as Administrator for audio access
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\start_native.ps1
```

### System Components Started
- **Whisper Server**: Speech-to-text processing
- **Cognitive Engine**: Python backend with LLM integration
- **Frontend**: Next.js/Tauri desktop application
- **Audio Pipeline**: FFmpeg → WebSocket → Whisper streaming

### Access Points
- **HUD Interface**: http://localhost:3118/hud
- **Whisper Server**: http://127.0.0.1:9080
- **WebSocket Stream**: ws://127.0.0.1:10080/hot_stream
- **Cognitive Engine**: ws://127.0.0.1:9082

### Stopping the System
```powershell
# Graceful shutdown
.\stop_native.ps1

# Or press Ctrl+C in the main terminal
```

## Audio Configuration

### Quick Start: Direct Microphone (No Setup Required)
The system automatically falls back to your default microphone if VB-Cable is not available. This works immediately but captures all system audio including your own voice.

### Recommended: VB-Audio Virtual Cable
For clean audio capture from specific applications:
1. Download VB-Audio Virtual Cable from: https://vb-audio.com/Cable/
2. Install and restart computer
3. Set applications to output to "CABLE Input"
4. System will capture from "CABLE Output"
5. Enables selective audio routing without background noise

## Configuration

### Environment Variables

#### Option 1: PowerShell Profile (Recommended for Windows)
Add to your PowerShell `$PROFILE`:
```powershell
$Env:COPILOT_ADVISOR_MODEL = "llama3:8b"
$Env:COPILOT_CHRONICLER_ENABLED = "true"
$Env:COPILOT_WHISPER_HOST = "127.0.0.1"
$Env:COPILOT_WHISPER_PORT = "9080"
```

#### Option 2: .env File (Alternative)
Create a `.env` file in the project root:
```
COPILOT_ADVISOR_MODEL=llama3:8b
COPILOT_CHRONICLER_ENABLED=true
COPILOT_WHISPER_HOST=127.0.0.1
COPILOT_WHISPER_PORT=9080
```

#### Option 3: Git Bash + .copilotrc (Unix-style)
If using Git Bash (contradicts fully native goal):
```bash
# Copy example configuration
cp .copilotrc.example .copilotrc
# Edit with Unix-style exports
```

### PowerShell Profile (Optional)
Add to `$PROFILE` for convenient aliases:
```powershell
function Start-Earshot { .\start_native.ps1 }
function Stop-Earshot { .\stop_native.ps1 }
function Setup-Earshot { .\setup_windows.ps1 }
```

## Troubleshooting

### Critical PowerShell Issues

#### 1. "Execution Policy" Error
```powershell
# Temporary bypass (recommended)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Or per-session
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

#### 2. Audio Pipeline Failures
**If the FFmpeg→WebSocket pipe fails:**

1. **Test manually in separate admin console first:**
   ```powershell
   # Open new PowerShell as Administrator
   ffmpeg -f dshow -i audio="Microphone" -ac 1 -ar 16000 -acodec pcm_s16le -f s16le - | websocat --binary ws://127.0.0.1:10080/hot_stream
   ```

2. **Debug your quoting/escaping:**
   ```powershell
   # Test each component separately
   ffmpeg -list_devices true -f dshow -i dummy  # List audio devices
   websocat --version  # Verify websocat works
   ```

3. **Common fixes:**
   - Run PowerShell as Administrator
   - Check audio device names with spaces: `"CABLE Output (VB-Audio Virtual Cable)"`
   - Verify WebSocket server is running on port 10080

### Common Issues

#### 3. Python Virtual Environment Issues
```powershell
# Recreate virtual environment
Remove-Item -Recurse -Force .venv
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r backend\requirements.txt
```

#### 4. Whisper Build Failures
- Ensure Visual Studio Build Tools are installed
- Use "Developer PowerShell for VS"
- Check CUDA installation if using GPU acceleration
- Verify CMake is in PATH: `cmake --version`

#### 5. Audio Pipeline Issues
- **Pipeline Failure**: If FFmpeg→WebSocket pipe fails, try running manually in separate admin console first
- **Quoting Issues**: PowerShell pipe escaping can be tricky - test individual commands
- **Device Access**: Verify VB-Audio Virtual Cable installation
- **Permissions**: Check Windows audio device permissions
- **Admin Rights**: Run PowerShell as Administrator for audio access
- **Manual Pipeline Test**:
  ```powershell
  # Test in separate terminal
  ffmpeg -f dshow -i audio="Microphone" -ac 1 -ar 16000 -acodec pcm_s16le -f s16le - | websocat --binary ws://127.0.0.1:10080/hot_stream
  ```

#### 6. Port Conflicts
```powershell
# Check what's using ports
netstat -an | findstr ":9080"
netstat -an | findstr ":10080"
netstat -an | findstr ":3118"
```

#### 7. Missing Dependencies
```powershell
# Verify all tools are in PATH
python --version
node --version
pnpm --version
git --version
cmake --version
rustc --version
ffmpeg -version
websocat --version
ollama --version
```

### Performance Optimization

#### For CPU-Only Systems
```powershell
# Build without CUDA
cmake -B build -DWHISPER_CUDA=OFF
```

#### For GPU Systems
- Ensure NVIDIA drivers are up to date
- Verify CUDA installation: `nvcc --version`
- Monitor GPU usage with Task Manager

## Development Workflow

### Building Changes
```powershell
# Backend changes
cd backend
python brain.py  # Test directly

# Frontend changes
cd frontend
pnpm dev  # Development server

# Tauri changes
pnpm tauri dev  # Development with hot reload
```

### Debugging
- Backend logs: `backend\brain.log`
- Whisper logs: Available in console output
- Frontend logs: Browser Developer Tools
- System logs: Windows Event Viewer

## Migration Benefits

- **Native Performance**: No WSL translation layer
- **Better Hardware Access**: Direct GPU and audio device access
- **Simplified Deployment**: Single-platform executable
- **Windows Integration**: Native notifications and system tray
- **Improved Stability**: Reduced cross-platform compatibility issues

## Support

For issues specific to the Windows migration:
1. Check this guide for common solutions
2. Verify all dependencies are properly installed
3. Ensure proper PowerShell execution policy
4. Check Windows Defender/antivirus interference

---

**System Requirements Summary:**
- Windows 10/11 (64-bit)
- 8GB+ RAM (16GB recommended)
- NVIDIA GPU (optional, for CUDA acceleration)
- Audio input device or VB-Audio Virtual Cable
- ~5GB disk space for toolchain and models