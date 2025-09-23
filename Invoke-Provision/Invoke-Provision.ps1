# This script runs in WinPE to capture and upload the Autopilot hash, then deploy the OS.

try {
    # Set High Performance power plan
    powercfg /s 8c5e7fda-e-bf-4a96-9a85-a6e23a8c635c

    # Find the USB drive by its "WINPE" label
    Write-Host "Searching for the WINPE USB drive..."
    $winpeVolume = Get-Volume -FileSystemLabel "WINPE"
    if (!$winpeVolume) {
        # Fallback if label is not found, search for a unique file
        $scriptPath = Get-ChildItem -Path "C:","D:","E:","F:","G:","H:" -Filter "Invoke-Provision.ps1" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($scriptPath) {
            $usbDriveLetter = $scriptPath.Directory.Root.Name.TrimEnd(":")
        } else {
            throw "Could not find the WINPE USB drive."
        }
    } else {
        $usbDriveLetter = $winpeVolume.DriveLetter
    }
    Write-Host "Found WINPE drive at $($usbDriveLetter):" -ForegroundColor Green

    # --- #region Direct Module Loading ---
    Write-Host "`nDirectly loading required module scripts..." -ForegroundColor Yellow
    $scriptRoot = "$($usbDriveLetter):\scripts"
    $modulesPath = Join-Path $scriptRoot "pwsh\Modules"

    # Load the Get-WindowsAutopilotInfo script directly by finding its .ps1 file
    $autopilotScript = Get-ChildItem -Path $modulesPath -Filter "Get-WindowsAutopilotInfo.ps1" -Recurse | Select-Object -First 1
    if ($autopilotScript) {
        Write-Host "Loading $($autopilotScript.FullName)..."
        . $autopilotScript.FullName
    } else { throw "Could not find Get-WindowsAutopilotInfo.ps1 on the USB." }

    # Load the Graph modules by finding and dot-sourcing their main .psm1 file
    $graphModules = @("MSAL.PS", "Microsoft.Graph.Authentication", "Microsoft.Graph.Beta.DeviceManagement", "Microsoft.Graph.Beta.Groups")
    foreach ($moduleName in $graphModules) {
        $modulePsm1 = Get-ChildItem -Path (Join-Path $modulesPath $moduleName) -Filter "*.psm1" -Recurse | Select-Object -First 1
        if ($modulePsm1) {
            Write-Host "Loading $($modulePsm1.FullName)..."
            . $modulePsm1.FullName
        } else {
            Write-Warning "Could not find .psm1 file for module $moduleName"
        }
    }
    # --- #endregion Direct Module Loading ---

    # --- #region Autopilot Hardware Hash Upload ---
    Write-Host "`nStarting Autopilot registration process..." -ForegroundColor Cyan
    $autopilotJsonPath = Join-Path $scriptRoot "AutopilotConfigurationFile.json"
    $outputFile = Join-Path $scriptRoot "autopilot-hash.csv"

    if (!(Test-Path $autopilotJsonPath)) { throw "AutopilotConfigurationFile.json not found!" }
    $autopilotProfile = Get-Content -Path $autopilotJsonPath | ConvertFrom-Json
    $groupTag = $autopilotProfile.CloudAssignedAutopilotProfile.groupTag
    Write-Host "Autopilot Group Tag found: $groupTag"

    Write-Host "Generating Autopilot hardware hash..."
    Get-WindowsAutopilotInfo -OutputFile $outputFile

    Write-Host "Authenticating to Microsoft Graph to upload hash..."
    Connect-MgGraph -Scopes "DeviceManagementServiceConfig.ReadWrite.All"
    Import-AutopilotCSV -CsvFile $outputFile -GroupTag $groupTag

    Write-Host "SUCCESS: Autopilot hash uploaded successfully." -ForegroundColor Green
    # --- #endregion Autopilot Hardware Hash Upload ---

    # Ask the user if they want to proceed with imaging
    Write-Host "`nAutopilot registration complete. Proceed with Windows installation?" -ForegroundColor Yellow
    $choice = Read-Host "(Y/N)"
    if ($choice -ne 'y') {
        throw "User cancelled the operation. You can now safely reboot."
    }

    # --- #region Full OS Deployment ---
    # (The rest of the OS Deployment script follows...)
    # --- #endregion Full OS Deployment ---

    Write-Host "`nSUCCESS: Provisioning process completed." -ForegroundColor Green
}
catch {
    Write-Error "An error occurred during provisioning: $($_.Exception.Message)"
}

Write-Host "Script finished. Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# The automatic reboot is now disabled.
# Restart-Computer -Force