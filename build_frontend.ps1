# Build Frontend for Earshot Copilot
# This script builds the Next.js frontend and packages it with Tauri

Write-Host "Building Earshot Copilot Frontend..." -ForegroundColor Green

# Navigate to frontend directory
Set-Location frontend

# Install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Yellow
pnpm install

# Build Next.js static export
Write-Host "Building Next.js static export..." -ForegroundColor Yellow
pnpm build

# Build Tauri application
Write-Host "Building Tauri application..." -ForegroundColor Yellow
pnpm tauri build

Write-Host "Frontend build complete!" -ForegroundColor Green
Write-Host "Executable location: frontend/src-tauri/target/release/earshot-copilot.exe" -ForegroundColor Cyan

# Return to root directory
Set-Location ..