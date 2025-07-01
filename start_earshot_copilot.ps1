# Start Earshot Copilot System
# This script starts the Python backend and Tauri frontend

Write-Host "Starting Earshot Copilot System..." -ForegroundColor Green

# Check if required files exist
if (-not (Test-Path "backend/brain_native.py")) {
    Write-Host "Error: backend/brain_native.py not found!" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "frontend/src-tauri/target/release/earshot-copilot.exe")) {
    Write-Host "Error: Frontend executable not found. Please run build_frontend.ps1 first!" -ForegroundColor Red
    exit 1
}

# Start Ollama server
Write-Host "Starting Ollama server..." -ForegroundColor Yellow
Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden

# Wait a moment for Ollama to start
Start-Sleep -Seconds 3

# Navigate to backend directory
Set-Location backend

# Start the Python backend
Write-Host "Starting Python backend..." -ForegroundColor Yellow
Start-Process -FilePath "python" -ArgumentList "brain_native.py" -WindowStyle Normal

# Wait a moment for backend to start
Start-Sleep -Seconds 2

# Return to root and start frontend
Set-Location ..
Write-Host "Starting Tauri frontend..." -ForegroundColor Yellow
Start-Process -FilePath "frontend/src-tauri/target/release/earshot-copilot.exe" -WindowStyle Normal

Write-Host "Earshot Copilot system started!" -ForegroundColor Green
Write-Host "Press any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")