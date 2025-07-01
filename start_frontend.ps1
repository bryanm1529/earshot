#!/usr/bin/env powershell
# Frontend Startup Script
# Part 2 of the two-part launch process

Write-Host "Starting Earshot Frontend (HUD)..." -ForegroundColor Green

# Navigate to frontend directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location "$scriptDir\frontend"

# Check if backend is running
Write-Host "Checking backend WebSocket connection..." -ForegroundColor Yellow
try {
    $wsTest = Test-NetConnection -ComputerName 127.0.0.1 -Port 9082 -ErrorAction SilentlyContinue
    if ($wsTest.TcpTestSucceeded) {
        Write-Host "✅ Backend WebSocket server detected" -ForegroundColor Green
    } else {
        throw "Port not accessible"
    }
} catch {
    Write-Host "⚠️ WARNING: Backend WebSocket server not responding" -ForegroundColor Yellow
    Write-Host "Make sure you've started the backend first:" -ForegroundColor Yellow
    Write-Host "  .\start_simple.ps1 or .\start_native_optimized.ps1" -ForegroundColor Cyan
    Write-Host ""
    $choice = Read-Host "Continue anyway? (y/N)"
    if ($choice -ne 'y' -and $choice -ne 'Y') {
        exit 1
    }
}

# Ensure static build exists
Write-Host "Checking static frontend build..." -ForegroundColor Yellow
if (-not (Test-Path "out")) {
    Write-Host "⚠️ Static build not found, creating it..." -ForegroundColor Yellow
    pnpm build
    if (-not (Test-Path "out")) {
        Write-Host "❌ Failed to create static build" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Static build created" -ForegroundColor Green
} else {
    Write-Host "✅ Static build found" -ForegroundColor Green
}

# Start Tauri with static files
Write-Host "Starting Tauri HUD with static frontend..." -ForegroundColor Yellow
Write-Host ""
Write-Host "🪟 The HUD window will appear shortly..." -ForegroundColor Green
Write-Host "🔌 It will connect to: ws://localhost:9082" -ForegroundColor Cyan
Write-Host "🎯 Look for the transparent overlay window" -ForegroundColor Cyan
Write-Host ""

pnpm tauri dev