#!/usr/bin/env powershell
# Simple Native Startup Script
# Strategic Pivot: One script, two commands, maximum simplicity

Write-Host "Starting Earshot Native Pipeline..." -ForegroundColor Green

# Step 1: Check if Ollama is running
Write-Host "Checking Ollama server..." -ForegroundColor Yellow
$ollamaRunning = $false
try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -Method GET -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        $ollamaRunning = $true
        Write-Host "Ollama is already running" -ForegroundColor Green
    }
} catch {
    Write-Host "Ollama not responding, starting it..." -ForegroundColor Yellow
}

# Step 2: Start Ollama if not running
if (-not $ollamaRunning) {
    Write-Host "Starting Ollama server..." -ForegroundColor Yellow
    Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden

    # Wait for Ollama to start
    $retries = 0
    while ($retries -lt 10) {
        Start-Sleep -Seconds 2
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -Method GET -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-Host "Ollama server started successfully" -ForegroundColor Green
                break
            }
        } catch {
            $retries++
            if ($retries -eq 10) {
                Write-Host "Failed to start Ollama after 10 retries" -ForegroundColor Red
                exit 1
            }
        }
    }
}

# Step 3: Navigate to project directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Step 4: Start Frontend
Write-Host "Starting Frontend..." -ForegroundColor Yellow
$FrontendProcess = Start-Process -FilePath "pnpm" -ArgumentList "dev" -WindowStyle Hidden -PassThru -WorkingDirectory ".\frontend"
Write-Host "Frontend started (PID: $($FrontendProcess.Id))" -ForegroundColor Green

# Step 5: Start the Python-native brain (this manages EVERYTHING else)
Write-Host "Starting Python-Native Cognitive Engine..." -ForegroundColor Yellow
Write-Host ""
Write-Host "SYSTEM READY! Access points:" -ForegroundColor Green
Write-Host "Frontend: http://localhost:3000" -ForegroundColor Cyan
Write-Host "HUD: http://localhost:3000/hud" -ForegroundColor Cyan
Write-Host "WebSocket: ws://localhost:9082" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop everything" -ForegroundColor Red
Write-Host ""

# This one command now manages:
# - Audio capture via ffmpeg subprocess
# - Whisper CLI processing via subprocess
# - Chronicler for context memory
# - Advisor for real-time assistance
# - WebSocket server for frontend communication
# - All error handling and process management
try {
    python .\backend\brain_native.py --debug
} finally {
    Write-Host ""
    Write-Host "Shutting down..." -ForegroundColor Yellow
    try { Stop-Process -Id $FrontendProcess.Id -Force } catch { }
    Write-Host "Shutdown complete" -ForegroundColor Green
}