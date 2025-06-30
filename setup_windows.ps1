# setup_windows.ps1
# Windows Environment Setup for Earshot Cognitive Co-Pilot
# Handles initial setup of Python virtual environment and dependencies

#Requires -Version 5.1

# Color output function
function Write-ColorOutput($Message, $Color = "White") {
    Write-Host $Message -ForegroundColor $Color
}

# Banner
Write-ColorOutput "" "Blue"
Write-ColorOutput "==================================================" "Blue"
Write-ColorOutput "🔧 Earshot Cognitive Co-Pilot - Windows Setup" "Blue"
Write-ColorOutput "   Initial Environment Configuration" "Blue"
Write-ColorOutput "==================================================" "Blue"
Write-ColorOutput "" "Blue"

# Check if we're in the correct directory
if (!(Test-Path "backend") -or !(Test-Path "frontend")) {
    Write-ColorOutput "❌ Please run this script from the project root directory" "Red"
    exit 1
}

# Check Python installation
Write-ColorOutput "🔍 Checking Python installation..." "Blue"
try {
    $pythonVersion = & python --version 2>&1
    Write-ColorOutput "   ✅ Python found: $pythonVersion" "Green"

    # Check if version is 3.10+
    if ($pythonVersion -match "Python 3\.([0-9]+)\.") {
        $minorVersion = [int]$matches[1]
        if ($minorVersion -lt 10) {
            Write-ColorOutput "⚠️  Python 3.10+ recommended, found: $pythonVersion" "Yellow"
        }
    }
}
catch {
    Write-ColorOutput "❌ Python not found. Please install Python 3.10+ from python.org" "Red"
    Write-ColorOutput "   Make sure to check 'Add Python to PATH' during installation" "Red"
    exit 1
}

# Check Node.js and pnpm
Write-ColorOutput "🔍 Checking Node.js and pnpm..." "Blue"
try {
    $nodeVersion = & node --version 2>&1
    Write-ColorOutput "   ✅ Node.js found: $nodeVersion" "Green"
}
catch {
    Write-ColorOutput "❌ Node.js not found. Please install Node.js LTS from nodejs.org" "Red"
    exit 1
}

try {
    $pnpmVersion = & pnpm --version 2>&1
    Write-ColorOutput "   ✅ pnpm found: v$pnpmVersion" "Green"
}
catch {
    Write-ColorOutput "⚠️  pnpm not found. Installing..." "Yellow"
    try {
        & npm install -g pnpm
        Write-ColorOutput "   ✅ pnpm installed successfully" "Green"
    }
    catch {
        Write-ColorOutput "❌ Failed to install pnpm. Please run: npm install -g pnpm" "Red"
        exit 1
    }
}

# Create Python virtual environment
Write-ColorOutput "" "Blue"
Write-ColorOutput "🐍 Setting up Python virtual environment..." "Blue"

if (Test-Path ".venv") {
    Write-ColorOutput "   Virtual environment already exists" "Yellow"
    $recreate = Read-Host "   Recreate virtual environment? (y/N)"
    if ($recreate.ToLower() -eq "y") {
        Write-ColorOutput "   Removing existing virtual environment..." "Gray"
        Remove-Item -Recurse -Force .venv
    } else {
        Write-ColorOutput "   Using existing virtual environment" "Green"
        $skipVenv = $true
    }
}

if (!$skipVenv) {
    Write-ColorOutput "   Creating virtual environment..." "Gray"
    & python -m venv .venv
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "❌ Failed to create virtual environment" "Red"
        exit 1
    }
    Write-ColorOutput "   ✅ Virtual environment created" "Green"
}

# Activate virtual environment and install dependencies
Write-ColorOutput "   Activating virtual environment and installing dependencies..." "Gray"
try {
    & .\.venv\Scripts\Activate.ps1

    # Upgrade pip first
    & python -m pip install --upgrade pip

    # Install backend dependencies
    & pip install -r backend\requirements.txt
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "❌ Failed to install Python dependencies" "Red"
        exit 1
    }
    Write-ColorOutput "   ✅ Python dependencies installed" "Green"
}
catch {
    Write-ColorOutput "❌ Failed to setup Python environment: $($_.Exception.Message)" "Red"
    exit 1
}

# Install frontend dependencies
Write-ColorOutput "" "Blue"
Write-ColorOutput "📦 Installing frontend dependencies..." "Blue"
try {
    Push-Location frontend
    & pnpm install
    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "❌ Failed to install frontend dependencies" "Red"
        Pop-Location
        exit 1
    }
    Write-ColorOutput "   ✅ Frontend dependencies installed" "Green"
    Pop-Location
}
catch {
    Write-ColorOutput "❌ Failed to install frontend dependencies: $($_.Exception.Message)" "Red"
    Pop-Location
    exit 1
}

# Check for required external tools
Write-ColorOutput "" "Blue"
Write-ColorOutput "🔍 Checking external dependencies..." "Blue"

# Check Git
try {
    $gitVersion = & git --version 2>&1
    Write-ColorOutput "   ✅ Git found: $gitVersion" "Green"
}
catch {
    Write-ColorOutput "❌ Git not found. Please install Git for Windows" "Red"
}

# Check Rust (for Tauri)
try {
    $rustVersion = & rustc --version 2>&1
    Write-ColorOutput "   ✅ Rust found: $rustVersion" "Green"
}
catch {
    Write-ColorOutput "⚠️  Rust not found. Install from https://rustup.rs/ for Tauri builds" "Yellow"
}

# Check CUDA (optional)
try {
    $nvccVersion = & nvcc --version 2>&1 | Select-String "release"
    if ($nvccVersion) {
        Write-ColorOutput "   ✅ CUDA found: $nvccVersion" "Green"
    } else {
        Write-ColorOutput "   ℹ️  CUDA not found (optional for GPU acceleration)" "Cyan"
    }
}
catch {
    Write-ColorOutput "   ℹ️  CUDA not found (optional for GPU acceleration)" "Cyan"
}

# Check websocat
try {
    $websocatVersion = & websocat --version 2>&1
    Write-ColorOutput "   ✅ websocat found: $websocatVersion" "Green"
}
catch {
    Write-ColorOutput "⚠️  websocat not found. Download from:" "Yellow"
    Write-ColorOutput "      https://github.com/vi/websocat/releases" "Yellow"
    Write-ColorOutput "      Add websocat.exe to your PATH" "Yellow"
}

# Check ffmpeg
try {
    $ffmpegVersion = & ffmpeg -version 2>&1 | Select-Object -First 1
    Write-ColorOutput "   ✅ ffmpeg found" "Green"
}
catch {
    Write-ColorOutput "⚠️  ffmpeg not found. Install from https://ffmpeg.org/download.html" "Yellow"
}

# Check Ollama
try {
    $ollamaVersion = & ollama --version 2>&1
    Write-ColorOutput "   ✅ Ollama found: $ollamaVersion" "Green"
}
catch {
    Write-ColorOutput "⚠️  Ollama not found. Install from https://ollama.ai/" "Yellow"
}

# Create configuration file if it doesn't exist
Write-ColorOutput "" "Blue"
Write-ColorOutput "⚙️  Configuration setup..." "Blue"

# Prefer .env for Windows, but support .copilotrc for compatibility
if (!(Test-Path ".env") -and !(Test-Path ".copilotrc")) {
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-ColorOutput "   ✅ Configuration file created from .env.example" "Green"
        Write-ColorOutput "   Edit .env to customize settings (recommended for Windows)" "Gray"
    } elseif (Test-Path ".copilotrc.example") {
        Copy-Item ".copilotrc.example" ".copilotrc"
        Write-ColorOutput "   ✅ Configuration file created from .copilotrc.example" "Green"
        Write-ColorOutput "   Edit .copilotrc to customize settings" "Gray"
    } else {
        Write-ColorOutput "   ℹ️  No example configuration found" "Cyan"
    }
} else {
    if (Test-Path ".env") {
        Write-ColorOutput "   ✅ .env configuration file exists" "Green"
    }
    if (Test-Path ".copilotrc") {
        Write-ColorOutput "   ✅ .copilotrc configuration file exists" "Green"
    }
}

# Summary
Write-ColorOutput "" "Green"
Write-ColorOutput "🎉 Windows setup completed!" "Green"
Write-ColorOutput "==================================================" "Blue"
Write-ColorOutput "📋 Next steps:" "Blue"
Write-ColorOutput "   1. Build whisper.cpp using the build scripts in backend/" "Gray"
Write-ColorOutput "   2. Download whisper models if needed" "Gray"
Write-ColorOutput "   3. Start Ollama and pull required models" "Gray"
Write-ColorOutput "   4. Run .\start_native.ps1 to start the system" "Gray"
Write-ColorOutput "" "Blue"
Write-ColorOutput "🔨 Build commands:" "Blue"
Write-ColorOutput "   cd backend" "Gray"
Write-ColorOutput "   .\build_whisper.cmd" "Gray"
Write-ColorOutput "   .\download-ggml-model.cmd tiny.en" "Gray"
Write-ColorOutput "" "Blue"
Write-ColorOutput "🧠 Ollama setup:" "Blue"
Write-ColorOutput "   ollama serve" "Gray"
Write-ColorOutput "   ollama pull llama3:8b" "Gray"
Write-ColorOutput "==================================================" "Blue"