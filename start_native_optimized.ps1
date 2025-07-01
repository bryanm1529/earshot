#!/usr/bin/env powershell
# Optimized Native Startup Script
# Python-Native Architecture with Smart Resource Management

param(
    [switch]$Debug,
    [string]$Priority = "BelowNormal",
    [int64]$AffinityMask = 0xFF0  # Use cores 4-11, leave 0-3 for OS/VS Code
)

Write-Host "🚀 Starting Earshot with Resource Optimization..." -ForegroundColor Green
Write-Host "   Priority: $Priority" -ForegroundColor Yellow
Write-Host "   CPU Affinity: 0x$($AffinityMask.ToString('X'))" -ForegroundColor Yellow

# --- Cleanup trap for Ctrl+C ---
$cleanup = {
    Write-Host ""
    Write-Host "🛑 Shutting down all processes..." -ForegroundColor Yellow

    # Stop Python processes (brain_native.py)
    Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -like "*brain_native.py*" -or
        $_.CommandLine -like "*ffmpeg*" -and $_.CommandLine -like "*CABLE*"
    } | ForEach-Object {
        Write-Host "  Stopping PID $($_.ProcessId)" -ForegroundColor Gray
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

    # Stop any Tauri frontend processes
    Get-Process -Name "*earshot*", "*meetily*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  Stopping frontend PID $($_.Id)" -ForegroundColor Gray
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }

    Write-Host "✅ Shutdown complete." -ForegroundColor Green
}

# Register cleanup for Ctrl+C
try {
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action $cleanup
} catch {
    # Ignore if already registered
}

# --- Configuration & Paths ---
$BrainScript = ".\backend\brain_native.py"
$PythonExe = "python"  # Use system Python
$FrontendScript = ".\start_frontend.ps1"

# Verify prerequisites
if (!(Test-Path $BrainScript)) {
    Write-Host "❌ Error: brain_native.py not found at $BrainScript" -ForegroundColor Red
    exit 1
}

# --- Step 1: Check/Start Ollama ---
Write-Host "📡 Checking Ollama server..." -ForegroundColor Yellow
$ollamaRunning = $false
try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -Method GET -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        $ollamaRunning = $true
        Write-Host "✅ Ollama is already running" -ForegroundColor Green
    }
} catch {
    Write-Host "⚠️ Ollama not responding, starting it..." -ForegroundColor Yellow
}

if (-not $ollamaRunning) {
    Write-Host "🔥 Starting Ollama server..." -ForegroundColor Yellow
    $ollamaProc = Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden -PassThru

    # Wait for Ollama to start
    $retries = 0
    while ($retries -lt 10) {
        Start-Sleep -Seconds 2
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:11434/api/tags" -Method GET -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-Host "✅ Ollama server started successfully" -ForegroundColor Green
                break
            }
        } catch {
            $retries++
            if ($retries -eq 10) {
                Write-Host "❌ Failed to start Ollama after 10 retries" -ForegroundColor Red
                exit 1
            }
        }
    }
}

# --- Step 2: Start Python-Native Backend with Resource Limits ---
Write-Host "🧠 Starting Python-Native Cognitive Engine with optimizations..." -ForegroundColor Yellow

$brainArgs = @(
    $BrainScript
)

if ($Debug) {
    $brainArgs += "--debug"
}

# Start the brain process
$brainProc = Start-Process -FilePath $PythonExe -ArgumentList $brainArgs -PassThru -WindowStyle Hidden

if ($brainProc) {
    # Apply resource optimizations
    try {
        Write-Host "🔧 Applying resource optimizations to backend..." -ForegroundColor Yellow

        # Set priority class (Below Normal to keep UI responsive)
        $brainProc.PriorityClass = $Priority
        Write-Host "   ✓ Priority set to $Priority" -ForegroundColor Gray

        # Set CPU affinity (confine to specific cores)
        $brainProc.ProcessorAffinity = $AffinityMask
        Write-Host "   ✓ CPU affinity set to cores 4-11" -ForegroundColor Gray

        Write-Host "✅ Backend optimizations applied (PID: $($brainProc.Id))" -ForegroundColor Green

    } catch {
        Write-Host "⚠️ Warning: Could not apply all optimizations: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "❌ Failed to start brain_native.py" -ForegroundColor Red
    exit 1
}

# --- Step 3: Wait for Backend to Initialize ---
Write-Host "⏳ Waiting for backend to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Check if WebSocket server is running
$backendReady = $false
for ($i = 1; $i -le 10; $i++) {
    try {
        $wsTest = Test-NetConnection -ComputerName 127.0.0.1 -Port 9082 -ErrorAction SilentlyContinue
        if ($wsTest.TcpTestSucceeded) {
            $backendReady = $true
            Write-Host "✅ Backend WebSocket server is ready" -ForegroundColor Green
            break
        }
    } catch { }

    Write-Host "   Attempt $i/10..." -ForegroundColor Gray
    Start-Sleep -Seconds 2
}

if (-not $backendReady) {
    Write-Host "⚠️ Backend may not be fully ready, but continuing..." -ForegroundColor Yellow
}

# --- Step 4: Launch Frontend ---
Write-Host "🎨 Launching Frontend (Tauri HUD)..." -ForegroundColor Yellow
Write-Host ""
Write-Host "🌟 SYSTEM READY! The backend is optimized for performance:" -ForegroundColor Green
Write-Host "   📊 Backend running with $Priority priority" -ForegroundColor Cyan
Write-Host "   🔧 CPU cores 4-11 reserved for AI processing" -ForegroundColor Cyan
Write-Host "   🖥️ Cores 0-3 free for VS Code and desktop" -ForegroundColor Cyan
Write-Host "   🌐 WebSocket: ws://localhost:9082" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎯 Next: Frontend will launch in a new window..." -ForegroundColor Yellow
Write-Host "🛑 Press Ctrl+C here to stop the entire system" -ForegroundColor Red
Write-Host ""

# Start frontend in a new PowerShell window
Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$FrontendScript`""

# --- Monitor and Keep Alive ---
Write-Host "🔍 Monitoring system health..." -ForegroundColor Yellow

try {
    while ($true) {
        # Check if brain process is still alive
        if ($brainProc.HasExited) {
            Write-Host "❌ Backend process died unexpectedly" -ForegroundColor Red
            break
        }

        # Show periodic status
        $timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "[$timestamp] System running... (Ctrl+C to stop)" -ForegroundColor Gray

        Start-Sleep -Seconds 30
    }
} catch [System.Management.Automation.PipelineStoppedException] {
    # User pressed Ctrl+C
    Write-Host ""
    Write-Host "🛑 Shutdown requested..." -ForegroundColor Yellow
} finally {
    # Cleanup will be handled by the registered event
}

Write-Host "👋 System stopped." -ForegroundColor Green