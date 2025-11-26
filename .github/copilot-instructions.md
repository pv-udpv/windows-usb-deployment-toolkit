# Copilot Instructions - Windows USB Deployment Toolkit

## Project Overview

**Purpose:** Interactive PowerShell tool for creating bootable USB drives with Windows, Office ODT, and MAS activation

**Tech Stack:**
- PowerShell 5.1+ (Core features)
- PowerShell 7+ (recommended)
- WMI/CIM for hardware detection
- .NET WebClient for downloads
- External tools: Rufus, Ventoy, ODT, MAS

**Target Audience:** Windows SysAdmins, DevOps engineers, IT support

## Code Style & Standards

### PowerShell Conventions

```powershell
# Function naming: Verb-Noun
function Get-USBDrives { }
function Invoke-RufusMethod { }
function Show-MainMenu { }

# Variables: camelCase
$targetUSB = $null
$isoPath = ""
$Config = @{}

# Parameters: PascalCase
param(
    [string]$WindowsIsoPath,
    [string]$Method
)

# Constants: PascalCase with descriptive names
$Global:Config = @{
    RufusUrl = '...'
    VentoyUrl = '...'
}
```

### Error Handling

```powershell
# Always use try-catch for critical operations
try {
    # Download, file operations, external process launch
}
catch {
    Write-ColoredMessage "Error: $_" -Type Error
    return $false
}

# Validate parameters
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({Test-Path $_})]
    [string]$IsoPath
)
```

### Logging Pattern

```powershell
# Use Write-ColoredMessage consistently
Write-ColoredMessage "Starting operation..." -Type Info
Write-ColoredMessage "Success!" -Type Success
Write-ColoredMessage "Warning: Non-critical issue" -Type Warning
Write-ColoredMessage "Fatal error" -Type Error

# Verbose for debugging
Write-Verbose "Detailed diagnostic info" -Verbose:$VerbosePreference
```

## Architecture Patterns

### Modularity

```powershell
# Separate concerns into functions
# Hardware detection
function Get-USBDrives { }

# UI/UX
function Show-USBSelection { }
function Show-MainMenu { }

# Business logic
function Invoke-RufusMethod { }
function Invoke-VentoyMethod { }

# Utilities
function Download-File { }
function Initialize-Workspace { }
```

### Configuration Management

```powershell
# Use hashtable for centralized config
$Global:Config = @{
    RufusUrl    = '...'
    VentoyUrl   = '...'
    WorkDir     = $WorkDir
    ToolsDir    = Join-Path $WorkDir 'Tools'
}

# Access config globally
Download-File -Url $Config.RufusUrl -OutputPath $rufusExe
```

### Return Values

```powershell
# Boolean for success/failure
function Invoke-RufusMethod {
    # ... logic ...
    return $true  # Success
    return $false # Failure
}

# Objects for data
function Get-USBDrives {
    return [PSCustomObject]@{
        Index = 0
        Model = "SanDisk"
        Size  = 32.0
    }
}
```

## Component-Specific Guidelines

### USB Detection (WMI)

```powershell
# Use WMI for hardware detection
Get-WmiObject -Class Win32_DiskDrive | Where-Object {
    $_.InterfaceType -eq 'USB' -and $_.MediaType -match 'Removable'
}

# Associate disk -> partition -> logical drive
$partitions = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='...'} WHERE AssocClass=Win32_DiskDriveToDiskPartition"
```

### File Operations

```powershell
# Always use -Force for automation
New-Item -Path $dir -ItemType Directory -Force | Out-Null
Copy-Item -Path $src -Destination $dst -Recurse -Force

# Suppress output with Out-Null
Expand-Archive -Path $zip -DestinationPath $dest -Force | Out-Null
```

### External Processes

```powershell
# Wait for completion
Start-Process -FilePath $exe -ArgumentList $args -Wait -NoNewWindow

# Interactive tools (Rufus, Ventoy)
Start-Process -FilePath $exe -Wait  # Let user interact with GUI
```

### Downloads

```powershell
# Use .NET WebClient for simple downloads
$webClient = New-Object System.Net.WebClient
$webClient.DownloadFile($url, $outputPath)

# Alternative: Invoke-WebRequest (slower but more features)
Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
```

## UI/UX Guidelines

### Color Coding

```powershell
# Info: Cyan - general information
# Success: Green - operation completed
# Warning: Yellow - non-critical issues
# Error: Red - failures

Write-ColoredMessage "Downloading..." -Type Info
Write-ColoredMessage "Download complete" -Type Success
Write-ColoredMessage "File already exists, skipping" -Type Warning
Write-ColoredMessage "Download failed" -Type Error
```

### User Prompts

```powershell
# Clear choices with visual indicators
Write-Host "  [1] " -NoNewline -ForegroundColor Yellow
Write-Host "Option description"
Write-Host "  [Q] " -NoNewline -ForegroundColor Red
Write-Host "Quit"

# Validate input
do {
    $choice = Read-Host "Select option"
    if ($choice -match '^[12Q]$') { break }
    Write-ColoredMessage "Invalid input" -Type Warning
} while ($true)
```

### Progress Indication

```powershell
# For long operations, provide feedback
Write-ColoredMessage "Downloading Rufus..." -Type Info
# ... download ...
Write-ColoredMessage "Rufus downloaded" -Type Success

# Use separators for sections
Write-ColoredMessage "═══════════════════════════════════════" -Type Info
Write-ColoredMessage "          SECTION TITLE" -Type Info
Write-ColoredMessage "═══════════════════════════════════════" -Type Info
```

## Testing Requirements

### Manual Testing Checklist

- [ ] USB detection with 0, 1, 2+ drives
- [ ] Rufus method with valid/invalid ISO
- [ ] Ventoy method with multiple ISOs
- [ ] MAS download and extraction
- [ ] ODT download and configuration
- [ ] FirstRun.cmd execution after Windows install
- [ ] Office silent install
- [ ] MAS activation (HWID, Ohook, KMS)

### Error Scenarios

- [ ] No USB drives connected
- [ ] Invalid ISO path
- [ ] Download failures (no internet)
- [ ] Insufficient disk space
- [ ] User cancellation mid-process
- [ ] Rufus/Ventoy launch failures

## Documentation Standards

### Function Headers

```powershell
<#
.SYNOPSIS
    Brief description of function
    
.DESCRIPTION
    Detailed explanation of what the function does
    
.PARAMETER TargetUSB
    USB drive object from Get-USBDrives
    
.PARAMETER IsoPath
    Full path to Windows ISO file
    
.EXAMPLE
    Invoke-RufusMethod -TargetUSB $usb -IsoPath "C:\Win11.iso"
    
.NOTES
    Author: pv-udpv
    Requires: Rufus executable
#>
function Invoke-RufusMethod {
    param([object]$TargetUSB, [string]$IsoPath)
    # ...
}
```

### Inline Comments

```powershell
# Download Rufus if not already cached
if (-not (Test-Path $rufusExe)) {
    Download-File -Url $Config.RufusUrl -OutputPath $rufusExe
}

# Launch Rufus and wait for user completion
Start-Process -FilePath $rufusExe -Wait
```

## Integration Points

### Rufus Integration

- Download: Latest portable version from GitHub releases
- Launch: Start-Process with -Wait for user interaction
- Post-process: Copy payload to USB root after completion

### Ventoy Integration

- Download: Ventoy Windows ZIP from GitHub
- Extract: Ventoy2Disk.exe from nested directories
- Post-install: Copy ISO to root, payload to `/PostInstall`

### MAS Integration

- Source: https://github.com/massgravel/Microsoft-Activation-Scripts
- Download: master.zip from GitHub
- Extract: Copy to payload directory
- Usage: User launches MAS_AIO.cmd post-install

### Office ODT Integration

- Download: Official ODT executable from Microsoft
- Extract: Self-extracting exe with `/extract:` parameter
- Config: Generate configuration.xml for silent install
- Languages: ru-ru + en-us
- Exclusions: OneDrive (Groove), Skype (Lync)

## Security Considerations

### Safe Downloads

```powershell
# Use HTTPS URLs only
$Config = @{
    RufusUrl = 'https://github.com/pbatard/rufus/releases/...'
    # Never use HTTP for downloads
}

# Validate file existence after download
if (-not (Test-Path $outputPath)) {
    Write-ColoredMessage "Download failed" -Type Error
    return $false
}
```

### User Confirmations

```powershell
# Warn before destructive operations
Write-ColoredMessage "WARNING: All data on USB will be erased!" -Type Warning
$confirm = Read-Host "Continue? (yes/no)"
if ($confirm -ne 'yes') {
    Write-ColoredMessage "Operation cancelled" -Type Warning
    return $false
}
```

### Admin Rights

```powershell
# Require admin at script level
#Requires -RunAsAdministrator

# Check in functions if needed
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This function requires administrator privileges"
}
```

## Performance Optimization

### Caching

```powershell
# Cache downloaded tools
if (Test-Path $rufusExe) {
    Write-ColoredMessage "Rufus already cached" -Type Success
} else {
    Download-File -Url $Config.RufusUrl -OutputPath $rufusExe
}
```

### Parallel Operations

```powershell
# Download multiple files concurrently (if needed in future)
$jobs = @()
$jobs += Start-Job { Download-File -Url $url1 -OutputPath $path1 }
$jobs += Start-Job { Download-File -Url $url2 -OutputPath $path2 }
$jobs | Wait-Job | Receive-Job
```

## Common Patterns to Avoid

❌ **Don't use Write-Host for data output**
```powershell
# Bad
Write-Host "Result: $value"

# Good
Write-Output $value
return [PSCustomObject]@{ Result = $value }
```

❌ **Don't suppress errors without logging**
```powershell
# Bad
Copy-Item $src $dst -ErrorAction SilentlyContinue

# Good
try {
    Copy-Item $src $dst -ErrorAction Stop
} catch {
    Write-ColoredMessage "Copy failed: $_" -Type Error
}
```

❌ **Don't hardcode paths**
```powershell
# Bad
$path = "C:\Temp\USB"

# Good
$path = Join-Path $env:TEMP 'USB'
$path = Join-Path $Config.WorkDir 'Payload'
```

## Future Enhancements Roadmap

1. **Windows Server ISO support** - detect Server editions, adjust configurations
2. **Driver integration** - DISM commands to inject drivers into WIM
3. **Automated Windows download** - API integration for official ISO downloads
4. **GUI version** - WPF/WinForms for visual interface
5. **Configuration profiles** - Save/load presets for different scenarios
6. **WinGet integration** - Post-install app deployment via winget
7. **Pester tests** - Automated testing framework
8. **CI/CD pipeline** - GitHub Actions for testing and releases

## Additional Notes

- All user-facing messages should be in Russian (as per user preference)
- Code comments can be in English for portability
- Follow PSScriptAnalyzer rules (add `.vscode/PSScriptAnalyzerSettings.psd1` if needed)
- Support both PowerShell 5.1 (Windows) and PowerShell 7+ (cross-platform)
- Optimize for readability over cleverness
- Each function should do one thing well
- Prefer explicit parameter names over positional
