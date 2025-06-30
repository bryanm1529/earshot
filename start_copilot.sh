#!/bin/bash

# Sprint 9: The Final Wire-Up - Robust System Launcher
# Starts the complete Earshot Cognitive Co-Pilot system with resilient process management

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Process tracking
WHISPER_PID=""
OLLAMA_PID=""
BRAIN_PID=""
FRONTEND_PID=""

# Cleanup function for proper shutdown
cleanup() {
    echo -e "\n${YELLOW}🛑 Shutting down Cognitive Co-Pilot system...${NC}"

    # Kill processes in reverse order
    if [ ! -z "$FRONTEND_PID" ] && kill -0 $FRONTEND_PID 2>/dev/null; then
        echo "Stopping frontend (PID: $FRONTEND_PID)..."
        kill -TERM $FRONTEND_PID 2>/dev/null || true
    fi

    if [ ! -z "$BRAIN_PID" ] && kill -0 $BRAIN_PID 2>/dev/null; then
        echo "Stopping brain.py (PID: $BRAIN_PID)..."
        kill -TERM $BRAIN_PID 2>/dev/null || true
    fi

    if [ ! -z "$WHISPER_PID" ] && kill -0 $WHISPER_PID 2>/dev/null; then
        echo "Stopping whisper server (PID: $WHISPER_PID)..."
        kill -TERM $WHISPER_PID 2>/dev/null || true
    fi

    # Note: We don't kill Ollama as it might be used by other applications

    # Wait for graceful shutdown
    sleep 2

    # Force kill if necessary
    for pid in $FRONTEND_PID $BRAIN_PID $WHISPER_PID; do
        if [ ! -z "$pid" ] && kill -0 $pid 2>/dev/null; then
            echo "Force killing process $pid..."
            kill -KILL $pid 2>/dev/null || true
        fi
    done

    echo -e "${GREEN}✅ System shutdown complete${NC}"
    exit 0
}

# Set up signal handlers for clean shutdown
trap cleanup INT TERM

# Banner
echo -e "${BLUE}"
echo "=================================================="
echo "🧠 Earshot Cognitive Co-Pilot System"
echo "   Sprint 9: The Final Wire-Up"
echo "=================================================="
echo -e "${NC}"

# Check for .copilotrc configuration
if [ -f ".copilotrc" ]; then
    echo -e "${GREEN}📋 Loading configuration from .copilotrc${NC}"
    source .copilotrc
    echo "   Configuration loaded successfully"
else
    echo -e "${YELLOW}📋 No .copilotrc found, using defaults${NC}"
fi

# Set default configuration if not specified
export COPILOT_ADVISOR_MODEL="${COPILOT_ADVISOR_MODEL:-llama3:8b}"
export COPILOT_CHRONICLER_ENABLED="${COPILOT_CHRONICLER_ENABLED:-true}"
export COPILOT_WHISPER_HOST="${COPILOT_WHISPER_HOST:-127.0.0.1}"
export COPILOT_WHISPER_PORT="${COPILOT_WHISPER_PORT:-9080}"
export COPILOT_OLLAMA_HOST="${COPILOT_OLLAMA_HOST:-127.0.0.1}"
export COPILOT_OLLAMA_PORT="${COPILOT_OLLAMA_PORT:-11434}"
export COPILOT_FRONTEND_HOST="${COPILOT_FRONTEND_HOST:-127.0.0.1}"
export COPILOT_FRONTEND_PORT="${COPILOT_FRONTEND_PORT:-9082}"

echo -e "${BLUE}🔧 Configuration:${NC}"
echo "   Advisor Model: $COPILOT_ADVISOR_MODEL"
echo "   Chronicler: $COPILOT_CHRONICLER_ENABLED"
echo "   Whisper: $COPILOT_WHISPER_HOST:$COPILOT_WHISPER_PORT"
echo "   Ollama: $COPILOT_OLLAMA_HOST:$COPILOT_OLLAMA_PORT"
echo "   Frontend WebSocket: $COPILOT_FRONTEND_HOST:$COPILOT_FRONTEND_PORT"

# Check dependencies
echo -e "\n${BLUE}🔍 Checking dependencies...${NC}"

# Check if Ollama is running
if ! curl -s "http://$COPILOT_OLLAMA_HOST:$COPILOT_OLLAMA_PORT/api/tags" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Ollama not running, starting...${NC}"
    if command -v ollama > /dev/null 2>&1; then
        ollama serve > /dev/null 2>&1 &
        OLLAMA_PID=$!
        echo "   Ollama started (PID: $OLLAMA_PID)"
        sleep 3
    else
        echo -e "${RED}❌ Ollama not found. Please install Ollama first.${NC}"
        exit 1
    fi
else
    echo "   ✅ Ollama is running"
fi

# Check for required models
echo -e "${BLUE}📦 Checking models...${NC}"
if ! curl -s "http://$COPILOT_OLLAMA_HOST:$COPILOT_OLLAMA_PORT/api/tags" | grep -q "$COPILOT_ADVISOR_MODEL"; then
    echo -e "${YELLOW}⚠️  Model $COPILOT_ADVISOR_MODEL not found, pulling...${NC}"
    ollama pull "$COPILOT_ADVISOR_MODEL"
fi
echo "   ✅ Model $COPILOT_ADVISOR_MODEL available"

# Check for whisper model
WHISPER_MODEL_PATH="backend/whisper-custom/server/models/ggml-tiny.en-q5_1.bin"
if [ ! -f "$WHISPER_MODEL_PATH" ]; then
    echo -e "${RED}❌ Whisper model not found at $WHISPER_MODEL_PATH${NC}"
    echo "   Please run the model download script first"
    exit 1
fi
echo "   ✅ Whisper model available"

# Start services
echo -e "\n${BLUE}🚀 Starting services...${NC}"

# 1. Start Whisper Server
echo "1. Starting Whisper server..."
cd backend/whisper-custom/server
export LD_LIBRARY_PATH=../../whisper.cpp/build/src:../../whisper.cpp/build/ggml/src:$LD_LIBRARY_PATH
./whisper-server-ws-final \
    --model models/ggml-tiny.en-q5_1.bin \
    --port $COPILOT_WHISPER_PORT \
    --host $COPILOT_WHISPER_HOST \
    --threads 2 > whisper-server.log 2>&1 &
WHISPER_PID=$!
cd ../../..
echo "   Whisper server started (PID: $WHISPER_PID)"

# Wait for whisper server to be ready
echo "   Waiting for Whisper server to initialize..."
for i in {1..30}; do
    if curl -s "http://$COPILOT_WHISPER_HOST:$COPILOT_WHISPER_PORT/" > /dev/null 2>&1; then
        echo "   ✅ Whisper server ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ Whisper server failed to start${NC}"
        cleanup
        exit 1
    fi
    sleep 1
done

# 2. Start Brain.py (Cognitive Engine)
echo "2. Starting Cognitive Engine..."
cd backend
python3 brain.py \
    --whisper-host $COPILOT_WHISPER_HOST \
    --whisper-port $((COPILOT_WHISPER_PORT + 1000)) \
    --ollama-host $COPILOT_OLLAMA_HOST \
    --ollama-port $COPILOT_OLLAMA_PORT \
    --frontend-host $COPILOT_FRONTEND_HOST \
    --frontend-port $COPILOT_FRONTEND_PORT > brain.log 2>&1 &
BRAIN_PID=$!
cd ..
echo "   Cognitive Engine started (PID: $BRAIN_PID)"

# Wait for brain to be ready
echo "   Waiting for Cognitive Engine to initialize..."
for i in {1..20}; do
    if netstat -ln 2>/dev/null | grep -q ":$COPILOT_FRONTEND_PORT " || ss -ln 2>/dev/null | grep -q ":$COPILOT_FRONTEND_PORT "; then
        echo "   ✅ Cognitive Engine ready"
        break
    fi
    if [ $i -eq 20 ]; then
        echo -e "${RED}❌ Cognitive Engine failed to start${NC}"
        cleanup
        exit 1
    fi
    sleep 1
done

# 3. Start Frontend (if not already running)
echo "3. Starting Frontend..."
cd frontend
if ! pgrep -f "next dev" > /dev/null; then
    npm run dev > frontend.log 2>&1 &
    FRONTEND_PID=$!
    echo "   Frontend started (PID: $FRONTEND_PID)"

    # Wait for frontend to be ready
    echo "   Waiting for Frontend to initialize..."
    for i in {1..30}; do
        if curl -s "http://localhost:3000" > /dev/null 2>&1; then
            echo "   ✅ Frontend ready"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${YELLOW}⚠️  Frontend may not be ready, continuing...${NC}"
        fi
        sleep 1
    done
else
    echo "   ✅ Frontend already running"
fi
cd ..

# System ready
echo -e "\n${GREEN}🎉 Cognitive Co-Pilot System is READY!${NC}"
echo -e "${BLUE}=================================================="
echo "🌐 Access Points:"
echo "   HUD Interface: http://localhost:3000/hud"
echo "   Whisper Server: http://$COPILOT_WHISPER_HOST:$COPILOT_WHISPER_PORT"
echo "   WebSocket Streaming: ws://$COPILOT_WHISPER_HOST:$((COPILOT_WHISPER_PORT + 1000))/hot_stream"
echo "   Cognitive Engine: ws://$COPILOT_FRONTEND_HOST:$COPILOT_FRONTEND_PORT"
echo ""
echo "🎮 Controls:"
echo "   Pause/Resume: Press Caps Lock in HUD"
echo "   Stop System: Press Ctrl+C in this terminal"
echo ""
echo "📊 Process IDs:"
echo "   Whisper Server: $WHISPER_PID"
echo "   Cognitive Engine: $BRAIN_PID"
echo "   Frontend: $FRONTEND_PID"
echo "   Ollama: $OLLAMA_PID"
echo "=================================================="
echo -e "${NC}"

# Keep the script running and monitor processes
echo -e "${BLUE}🔄 System monitoring active. Press Ctrl+C to stop.${NC}"

while true; do
    # Check if critical processes are still running
    if [ ! -z "$WHISPER_PID" ] && ! kill -0 $WHISPER_PID 2>/dev/null; then
        echo -e "${RED}❌ Whisper server died unexpectedly${NC}"
        break
    fi

    if [ ! -z "$BRAIN_PID" ] && ! kill -0 $BRAIN_PID 2>/dev/null; then
        echo -e "${RED}❌ Cognitive Engine died unexpectedly${NC}"
        break
    fi

    sleep 5
done

# If we get here, something went wrong
cleanup