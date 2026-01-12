# build-and-release.ps1
# Build gopls for multiple platforms and upload to GitHub Release

param(
    [string]$Version = "v0.0.1",
    [switch]$Draft,
    [string]$Title = ""
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

Write-Info "=== Starting Build and Release Process ==="

# Check if gh CLI is installed
Write-Info "Checking for GitHub CLI..."
$ghInstalled = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghInstalled) {
    Write-Error "GitHub CLI (gh) is not installed. Please install it from https://cli.github.com/"
    exit 1
}
Write-Success "GitHub CLI found"

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
    
    $BuiltTargets = @()
    
    foreach ($Target in $Targets) {
        $PlatformDir = Join-Path $BinDir $Target.OS
        $ArchDir = Join-Path $PlatformDir $Target.Arch
        $OutputName = "gopls$($Target.Ext)"
        $OutputPath = Join-Path $ArchDir $OutputName
        
        Write-Info "Building for $($Target.OS)/$($Target.Arch)..."
        
        # Create platform/arch directory
        New-Item -ItemType Directory -Path $ArchDir -Force | Out-Null
        
        $env:GOOS = $Target.OS
        $env:CGO_ENABLED = "0"
        $env:GOARCH = $Target.Arch
        
        go build -o $OutputPath -ldflags "-s -w" .
        
        if ($LASTEXITCODE -eq 0) {
            $Size = (Get-Item $OutputPath).Length / 1MB
            $SizeFormatted = "{0:N2}" -f $Size
            Write-Success "  [OK] Built successfully ($SizeFormatted MB)"
            $BuiltTargets += @{
                OS = $Target.OS
                Arch = $Target.Arch
                Dir = $ArchDir
            }
        } else {
            Write-Error "  [FAIL] Build failed for $($Target.OS)/$($Target.Arch)"
        }
    }

    # Return to root directory
    Pop-Location

    # Create tar.gz archives for each platform/arch
    Write-Info "`nCreating tar.gz archives..."
    
    $Archives = @()
    
    foreach ($Target in $BuiltTargets) {
        $ArchiveName = "gopls-$($Target.OS)-$($Target.Arch).tar.gz"
        $ArchivePath = Join-Path $BinDir $ArchiveName
        
        Write-Info "Creating $ArchiveName..."
        
        # Change to bin directory to create archive with relative paths
        Push-Location $BinDir
        
        # Create archive with platform/arch folder structure
        $RelativePath = Join-Path $Target.OS $Target.Arch
        tar -czf $ArchiveName $RelativePath
        
        Pop-Location
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $ArchivePath)) {
            $ArchiveSize = (Get-Item $ArchivePath).Length / 1MB
            $ArchiveSizeFormatted = "{0:N2}" -f $ArchiveSize
            Write-Success "  [OK] Created $ArchiveName ($ArchiveSizeFormatted MB)"
            $Archives += $ArchiveName
        } else {
            Write-Error "  [FAIL] Failed to create $ArchiveName"
        }
    }

    # Create GitHub Release
    Write-Info "`nCreating GitHub Release $Version..."
    
    Push-Location $RootDir
    
    # Build the gh release create command
    $releaseArgs = @("release", "create", $Version, "--generate-notes")
    
    if ($Draft) {
        $releaseArgs += "--draft"
        Write-Info "Creating as draft release"
    }
    
    if ($Title -ne "") {
        $releaseArgs += "--title"
        $releaseArgs += $Title
    }
    
    # Add all archives as arguments
    foreach ($Archive in $Archives) {
        $ArchivePath = Join-Path $BinDir $Archive
        $releaseArgs += $ArchivePath
    }
    
    Write-Info "Uploading $($Archives.Count) archives to GitHub..."
    
    # Execute gh release create
    & gh @releaseArgs
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "`nRelease created successfully!"
    } else {
        Write-Error "Failed to create release"
        exit 1
    }
    
    Pop-Location

    # Summary
    Write-Info "`n=== Build and Release Summary ==="
    Write-Success "Binaries built: $($BuiltTargets.Count)"
    Write-Success "Archives created: $($Archives.Count)"
    Write-Success "Release version: $Version"
    
    if ($Draft) {
        Write-Info "Release Status: DRAFT (not published)"
    } else {
        Write-Success "Release Status: PUBLISHED"
    }
    
    # List all archives
    Write-Info "`nUploaded archives:"
    foreach ($Archive in $Archives) {
        $ArchivePath = Join-Path $BinDir $Archive
        if (Test-Path $ArchivePath) {
            $Size = (Get-Item $ArchivePath).Length / 1MB
            $SizeFormatted = "{0:N2}" -f $Size
            Write-Host "  - $Archive ($SizeFormatted MB)"
        }
    }
    
    Write-Info "`nDirectory structure:"
    Write-Host "  bin/" -ForegroundColor Yellow
    foreach ($Target in $BuiltTargets) {
        Write-Host "    $($Target.OS)/" -ForegroundColor Yellow
        Write-Host "      $($Target.Arch)/" -ForegroundColor Yellow
        Write-Host "        gopls$($Target.Ext)" -ForegroundColor Green
    }
    
    Write-Info "`nTo fetch the tag locally, run:"
    Write-Host "  git fetch --tags origin" -ForegroundColor Yellow

} catch {
    Write-Error "Build and release process failed: $_"
    Pop-Location
    exit 1
}

Write-Success "`n=== Build and Release Complete ==="