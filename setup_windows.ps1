param()
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "Starting Earshot Windows setup..." -ForegroundColor Cyan

# 1) Must be run from repo root
if (-not ((Test-Path ".\backend") -and (Test-Path ".\frontend"))) {
    Write-Error "ERROR: Run this from the project root (where backend/ and frontend/ live)."
    exit 1
}

# 2) Check Python 3.10+
Write-Host "Checking Python..."
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: Python 3.10+ not found in PATH."
    exit 1
}

# 3) Check Node.js & pnpm
Write-Host "Checking Node.js + pnpm..."
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: Node.js LTS not found."
    exit 1
}
if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    Write-Host "WARNING: pnpm missing - installing globally..."
    npm install -g pnpm
}

# 4) Create & activate venv
Write-Host "Setting up Python venv..."
if (-not (Test-Path ".venv")) {
    python -m venv .venv
}
& .\.venv\Scripts\Activate.ps1
pip install --upgrade pip
pip install -r backend\requirements.txt

# 5) Install frontend deps
Write-Host "Installing frontend (pnpm)..."
Push-Location frontend
pnpm install
Pop-Location

# 6) Check for websocat
Write-Host "Verifying WebSocket pipe tool..."
if (Get-Command websocat -ErrorAction SilentlyContinue) {
    Write-Host "   OK: websocat found"
}
else {
    Write-Warning "WARNING: websocat not found. Install and add to PATH."
}

# 7) Check ffmpeg & ollama
Write-Host "Verifying ffmpeg + Ollama..."
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Warning "WARNING: ffmpeg not found."
} else {
    Write-Host "   OK: ffmpeg found"
}
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Warning "WARNING: ollama not found."
} else {
    Write-Host "   OK: ollama found"
}

Write-Host ""
Write-Host "Setup complete! Next steps:" -ForegroundColor Green
Write-Host " 1. Build whisper: cd backend\whisper.cpp and run build_whisper.cmd" -ForegroundColor Gray
Write-Host " 2. Download models: backend\download-ggml-model.cmd tiny.en" -ForegroundColor Gray
Write-Host " 3. Start Ollama: ollama serve then ollama pull llama3:8b" -ForegroundColor Gray
Write-Host " 4. Run: .\start_native.ps1" -ForegroundColor Gray
Write-Host ""