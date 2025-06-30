#!/bin/bash

# Sprint 6: The Cognitive Engine Launch Configuration
# Complete system startup for real-time conversational assistance

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[LAUNCH]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
WHISPER_MODEL="models/ggml-tiny.en-q5_1.bin"
WHISPER_HOST="127.0.0.1"
WHISPER_PORT="8178"
OLLAMA_HOST="127.0.0.1"
OLLAMA_PORT="11434"
BACKEND_THREADS=2
GPU_LAYERS_WHISPER=18
GPU_LAYERS_OLLAMA=32

# Check dependencies
check_dependencies() {
    log_info "Checking Sprint 6 dependencies..."

    # Check if whisper server exists
    if [ ! -f "whisper-server-package/whisper-server" ]; then
        log_error "Whisper server not found. Run build_whisper.sh first."
        exit 1
    fi

    # Check if models exist
    if [ ! -f "whisper-server-package/$WHISPER_MODEL" ]; then
        log_error "Whisper model not found: $WHISPER_MODEL"
        exit 1
    fi

    # Check if ollama is installed
    if ! command -v ollama &> /dev/null; then
        log_error "Ollama not installed. Please install Ollama first."
        exit 1
    fi

    # Check if Python dependencies are available
    if [ ! -f "brain.py" ]; then
        log_error "Cognitive engine (brain.py) not found."
        exit 1
    fi

    log_success "All dependencies checked"
}

# Start Whisper server
start_whisper() {
    log_info "Starting Whisper server with Sprint 5 optimizations..."

    cd whisper-server-package

    # Sprint 6: GPU configuration for dual model setup
    export CUDA_VISIBLE_DEVICES=0

    ./whisper-server \
        --model "$WHISPER_MODEL" \
        --host "$WHISPER_HOST" \
        --port "$WHISPER_PORT" \
        --backend cuda \
        --step-ms 256 \
        --length-ms 2000 \
        --keep-ms 0 \
        --n-gpu-layers "$GPU_LAYERS_WHISPER" \
        --use-gpu true \
        --no-timestamps \
        --threads "$BACKEND_THREADS" &

    WHISPER_PID=$!
    cd ..

    log_info "Whisper server starting (PID: $WHISPER_PID)..."
    sleep 3

    # Verify whisper server is running
    if curl -s "http://$WHISPER_HOST:$WHISPER_PORT/" > /dev/null 2>&1; then
        log_success "Whisper server running at http://$WHISPER_HOST:$WHISPER_PORT"
    else
        log_error "Failed to start Whisper server"
        exit 1
    fi
}

# Start Ollama server with models
start_ollama() {
    log_info "Starting Ollama server with Llama-3 8B..."

    # Check if ollama daemon is running
    if ! pgrep -f "ollama serve" > /dev/null; then
        log_info "Starting Ollama daemon..."
        ollama serve &
        OLLAMA_DAEMON_PID=$!
        sleep 5
    else
        log_info "Ollama daemon already running"
    fi

    # Sprint 6: Pull required models if not available
    log_info "Ensuring required models are available..."

    # Pull Llama-3 8B for Advisor
    if ! ollama list | grep -q "llama3:8b-instruct-q4_k_m"; then
        log_info "Pulling Llama-3 8B model (this may take a while)..."
        ollama pull llama3:8b-instruct-q4_k_m
    fi

    # Pull Phi-3 mini for Chronicler
    if ! ollama list | grep -q "phi3:mini-instruct-q4"; then
        log_info "Pulling Phi-3 mini model..."
        ollama pull phi3:mini-instruct-q4
    fi

    log_success "Ollama server ready at http://$OLLAMA_HOST:$OLLAMA_PORT"
}

# Start cognitive engine
start_cognitive_engine() {
    log_info "Starting Cognitive Engine..."

    # Sprint 6: Start the brain with proper configuration
    python3 brain.py \
        --whisper-host "$WHISPER_HOST" \
        --whisper-port "$WHISPER_PORT" \
        --ollama-host "$OLLAMA_HOST" \
        --ollama-port "$OLLAMA_PORT" \
        --websocket "ws://localhost:8080" \
        --debug &

    BRAIN_PID=$!

    log_success "Cognitive Engine started (PID: $BRAIN_PID)"
}

# Monitor system health
monitor_system() {
    log_info "Monitoring system health..."

    while true; do
        sleep 30

        # Check Whisper server
        if ! curl -s "http://$WHISPER_HOST:$WHISPER_PORT/" > /dev/null 2>&1; then
            log_error "Whisper server down!"
            break
        fi

        # Check Ollama server
        if ! curl -s "http://$OLLAMA_HOST:$OLLAMA_PORT/api/tags" > /dev/null 2>&1; then
            log_error "Ollama server down!"
            break
        fi

        # Check cognitive engine
        if ! kill -0 "$BRAIN_PID" 2>/dev/null; then
            log_error "Cognitive engine stopped!"
            break
        fi

        log_info "System health: OK"
    done
}

# Cleanup on exit
cleanup() {
    log_info "Shutting down Sprint 6 system..."

    # Kill cognitive engine
    if [ ! -z "$BRAIN_PID" ]; then
        kill "$BRAIN_PID" 2>/dev/null || true
    fi

    # Kill whisper server
    if [ ! -z "$WHISPER_PID" ]; then
        kill "$WHISPER_PID" 2>/dev/null || true
    fi

    # Kill ollama daemon if we started it
    if [ ! -z "$OLLAMA_DAEMON_PID" ]; then
        kill "$OLLAMA_DAEMON_PID" 2>/dev/null || true
    fi

    log_success "System shutdown complete"
}

# Main launch sequence
main() {
    echo "🧠 Sprint 6: The Cognitive Engine"
    echo "=================================="
    echo "Starting complete system for real-time conversational assistance"
    echo ""

    # Set cleanup trap
    trap cleanup EXIT

    # Check dependencies
    check_dependencies

    # Start components in order
    start_whisper
    start_ollama
    start_cognitive_engine

    echo ""
    log_success "🚀 Sprint 6 System Launched!"
    echo ""
    echo "Available endpoints:"
    echo "  Whisper Hot Stream:  http://$WHISPER_HOST:$WHISPER_PORT/hot_stream"
    echo "  Whisper Cold Path:   http://$WHISPER_HOST:$WHISPER_PORT/inference"
    echo "  Ollama API:          http://$OLLAMA_HOST:$OLLAMA_PORT"
    echo "  Cognitive Engine:    Running with debug output"
    echo ""
    echo "System is ready for testing!"
    echo "Press Ctrl+C to shutdown..."

    # Monitor and wait
    monitor_system
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    cd "$(dirname "$0")"
    main "$@"
fi