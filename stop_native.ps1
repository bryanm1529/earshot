# stop_native.ps1
# Graceful shutdown script for Earshot Cognitive Co-Pilot on Windows

#Requires -Version 5.1

# Color output function
function Write-ColorOutput($Message, $Color = "White") {
    Write-Host $Message -ForegroundColor $Color
}

# Banner
Write-ColorOutput "" "Red"
Write-ColorOutput "==================================================" "Red"
Write-ColorOutput "🛑 Earshot Cognitive Co-Pilot - System Shutdown" "Red"
Write-ColorOutput "   Graceful Process Termination" "Red"
Write-ColorOutput "==================================================" "Red"
Write-ColorOutput "" "Red"

# Define process names to stop
$ProcessesToStop = @(
    @{ Name = "whisper-server"; Description = "Whisper Server" },
    @{ Name = "server"; Description = "Whisper Server (alt)" },
    @{ Name = "python"; Description = "Python Backend (Brain)" },
    @{ Name = "node"; Description = "Node.js Frontend" },
    @{ Name = "ffmpeg"; Description = "FFmpeg Audio Pipeline" },
    @{ Name = "websocat"; Description = "WebSocket Audio Bridge" },
    @{ Name = "earshot-copilot"; Description = "Tauri Application" }
)

# Optional processes (don't error if not found)
$OptionalProcesses = @(
    @{ Name = "ollama"; Description = "Ollama LLM Server" }
)

Write-ColorOutput "🔍 Scanning for running processes..." "Blue"

$foundProcesses = @()

# Check for main processes
foreach ($procInfo in $ProcessesToStop) {
    $processes = Get-Process -Name $procInfo.Name -ErrorAction SilentlyContinue
    if ($processes) {
        foreach ($proc in $processes) {
            $foundProcesses += @{
                Process = $proc
                Description = $procInfo.Description
                Required = $true
            }
        }
        Write-ColorOutput "   Found: $($procInfo.Description) (PID: $($processes.Id -join ', '))" "Yellow"
    }
}

# Check for optional processes
foreach ($procInfo in $OptionalProcesses) {
    $processes = Get-Process -Name $procInfo.Name -ErrorAction SilentlyContinue
    if ($processes) {
        foreach ($proc in $processes) {
            $foundProcesses += @{
                Process = $proc
                Description = $procInfo.Description
                Required = $false
            }
        }
        Write-ColorOutput "   Found: $($procInfo.Description) (PID: $($processes.Id -join ', ')) [Optional]" "Cyan"
    }
}

if ($foundProcesses.Count -eq 0) {
    Write-ColorOutput "✅ No Earshot processes found running" "Green"
    Write-ColorOutput "   System appears to be already stopped" "Gray"
    exit 0
}

Write-ColorOutput "" "Blue"
Write-ColorOutput "📊 Found $($foundProcesses.Count) process(es) to stop" "Blue"

# Ask for confirmation
$confirmation = Read-Host "   Proceed with shutdown? (Y/n)"
if ($confirmation.ToLower() -eq "n") {
    Write-ColorOutput "❌ Shutdown cancelled by user" "Yellow"
    exit 0
}

Write-ColorOutput "" "Red"
Write-ColorOutput "🛑 Initiating graceful shutdown..." "Red"

# First pass: Try graceful termination
Write-ColorOutput "   Phase 1: Graceful termination..." "Gray"
$gracefulStopped = @()

foreach ($procInfo in $foundProcesses) {
    $proc = $procInfo.Process
    $desc = $procInfo.Description

    try {
        if (!$proc.HasExited) {
            Write-ColorOutput "   Stopping $desc (PID: $($proc.Id))..." "Gray"

            # Try graceful close first
            if ($proc.CloseMainWindow()) {
                # Wait a moment for graceful shutdown
                if ($proc.WaitForExit(3000)) {
                    Write-ColorOutput "   ✅ $desc stopped gracefully" "Green"
                    $gracefulStopped += $proc.Id
                    continue
                }
            }

            # If graceful didn't work, use SIGTERM equivalent
            $proc.Kill()
            if ($proc.WaitForExit(2000)) {
                Write-ColorOutput "   ✅ $desc terminated" "Green"
                $gracefulStopped += $proc.Id
            } else {
                Write-ColorOutput "   ⚠️  $desc may still be running" "Yellow"
            }
        } else {
            Write-ColorOutput "   ✅ $desc already stopped" "Green"
            $gracefulStopped += $proc.Id
        }
    }
    catch {
        Write-ColorOutput "   ⚠️  Error stopping $desc : $($_.Exception.Message)" "Yellow"
    }
}

# Second pass: Force kill any remaining processes
Start-Sleep -Seconds 2

Write-ColorOutput "   Phase 2: Force termination of remaining processes..." "Gray"
$forceKilled = 0

foreach ($procInfo in $ProcessesToStop) {
    $remainingProcesses = Get-Process -Name $procInfo.Name -ErrorAction SilentlyContinue
    foreach ($proc in $remainingProcesses) {
        if ($proc.Id -notin $gracefulStopped) {
            try {
                Write-ColorOutput "   Force killing $($procInfo.Description) (PID: $($proc.Id))..." "Red"
                Stop-Process -Id $proc.Id -Force
                $forceKilled++
            }
            catch {
                Write-ColorOutput "   ❌ Failed to force kill PID $($proc.Id): $($_.Exception.Message)" "Red"
            }
        }
    }
}

# Clean up any temporary files or connections
Write-ColorOutput "   Phase 3: Cleanup..." "Gray"

# Try to clean up any hanging WebSocket connections
try {
    $tcpConnections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                     Where-Object { $_.LocalPort -in @(9080, 10080, 3118, 9082) }

    if ($tcpConnections) {
        Write-ColorOutput "   Found listening ports that may need cleanup..." "Yellow"
        foreach ($conn in $tcpConnections) {
            Write-ColorOutput "   Port $($conn.LocalPort) may still be in use" "Yellow"
        }
    }
}
catch {
    # Ignore errors in cleanup phase
}

# Final verification
Write-ColorOutput "" "Blue"
Write-ColorOutput "🔍 Final verification..." "Blue"

$stillRunning = @()
foreach ($procInfo in $ProcessesToStop) {
    $remaining = Get-Process -Name $procInfo.Name -ErrorAction SilentlyContinue
    if ($remaining) {
        $stillRunning += "$($procInfo.Description) (PID: $($remaining.Id -join ', '))"
    }
}

if ($stillRunning.Count -eq 0) {
    Write-ColorOutput "✅ All Earshot processes successfully stopped!" "Green"

    # Show summary
    Write-ColorOutput "" "Green"
    Write-ColorOutput "📊 Shutdown Summary:" "Green"
    Write-ColorOutput "   Gracefully stopped: $($gracefulStopped.Count) processes" "Gray"
    if ($forceKilled -gt 0) {
        Write-ColorOutput "   Force terminated: $forceKilled processes" "Gray"
    }
    Write-ColorOutput "   System is now fully stopped" "Gray"
} else {
    Write-ColorOutput "⚠️  Some processes may still be running:" "Yellow"
    foreach ($proc in $stillRunning) {
        Write-ColorOutput "   $proc" "Yellow"
    }
    Write-ColorOutput "" "Yellow"
    Write-ColorOutput "💡 You may need to manually stop these processes or restart your computer" "Yellow"
}

Write-ColorOutput "" "Blue"
Write-ColorOutput "==================================================" "Blue"
Write-ColorOutput "🛑 Shutdown procedure completed" "Blue"
Write-ColorOutput "==================================================" "Blue"