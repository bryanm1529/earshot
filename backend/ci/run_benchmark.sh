#!/bin/bash

# Sprint 5 Phase 3: CI Latency Gate
# Prevents both speed and accuracy regressions from entering main branch

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
LATENCY_THRESHOLD_MS=180  # 95th percentile threshold
FIXTURE_DIR="ci/fixtures"
FIXTURE_AUDIO="$FIXTURE_DIR/test_sample.wav"
FIXTURE_TRANSCRIPT="$FIXTURE_DIR/expected_transcript.txt"
SERVER_HOST="127.0.0.1"
SERVER_PORT="8178"
BENCHMARK_ITERATIONS=5

log_info() {
    echo -e "${BLUE}[BENCHMARK]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    return 1
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if server is running
check_server() {
    log_info "Checking if server is running on $SERVER_HOST:$SERVER_PORT..."
    if curl -s "http://$SERVER_HOST:$SERVER_PORT/" > /dev/null 2>&1; then
        log_success "Server is running"
        return 0
    else
        log_error "Server is not running. Please start it first."
        return 1
    fi
}

# Check for fixture files
check_fixtures() {
    log_info "Checking for benchmark fixtures..."

    if [ ! -f "$FIXTURE_AUDIO" ]; then
        log_error "Fixture audio file not found: $FIXTURE_AUDIO"
        return 1
    fi

    if [ ! -f "$FIXTURE_TRANSCRIPT" ]; then
        log_error "Expected transcript file not found: $FIXTURE_TRANSCRIPT"
        return 1
    fi

    log_success "All fixtures found"
    return 0
}

# Run single benchmark iteration
run_benchmark_iteration() {
    local iteration=$1
    local endpoint=$2

    log_info "Running iteration $iteration on $endpoint..."

    # Measure latency
    local start_time=$(date +%s%3N)

    local response=$(curl -s -X POST \
        -F "file=@$FIXTURE_AUDIO" \
        -F "response_format=json" \
        "http://$SERVER_HOST:$SERVER_PORT$endpoint")

    local end_time=$(date +%s%3N)
    local latency=$((end_time - start_time))

    # Extract text from response
    local actual_text=$(echo "$response" | jq -r '.text // empty' 2>/dev/null)

    if [ -z "$actual_text" ]; then
        log_error "Failed to extract text from response"
        return 1
    fi

    echo "$latency,$actual_text"
    return 0
}

# Calculate statistics
calculate_stats() {
    local latencies=($1)
    local count=${#latencies[@]}

    if [ $count -eq 0 ]; then
        echo "0,0,0,0"
        return
    fi

    # Sort latencies
    IFS=$'\n' sorted=($(sort -n <<<"${latencies[*]}"))
    unset IFS

    # Calculate statistics
    local min=${sorted[0]}
    local max=${sorted[$((count-1))]}
    local median=${sorted[$((count/2))]}

    # Calculate 95th percentile
    local p95_index=$(( (count * 95) / 100 ))
    local p95=${sorted[$p95_index]}

    # Calculate mean
    local sum=0
    for latency in "${latencies[@]}"; do
        sum=$((sum + latency))
    done
    local mean=$((sum / count))

    echo "$min,$max,$median,$mean,$p95"
}

# Compare transcripts
compare_transcripts() {
    local actual="$1"
    local expected_file="$2"

    if [ ! -f "$expected_file" ]; then
        log_error "Expected transcript file not found: $expected_file"
        return 1
    fi

    local expected=$(cat "$expected_file")

    # Normalize text for comparison (remove extra whitespace, lowercase)
    local actual_norm=$(echo "$actual" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | xargs)
    local expected_norm=$(echo "$expected" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | xargs)

    if [ "$actual_norm" = "$expected_norm" ]; then
        log_success "Transcript matches expected output"
        return 0
    else
        log_error "Transcript does not match expected output"
        log_error "Expected: $expected_norm"
        log_error "Actual:   $actual_norm"
        return 1
    fi
}

# Run full benchmark suite
run_benchmark_suite() {
    local endpoint="$1"
    local suite_name="$2"

    log_info "Running $suite_name benchmark suite ($BENCHMARK_ITERATIONS iterations)..."

    local latencies=()
    local transcripts=()
    local failed_iterations=0

    for i in $(seq 1 $BENCHMARK_ITERATIONS); do
        local result=$(run_benchmark_iteration $i "$endpoint")

        if [ $? -eq 0 ]; then
            local latency=$(echo "$result" | cut -d',' -f1)
            local transcript=$(echo "$result" | cut -d',' -f2-)

            latencies+=($latency)
            transcripts+=("$transcript")

            log_info "Iteration $i: ${latency}ms"
        else
            log_error "Iteration $i failed"
            failed_iterations=$((failed_iterations + 1))
        fi
    done

    if [ $failed_iterations -gt 0 ]; then
        log_error "$failed_iterations/$BENCHMARK_ITERATIONS iterations failed"
        return 1
    fi

    # Calculate statistics
    local stats=$(calculate_stats "${latencies[*]}")
    local min=$(echo "$stats" | cut -d',' -f1)
    local max=$(echo "$stats" | cut -d',' -f2)
    local median=$(echo "$stats" | cut -d',' -f3)
    local mean=$(echo "$stats" | cut -d',' -f4)
    local p95=$(echo "$stats" | cut -d',' -f5)

    # Report results
    echo ""
    echo "=== $suite_name Results ==="
    echo "Min:       ${min}ms"
    echo "Max:       ${max}ms"
    echo "Median:    ${median}ms"
    echo "Mean:      ${mean}ms"
    echo "95th pct:  ${p95}ms"
    echo ""

    # Check latency threshold
    if [ $p95 -gt $LATENCY_THRESHOLD_MS ]; then
        log_error "95th percentile latency (${p95}ms) exceeds threshold (${LATENCY_THRESHOLD_MS}ms)"
        return 1
    else
        log_success "95th percentile latency (${p95}ms) within threshold (${LATENCY_THRESHOLD_MS}ms)"
    fi

    # Check transcript accuracy (use first transcript)
    if [ ${#transcripts[@]} -gt 0 ]; then
        compare_transcripts "${transcripts[0]}" "$FIXTURE_TRANSCRIPT"
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    return 0
}

# Main benchmark function
main() {
    echo "🧪 Sprint 5: CI Latency Gate & Accuracy Check"
    echo "=============================================="

    # Preliminary checks
    check_server || exit 1
    check_fixtures || exit 1

    # Create output directory for results
    mkdir -p "ci/results"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local results_file="ci/results/benchmark_$timestamp.json"

    local overall_success=true

    # Test hot stream endpoint (Sprint 5 primary)
    log_info "Testing hot stream endpoint (/hot_stream)..."
    if run_benchmark_suite "/hot_stream" "Hot Stream"; then
        log_success "Hot stream benchmark passed"
    else
        log_error "Hot stream benchmark failed"
        overall_success=false
    fi

    # Test cold inference endpoint (compatibility)
    log_info "Testing inference endpoint (/inference)..."
    if run_benchmark_suite "/inference" "Cold Inference"; then
        log_success "Cold inference benchmark passed"
    else
        log_error "Cold inference benchmark failed"
        overall_success=false
    fi

    # Final result
    echo ""
    echo "=== Overall Results ==="
    if [ "$overall_success" = true ]; then
        log_success "All benchmarks passed - no regressions detected"
        echo "Results saved to: $results_file"
        exit 0
    else
        log_error "Some benchmarks failed - performance or accuracy regression detected"
        echo "Results saved to: $results_file"
        exit 1
    fi
}

# Script help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Sprint 5 CI Benchmark Script"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --host HOST          Server host (default: $SERVER_HOST)"
    echo "  --port PORT          Server port (default: $SERVER_PORT)"
    echo "  --threshold MS       Latency threshold in ms (default: $LATENCY_THRESHOLD_MS)"
    echo "  --iterations N       Number of test iterations (default: $BENCHMARK_ITERATIONS)"
    echo "  --help               Show this help message"
    echo ""
    echo "Requirements:"
    echo "  - Server must be running"
    echo "  - Fixture files must exist: $FIXTURE_AUDIO, $FIXTURE_TRANSCRIPT"
    echo "  - jq must be installed for JSON parsing"
    echo ""
    echo "Exit codes:"
    echo "  0 - All benchmarks passed"
    echo "  1 - Performance or accuracy regression detected"
    exit 0
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            SERVER_HOST="$2"
            shift 2
            ;;
        --port)
            SERVER_PORT="$2"
            shift 2
            ;;
        --threshold)
            LATENCY_THRESHOLD_MS="$2"
            shift 2
            ;;
        --iterations)
            BENCHMARK_ITERATIONS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check dependencies
if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed. Please install jq."
    exit 1
fi

if ! command -v curl &> /dev/null; then
    log_error "curl is required but not installed. Please install curl."
    exit 1
fi

# Run main benchmark
main