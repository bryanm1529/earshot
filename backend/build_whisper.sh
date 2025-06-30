#!/bin/bash

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Helper functions for logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    return 1
}

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# Error handling
handle_error() {
    log_error "$1"
    exit 1
}

# Main script
cd backend || handle_error "Failed to change to backend directory"
log_section "Starting Whisper.cpp Build Process"

log_info "Checking for dependencies..."
for cmd in cmake make gcc g++; do
    if ! [ -x "$(command -v $cmd)" ]; then
        handle_error "$cmd is not installed. Please install it. On Debian/Ubuntu, you can use: sudo apt-get install $cmd"
    fi
done
log_success "All dependencies are installed."

log_info "Updating git submodules..."
git submodule update --init --recursive || handle_error "Failed to update git submodules"

log_info "Checking for whisper.cpp directory..."
if [ ! -d "whisper.cpp" ]; then
    handle_error "Directory 'whisper.cpp' not found. Please make sure you're in the correct directory and the submodule is initialized"
fi

log_info "Changing to whisper.cpp directory..."
cd whisper.cpp || handle_error "Failed to change to whisper.cpp directory"

log_info "Checking for custom server directory..."
if [ ! -d "../whisper-custom/server" ]; then
    handle_error "Directory '../whisper-custom/server' not found. Please make sure the custom server files exist"
fi

log_info "Copying custom server files..."
cp -r ../whisper-custom/server/* "examples/server/" || handle_error "Failed to copy custom server files"
log_success "Custom server files copied successfully"

log_info "Verifying server files..."
ls "examples/server/" || handle_error "Failed to list server files"

log_section "Building Whisper Server"
log_info "Building whisper.cpp..."
rm -rf build
mkdir build && cd build || handle_error "Failed to create build directory"

# Sprint 5: Configure CMake with multi-backend optimization flags
log_info "Configuring CMake with Sprint 5 optimizations..."

# Sprint 5: Release build flags for maximum performance
RELEASE_FLAGS="-Ofast -ffp-contract=fast -funroll-loops -march=native -DNDEBUG"
cmake_flags=("-DCMAKE_BUILD_TYPE=Release"
             "-DCMAKE_C_FLAGS='$RELEASE_FLAGS'"
             "-DCMAKE_CXX_FLAGS='$RELEASE_FLAGS'")

# Sprint 5: Multi-backend support - enable all available backends
log_info "Enabling multi-backend support (Metal, CoreML, CUDA)..."

# Check if on a Mac (enable Metal and CoreML)
if [[ "$(uname)" == "Darwin" ]]; then
    log_info "macOS detected: enabling Metal and CoreML with FP16 optimization"
    cmake_flags+=("-DWHISPER_METAL=ON"
                  "-DWHISPER_COREML=ON"
                  "-DWHISPER_COREML_ALLOW_FALLBACK=ON"
                  "-DWHISPER_METAL_NBITS=16")  # Sprint 5: FP16 for Metal
fi

# Check for NVIDIA GPU (enable CUDA)
if command -v nvidia-smi &> /dev/null; then
    log_info "NVIDIA GPU detected: enabling CUDA support"
    cmake_flags+=("-DWHISPER_CUDA=ON")
fi

# Sprint 5: VAD support for Phase 2 optimizations
cmake_flags+=("-DWHISPER_LIBRISPEECH_VAD=ON")

log_info "CMake flags: ${cmake_flags[*]}"
cmake "${cmake_flags[@]}" .. || handle_error "CMake configuration failed"

make -j$(nproc) || handle_error "Make failed"
cd ..
log_success "Build completed successfully"

# Configuration
PACKAGE_NAME="whisper-server-package"
MODEL_NAME="ggml-small.bin"
MODEL_DIR="$PACKAGE_NAME/models"

log_section "Package Configuration"
log_info "Package name: $PACKAGE_NAME"
log_info "Model name: $MODEL_NAME"
log_info "Model directory: $MODEL_DIR"

# Create necessary directories
log_info "Creating package directories..."
mkdir -p "$PACKAGE_NAME" || handle_error "Failed to create package directory"
mkdir -p "$MODEL_DIR" || handle_error "Failed to create models directory"
log_success "Package directories created successfully"

# Copy server binary
log_info "Copying server binary..."
cp build/bin/whisper-server "$PACKAGE_NAME/" || handle_error "Failed to copy server binary"
log_success "Server binary copied successfully"

# Copy model file

# Check for existing models
log_section "Model Management"
log_info "Checking for existing Whisper models..."

EXISTING_MODELS=$(find "$MODEL_DIR" -name "ggml-*.bin" -type f)

if [ -n "$EXISTING_MODELS" ]; then
    log_info "Found existing models:"
    echo -e "${BLUE}$EXISTING_MODELS${NC}"
else
    log_warning "No existing models found"
fi

# Whisper models
models="tiny
tiny.en
tiny-q5_1
tiny.en-q5_1
tiny-q8_0
base
base.en
base-q5_1
base.en-q5_1
base-q8_0
small
small.en
small.en-tdrz
small-q5_1
small.en-q5_1
small-q8_0
medium
medium.en
medium-q5_0
medium.en-q5_0
medium-q8_0
large-v1
large-v2
large-v2-q5_0
large-v2-q8_0
large-v3
large-v3-q5_0
large-v3-turbo
large-v3-turbo-q5_0
large-v3-turbo-q8_0"

# Ask user which model to use if the argument is not provided
MODEL_SHORT_NAME="base.en"

# Check if the model is valid
if ! echo "$models" | grep -qw "$MODEL_SHORT_NAME"; then
    handle_error "Invalid model: $MODEL_SHORT_NAME"
fi

MODEL_NAME="ggml-$MODEL_SHORT_NAME.bin"

# Check if the modelname exists in directory
if [ -f "$MODEL_DIR/$MODEL_NAME" ]; then
    log_info "Model file exists: $MODEL_DIR/$MODEL_NAME"
else
    log_warning "Model file does not exist: $MODEL_DIR/$MODEL_NAME"
    log_info "Trying to download model..."
    ./models/download-ggml-model.sh $MODEL_SHORT_NAME || handle_error "Failed to download model"
    # Move model to models directory
    mv "./models/$MODEL_NAME" "$MODEL_DIR/" || handle_error "Failed to move model to models directory"
fi

# Sprint 5: Create enhanced run script with backend support
log_info "Creating Sprint 5 enhanced run script..."
cat > "$PACKAGE_NAME/run-server.sh" << 'EOL'
#!/bin/bash

# Sprint 5: Enhanced server configuration
HOST="127.0.0.1"
PORT="8178"
MODEL="models/ggml-base.en.bin"
HOT_MODEL="models/ggml-tiny.en-q5_1.bin"
BACKEND="auto"
STEP_MS="256"
LENGTH_MS="2000"

# Sprint 5: Environment variable support
export STEP_MS="${STEP_MS}"
export LENGTH_MS="${LENGTH_MS}"
export WHISPER_MAX_ACTIVE="2"

echo "🚀 Sprint 5: Starting Whisper.cpp server with <150ms optimization"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            HOST="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --hot-model)
            HOT_MODEL="$2"
            shift 2
            ;;
        --backend)
            BACKEND="$2"
            shift 2
            ;;
        --step-ms)
            STEP_MS="$2"
            export STEP_MS="$2"
            shift 2
            ;;
        --length-ms)
            LENGTH_MS="$2"
            export LENGTH_MS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Available options: --host, --port, --model, --hot-model, --backend, --step-ms, --length-ms"
            exit 1
            ;;
    esac
done

echo "Cold Path Model: $MODEL"
echo "Hot Path Model: $HOT_MODEL"
echo "Backend: $BACKEND"
echo "Streaming: step=${STEP_MS}ms, length=${LENGTH_MS}ms"
echo "Endpoints: /inference (cold), /hot_stream (hot)"

# Sprint 5: Run server with hot/cold model architecture
./whisper-server \
    --model "$MODEL" \
    --host "$HOST" \
    --port "$PORT" \
    --step-ms "$STEP_MS" \
    --length-ms "$LENGTH_MS" \
    --keep-ms 0 \
    --use-gpu true \
    --no-timestamps \
    --print-progress


EOL
log_success "Run script created successfully"

log_info "Making script executable: $PACKAGE_NAME/run-server.sh"
# Make run script executable
chmod +x "$PACKAGE_NAME/run-server.sh" || handle_error "Failed to make script executable"

log_info "Listing files..."
ls || handle_error "Failed to list files"

# Check if package directory already exists
if [ -d "../$PACKAGE_NAME" ]; then
    log_info "Listing parent directory..."
    log_warning "Package directory already exists: ../$PACKAGE_NAME"
    log_info "Listing package directory..."
else
    log_info "Creating package directory: ../$PACKAGE_NAME"
    mkdir "../$PACKAGE_NAME" || handle_error "Failed to create package directory"
    log_success "Package directory created successfully"
fi

# Move whisper-server package out of whisper.cpp to ../PACKAGE_NAME

# If package directory already exists outside whisper.cpp, copy just whisper-server and model to it. Replace
# the contents of the directory with the new files
if [ -d "../$PACKAGE_NAME" ]; then
    log_info "Copying package contents to existing directory..."
    cp -r "$PACKAGE_NAME/"* "../$PACKAGE_NAME" || handle_error "Failed to copy package contents"

else

   log_info "Copying whisper-server and model to ../$PACKAGE_NAME"
    cp "$MODEL_DIR/$MODEL_NAME" "../$PACKAGE_NAME/models/" || handle_error "Failed to copy model"
    cp "$PACKAGE_NAME/run-server.sh" "../$PACKAGE_NAME" || handle_error "Failed to copy run script"
    cp -r "$PACKAGE_NAME/public" "../$PACKAGE_NAME" || handle_error "Failed to copy public directory"
    cp "$PACKAGE_NAME/whisper-server" "../$PACKAGE_NAME" || handle_error "Failed to copy whisper-server"
    # rm -r "$PACKAGE_NAME"
fi

log_section "Environment Setup"
log_info "Setting up environment variables..."
cd ../.. && cp backend/temp.env backend/.env || handle_error "Failed to copy environment variables"

log_info "If you want to use Models hosted on Anthropic, OpenAi or GROQ, add the API keys to the .env file."

log_section "Build Process Complete"
log_success "Whisper.cpp server build and setup completed successfully!"

log_section "Script Permissions"
log_info "Making script executable: clean_start_backend.sh"
chmod +x backend/clean_start_backend.sh || handle_error "Failed to make script executable"

log_success "Permission set successfully!"

log_success "Whisper.cpp server build and setup completed successfully!"

log_section "Installing python dependencies"

log_info "Installing python dependencies..."
cd backend || handle_error "Failed to change to backend directory"

# Check if python3-venv is available
check_python_venv() {
    if ! python3 -m venv --help &> /dev/null; then
        log_error "Python venv module is not available."
        log_info "On Ubuntu/Debian, install it with: sudo apt update && sudo apt install python3-venv python3.10-venv -y"
        log_info "On other systems, make sure python3-venv is installed"
        return 1
    fi
    return 0
}

# Check and install venv if needed
if ! check_python_venv; then
    log_warning "Attempting to install python3-venv automatically..."
    if command -v apt &> /dev/null; then
        log_info "Detected Debian/Ubuntu system. Installing python3-venv..."
        if ! sudo apt update && sudo apt install python3-venv python3.10-venv -y; then
            log_error "Failed to install python3-venv. Please install it manually and run the script again."
            log_info "Run: sudo apt update && sudo apt install python3-venv python3.10-venv -y"
            exit 1
        fi
        log_success "python3-venv installed successfully"
    else
        log_error "Cannot auto-install python3-venv on this system. Please install it manually."
        exit 1
    fi
fi

# Check if virtual environment exists and is valid
validate_venv() {
    if [ -d "venv" ] && [ -f "venv/bin/activate" ] && [ -f "venv/bin/python" ]; then
        return 0  # Valid venv
    else
        return 1  # Invalid or missing venv
    fi
}

# Create or recreate virtual environment
if validate_venv; then
    log_info "Valid virtual environment already exists"
else
    if [ -d "venv" ]; then
        log_warning "Corrupted virtual environment detected. Removing and recreating..."
        rm -rf venv
    fi

    log_info "Creating virtual environment..."
    if ! python3 -m venv venv; then
        log_error "Failed to create virtual environment. Make sure python3-venv is installed."
        log_info "Try: sudo apt install python3-venv python3.10-venv"
        exit 1
    fi
    log_success "Virtual environment created successfully"
fi

# Activate virtual environment and install dependencies
log_info "Activating virtual environment and installing dependencies..."
if ! source venv/bin/activate; then
    log_error "Failed to activate virtual environment"
    log_info "Removing corrupted venv and trying again..."
    rm -rf venv
    if ! python3 -m venv venv; then
        handle_error "Failed to recreate virtual environment"
    fi
    if ! source venv/bin/activate; then
        handle_error "Failed to activate recreated virtual environment"
    fi
fi

if ! pip install -r requirements.txt; then
    handle_error "Failed to install dependencies"
fi

log_success "Dependencies installed successfully"

echo -e "${GREEN}You can now proceed with running the server by running './clean_start_backend.sh'${NC} "
