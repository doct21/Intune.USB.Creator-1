<#
.SYNOPSIS
    This script runs in WinPE. It performs an online Autopilot registration
    and then executes a full, bare-metal Windows OS deployment.
#>

# --- Main process ---
try {
    # --- START OF SCRIPT ---
    # Set power policy to High Performance for speed
    powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    
    # Dynamically find the USB drive by its "WINPE" label
    Write-Host "Searching for the WINPE USB drive..." -ForegroundColor Cyan
    $winpeVolume = Get-Volume -FileSystemLabel "WINPE"
    if (!$winpeVolume) { throw "Could not find the 'WINPE' volume. Cannot proceed." }
    $usbDriveLetter = $winpeVolume.DriveLetter
    Write-Host "Found WINPE drive at $($usbDriveLetter):" -ForegroundColor Green

    # --- #region Autopilot Hardware Hash Upload ---
    Write-Host "`nStarting Autopilot registration process..." -ForegroundColor Yellow
    
    # Define paths on the USB drive
    $scriptRoot = "$($usbDriveLetter):\scripts"
    $pwshPath = Join-Path $scriptRoot "pwsh\pwsh.exe"
    $autopilotJsonPath = Join-Path $scriptRoot "AutopilotConfigurationFile.json"
    $outputFile = Join-Path $scriptRoot "autopilot-hash.csv"
    $autopilotScriptBlock = {
        param($autopilotJsonPath, $outputFile)
        
        # This code block will be executed by the PowerShell 7 engine
        
        # Import the required Graph modules from the USB drive
        Import-Module Microsoft.Graph.Authentication
        Import-Module Microsoft.Graph.Beta.DeviceManagement
        Import-Module Microsoft.Graph.Beta.Groups
        
        # Get the Autopilot profile info from the JSON
        if (!(Test-Path $autopilotJsonPath)) { throw "AutopilotConfigurationFile.json not found!" }
        $autopilotProfile = Get-Content -Path $autopilotJsonPath | ConvertFrom-Json
        $groupTag = $autopilotProfile.CloudAssignedAutopilotProfile.groupTag
        Write-Host "Autopilot Group Tag found: $groupTag"

        # Generate the hardware hash
        Write-Host "Generating Autopilot hardware hash..."
        Get-WindowsAutopilotInfo -OutputFile $outputFile
        
        # Authenticate and upload the hash (This is where the login prompt appears)
        Write-Host "Authenticating to Microsoft Graph to upload hash..."
        Connect-MgGraph -Scopes "DeviceManagementServiceConfig.ReadWrite.All"
        Import-AutopilotCSV -CsvFile $outputFile -GroupTag $groupTag
        
        Write-Host "SUCCESS: Autopilot hash uploaded successfully." -ForegroundColor Green
    }
    
    # Execute the Autopilot script block using the PowerShell 7 engine from the USB
    & $pwshPath -ExecutionPolicy Bypass -Command $autopilotScriptBlock -Args $autopilotJsonPath, $outputFile

    # --- #endregion Autopilot Hardware Hash Upload ---

    # Ask the user if they want to proceed with imaging
    Write-Host "`nAutopilot registration complete. Proceed with Windows installation?" -ForegroundColor Yellow
    $choice = Read-Host "(Y/N)"
    if ($choice -ne 'y') {
        throw "User cancelled the operation. You can now safely reboot."
    }

    # --- #region Full OS Deployment ---
    
    Write-Host "`nStarting full OS deployment..." -ForegroundColor Yellow
    $osImageDrive = Get-Volume -FileSystemLabel "Images" | Select-Object -ExpandProperty DriveLetter
    $installWimPath = "$($osImageDrive):\install.wim"
    $targetDisk = Get-Disk | Where-Object { $_.BusType -ne "USB" } | Select-Object -First 1

    Write-Host "Wiping and partitioning target disk #$($targetDisk.Number)..." -ForegroundColor Cyan
    $uefiCheck = Get-ItemPropertyValue -Path HKLM:\SYSTEM\CurrentControlSet\Control -Name 'PEFirmwareType'
    Clear-Disk -Number $targetDisk.Number -RemoveData -Confirm:$false
    Initialize-Disk -Number $targetDisk.Number -PartitionStyle GPT
    # Create Partitions based on UEFI check
    if ($uefiCheck -eq 2) { # UEFI
        New-Partition -DiskNumber $targetDisk.Number -Size 100MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "System" | Out-Null
        New-Partition -DiskNumber $targetDisk.Number -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' | Out-Null
        $winPartition = New-Partition -DiskNumber $targetDisk.Number -Size (([math]::Round((Get-Disk -Number $targetDisk.Number).Size / 1GB) - 1) * 1024MB) | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Windows"
        New-Partition -DiskNumber $targetDisk.Number -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Recovery" | Out-Null
    } else { # BIOS
        throw "BIOS mode is not supported by this script."
    }

    Write-Host "Applying Windows image..." -ForegroundColor Cyan
    $imageIndexJson = Get-Content -Path "$($osImageDrive):\imageIndex.json" -Raw | ConvertFrom-Json
    DISM.exe /Apply-Image /ImageFile:$installWimPath /Index:$($imageIndexJson.imageIndex) /ApplyDir:"$($winPartition.DriveLetter):\"

    Write-Host "Applying drivers..." -ForegroundColor Cyan
    DISM.exe /Image:"$($winPartition.DriveLetter):\" /Add-Driver /Driver:"$($osImageDrive):\Drivers" /Recurse

    Write-Host "Setting up boot files..." -ForegroundColor Cyan
    $systemPartition = Get-Partition -DiskNumber $targetDisk.Number | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
    bcdboot.exe "$($winPartition.DriveLetter):\Windows" /s "$($systemPartition.DriveLetter):" /f UEFI

    # --- #endregion Full OS Deployment ---

    Write-Host "`nSUCCESS: Provisioning process completed." -ForegroundColor Green
}
catch {
    Write-Error "An error occurred during provisioning: $($_.Exception.Message)"
}

Write-Host "Script finished. Press any key to reboot..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Restart-Computer -Force