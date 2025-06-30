## 🔧 Port Configuration Summary

**Standard Port Allocation:**
- **Whisper HTTP Server**: 9080
- **Whisper WebSocket**: 10080 (calculated as HTTP + 1000)
- **Brain WebSocket Server**: 9082  
- **Frontend Dev Server**: 3118
- **Ollama API**: 11434

**Windows Configuration (.env):**
```
COPILOT_WHISPER_PORT=9080        # HTTP server
COPILOT_FRONTEND_PORT=9082       # Brain WebSocket
```

**Linux Configuration (.copilotrc):**
```bash
export COPILOT_WHISPER_PORT="9080"
export COPILOT_FRONTEND_PORT="9082"
```

**Audio Pipeline:**
- FFmpeg captures audio
- websocat sends to: ws://127.0.0.1:10080/hot_stream
- Brain connects to same WebSocket for transcription
