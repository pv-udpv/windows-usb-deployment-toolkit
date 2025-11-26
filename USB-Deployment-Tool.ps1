<#
.SYNOPSIS
    Interactive Windows USB Deployment Toolkit
    
.DESCRIPTION
    Creates bootable USB with Windows ISO, Office ODT, and MAS activation
    Supports Rufus and Ventoy methods with automatic configuration
    Includes enhanced USB detection with partition, bootloader, and content analysis
    
.NOTES
    Author: pv-udpv
    Version: 1.1.0
    Requires: PowerShell 5.1+, Admin rights
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Rufus', 'Ventoy', 'Auto')]
    [string]$Method = 'Auto',
    
    [Parameter(Mandatory = $false)]
    [string]$WindowsIsoPath,
    
    [Parameter(Mandatory = $false)]
    [string]$WorkDir = "$env:TEMP\USBDeployment"
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$Global:Config = @{
    RufusUrl     = 'https://github.com/pbatard/rufus/releases/download/v4.6/rufus-4.6p.exe'
    VentoyUrl    = 'https://github.com/ventoy/Ventoy/releases/download/v1.0.99/ventoy-1.0.99-windows.zip'
    MASUrl       = 'https://github.com/massgravel/Microsoft-Activation-Scripts/archive/refs/heads/master.zip'
    ODTUrl       = 'https://download.microsoft.com/download/2/7/A/27AF1BE6-DD20-4CB4-B154-EBAB8A7D4A7E/officedeploymenttool_17328-20162.exe'
    WorkDir      = $WorkDir
    ToolsDir     = Join-Path $WorkDir 'Tools'
    PayloadDir   = Join-Path $WorkDir 'Payload'
    ISODir       = Join-Path $WorkDir 'ISO'
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-ColoredMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )
    
    $color = switch ($Type) {
        'Info'    { 'Cyan' }
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
    }
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor Gray
    Write-Host $Message -ForegroundColor $color
}

function Initialize-Workspace {
    Write-ColoredMessage "Initializing workspace..." -Type Info
    
    @($Config.WorkDir, $Config.ToolsDir, $Config.PayloadDir, $Config.ISODir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
            Write-Verbose "Created directory: $_"
        }
    }
    
    Write-ColoredMessage "Workspace ready: $($Config.WorkDir)" -Type Success
}

function Get-USBDrives {
    Write-ColoredMessage "Scanning for USB drives..." -Type Info
    
    $usbDrives = Get-WmiObject -Class Win32_DiskDrive | Where-Object {
        $_.InterfaceType -eq 'USB' -and $_.MediaType -match 'Removable'
    } | ForEach-Object {
        $disk = $_
        $partitions = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($disk.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition"
        
        foreach ($partition in $partitions) {
            $logicalDisk = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($partition.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition"
            
            if ($logicalDisk) {
                [PSCustomObject]@{
                    Index        = $disk.Index
                    DeviceID     = $disk.DeviceID
                    Model        = $disk.Model.Trim()
                    Size         = [math]::Round($disk.Size / 1GB, 2)
                    DriveLetter  = $logicalDisk.DeviceID
                    VolumeName   = $logicalDisk.VolumeName
                    FileSystem   = $logicalDisk.FileSystem
                }
            }
        }
    }
    
    return $usbDrives
}

function Get-USBDrivesDetailed {
    <#
    .SYNOPSIS
        Enhanced USB drive scanning with partition, bootloader, and content detection
        
    .DESCRIPTION
        Detects USB drives and analyzes:
        - Partition style (GPT/MBR/RAW)
        - Existing bootloaders (Ventoy, Rufus, Generic UEFI)
        - Boot capability (UEFI/BIOS)
        - EFI partition presence
        - Content type (ISOs, Windows media)
        - Warnings for existing data
        
    .EXAMPLE
        $drives = Get-USBDrivesDetailed
        
    .NOTES
        Requires Administrator rights
    #>
    
    Write-ColoredMessage "Scanning for USB drives (detailed)..." -Type Info
    
    $usbDrives = Get-WmiObject -Class Win32_DiskDrive | Where-Object {
        $_.InterfaceType -eq 'USB' -and $_.MediaType -match 'Removable'
    } | ForEach-Object {
        $disk = $_
        $diskNumber = $disk.Index
        
        # Get partition style (GPT/MBR/RAW) using Get-Disk
        $diskInfo = $null
        $partitionStyle = 'Unknown'
        try {
            $diskInfo = Get-Disk -Number $diskNumber -ErrorAction SilentlyContinue
            if ($diskInfo) {
                $partitionStyle = $diskInfo.PartitionStyle
            }
        }
        catch {
            Write-Verbose "Could not get disk info for disk $diskNumber : $_"
        }
        
        # Get partitions using Get-Partition
        $partitions = $null
        $partitionCount = 0
        try {
            $partitions = Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue
            if ($partitions) {
                $partitionCount = @($partitions).Count
            }
        }
        catch {
            Write-Verbose "Could not get partitions for disk $diskNumber : $_"
        }
        
        # Detect EFI partition (GUID: c12a7328-f81f-11d2-ba4b-00a0c93ec93b)
        $hasEFIPartition = $false
        if ($partitions -and $partitionStyle -eq 'GPT') {
            $efiPartition = $partitions | Where-Object {
                $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
            }
            $hasEFIPartition = [bool]$efiPartition
        }
        
        # Get WMI partitions and logical disks for drive letter mapping
        $wmiPartitions = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($disk.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition"
        
        $primaryDriveLetter = $null
        $primaryVolumeName = $null
        $primaryFileSystem = $null
        $allDriveLetters = @()
        
        foreach ($wmiPartition in $wmiPartitions) {
            $logicalDisk = Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($wmiPartition.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition"
            if ($logicalDisk) {
                if (-not $primaryDriveLetter) {
                    $primaryDriveLetter = $logicalDisk.DeviceID
                    $primaryVolumeName = $logicalDisk.VolumeName
                    $primaryFileSystem = $logicalDisk.FileSystem
                }
                $allDriveLetters += $logicalDisk.DeviceID
            }
        }
        
        # Initialize detection variables
        $bootloader = 'None'
        $bootType = 'Unknown'
        $contentType = 'Empty'
        $isoFiles = @()
        $warnings = @()
        
        # Analyze each partition with drive letter
        foreach ($driveLetter in $allDriveLetters) {
            $drivePath = "$driveLetter\"
            
            if (-not (Test-Path $drivePath -ErrorAction SilentlyContinue)) {
                continue
            }
            
            # Check for Ventoy
            if (Test-Path "$drivePath`ventoy" -ErrorAction SilentlyContinue) {
                $bootloader = 'Ventoy'
                $bootType = 'UEFI/BIOS (Multi-boot)'
                
                # Try to get Ventoy version from grub.cfg
                $grubCfg = "$drivePath`grub\grub.cfg"
                
                if (Test-Path $grubCfg -ErrorAction SilentlyContinue) {
                    try {
                        $grubContent = Get-Content $grubCfg -Raw -ErrorAction SilentlyContinue
                        if ($grubContent -match 'Ventoy\s+(\d+\.\d+\.\d+)') {
                            $bootloader = "Ventoy $($Matches[1])"
                        }
                    }
                    catch { }
                }
                
                $warnings += 'Ventoy detected - will be overwritten!'
                
                # Check for ISO files (only at root level for performance)
                $isoFilesList = Get-ChildItem -Path $drivePath -Filter '*.iso' -ErrorAction SilentlyContinue
                if ($isoFilesList) {
                    $isoFiles = $isoFilesList | Select-Object -ExpandProperty Name
                    $contentType = "$($isoFiles.Count) ISO file(s)"
                    $warnings += "Contains $($isoFiles.Count) ISO files"
                }
            }
            # Check for Windows bootloader (Rufus or manual)
            elseif ((Test-Path "$drivePath`bootmgr.efi" -ErrorAction SilentlyContinue) -or 
                    (Test-Path "$drivePath`bootmgr" -ErrorAction SilentlyContinue)) {
                $bootloader = 'Windows Bootloader'
                
                if ($hasEFIPartition -or (Test-Path "$drivePath`efi\boot\bootx64.efi" -ErrorAction SilentlyContinue)) {
                    $bootType = 'UEFI'
                } else {
                    $bootType = 'BIOS'
                }
                
                # Check if it's Windows installation media
                if (Test-Path "$drivePath`sources\install.wim" -ErrorAction SilentlyContinue) {
                    $contentType = 'Windows Installation Media'
                    $warnings += 'Contains Windows installation media'
                } elseif (Test-Path "$drivePath`sources\install.esd" -ErrorAction SilentlyContinue) {
                    $contentType = 'Windows Installation Media'
                    $warnings += 'Contains Windows installation media'
                }
                
                $warnings += 'Windows bootloader detected - will be overwritten!'
            }
            # Check for generic UEFI boot
            elseif (Test-Path "$drivePath`efi\boot\bootx64.efi" -ErrorAction SilentlyContinue) {
                $bootloader = 'Generic UEFI'
                $bootType = 'UEFI'
                $warnings += 'UEFI bootloader detected - will be overwritten!'
            }
            # Check for GRUB (Linux)
            elseif (Test-Path "$drivePath`grub" -ErrorAction SilentlyContinue) {
                $bootloader = 'GRUB (Linux)'
                $bootType = 'UEFI/BIOS'
                $warnings += 'Linux bootloader detected - will be overwritten!'
            }
        }
        
        # Determine boot type based on partition style if not detected
        if ($bootType -eq 'Unknown') {
            if ($partitionStyle -eq 'GPT') {
                $bootType = if ($hasEFIPartition) { 'UEFI capable' } else { 'Not formatted for boot' }
            } elseif ($partitionStyle -eq 'MBR') {
                $bootType = 'BIOS capable'
            } elseif ($partitionStyle -eq 'RAW') {
                $bootType = 'Not formatted'
            }
        }
        
        # Determine status and recommendation
        $status = 'Ready'
        $recommendation = 'Ready for deployment'
        
        if ($warnings.Count -gt 0) {
            $status = 'Warning'
            $recommendation = 'Backup data before proceeding'
        }
        
        if ($partitionStyle -eq 'RAW' -or -not $primaryFileSystem) {
            $contentType = 'Unformatted'
            $recommendation = 'Can be formatted and used'
        }
        
        [PSCustomObject]@{
            Index            = $diskNumber
            DeviceID         = $disk.DeviceID
            Model            = $disk.Model.Trim()
            Size             = [math]::Round($disk.Size / 1GB, 2)
            DriveLetter      = $primaryDriveLetter
            VolumeName       = $primaryVolumeName
            FileSystem       = $primaryFileSystem
            PartitionStyle   = $partitionStyle
            PartitionCount   = $partitionCount
            HasEFIPartition  = $hasEFIPartition
            Bootloader       = $bootloader
            BootType         = $bootType
            ContentType      = $contentType
            ISOFiles         = ($isoFiles -join ', ')
            Status           = $status
            Warnings         = $warnings
            Recommendation   = $recommendation
        }
    }
    
    return $usbDrives
}

function Show-USBSelection {
    $usbDrives = Get-USBDrives
    
    if (-not $usbDrives) {
        Write-ColoredMessage "No USB drives detected!" -Type Error
        return $null
    }
    
    Write-Host ""
    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
    Write-ColoredMessage "              AVAILABLE USB DRIVES" -Type Info
    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
    Write-Host ""
    
    for ($i = 0; $i -lt $usbDrives.Count; $i++) {
        $drive = $usbDrives[$i]
        Write-Host "  [$i] " -NoNewline -ForegroundColor Yellow
        Write-Host "$($drive.DriveLetter) - $($drive.Model)" -NoNewline
        Write-Host " ($($drive.Size) GB)" -ForegroundColor Gray
        if ($drive.VolumeName) {
            Write-Host "      Label: $($drive.VolumeName) | FS: $($drive.FileSystem)" -ForegroundColor DarkGray
        }
    }
    
    Write-Host ""
    Write-Host "  [Q] " -NoNewline -ForegroundColor Red
    Write-Host "Quit"
    Write-Host ""
    
    do {
        $selection = Read-Host "Select USB drive number"
        
        if ($selection -eq 'Q') {
            return $null
        }
        
        if ($selection -match '^\d+$' -and [int]$selection -lt $usbDrives.Count) {
            return $usbDrives[[int]$selection]
        }
        
        Write-ColoredMessage "Invalid selection. Please try again." -Type Warning
    } while ($true)
}

function Show-USBSelectionEnhanced {
    <#
    .SYNOPSIS
        Enhanced USB drive selection with detailed information display
        
    .DESCRIPTION
        Displays USB drives with partition, bootloader, and content details.
        Includes color-coded status, warnings, and safety confirmations.
        
    .EXAMPLE
        $selectedUSB = Show-USBSelectionEnhanced
        
    .NOTES
        Uses Get-USBDrivesDetailed for enhanced detection
    #>
    
    # Main loop for rescan capability (avoids recursion)
    while ($true) {
        $usbDrives = Get-USBDrivesDetailed
        
        if (-not $usbDrives) {
            Write-ColoredMessage "No USB drives detected!" -Type Error
            Write-Host ""
            Write-Host "  Possible causes:" -ForegroundColor Gray
            Write-Host "  - No USB drives connected" -ForegroundColor Gray
            Write-Host "  - USB drives not recognized by Windows" -ForegroundColor Gray
            Write-Host "  - USB drives are in use by another process" -ForegroundColor Gray
            Write-Host ""
            return $null
        }
        
        # Ensure $usbDrives is an array
        $usbDrives = @($usbDrives)
        
        Write-Host ""
        Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
        Write-ColoredMessage "          AVAILABLE USB DRIVES (DETAILED SCAN)" -Type Info
        Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
        Write-Host ""
        
        for ($i = 0; $i -lt $usbDrives.Count; $i++) {
            $drive = $usbDrives[$i]
            
            # Drive header line
            Write-Host "  [$i] " -NoNewline -ForegroundColor Yellow
            if ($drive.DriveLetter) {
                Write-Host "$($drive.DriveLetter) - " -NoNewline
            }
            Write-Host "$($drive.Model)" -NoNewline
            Write-Host " ($($drive.Size) GB)" -ForegroundColor Gray
            
            # Partition and bootloader info
            $partitionInfo = "Partition: $($drive.PartitionStyle)"
            $bootloaderInfo = "Bootloader: $($drive.Bootloader)"
            $bootTypeInfo = "Type: $($drive.BootType)"
            
            Write-Host "      " -NoNewline
            Write-Host "$partitionInfo" -NoNewline -ForegroundColor Cyan
            Write-Host " | " -NoNewline -ForegroundColor Gray
            Write-Host "$bootloaderInfo" -NoNewline -ForegroundColor Cyan
            Write-Host " | " -NoNewline -ForegroundColor Gray
            Write-Host "$bootTypeInfo" -ForegroundColor Cyan
            
            # Content info (if not empty)
            if ($drive.ContentType -and $drive.ContentType -ne 'Empty') {
                Write-Host "      Content: " -NoNewline -ForegroundColor Gray
                Write-Host "$($drive.ContentType)" -ForegroundColor White
            }
            
            # ISO files list (if any)
            if ($drive.ISOFiles) {
                Write-Host "      ISO Files: " -NoNewline -ForegroundColor Gray
                Write-Host "$($drive.ISOFiles)" -ForegroundColor DarkCyan
            }
            
            # Warnings
            foreach ($warning in $drive.Warnings) {
                Write-Host "      " -NoNewline
                Write-Host ([char]0x26A0) -NoNewline -ForegroundColor Yellow  # Warning symbol
                Write-Host "  $warning" -ForegroundColor Yellow
            }
            
            # Status indicator
            if ($drive.Status -eq 'Warning') {
                Write-Host "      Status: " -NoNewline -ForegroundColor Gray
                Write-Host ([char]0x26A0) -NoNewline -ForegroundColor Yellow
                Write-Host "  $($drive.Recommendation)" -ForegroundColor Yellow
            } else {
                Write-Host "      Status: " -NoNewline -ForegroundColor Gray
                Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green  # Checkmark
                Write-Host " $($drive.Recommendation)" -ForegroundColor Green
            }
            
            Write-Host ""
        }
        
        Write-Host "  [Q] " -NoNewline -ForegroundColor Red
        Write-Host "Quit"
        Write-Host "  [R] " -NoNewline -ForegroundColor Cyan
        Write-Host "Rescan USB drives"
        Write-Host ""
        
        # Selection loop
        $rescanRequested = $false
        do {
            $selection = Read-Host "Select USB drive number"
            
            if ($selection -eq 'Q' -or $selection -eq 'q') {
                return $null
            }
            
            if ($selection -eq 'R' -or $selection -eq 'r') {
                # Break inner loop to rescan (outer loop will restart)
                $rescanRequested = $true
                break
            }
            
            if ($selection -match '^\d+$' -and [int]$selection -lt $usbDrives.Count) {
                $selectedDrive = $usbDrives[[int]$selection]
                
                # If drive has warnings, require explicit confirmation
                if ($selectedDrive.Warnings.Count -gt 0) {
                    Write-Host ""
                    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Warning
                    Write-Host "  " -NoNewline
                    Write-Host ([char]0x26A0) -NoNewline -ForegroundColor Red
                    Write-Host "  WARNING: Selected USB drive has existing data!" -ForegroundColor Red
                    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Warning
                    Write-Host ""
                    
                    Write-Host "  Drive: " -NoNewline -ForegroundColor Gray
                    Write-Host "$($selectedDrive.Model) ($($selectedDrive.Size) GB)" -ForegroundColor White
                    Write-Host ""
                    Write-Host "  Current State:" -ForegroundColor Gray
                    
                    foreach ($warning in $selectedDrive.Warnings) {
                        Write-Host "    " -NoNewline
                        Write-Host ([char]0x26A0) -NoNewline -ForegroundColor Yellow
                        Write-Host "  $warning" -ForegroundColor Yellow
                    }
                    
                    Write-Host ""
                    Write-Host "  All data on this drive will be " -NoNewline -ForegroundColor Gray
                    Write-Host "PERMANENTLY ERASED!" -ForegroundColor Red
                    Write-Host ""
                    
                    $confirm = Read-Host "Are you ABSOLUTELY sure you want to continue? (type 'YES' to confirm)"
                    
                    if ($confirm -ceq 'YES') {
                        Write-ColoredMessage "Proceeding with selected USB drive..." -Type Info
                        return $selectedDrive
                    } else {
                        Write-ColoredMessage "Operation cancelled. Please select a different drive." -Type Warning
                        Write-Host ""
                        continue
                    }
                }
                
                return $selectedDrive
            }
            
            Write-ColoredMessage "Invalid selection. Please try again." -Type Warning
        } while ($true)
        
        # If rescan was requested, continue outer loop (rescan)
        if ($rescanRequested) {
            continue
        }
    }
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath,
        [string]$Description = "File"
    )
    
    try {
        Write-ColoredMessage "Downloading $Description..." -Type Info
        Write-Verbose "URL: $Url"
        Write-Verbose "Output: $OutputPath"
        
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($Url, $OutputPath)
        
        Write-ColoredMessage "Downloaded: $Description" -Type Success
        return $true
    }
    catch {
        Write-ColoredMessage "Failed to download $Description : $_" -Type Error
        return $false
    }
}

function Get-WindowsISO {
    if ($WindowsIsoPath -and (Test-Path $WindowsIsoPath)) {
        Write-ColoredMessage "Using provided ISO: $WindowsIsoPath" -Type Success
        return $WindowsIsoPath
    }
    
    Write-Host ""
    Write-ColoredMessage "Windows ISO Selection" -Type Info
    Write-ColoredMessage "─────────────────────────────────────────────────────────────" -Type Info
    Write-Host ""
    Write-Host "  [1] " -NoNewline -ForegroundColor Yellow
    Write-Host "Specify path to existing ISO"
    Write-Host "  [2] " -NoNewline -ForegroundColor Yellow
    Write-Host "Download Windows 11 (requires manual download via browser)"
    Write-Host "  [3] " -NoNewline -ForegroundColor Yellow
    Write-Host "Skip ISO (configure USB only)"
    Write-Host ""
    
    $choice = Read-Host "Select option"
    
    switch ($choice) {
        '1' {
            do {
                $path = Read-Host "Enter full path to Windows ISO"
                if (Test-Path $path) {
                    return $path
                }
                Write-ColoredMessage "File not found. Please try again." -Type Warning
            } while ($true)
        }
        '2' {
            Write-ColoredMessage "Opening Windows 11 download page..." -Type Info
            Start-Process "https://www.microsoft.com/software-download/windows11"
            Write-Host ""
            Write-ColoredMessage "Please download Windows 11 ISO and save it to:" -Type Info
            Write-Host "  $($Config.ISODir)" -ForegroundColor Yellow
            Write-Host ""
            Read-Host "Press Enter when download is complete"
            
            $isoFiles = Get-ChildItem -Path $Config.ISODir -Filter "*.iso" -ErrorAction SilentlyContinue
            if ($isoFiles) {
                return $isoFiles[0].FullName
            } else {
                Write-ColoredMessage "No ISO found in directory. Proceeding without ISO." -Type Warning
                return $null
            }
        }
        '3' {
            Write-ColoredMessage "Skipping ISO configuration." -Type Warning
            return $null
        }
        default {
            Write-ColoredMessage "Invalid option. Skipping ISO." -Type Warning
            return $null
        }
    }
}

# ============================================================================
# PAYLOAD PREPARATION
# ============================================================================

function Get-MASActivation {
    Write-ColoredMessage "Preparing MAS (Microsoft Activation Scripts)..." -Type Info
    
    $masZip = Join-Path $Config.ToolsDir 'MAS.zip'
    $masExtract = Join-Path $Config.ToolsDir 'MAS'
    
    if (-not (Test-Path $masExtract)) {
        if (Download-File -Url $Config.MASUrl -OutputPath $masZip -Description "MAS Scripts") {
            Expand-Archive -Path $masZip -DestinationPath $masExtract -Force
            Write-ColoredMessage "MAS extracted successfully" -Type Success
        } else {
            return $false
        }
    } else {
        Write-ColoredMessage "MAS already available" -Type Success
    }
    
    # Copy MAS to payload
    $masPayload = Join-Path $Config.PayloadDir 'MAS'
    Copy-Item -Path "$masExtract\Microsoft-Activation-Scripts-master\*" -Destination $masPayload -Recurse -Force
    
    Write-ColoredMessage "MAS ready in payload" -Type Success
    return $true
}

function Get-OfficeODT {
    Write-ColoredMessage "Preparing Office Deployment Tool..." -Type Info
    
    $odtExe = Join-Path $Config.ToolsDir 'officedeploymenttool.exe'
    $odtExtract = Join-Path $Config.ToolsDir 'ODT'
    
    if (-not (Test-Path $odtExtract)) {
        if (Download-File -Url $Config.ODTUrl -OutputPath $odtExe -Description "Office Deployment Tool") {
            # Extract ODT (self-extracting executable)
            Start-Process -FilePath $odtExe -ArgumentList "/quiet /extract:`"$odtExtract`"" -Wait -NoNewWindow
            Write-ColoredMessage "ODT extracted successfully" -Type Success
        } else {
            return $false
        }
    } else {
        Write-ColoredMessage "ODT already available" -Type Success
    }
    
    # Create Office configuration
    $odtPayload = Join-Path $Config.PayloadDir 'Office'
    if (-not (Test-Path $odtPayload)) {
        New-Item -Path $odtPayload -ItemType Directory -Force | Out-Null
    }
    
    # Copy setup.exe
    Copy-Item -Path "$odtExtract\setup.exe" -Destination $odtPayload -Force
    
    # Generate configuration.xml
    $configXml = @'
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="ru-ru" />
      <Language ID="en-us" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="AUTOACTIVATE" Value="1" />
</Configuration>
'@
    
    $configXml | Out-File -FilePath (Join-Path $odtPayload 'configuration.xml') -Encoding UTF8
    
    Write-ColoredMessage "Office ODT ready in payload" -Type Success
    return $true
}

function Create-AutorunScript {
    Write-ColoredMessage "Creating autorun scripts..." -Type Info
    
    # Create FirstRun.cmd for post-install execution
    $firstRunCmd = @'
@echo off
REM Windows Post-Install Automation Script
REM Author: pv-udpv

echo ========================================
echo   Windows Post-Install Setup
echo ========================================
echo.

REM Set script directory
set SCRIPT_DIR=%~dp0

echo [1/3] Installing Microsoft Office...
if exist "%SCRIPT_DIR%Office\setup.exe" (
    cd /d "%SCRIPT_DIR%Office"
    setup.exe /configure configuration.xml
    echo Office installation started in background.
) else (
    echo Office files not found. Skipping.
)

echo.
echo [2/3] Waiting for Office installation to complete...
timeout /t 30 /nobreak

echo.
echo [3/3] Launching MAS Activation...
if exist "%SCRIPT_DIR%MAS\MAS_AIO.cmd" (
    cd /d "%SCRIPT_DIR%MAS"
    start MAS_AIO.cmd
    echo MAS activation tool launched.
) else (
    echo MAS not found. Skipping activation.
)

echo.
echo ========================================
echo   Post-Install Setup Complete
echo ========================================
echo.
echo Please follow MAS activation wizard.
echo.
pause
'@
    
    $firstRunCmd | Out-File -FilePath (Join-Path $Config.PayloadDir 'FirstRun.cmd') -Encoding ASCII
    
    # Create README
    $readme = @'
# Windows USB Deployment Toolkit - Payload

## Contents

### MAS (Microsoft Activation Scripts)
- Location: /MAS/
- Usage: Run MAS_AIO.cmd after Windows installation
- Features: HWID, KMS38, Online KMS activation

### Office Deployment Tool
- Location: /Office/
- Configuration: configuration.xml (O365 ProPlus, RU+EN)
- Silent install: Automatic via FirstRun.cmd

### FirstRun.cmd
- Automated post-install script
- Installs Office silently
- Launches MAS activation

## Usage Instructions

### Method 1: Automatic (via FirstRun.cmd)
1. After Windows installation, copy entire USB contents to C:\Temp
2. Run FirstRun.cmd as Administrator
3. Follow MAS activation wizard

### Method 2: Manual
1. Install Office: Office\setup.exe /configure Office\configuration.xml
2. Activate: Run MAS\MAS_AIO.cmd

## Notes
- Office installation runs silently (no UI)
- MAS requires user interaction for activation method selection
- Internet connection required for Office download/activation

Generated by: Windows USB Deployment Toolkit
Repository: https://github.com/pv-udpv/windows-usb-deployment-toolkit
'@
    
    $readme | Out-File -FilePath (Join-Path $Config.PayloadDir 'README.md') -Encoding UTF8
    
    Write-ColoredMessage "Autorun scripts created" -Type Success
}

# ============================================================================
# RUFUS METHOD
# ============================================================================

function Invoke-RufusMethod {
    param([object]$TargetUSB, [string]$IsoPath)
    
    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
    Write-ColoredMessage "              RUFUS METHOD" -Type Info
    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
    
    # Download Rufus
    $rufusExe = Join-Path $Config.ToolsDir 'rufus.exe'
    if (-not (Test-Path $rufusExe)) {
        if (-not (Download-File -Url $Config.RufusUrl -OutputPath $rufusExe -Description "Rufus")) {
            return $false
        }
    }
    
    Write-Host ""
    Write-ColoredMessage "Rufus will be launched with the following settings:" -Type Info
    Write-Host "  Target USB: " -NoNewline
    Write-Host "$($TargetUSB.DriveLetter) - $($TargetUSB.Model) ($($TargetUSB.Size) GB)" -ForegroundColor Yellow
    if ($IsoPath) {
        Write-Host "  Windows ISO: " -NoNewline
        Write-Host "$IsoPath" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-ColoredMessage "WARNING: All data on the USB drive will be erased!" -Type Warning
    Write-Host ""
    
    $confirm = Read-Host "Continue? (yes/no)"
    if ($confirm -ne 'yes') {
        Write-ColoredMessage "Operation cancelled by user." -Type Warning
        return $false
    }
    
    # Launch Rufus
    Write-ColoredMessage "Launching Rufus..." -Type Info
    Write-Host ""
    Write-ColoredMessage "RUFUS INSTRUCTIONS:" -Type Info
    Write-Host "  1. Select your USB device: $($TargetUSB.Model)" -ForegroundColor Cyan
    if ($IsoPath) {
        Write-Host "  2. Click SELECT and choose: $IsoPath" -ForegroundColor Cyan
    }
    Write-Host "  3. Partition scheme: GPT" -ForegroundColor Cyan
    Write-Host "  4. Target system: UEFI" -ForegroundColor Cyan
    Write-Host "  5. Click START" -ForegroundColor Cyan
    Write-Host "  6. Wait for completion and close Rufus" -ForegroundColor Cyan
    Write-Host ""
    
    Start-Process -FilePath $rufusExe -Wait
    
    Write-Host ""
    $completed = Read-Host "Did Rufus complete successfully? (yes/no)"
    
    if ($completed -eq 'yes') {
        # Copy payload to USB
        Write-ColoredMessage "Copying payload files to USB..." -Type Info
        
        $usbPayloadDir = Join-Path $TargetUSB.DriveLetter 'PostInstall'
        Copy-Item -Path $Config.PayloadDir -Destination $usbPayloadDir -Recurse -Force
        
        Write-ColoredMessage "Payload copied to: $usbPayloadDir" -Type Success
        return $true
    } else {
        Write-ColoredMessage "Rufus operation incomplete." -Type Warning
        return $false
    }
}

# ============================================================================
# VENTOY METHOD
# ============================================================================

function Invoke-VentoyMethod {
    param([object]$TargetUSB, [string]$IsoPath)
    
    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
    Write-ColoredMessage "              VENTOY METHOD" -Type Info
    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
    
    # Download Ventoy
    $ventoyZip = Join-Path $Config.ToolsDir 'ventoy.zip'
    $ventoyExtract = Join-Path $Config.ToolsDir 'Ventoy'
    
    if (-not (Test-Path $ventoyExtract)) {
        if (Download-File -Url $Config.VentoyUrl -OutputPath $ventoyZip -Description "Ventoy") {
            Expand-Archive -Path $ventoyZip -DestinationPath $Config.ToolsDir -Force
            Write-ColoredMessage "Ventoy extracted successfully" -Type Success
        } else {
            return $false
        }
    }
    
    $ventoyExe = Get-ChildItem -Path $Config.ToolsDir -Filter 'Ventoy2Disk.exe' -Recurse | Select-Object -First 1
    
    if (-not $ventoyExe) {
        Write-ColoredMessage "Ventoy2Disk.exe not found!" -Type Error
        return $false
    }
    
    Write-Host ""
    Write-ColoredMessage "Ventoy will be launched with the following settings:" -Type Info
    Write-Host "  Target USB: " -NoNewline
    Write-Host "$($TargetUSB.DriveLetter) - $($TargetUSB.Model) ($($TargetUSB.Size) GB)" -ForegroundColor Yellow
    Write-Host ""
    Write-ColoredMessage "WARNING: All data on the USB drive will be erased!" -Type Warning
    Write-Host ""
    
    $confirm = Read-Host "Continue? (yes/no)"
    if ($confirm -ne 'yes') {
        Write-ColoredMessage "Operation cancelled by user." -Type Warning
        return $false
    }
    
    # Launch Ventoy
    Write-ColoredMessage "Launching Ventoy2Disk..." -Type Info
    Write-Host ""
    Write-ColoredMessage "VENTOY INSTRUCTIONS:" -Type Info
    Write-Host "  1. Select device: $($TargetUSB.Model)" -ForegroundColor Cyan
    Write-Host "  2. Click Install" -ForegroundColor Cyan
    Write-Host "  3. Confirm installation" -ForegroundColor Cyan
    Write-Host "  4. Wait for completion" -ForegroundColor Cyan
    Write-Host ""
    
    Start-Process -FilePath $ventoyExe.FullName -Wait
    
    Write-Host ""
    $completed = Read-Host "Did Ventoy install successfully? (yes/no)"
    
    if ($completed -eq 'yes') {
        # Copy ISO to Ventoy partition
        if ($IsoPath) {
            Write-ColoredMessage "Copying Windows ISO to Ventoy..." -Type Info
            $ventoyIsoPath = Join-Path $TargetUSB.DriveLetter (Split-Path -Leaf $IsoPath)
            Copy-Item -Path $IsoPath -Destination $ventoyIsoPath -Force
            Write-ColoredMessage "ISO copied to: $ventoyIsoPath" -Type Success
        }
        
        # Create Ventoy plugin directory structure
        $ventoyDir = Join-Path $TargetUSB.DriveLetter 'ventoy'
        $scriptDir = Join-Path $ventoyDir 'scripts'
        
        New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
        
        # Copy payload
        $payloadDest = Join-Path $TargetUSB.DriveLetter 'PostInstall'
        Copy-Item -Path $Config.PayloadDir -Destination $payloadDest -Recurse -Force
        
        # Create autounattend.xml (basic template)
        $autounattend = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <UserData>
                <AcceptEula>true</AcceptEula>
            </UserData>
        </component>
    </settings>
</unattend>
'@
        
        $autounattend | Out-File -FilePath (Join-Path $scriptDir 'autounattend.xml') -Encoding UTF8
        
        Write-ColoredMessage "Payload and scripts copied to USB" -Type Success
        Write-Host ""
        Write-ColoredMessage "NEXT STEPS:" -Type Info
        Write-Host "  1. Boot from USB and select Windows ISO" -ForegroundColor Cyan
        Write-Host "  2. After Windows installation, run:" -ForegroundColor Cyan
        Write-Host "     D:\PostInstall\FirstRun.cmd (as Administrator)" -ForegroundColor Yellow
        Write-Host ""
        
        return $true
    } else {
        Write-ColoredMessage "Ventoy operation incomplete." -Type Warning
        return $false
    }
}

# ============================================================================
# MAIN WORKFLOW
# ============================================================================

function Show-MainMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                                               ║" -ForegroundColor Cyan
    Write-Host "  ║       Windows USB Deployment Toolkit v1.1.0                   ║" -ForegroundColor Cyan
    Write-Host "  ║       Windows + Office ODT + MAS Activation                   ║" -ForegroundColor Cyan
    Write-Host "  ║                                                               ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Repository: " -NoNewline
    Write-Host "https://github.com/pv-udpv/windows-usb-deployment-toolkit" -ForegroundColor Yellow
    Write-Host ""
}

function Start-Deployment {
    Show-MainMenu
    
    # Initialize workspace
    Initialize-Workspace
    
    # Select USB drive (using enhanced detection)
    $targetUSB = Show-USBSelectionEnhanced
    if (-not $targetUSB) {
        Write-ColoredMessage "No USB drive selected. Exiting." -Type Warning
        return
    }
    
    # Get Windows ISO
    $isoPath = Get-WindowsISO
    
    # Prepare payload
    Write-Host ""
    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
    Write-ColoredMessage "              PREPARING PAYLOAD" -Type Info
    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
    Write-Host ""
    
    Get-MASActivation
    Get-OfficeODT
    Create-AutorunScript
    
    # Select method
    Write-Host ""
    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
    Write-ColoredMessage "              METHOD SELECTION" -Type Info
    Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Info
    Write-Host ""
    Write-Host "  [1] " -NoNewline -ForegroundColor Yellow
    Write-Host "Rufus (Simple, single-boot, Windows Setup customization)"
    Write-Host "  [2] " -NoNewline -ForegroundColor Yellow
    Write-Host "Ventoy (Multi-boot, copy ISOs as files)"
    Write-Host ""
    
    $methodChoice = Read-Host "Select method"
    
    $success = $false
    switch ($methodChoice) {
        '1' {
            $success = Invoke-RufusMethod -TargetUSB $targetUSB -IsoPath $isoPath
        }
        '2' {
            $success = Invoke-VentoyMethod -TargetUSB $targetUSB -IsoPath $isoPath
        }
        default {
            Write-ColoredMessage "Invalid method selected." -Type Error
            return
        }
    }
    
    if ($success) {
        Write-Host ""
        Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Success
        Write-ColoredMessage "              DEPLOYMENT COMPLETE" -Type Success
        Write-ColoredMessage "═══════════════════════════════════════════════════════════════" -Type Success
        Write-Host ""
        Write-ColoredMessage "USB is ready for deployment!" -Type Success
        Write-Host ""
        Write-ColoredMessage "After Windows installation:" -Type Info
        Write-Host "  1. Open File Explorer" -ForegroundColor Cyan
        Write-Host "  2. Navigate to USB drive" -ForegroundColor Cyan
        Write-Host "  3. Run PostInstall\FirstRun.cmd as Administrator" -ForegroundColor Cyan
        Write-Host ""
        Write-ColoredMessage "This will automatically:" -Type Info
        Write-Host "  • Install Microsoft Office (silent)" -ForegroundColor Green
        Write-Host "  • Launch MAS activation tool" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-ColoredMessage "Deployment failed or incomplete." -Type Error
    }
}

# ============================================================================
# ENTRY POINT
# ============================================================================

try {
    Start-Deployment
}
catch {
    Write-ColoredMessage "Fatal error: $_" -Type Error
    Write-ColoredMessage "Stack trace: $($_.ScriptStackTrace)" -Type Error
}
finally {
    Write-Host ""
    Read-Host "Press Enter to exit"
}
