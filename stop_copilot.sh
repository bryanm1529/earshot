#!/bin/bash

# Sprint 9: The Final Wire-Up - Robust System Stopper
# Stops the complete Earshot Cognitive Co-Pilot system using pkill for resilience

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "=================================================="
echo "🛑 Stopping Cognitive Co-Pilot System"
echo "   Sprint 9: Robust Shutdown"
echo "=================================================="
echo -e "${NC}"

# Function to stop a process by name with confirmation
stop_process() {
    local process_name="$1"
    local display_name="$2"

    echo -e "${YELLOW}Stopping $display_name...${NC}"

    if pkill -f "$process_name" 2>/dev/null; then
        echo "   ✅ $display_name stopped"

        # Wait for graceful shutdown
        for i in {1..5}; do
            if ! pgrep -f "$process_name" > /dev/null 2>&1; then
                break
            fi
            sleep 1
        done

        # Force kill if still running
        if pgrep -f "$process_name" > /dev/null 2>&1; then
            echo "   ⚠️  Force killing $display_name..."
            pkill -9 -f "$process_name" 2>/dev/null || true
        fi
    else
        echo "   ℹ️  $display_name was not running"
    fi
}

# Stop processes in reverse dependency order
echo -e "${BLUE}🔄 Shutting down services...${NC}"

# 1. Stop Frontend (Next.js dev server)
stop_process "next dev" "Frontend"

# 2. Stop Cognitive Engine (brain.py)
stop_process "brain.py" "Cognitive Engine"

# 3. Stop Whisper Server
stop_process "whisper-server-ws" "Whisper Server"

# Note: We don't stop Ollama as it might be used by other applications
# If you want to stop Ollama as well, uncomment the following line:
# stop_process "ollama serve" "Ollama"

echo -e "\n${GREEN}✅ Cognitive Co-Pilot System shutdown complete${NC}"

# Check if any related processes are still running
echo -e "\n${BLUE}🔍 Checking for remaining processes...${NC}"

remaining_processes=0

if pgrep -f "whisper-server-ws" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Warning: whisper-server-ws processes still running${NC}"
    remaining_processes=$((remaining_processes + 1))
fi

if pgrep -f "brain.py" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Warning: brain.py processes still running${NC}"
    remaining_processes=$((remaining_processes + 1))
fi

if pgrep -f "next dev" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Warning: Next.js dev processes still running${NC}"
    remaining_processes=$((remaining_processes + 1))
fi

if [ $remaining_processes -eq 0 ]; then
    echo "   ✅ All processes stopped successfully"
else
    echo -e "${YELLOW}   ⚠️  $remaining_processes process(es) may need manual cleanup${NC}"
    echo ""
    echo "   To manually kill remaining processes:"
    echo "   pkill -9 -f \"whisper-server-ws\""
    echo "   pkill -9 -f \"brain.py\""
    echo "   pkill -9 -f \"next dev\""
fi

echo -e "\n${GREEN}🎉 Shutdown procedure complete!${NC}"