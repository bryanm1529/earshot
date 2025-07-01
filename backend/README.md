# Earshot Cognitive Backend

Python-native real-time AI assistant with stdin-Stream Architecture

> **For complete setup instructions, see the main [README.md](../README.md)**
> This document covers backend-specific technical details.

## Features
- ⚡ **High-Performance Streaming**: Custom `whisper-stream-stdin` tool for true real-time transcription
- 🎤 **Zero-Latency Audio Processing**: Direct FFmpeg → Whisper pipeline eliminates file I/O bottlenecks
- 🧠 **Intelligent Question Detection**: AI-powered regex patterns for instant question recognition
- 💡 **Contextual Assistance**: LLM-powered responses using Ollama with conversation memory
- 🌐 **WebSocket Integration**: Real-time communication with frontend HUD interface
- 🚫 **No Temporary Files**: Pure in-memory streaming for maximum performance

## Requirements
- **Python 3.10+** (with PATH configuration)
- **FFmpeg** (for audio capture)
- **C++ compiler** (for building custom whisper-stream-stdin tool)
- **CMake** (for Whisper.cpp build system)
- **Git** (for submodules)
- **Ollama** (for local LLM inference)
- **VB-Audio Virtual Cable** (for audio routing)

## Installation

### Prerequisites Installation

#### For Windows:
1. **Python 3.9+**:
   - Download and install from [Python.org](https://www.python.org/downloads/)
   - Ensure you check "Add Python to PATH" during installation
   - Verify installation: `python --version`

2. **FFmpeg**:
   - Download from [FFmpeg.org](https://ffmpeg.org/download.html) or install via [Chocolatey](https://chocolatey.org/): `choco install ffmpeg`
   - Add FFmpeg to your PATH environment variable
   - Verify installation: `ffmpeg -version`

3. **C++ Compiler**:
   - Install Visual Studio Build Tools from [Microsoft](https://visualstudio.microsoft.com/visual-cpp-build-tools/)
   - Select "Desktop development with C++" workload during installation
   - Verify installation: `cl` (should show the compiler version)

4. **CMake**:
   - Download and install from [CMake.org](https://cmake.org/download/)
   - Ensure you select "Add CMake to the system PATH" during installation
   - Verify installation: `cmake --version`

5. **Git**:
   - Download and install from [Git-scm.com](https://git-scm.com/download/win)
   - Verify installation: `git --version`

6. **Ollama**:
   - Download and install from [Ollama.com](https://ollama.com/download)
   - Start Ollama service
   - Pull required models: `ollama pull mistral` (or your preferred model)
   - Verify installation: `ollama list`

#### For macOS:
1. **Python 3.9+**:
   - Install via Homebrew: `brew install python@3.9`
   - Or download from [Python.org](https://www.python.org/downloads/)
   - Verify installation: `python3 --version`

2. **FFmpeg**:
   - Install via Homebrew: `brew install ffmpeg`
   - Verify installation: `ffmpeg -version`

3. **C++ Compiler**:
   - Install Xcode Command Line Tools: `xcode-select --install`
   - Verify installation: `clang --version`

4. **CMake**:
   - Install via Homebrew: `brew install cmake`
   - Verify installation: `cmake --version`

5. **Git**:
   - Install via Homebrew: `brew install git`
   - Or install Xcode Command Line Tools: `xcode-select --install`
   - Verify installation: `git --version`

6. **Ollama**:
   - Install via Homebrew: `brew install ollama`
   - Or download from [Ollama.com](https://ollama.com/download)
   - Start Ollama service: `ollama serve`
   - Pull required models: `ollama pull mistral` (or your preferred model)
   - Verify installation: `ollama list`



### 2. Python Dependencies
Install Python dependencies:

#### For Windows:
```cmd
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

#### For macOS:
```bash
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt
```

### 3. Build Custom Whisper Streaming Tool

The custom `whisper-stream-stdin` tool is the core breakthrough that enables true real-time transcription:

#### For Windows:
```powershell
cd whisper.cpp
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
cmake -B build -DWHISPER_CUDA=ON -DWHISPER_BUILD_EXAMPLES=ON
cmake --build build --config Release
```

#### Verify the build:
```powershell
ls whisper.cpp/build/bin/Release/whisper-stream-stdin.exe
```

This creates the custom streaming tool that eliminates file I/O bottlenecks for true real-time performance.

### 4. Running the Python-Native Backend

#### Quick Start:
```powershell
# Start the cognitive engine with stdin-streaming
python brain_native.py --debug
```

#### What happens:
1. **Direct Streaming Pipeline**: FFmpeg → whisper-stream-stdin → Python
2. **WebSocket Server**: Starts on `ws://localhost:9082` for frontend communication
3. **Real-time Processing**: Sub-second transcription with zero file I/O
4. **LLM Integration**: Ollama-powered contextual assistance

#### Production Usage:
```powershell
# From project root
.\start_simple.ps1     # Starts backend in production mode
```

#### Logs you'll see:
```
🎙️ Starting direct audio pipeline:
  FFmpeg: ffmpeg -f dshow -i audio=CABLE Output...
  Whisper: whisper-stream-stdin.exe -m model.bin...
🌐 Frontend WebSocket server started on ws://localhost:9082
📝 Real-time transcript: [live audio appears here]
```

## Architecture Overview

### stdin-Stream Pipeline
```
FFmpeg → whisper-stream-stdin.exe → Python → WebSocket → Frontend
   ↓           ↓                      ↓         ↓          ↓
Audio      Real-time              Callback  Broadcast   HUD
Capture    Transcription         Processing  Response   Display
```

## Services
The backend runs a unified Python-native service:
1. **Audio Pipeline**: Direct FFmpeg → whisper-stream-stdin streaming
2. **Cognitive Engine**: Question detection, context management, LLM integration
3. **WebSocket Server**: Real-time communication with frontend on `ws://localhost:9082`
4. **Process Management**: Robust subprocess handling with automatic restart

## Platform-Specific Information

### Windows
- The Windows scripts create separate command windows for each service, allowing you to see the output in real-time
- You can check the status of services using `check_status.cmd`
- If you prefer to start services individually:
  - `start_whisper_server.cmd [model]` - Starts just the Whisper server
  - `start_python_backend.cmd [port]` - Starts just the Python backend

### macOS
- The macOS scripts run services in the foreground by default
- To run services in the background, you can use:
  ```bash
  nohup ./whisper-server/whisper-server -m ./models/ggml-base.en.bin -p 8178 > whisper.log 2>&1 &
  nohup uvicorn main:app --host 0.0.0.0 --port 5167 > backend.log 2>&1 &
  ```
- To check running services: `ps aux | grep -E "whisper-server|uvicorn"`
- To view logs: `tail -f whisper.log` or `tail -f backend.log`

## Troubleshooting

### Common Issues on Windows
- If you see "whisper-server.exe not found", run `build_whisper.cmd` first
- If a model fails to download, try running `download-ggml-model.cmd [model]` directly
- If services don't start, check if ports 8178 (Whisper) and 5167 (Backend) are available
- Ensure you have administrator privileges when running the scripts
- If PowerShell script execution is blocked, run PowerShell as administrator and use:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
  ```
- If you encounter "Access is denied" errors, try running Command Prompt as administrator
- For Visual Studio Build Tools issues, try reinstalling with the correct C++ components
- If CMake can't find the compiler, ensure Visual Studio Build Tools are properly installed and PATH variables are set

### Common Issues on macOS
- If scripts fail with "Permission denied", run `chmod +x script_name.sh` to make them executable
- If you see "command not found: python", use `python3` instead
- If building Whisper fails with compiler errors, ensure Xcode Command Line Tools are installed
- For "Port already in use" errors, find and kill the process using:
  ```bash
  lsof -i :5167  # For backend port
  lsof -i :8178  # For Whisper server port
  kill -9 PID    # Replace PID with the actual process ID
  ```
- If Ollama fails to start, check if the service is running with `ps aux | grep ollama`
- For library loading issues, ensure all dependencies are properly installed
- If you encounter "xcrun: error", reinstall the Xcode Command Line Tools:
  ```bash
  xcode-select --install
  ```
- For M1/M2 Macs, ensure you're using ARM-compatible versions of software

### General Troubleshooting
- If services fail to start, the script will automatically clean up processes
- Check logs for detailed error messages
- Ensure all ports (5167 for backend, 8178 for Whisper) are available
- Verify API keys if using Claude or Groq
- For Ollama, ensure the Ollama service is running and models are pulled
- If build fails:
  - Ensure all dependencies (CMake, C++ compiler) are installed
  - Check if git submodules are properly initialized
  - Verify you have write permissions in the directory

## stdin-Stream Configuration

The Cognitive Engine (`brain_native.py`) supports the following configuration options:

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `COPILOT_ADVISOR_MODEL` | `llama3:8b` | Ollama model for real-time question answering |
| `COPILOT_CHRONICLER_ENABLED` | `true` | Enable/disable context management system |

### Example Usage

```bash
# Use a faster model for better performance
export COPILOT_ADVISOR_MODEL="phi3:mini"

# Disable context management for testing
export COPILOT_CHRONICLER_ENABLED="false"

# Start the cognitive engine
python brain_native.py --debug
```

### Configuration Verification

On startup, the brain_native.py script logs the effective configuration:

```
🔧 Native Config: Advisor model=llama3:8b
🔧 Audio device: CABLE Output (VB-Audio Virtual Cable)
🔧 Whisper model: whisper.cpp/models/for-tests-ggml-tiny.en.bin
```

### Performance Targets

- **Transcription Latency**: <1 second (achieved with stdin-streaming)
- **Response Time**: <700ms for LLM responses
- **Accuracy**: >50% keyword match rate
- **Reliability**: >80% successful response rate

### Integration Status

✅ **stdin-Stream Architecture**: Custom whisper tool eliminates file I/O bottlenecks
✅ **Ollama Integration**: Real LLM responses with bullet-point formatting
✅ **Direct Audio Pipeline**: FFmpeg → whisper-stream-stdin → Python streaming
✅ **WebSocket Communication**: Real-time frontend integration
✅ **Context Management**: Rolling conversation history with intelligent processing
✅ **Performance Achievement**: Sub-second transcription with zero temporary files
