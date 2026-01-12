# build-and-package.ps1
# Build gopls for multiple platforms and compress the output

param(
    [string]$Version = "0.0.1"
)

# Color output functions
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Error { Write-Host $args -ForegroundColor Red }

# Get script root directory
$RootDir = $PSScriptRoot
$GoplsDir = Join-Path $RootDir "gopls"
$BinDir = Join-Path $RootDir "bin"

# Target platforms and architectures
$Targets = @(
    @{ OS = "windows"; Arch = "amd64"; Ext = ".exe" },
    @{ OS = "windows"; Arch = "arm64"; Ext = ".exe" },
    @{ OS = "linux"; Arch = "amd64"; Ext = "" },
    @{ OS = "linux"; Arch = "arm64"; Ext = "" },
    @{ OS = "darwin"; Arch = "amd64"; Ext = "" },
    @{ OS = "darwin"; Arch = "arm64"; Ext = "" }
)

Write-Info "=== Starting Build Process ==="

# Check if gopls directory exists
if (-not (Test-Path $GoplsDir)) {
    Write-Error "Error: gopls directory not found at $GoplsDir"
    exit 1
}

# Navigate to gopls directory
Write-Info "Navigating to gopls directory..."
Push-Location $GoplsDir

try {
    # Install dependencies
    Write-Info "Installing dependencies..."
    go mod download
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download dependencies"
    }
    
    go mod tidy
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to tidy dependencies"
    }
    
    Write-Success "Dependencies installed successfully"

    # Create/Clean bin directory
    if (Test-Path $BinDir) {
        Write-Info "Cleaning existing bin directory..."
        Remove-Item $BinDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    Write-Success "Bin directory ready"

    # Build for each platform
    Write-Info "`nBuilding for multiple platforms..."
    
    foreach ($Target in $Targets) {
        $OutputName = "gopls-$($Target.OS)-$($Target.Arch)$($Target.Ext)"
        $OutputPath = Join-Path $BinDir $OutputName
        
        Write-Info "Building $OutputName..."
        
        $env:GOOS = $Target.OS
        $env:CGO_ENABLED = "0"
        $env:GOARCH = $Target.Arch
        
        go build -o $OutputPath -ldflags "-s -w" .
        
        if ($LASTEXITCODE -eq 0) {
            $Size = (Get-Item $OutputPath).Length / 1MB
            $SizeFormatted = "{0:N2}" -f $Size
            Write-Success "  [OK] Built successfully ($SizeFormatted MB)"
        } else {
            Write-Error "  [FAIL] Build failed for $OutputName"
        }
    }

    # Return to root directory
    Pop-Location

    # Compress bin folder
    Write-Info "`nCompressing bin folder..."
    $ArchiveName = "gopls-binaries-v$Version.zip"
    $ArchivePath = Join-Path $RootDir $ArchiveName

    # Remove existing archive if it exists
    if (Test-Path $ArchivePath) {
        Remove-Item $ArchivePath -Force
    }

    # Create compressed archive
    Compress-Archive -Path $BinDir -DestinationPath $ArchivePath -CompressionLevel Optimal
    
    if (Test-Path $ArchivePath) {
        $ArchiveSize = (Get-Item $ArchivePath).Length / 1MB
        $ArchiveSizeFormatted = "{0:N2}" -f $ArchiveSize
        Write-Success "Archive created: $ArchiveName ($ArchiveSizeFormatted MB)"
    } else {
        Write-Error "Failed to create archive"
        exit 1
    }

    # Summary
    Write-Info "`n=== Build Summary ==="
    Write-Success "Binaries built: $($Targets.Count)"
    Write-Success "Output directory: $BinDir"
    Write-Success "Archive: $ArchivePath"
    
    # List all binaries
    Write-Info "`nBuilt binaries:"
    Get-ChildItem $BinDir | ForEach-Object {
        $Size = $_.Length / 1MB
        $SizeFormatted = "{0:N2}" -f $Size
        Write-Host "  - $($_.Name) ($SizeFormatted MB)"
    }

} catch {
    Write-Error "Build process failed: $_"
    Pop-Location
    exit 1
}

Write-Success "`n=== Build Complete ==="