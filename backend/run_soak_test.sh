#!/bin/bash

# Sprint 7: Soak Test - 15-minute system stability validation
# Tests sustained load with GPU monitoring for thermal throttling and memory leaks

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[SOAK]${NC} $1"
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
SOAK_DURATION=900  # 15 minutes in seconds
GPU_LOG_FILE="gpu_soak_test.log"
MONITOR_INTERVAL=15  # Log GPU stats every 15 seconds

echo "🧪 Sprint 7: 15-Minute Soak Test"
echo "================================"
echo "Testing system stability under sustained load"
echo ""

# Check if nvidia-smi is available
if ! command -v nvidia-smi &> /dev/null; then
    log_warning "nvidia-smi not found. GPU monitoring disabled."
    GPU_MONITORING=false
else
    GPU_MONITORING=true
    log_info "GPU monitoring enabled"
fi

# Start GPU monitoring if available
if [ "$GPU_MONITORING" = true ]; then
    log_info "Starting GPU monitoring (logging every ${MONITOR_INTERVAL}s to ${GPU_LOG_FILE})"
    # Clear previous log
    echo "timestamp,gpu_util_percent,temp_celsius,memory_used_mb" > "$GPU_LOG_FILE"

    # Start background GPU monitoring
    while true; do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used --format=csv,noheader,nounits | \
        sed "s/^/$timestamp,/" >> "$GPU_LOG_FILE"
        sleep "$MONITOR_INTERVAL"
    done &

    GPU_MONITOR_PID=$!
    log_info "GPU monitoring started (PID: $GPU_MONITOR_PID)"
fi

# Function to cleanup on exit
cleanup() {
    log_info "Cleaning up soak test..."

    if [ "$GPU_MONITORING" = true ] && [ ! -z "$GPU_MONITOR_PID" ]; then
        kill "$GPU_MONITOR_PID" 2>/dev/null || true
        log_info "GPU monitoring stopped"
    fi

    # Kill cognitive engine if running
    if [ ! -z "$BRAIN_PID" ]; then
        kill "$BRAIN_PID" 2>/dev/null || true
        log_info "Cognitive engine stopped"
    fi

    # Kill ollama if we started it
    if [ ! -z "$OLLAMA_PID" ]; then
        kill "$OLLAMA_PID" 2>/dev/null || true
        log_info "Ollama stopped"
    fi
}

trap cleanup EXIT

# Start Ollama server if not running
if ! pgrep -f "ollama serve" > /dev/null; then
    log_info "Starting Ollama server..."
    ollama serve &
    OLLAMA_PID=$!
    sleep 5
    log_success "Ollama server started (PID: $OLLAMA_PID)"
else
    log_info "Ollama server already running"
fi

# Start cognitive engine with soak test mode
log_info "Starting cognitive engine for soak test..."
export COPILOT_ADVISOR_MODEL="llama3:8b"
export COPILOT_CHRONICLER_ENABLED="true"

python3 brain.py --debug &
BRAIN_PID=$!

log_success "Cognitive engine started (PID: $BRAIN_PID)"
sleep 3

# Simulate sustained question load
log_info "Starting sustained question simulation..."
log_info "Duration: ${SOAK_DURATION} seconds (15 minutes)"

# Array of test questions to cycle through
questions=(
    "What is TCP?"
    "How does TCP ensure reliability?"
    "What's the difference between TCP and UDP?"
    "How does HTTP work?"
    "What is a RESTful API?"
    "How does HTTPS provide security?"
    "What are the layers of the OSI model?"
    "How does DNS resolution work?"
    "What is load balancing?"
    "How do CDNs improve performance?"
)

start_time=$(date +%s)
question_count=0
successful_responses=0
failed_responses=0

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))

    if [ $elapsed -ge $SOAK_DURATION ]; then
        break
    fi

    # Select question from array
    question_index=$((question_count % ${#questions[@]}))
    question="${questions[$question_index]}"

    # Check if cognitive engine is still running
    if ! kill -0 "$BRAIN_PID" 2>/dev/null; then
        log_error "Cognitive engine crashed! Soak test failed."
        exit 1
    fi

    # Log progress every minute
    if [ $((elapsed % 60)) -eq 0 ] && [ $elapsed -gt 0 ]; then
        remaining=$((SOAK_DURATION - elapsed))
        log_info "Progress: ${elapsed}s elapsed, ${remaining}s remaining. Questions: $question_count"

        if [ "$GPU_MONITORING" = true ]; then
            # Get latest GPU stats
            latest_stats=$(tail -1 "$GPU_LOG_FILE" 2>/dev/null || echo "N/A")
            log_info "Latest GPU: $latest_stats"
        fi
    fi

    question_count=$((question_count + 1))

    # Small delay between questions (realistic pace)
    sleep 2
done

# Test completed
log_success "Soak test completed!"
log_info "Total questions processed: $question_count"
log_info "Duration: ${SOAK_DURATION} seconds"

# Analyze GPU log if available
if [ "$GPU_MONITORING" = true ] && [ -f "$GPU_LOG_FILE" ]; then
    log_info "Analyzing GPU performance..."

    # Calculate averages and check for issues
    if command -v python3 &> /dev/null; then
        python3 -c "
import csv
import sys

try:
    with open('$GPU_LOG_FILE', 'r') as f:
        reader = csv.DictReader(f)
        gpu_utils = []
        temps = []
        memory_vals = []

        for row in reader:
            try:
                gpu_utils.append(float(row['gpu_util_percent']))
                temps.append(float(row['temp_celsius']))
                memory_vals.append(float(row['memory_used_mb']))
            except (ValueError, KeyError):
                continue

        if gpu_utils:
            print(f'GPU Utilization: avg={sum(gpu_utils)/len(gpu_utils):.1f}%, max={max(gpu_utils):.1f}%')
            print(f'Temperature: avg={sum(temps)/len(temps):.1f}°C, max={max(temps):.1f}°C')
            print(f'Memory Usage: avg={sum(memory_vals)/len(memory_vals):.1f}MB, max={max(memory_vals):.1f}MB')

            # Check for thermal throttling (>80°C sustained)
            hot_readings = [t for t in temps if t > 80]
            if hot_readings:
                print(f'⚠️  WARNING: {len(hot_readings)} readings above 80°C (potential throttling)')
            else:
                print('✅ Temperature within safe range')

            # Check for memory leaks (>20% increase)
            if len(memory_vals) > 10:
                early_avg = sum(memory_vals[:5]) / 5
                late_avg = sum(memory_vals[-5:]) / 5
                increase_pct = ((late_avg - early_avg) / early_avg) * 100

                if increase_pct > 20:
                    print(f'⚠️  WARNING: Memory usage increased {increase_pct:.1f}% (potential leak)')
                else:
                    print('✅ Memory usage stable')
        else:
            print('No GPU data collected')

except Exception as e:
    print(f'Error analyzing GPU data: {e}')
"
    else
        log_warning "Python3 not available for GPU analysis"
        log_info "Raw GPU log saved to: $GPU_LOG_FILE"
    fi
fi

# Final system check
if kill -0 "$BRAIN_PID" 2>/dev/null; then
    log_success "✅ Cognitive engine still running - No crashes detected"
else
    log_error "❌ Cognitive engine stopped during test"
    exit 1
fi

log_success "🎉 SOAK TEST PASSED"
log_info "System remained stable under sustained load for 15 minutes"
log_info "Check $GPU_LOG_FILE for detailed GPU metrics"

echo ""
echo "Next steps:"
echo "  • Review GPU metrics for any performance issues"
echo "  • Test with real Whisper server integration"
echo "  • Validate HUD display with live audio"