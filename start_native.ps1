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

# Configuration Loading Function
function Load-DotEnvFile($filePath) {
    if (Test-Path $filePath) {
        Write-ColorOutput "📋 Loading configuration from $filePath" "Green"
        Get-Content $filePath | ForEach-Object {
            if ($_ -match '^([^#].*)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim().Trim('"').Trim("'")
                Set-Item -Path "env:$name" -Value $value
                Write-ColorOutput "   Set $name = $value" "Gray"
            }
        }
        return $true
    }
    return $false
}

# Load configuration from various sources
$configLoaded = $false

# 1. Try to load .env file (recommended for Windows)
if (Load-DotEnvFile ".env") {
    $configLoaded = $true
}

# 2. Check for .copilotrc and convert to .env format
if (!$configLoaded -and (Test-Path ".copilotrc")) {
    Write-ColorOutput "📋 Found .copilotrc, converting to environment variables" "Green"
    Get-Content ".copilotrc" | ForEach-Object {
        if ($_ -match '^export\s+([^=]+)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"').Trim("'")
            Set-Item -Path "env:$name" -Value $value
            Write-ColorOutput "   Set $name = $value" "Gray"
        }
    }
    $configLoaded = $true
}

if (!$configLoaded) {
    Write-ColorOutput "📋 No configuration file found, using defaults" "Yellow"
}

# Set configuration defaults with environment variable overrides
$env:COPILOT_ADVISOR_MODEL = if ($env:COPILOT_ADVISOR_MODEL) { $env:COPILOT_ADVISOR_MODEL } else { "llama3:8b" }
$env:COPILOT_CHRONICLER_ENABLED = if ($env:COPILOT_CHRONICLER_ENABLED) { $env:COPILOT_CHRONICLER_ENABLED } else { "true" }
$env:COPILOT_WHISPER_HOST = if ($env:COPILOT_WHISPER_HOST) { $env:COPILOT_WHISPER_HOST } else { "127.0.0.1" }
$env:COPILOT_WHISPER_PORT = if ($env:COPILOT_WHISPER_PORT) { $env:COPILOT_WHISPER_PORT } else { "9080" }
$env:COPILOT_OLLAMA_HOST = if ($env:COPILOT_OLLAMA_HOST) { $env:COPILOT_OLLAMA_HOST } else { "127.0.0.1" }
$env:COPILOT_OLLAMA_PORT = if ($env:COPILOT_OLLAMA_PORT) { $env:COPILOT_OLLAMA_PORT } else { "11434" }
$env:COPILOT_FRONTEND_HOST = if ($env:COPILOT_FRONTEND_HOST) { $env:COPILOT_FRONTEND_HOST } else { "127.0.0.1" }
$env:COPILOT_FRONTEND_PORT = if ($env:COPILOT_FRONTEND_PORT) { $env:COPILOT_FRONTEND_PORT } else { "9082" }

# Configuration & Paths using environment variables
$WhisperExe = ".\backend\whisper.cpp\build\bin\Release\server.exe"
$WhisperModelPath = ".\backend\whisper.cpp\models\ggml-tiny.en-q5_1.bin"
$BrainScript = ".\backend\brain.py"
$PythonExe = ".\.venv\Scripts\python.exe"
$WhisperHost = $env:COPILOT_WHISPER_HOST
$WhisperPort = [int]$env:COPILOT_WHISPER_PORT
$WhisperWsPort = $WhisperPort + 1000  # Follow same convention as Linux version
$WhisperWsUrl = "ws://${WhisperHost}:${WhisperWsPort}/hot_stream"
$FrontendPort = 3118  # Next.js dev server port (consistent with package.json)
$OllamaHost = $env:COPILOT_OLLAMA_HOST
$OllamaPort = [int]$env:COPILOT_OLLAMA_PORT

# Banner
Write-ColorOutput "" "Blue"
Write-ColorOutput "==================================================" "Blue"
Write-ColorOutput "🧠 Earshot Cognitive Co-Pilot System" "Blue"
Write-ColorOutput "   Native Windows Production Release" "Blue"
Write-ColorOutput "==================================================" "Blue"
Write-ColorOutput "" "Blue"

Write-ColorOutput "🔧 Configuration:" "Blue"
Write-ColorOutput "   Advisor Model: $env:COPILOT_ADVISOR_MODEL" "Gray"
Write-ColorOutput "   Chronicler: $env:COPILOT_CHRONICLER_ENABLED" "Gray"
Write-ColorOutput "   Whisper Server: ${WhisperHost}:${WhisperPort}" "Gray"
Write-ColorOutput "   WebSocket Stream: ${WhisperHost}:${WhisperWsPort}" "Gray"
Write-ColorOutput "   Ollama: ${OllamaHost}:${OllamaPort}" "Gray"
Write-ColorOutput "   Frontend: http://localhost:${FrontendPort}" "Gray"
Write-ColorOutput "   Cognitive Engine WebSocket: $env:COPILOT_FRONTEND_HOST:$env:COPILOT_FRONTEND_PORT" "Gray"

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

# Check for required models
Write-ColorOutput "" "Blue"
Write-ColorOutput "📦 Checking models..." "Blue"
try {
    $modelsResponse = Invoke-RestMethod -Uri "http://${OllamaHost}:${OllamaPort}/api/tags" -Method Get -TimeoutSec 5 -ErrorAction Stop
    $availableModels = $modelsResponse.models | ForEach-Object { $_.name }

    if ($availableModels -contains $env:COPILOT_ADVISOR_MODEL) {
        Write-ColorOutput "   ✅ Model $env:COPILOT_ADVISOR_MODEL available" "Green"
    } else {
        Write-ColorOutput "⚠️  Model $env:COPILOT_ADVISOR_MODEL not found, pulling..." "Yellow"
        try {
            $pullProcess = Start-Process -FilePath "ollama" -ArgumentList "pull", $env:COPILOT_ADVISOR_MODEL -WindowStyle Hidden -Wait -PassThru
            if ($pullProcess.ExitCode -eq 0) {
                Write-ColorOutput "   ✅ Model $env:COPILOT_ADVISOR_MODEL downloaded successfully" "Green"
            } else {
                Write-ColorOutput "⚠️  Failed to download model, continuing anyway..." "Yellow"
            }
        }
        catch {
            Write-ColorOutput "⚠️  Could not download model: $($_.Exception.Message)" "Yellow"
        }
    }
}
catch {
    Write-ColorOutput "⚠️  Could not check models, continuing..." "Yellow"
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
        "--frontend-host", $env:COPILOT_FRONTEND_HOST,
        "--frontend-port", $env:COPILOT_FRONTEND_PORT
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

    # Create the pipeline using direct piping for better reliability
    Write-ColorOutput "Starting audio pipeline components..." "Gray"

    # Build the pipeline command
    $ffmpegCmd = "ffmpeg " + ($ffmpegArgs -join " ")
    $websocatCmd = "websocat " + ($websocatArgs -join " ")
    $pipelineCmd = "$ffmpegCmd | $websocatCmd"

    Write-ColorOutput "Pipeline command: $pipelineCmd" "Gray"

    # Start the pipeline as a background job with proper error handling
    $pipelineJob = Start-Job -ScriptBlock {
        param($pipelineCommand, $ffmpegArgs, $websocatArgs, $WhisperWsUrl)

        try {
            # Start ffmpeg process
            $ffmpegProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
            $ffmpegProcessInfo.FileName = "ffmpeg"
            $ffmpegProcessInfo.Arguments = $ffmpegArgs -join " "
            $ffmpegProcessInfo.UseShellExecute = $false
            $ffmpegProcessInfo.RedirectStandardOutput = $true
            $ffmpegProcessInfo.RedirectStandardError = $true
            $ffmpegProcess = [System.Diagnostics.Process]::Start($ffmpegProcessInfo)

            # Start websocat process
            $websocatProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
            $websocatProcessInfo.FileName = "websocat"
            $websocatProcessInfo.Arguments = $websocatArgs -join " "
            $websocatProcessInfo.UseShellExecute = $false
            $websocatProcessInfo.RedirectStandardInput = $true
            $websocatProcessInfo.RedirectStandardError = $true
            $websocatProcess = [System.Diagnostics.Process]::Start($websocatProcessInfo)

            # Pipe data between processes
            $buffer = New-Object byte[] 4096
            $ffmpegStream = $ffmpegProcess.StandardOutput.BaseStream
            $websocatStream = $websocatProcess.StandardInput.BaseStream

            while (!$ffmpegProcess.HasExited -and !$websocatProcess.HasExited) {
                $bytesRead = $ffmpegStream.Read($buffer, 0, $buffer.Length)
                if ($bytesRead -gt 0) {
                    $websocatStream.Write($buffer, 0, $bytesRead)
                    $websocatStream.Flush()
                }
            }
        }
        catch {
            Write-Error "Pipeline error: $($_.Exception.Message)"
            throw
        }
        finally {
            if ($ffmpegProcess -and !$ffmpegProcess.HasExited) { $ffmpegProcess.Kill() }
            if ($websocatProcess -and !$websocatProcess.HasExited) { $websocatProcess.Kill() }
        }
    } -ArgumentList $pipelineCmd, $ffmpegArgs, $websocatArgs, $WhisperWsUrl

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