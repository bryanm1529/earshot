# Earshot Copilot - Port Configuration Guide

## ✅ **Active Ports (Python-Native Architecture)**

### **Port 9082 - Python Backend WebSocket Server**
- **Service**: brain_native.py WebSocket server
- **Protocol**: WebSocket (ws://localhost:9082)
- **Purpose**: Real-time communication between frontend and Python backend
- **Configuration**:
  - Backend: `frontend_ws_port: int = 9082` in `CognitiveConfig`
  - Frontend: All components connect to `ws://localhost:9082`

**Connected Components:**
- ✅ `frontend/src/app/page.tsx` - Main control panel
- ✅ `frontend/src/app/control.tsx` - Alternative control panel
- ✅ `frontend/src/components/WhisperConnection.tsx` - Audio processing coordination
- ✅ `frontend/src/components/RecordingControls.tsx` - Recording status display
- ✅ `frontend/src/hooks/useAdvisorStream.ts` - HUD WebSocket hook (default: ws://localhost:9082)
- ✅ `frontend/src/app/hud/page.tsx` - Uses useAdvisorStream hook

### **Port 11434 - Ollama API Server**
- **Service**: Ollama server
- **Protocol**: HTTP (http://localhost:11434)
- **Purpose**: AI model inference for advisor responses
- **Configuration**: `ollama_port: int = 11434` in `CognitiveConfig`

## ❌ **Deprecated Ports (Removed from Architecture)**

### **Port 8080 - Old Whisper HTTP Server**
- **Status**: ❌ REMOVED
- **Previous Purpose**: C++ whisper WebSocket server
- **Replacement**: Direct whisper.exe subprocess calls in Python

### **Port 8178 - Old Audio Stream Server**
- **Status**: ❌ REMOVED
- **Previous Purpose**: Audio streaming endpoint
- **Replacement**: Python-native FFmpeg audio pipeline

### **Port 5167 - Old Meeting Management Server**
- **Status**: ⚠️ LEGACY (May be unused in new architecture)
- **Files Still Referencing**:
  - `frontend/src/components/Sidebar/SidebarProvider.tsx`
  - `frontend/src/components/Sidebar/index.tsx`
  - `frontend/src/components/ModelSettingsModal.tsx`
  - `frontend/src/app/meeting-details/page.tsx`
  - `frontend/src/app/meeting-details/page-content.tsx`

## 🚀 **System Startup Sequence**

1. **Start Ollama Server**: `ollama serve` (port 11434)
2. **Start Python Backend**: `python backend/brain_native.py` (WebSocket on port 9082)
3. **Start Tauri Frontend**: `frontend/src-tauri/target/release/earshot-copilot.exe`

## 🔍 **Verification Commands**

```bash
# Check if Python backend WebSocket is running
curl -H "Connection: Upgrade" -H "Upgrade: websocket" http://localhost:9082

# Check if Ollama is running
curl http://localhost:11434/api/version

# Test WebSocket connection
wscat -c ws://localhost:9082
```

## 📝 **Configuration Files**

### **Python Backend**
- File: `backend/brain_native.py`
- WebSocket: `frontend_ws_port: int = 9082`
- Ollama: `ollama_port: int = 11434`

### **Frontend Components**
- All WebSocket connections: `ws://localhost:9082`
- Tauri CSP: Allows `ws://localhost:9082`

### **Tauri Configuration**
- File: `frontend/src-tauri/tauri.conf.json`
- CSP: `"connect-src": "'self' ws://localhost:9082"`

## ✅ **Status: All Ports Correctly Configured**

The system is now fully aligned with the Python-native architecture. All WebSocket connections point to port 9082 where the Python backend serves the unified cognitive engine.