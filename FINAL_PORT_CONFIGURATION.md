# 🔌 Final Port Configuration - Earshot Cognitive Co-Pilot

## 📋 **Standard Port Allocation**

| Component | Port | Protocol | Description |
|-----------|------|----------|-------------|
| **Whisper HTTP Server** | 9080 | HTTP | REST API for speech-to-text |
| **Whisper WebSocket** | 10080 | WebSocket | Real-time audio streaming (HTTP + 1000) |
| **Brain WebSocket Server** | 9082 | WebSocket | Cognitive engine communication |
| **Frontend Dev Server** | 3118 | HTTP | Next.js development server |
| **Ollama API** | 11434 | HTTP | LLM inference API |

## ⚙️ **Configuration Files**

### Windows (.env)
```env
COPILOT_WHISPER_HOST=127.0.0.1
COPILOT_WHISPER_PORT=9080            # HTTP server port
COPILOT_OLLAMA_HOST=127.0.0.1
COPILOT_OLLAMA_PORT=11434
COPILOT_FRONTEND_HOST=127.0.0.1
COPILOT_FRONTEND_PORT=9082           # Brain WebSocket port
```

### Linux (.copilotrc)
```bash
export COPILOT_WHISPER_HOST="127.0.0.1"
export COPILOT_WHISPER_PORT="9080"
export COPILOT_OLLAMA_HOST="127.0.0.1"
export COPILOT_OLLAMA_PORT="11434"
export COPILOT_FRONTEND_HOST="127.0.0.1"
export COPILOT_FRONTEND_PORT="9082"
```

## 🔄 **Port Calculation Logic**

### Whisper WebSocket Port
- **Formula**: `WHISPER_WS_PORT = WHISPER_HTTP_PORT + 1000`
- **Example**: HTTP 9080 → WebSocket 10080
- **Used by**: Audio pipeline (ffmpeg → websocat) and brain.py

### Process Arguments
```powershell
# Windows start_native.ps1
--whisper-port 10080    # WebSocket port passed to brain.py
--frontend-port 9082    # Brain WebSocket server port

# Linux start_copilot.sh
--whisper-port $((COPILOT_WHISPER_PORT + 1000))  # 10080
--frontend-port $COPILOT_FRONTEND_PORT           # 9082
```

## 🌐 **Access Points**

| Service | URL | Purpose |
|---------|-----|---------|
| **HUD Interface** | http://localhost:3118/hud | Main user interface |
| **Whisper Server** | http://127.0.0.1:9080 | Speech API endpoint |
| **Whisper WebSocket** | ws://127.0.0.1:10080/hot_stream | Real-time audio |
| **Brain WebSocket** | ws://127.0.0.1:9082 | Cognitive engine |
| **Ollama API** | http://127.0.0.1:11434/api | LLM inference |

## 🔧 **Audio Pipeline Flow**

```
Audio Input → FFmpeg → websocat → ws://127.0.0.1:10080/hot_stream → Whisper
                                                                       ↓
Frontend ← Brain WebSocket ← Brain.py ← Whisper WebSocket ← Transcription
ws://127.0.0.1:9082     (processes)     ws://127.0.0.1:10080
```

## 🛠️ **Troubleshooting Ports**

### Windows
```powershell
# Check all system ports
netstat -an | findstr ":9080"   # Whisper HTTP
netstat -an | findstr ":10080"  # Whisper WebSocket
netstat -an | findstr ":9082"   # Brain WebSocket
netstat -an | findstr ":3118"   # Frontend
netstat -an | findstr ":11434"  # Ollama
```

### Linux
```bash
# Check all system ports
netstat -ln | grep :9080   # Whisper HTTP
netstat -ln | grep :10080  # Whisper WebSocket
netstat -ln | grep :9082   # Brain WebSocket
netstat -ln | grep :3118   # Frontend
netstat -ln | grep :11434  # Ollama
```

## ❌ **Common Port Conflicts**

| Port | Potential Conflict | Solution |
|------|-------------------|----------|
| 9080 | Other HTTP services | Change `COPILOT_WHISPER_PORT` |
| 10080 | WebSocket services | Will auto-adjust with Whisper port |
| 9082 | Other WebSocket apps | Change `COPILOT_FRONTEND_PORT` |
| 3118 | Next.js conflicts | Modify `package.json` dev script |
| 11434 | Multiple Ollama instances | Stop other Ollama services |

## ✅ **Port Validation Checklist**

- [ ] **Whisper HTTP** (9080) - `curl http://127.0.0.1:9080/`
- [ ] **Whisper WebSocket** (10080) - Audio pipeline connects successfully
- [ ] **Brain WebSocket** (9082) - Frontend connects successfully
- [ ] **Frontend** (3118) - `curl http://localhost:3118/`
- [ ] **Ollama** (11434) - `curl http://127.0.0.1:11434/api/tags`

---

**This configuration is now standardized across Windows and Linux platforms.**