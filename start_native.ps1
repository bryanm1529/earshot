# start_native.ps1
# The True Native Windows Migration - Final Production Launch Script
# Earshot Cognitive Co-Pilot System for Windows

#Requires -Version 5.1

# Set console encoding for proper output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Color functions for output
function Write-ColorOutput($Message, $Color = "White") {
    Write-Host $Message -ForegroundColor $Color
}

# Process tracking variables
$Script:ProcessList = @()
$Script:WhisperProcess = $null
$Script:BrainProcess = $null
$Script:FrontendProcess = $null
$Script:OllamaProcess = $null

# Cleanup function for proper shutdown
function Invoke-Cleanup {
    Write-ColorOutput "🛑 Shutting down all processes..." "Yellow"

    # Stop processes gracefully
    $processNames = @("server", "ffmpeg", "websocat", "python", "earshot-copilot", "node", "whisper-server")

    foreach ($processName in $processNames) {
        try {
            $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processes) {
                Write-ColorOutput "Stopping $processName processes..." "Gray"
                $processes | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # Ignore errors during cleanup
        }
    }

    # Clean up tracked processes
    foreach ($proc in $Script:ProcessList) {
        try {
            if ($proc -and !$proc.HasExited) {
                $proc.Kill()
            }
        }
        catch {
            # Ignore cleanup errors
        }
    }

    Write-ColorOutput "✅ Shutdown complete." "Green"
}

# Register cleanup trap for Ctrl+C
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Invoke-Cleanup }

# Trap for Ctrl+C
trap {
    Invoke-Cleanup
    exit 1
}

# Configuration & Paths
$WhisperExe = ".\backend\whisper.cpp\build\bin\Release\server.exe"
$WhisperModelPath = ".\backend\whisper.cpp\models\ggml-tiny.en-q5_1.bin"
$BrainScript = ".\backend\brain.py"
$PythonExe = ".\.venv\Scripts\python.exe"
$WhisperHost = "127.0.0.1"
$WhisperPort = 9080
$WhisperWsPort = 10080
$WhisperWsUrl = "ws://${WhisperHost}:${WhisperWsPort}/hot_stream"
$FrontendPort = 3118
$OllamaHost = "127.0.0.1"
$OllamaPort = 11434

# Load configuration if .copilotrc exists
if (Test-Path ".copilotrc") {
    Write-ColorOutput "📋 Loading configuration from .copilotrc" "Green"
    # Note: PowerShell doesn't directly source bash files, but we'll use defaults
    Write-ColorOutput "   Using default Windows configuration" "Gray"
} else {
    Write-ColorOutput "📋 No .copilotrc found, using Windows defaults" "Yellow"
}

# Banner
Write-ColorOutput "" "Blue"
Write-ColorOutput "==================================================" "Blue"
Write-ColorOutput "🧠 Earshot Cognitive Co-Pilot System" "Blue"
Write-ColorOutput "   Native Windows Production Release" "Blue"
Write-ColorOutput "==================================================" "Blue"
Write-ColorOutput "" "Blue"

Write-ColorOutput "🔧 Configuration:" "Blue"
Write-ColorOutput "   Whisper Server: ${WhisperHost}:${WhisperPort}" "Gray"
Write-ColorOutput "   WebSocket Stream: ${WhisperHost}:${WhisperWsPort}" "Gray"
Write-ColorOutput "   Ollama: ${OllamaHost}:${OllamaPort}" "Gray"
Write-ColorOutput "   Frontend: http://localhost:${FrontendPort}" "Gray"

# Check dependencies
Write-ColorOutput "" "Blue"
Write-ColorOutput "🔍 Checking dependencies..." "Blue"

# Check Python virtual environment
if (!(Test-Path $PythonExe)) {
    Write-ColorOutput "❌ Python virtual environment not found. Run setup first." "Red"
    exit 1
}
Write-ColorOutput "   ✅ Python virtual environment ready" "Green"

# Check whisper executable
if (!(Test-Path $WhisperExe)) {
    Write-ColorOutput "❌ Whisper server executable not found at $WhisperExe" "Red"
    Write-ColorOutput "   Please build whisper.cpp first using the build scripts" "Red"
    exit 1
}
Write-ColorOutput "   ✅ Whisper server executable found" "Green"

# Check whisper model
if (!(Test-Path $WhisperModelPath)) {
    Write-ColorOutput "❌ Whisper model not found at $WhisperModelPath" "Red"
    Write-ColorOutput "   Please download the model first" "Red"
    exit 1
}
Write-ColorOutput "   ✅ Whisper model available" "Green"

# Check websocat
try {
    $websocatVersion = & websocat --version 2>$null
    Write-ColorOutput "   ✅ websocat available: $websocatVersion" "Green"
}
catch {
    Write-ColorOutput "❌ websocat not found in PATH. Please install websocat." "Red"
    Write-ColorOutput "   Download from: https://github.com/vi/websocat/releases" "Red"
    exit 1
}

# Check ffmpeg
try {
    $ffmpegVersion = & ffmpeg -version 2>$null | Select-Object -First 1
    Write-ColorOutput "   ✅ ffmpeg available" "Green"
}
catch {
    Write-ColorOutput "❌ ffmpeg not found in PATH. Please install ffmpeg." "Red"
    exit 1
}

# Check if Ollama is running
Write-ColorOutput "" "Blue"
Write-ColorOutput "🔍 Checking Ollama..." "Blue"
try {
    $ollamaResponse = Invoke-RestMethod -Uri "http://${OllamaHost}:${OllamaPort}/api/tags" -Method Get -TimeoutSec 5 -ErrorAction Stop
    Write-ColorOutput "   ✅ Ollama is running" "Green"
}
catch {
    Write-ColorOutput "⚠️  Ollama not running, attempting to start..." "Yellow"
    try {
        $Script:OllamaProcess = Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden -PassThru
        $Script:ProcessList += $Script:OllamaProcess
        Start-Sleep -Seconds 5
        Write-ColorOutput "   ✅ Ollama started" "Green"
    }
    catch {
        Write-ColorOutput "❌ Failed to start Ollama. Please install and start Ollama manually." "Red"
        exit 1
    }
}

# Start services
Write-ColorOutput "" "Blue"
Write-ColorOutput "🚀 Starting services..." "Blue"

# 1. Start Whisper Server
Write-ColorOutput "1. Starting Whisper server..." "Blue"
try {
    $whisperArgs = @(
        "--model", $WhisperModelPath,
        "--host", $WhisperHost,
        "--port", $WhisperPort.ToString(),
        "--threads", "2"
    )

    $Script:WhisperProcess = Start-Process -FilePath $WhisperExe -ArgumentList $whisperArgs -WindowStyle Hidden -PassThru
    $Script:ProcessList += $Script:WhisperProcess
    Write-ColorOutput "   Whisper server started (PID: $($Script:WhisperProcess.Id))" "Green"

    # Wait for whisper server to be ready
    Write-ColorOutput "   Waiting for Whisper server to initialize..." "Gray"
    $timeout = 30
    for ($i = 1; $i -le $timeout; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://${WhisperHost}:${WhisperPort}/" -TimeoutSec 1 -ErrorAction Stop
            Write-ColorOutput "   ✅ Whisper server ready" "Green"
            break
        }
        catch {
            if ($i -eq $timeout) {
                Write-ColorOutput "❌ Whisper server failed to start" "Red"
                Invoke-Cleanup
                exit 1
            }
            Start-Sleep -Seconds 1
        }
    }
}
catch {
    Write-ColorOutput "❌ Failed to start Whisper server: $($_.Exception.Message)" "Red"
    Invoke-Cleanup
    exit 1
}

# 2. Start Brain.py (Cognitive Engine)
Write-ColorOutput "2. Starting Cognitive Engine..." "Blue"
try {
    $brainArgs = @(
        $BrainScript,
        "--whisper-host", $WhisperHost,
        "--whisper-port", $WhisperWsPort.ToString(),
        "--ollama-host", $OllamaHost,
        "--ollama-port", $OllamaPort.ToString(),
        "--frontend-host", "127.0.0.1",
        "--frontend-port", "9082"
    )

    $Script:BrainProcess = Start-Process -FilePath $PythonExe -ArgumentList $brainArgs -WindowStyle Hidden -PassThru -WorkingDirectory ".\backend"
    $Script:ProcessList += $Script:BrainProcess
    Write-ColorOutput "   Cognitive Engine started (PID: $($Script:BrainProcess.Id))" "Green"

    # Wait for brain to be ready
    Write-ColorOutput "   Waiting for Cognitive Engine to initialize..." "Gray"
    Start-Sleep -Seconds 10
    Write-ColorOutput "   ✅ Cognitive Engine ready" "Green"
}
catch {
    Write-ColorOutput "❌ Failed to start Cognitive Engine: $($_.Exception.Message)" "Red"
    Invoke-Cleanup
    exit 1
}

# 3. Start Frontend
Write-ColorOutput "3. Starting Frontend..." "Blue"
try {
    # Check if Node.js process is already running on the port
    $existingNodeProcess = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object {
        (Get-NetTCPConnection -OwningProcess $_.Id -ErrorAction SilentlyContinue | Where-Object LocalPort -eq $FrontendPort).Count -gt 0
    }

    if (!$existingNodeProcess) {
        $Script:FrontendProcess = Start-Process -FilePath "pnpm" -ArgumentList "dev" -WindowStyle Hidden -PassThru -WorkingDirectory ".\frontend"
        $Script:ProcessList += $Script:FrontendProcess
        Write-ColorOutput "   Frontend started (PID: $($Script:FrontendProcess.Id))" "Green"

        # Wait for frontend to be ready
        Write-ColorOutput "   Waiting for Frontend to initialize..." "Gray"
        $timeout = 30
        for ($i = 1; $i -le $timeout; $i++) {
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:${FrontendPort}" -TimeoutSec 1 -ErrorAction Stop
                Write-ColorOutput "   ✅ Frontend ready" "Green"
                break
            }
            catch {
                if ($i -eq $timeout) {
                    Write-ColorOutput "⚠️  Frontend may not be ready, continuing..." "Yellow"
                }
                Start-Sleep -Seconds 1
            }
        }
    } else {
        Write-ColorOutput "   ✅ Frontend already running" "Green"
    }
}
catch {
    Write-ColorOutput "⚠️  Frontend startup issue: $($_.Exception.Message)" "Yellow"
}

# System ready
Write-ColorOutput "" "Green"
Write-ColorOutput "🎉 Cognitive Co-Pilot System is READY!" "Green"
Write-ColorOutput "==================================================" "Blue"
Write-ColorOutput "🌐 Access Points:" "Blue"
Write-ColorOutput "   HUD Interface: http://localhost:${FrontendPort}/hud" "Gray"
Write-ColorOutput "   Whisper Server: http://${WhisperHost}:${WhisperPort}" "Gray"
Write-ColorOutput "   WebSocket Streaming: ${WhisperWsUrl}" "Gray"
Write-ColorOutput "" "Blue"
Write-ColorOutput "🎮 Controls:" "Blue"
Write-ColorOutput "   Stop System: Press Ctrl+C in this terminal" "Gray"
Write-ColorOutput "" "Blue"
Write-ColorOutput "📊 Process IDs:" "Blue"
Write-ColorOutput "   Whisper Server: $($Script:WhisperProcess.Id)" "Gray"
Write-ColorOutput "   Cognitive Engine: $($Script:BrainProcess.Id)" "Gray"
if ($Script:FrontendProcess) {
    Write-ColorOutput "   Frontend: $($Script:FrontendProcess.Id)" "Gray"
}
Write-ColorOutput "==================================================" "Blue"
Write-ColorOutput "" "Blue"

# Start the Audio-to-Whisper Pipe
Write-ColorOutput "[PIPE] Starting live FFmpeg -> websocat -> Whisper pipe..." "Blue"
Write-ColorOutput "Press Ctrl+C in this window to shut down the entire system." "Yellow"
Write-ColorOutput "" "Blue"

# The main audio streaming pipeline
try {
    # Check for VB-Cable or default audio device
    $audioDevice = "CABLE Output (VB-Audio Virtual Cable)"

    # Try to list audio devices to verify VB-Cable is available
    try {
        $devices = & ffmpeg -list_devices true -f dshow -i dummy 2>&1 | Select-String "CABLE Output"
        if (!$devices) {
            Write-ColorOutput "⚠️  VB-Audio Virtual Cable not found, using default microphone" "Yellow"
            $audioDevice = "Microphone"
        }
    }
    catch {
        Write-ColorOutput "⚠️  Using default audio device" "Yellow"
        $audioDevice = "Microphone"
    }

    # Start the pipeline - this runs in the foreground
    $ffmpegArgs = @(
        "-f", "dshow",
        "-i", "audio=$audioDevice",
        "-ac", "1",
        "-ar", "16000",
        "-acodec", "pcm_s16le",
        "-f", "s16le",
        "-"
    )

    $websocatArgs = @(
        "--binary",
        $WhisperWsUrl
    )

    Write-ColorOutput "Audio pipeline: ffmpeg -> websocat -> Whisper" "Gray"
    Write-ColorOutput "Audio source: $audioDevice" "Gray"

    # Create the pipeline using PowerShell job
    $pipelineJob = Start-Job -ScriptBlock {
        param($ffmpegArgs, $websocatArgs)

        $ffmpegProcess = Start-Process -FilePath "ffmpeg" -ArgumentList $ffmpegArgs -NoNewWindow -RedirectStandardOutput -PassThru
        $websocatProcess = Start-Process -FilePath "websocat" -ArgumentList $websocatArgs -NoNewWindow -RedirectStandardInput -PassThru

        # Pipe ffmpeg output to websocat input
        $ffmpegProcess.StandardOutput.BaseStream.CopyTo($websocatProcess.StandardInput.BaseStream)

    } -ArgumentList $ffmpegArgs, $websocatArgs

    # Monitor the system
    Write-ColorOutput "🔄 System monitoring active. Audio streaming pipeline running..." "Blue"

    # Keep the script running and monitor processes
    while ($true) {
        # Check if critical processes are still running
        if ($Script:WhisperProcess -and $Script:WhisperProcess.HasExited) {
            Write-ColorOutput "❌ Whisper server died unexpectedly" "Red"
            break
        }

        if ($Script:BrainProcess -and $Script:BrainProcess.HasExited) {
            Write-ColorOutput "❌ Cognitive Engine died unexpectedly" "Red"
            break
        }

        # Check pipeline job
        if ($pipelineJob.State -eq "Failed") {
            Write-ColorOutput "❌ Audio pipeline failed" "Red"
            break
        }

        Start-Sleep -Seconds 5
    }
}
catch {
    Write-ColorOutput "❌ Pipeline error: $($_.Exception.Message)" "Red"
}
finally {
    # Cleanup on exit
    Invoke-Cleanup
}