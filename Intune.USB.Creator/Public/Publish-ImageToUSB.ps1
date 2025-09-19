
using module '..\Classes\ImageUSB.psm1'

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}


function Publish-ImageToUSB {
    [cmdletbinding()]
    param (
        [parameter(ParameterSetName = "Build", Mandatory = $true)]
        [parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$winPEPath,

        [parameter(ParameterSetName = "Build", Mandatory = $true)]
        [parameter(ParameterSetName = "Default", Mandatory = $true)]
        [string]$windowsIsoPath,

        [parameter(ParameterSetName = "Build", Mandatory = $false)]
        [parameter(ParameterSetName = "Default", Mandatory = $false)]
        [switch]$getAutoPilotCfg,

        [parameter(ParameterSetName = "Build", Mandatory = $true)]
        [string]$imageIndex,

        [parameter(ParameterSetName = "Build", Mandatory = $true)]
        [string]$diskNum
    )

   $script:provisionUrl = "C:\Dev\Intune.USB.Creator\Invoke-Provision\Invoke-Provision.ps1"
    #region Main Process
    try {
        #region start diagnostic // show welcome
        $errorMsg = $null
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $welcomeScreen = "ICAgIF9fICBfXyAgICBfXyAgX19fX19fICBfX19fX18gIF9fX19fXwogICAvXCBcL1wgIi0uLyAgXC9cICBfXyBcL1wgIF9fX1wvXCAgX19fXAogICBcIFwgXCBcIFwtLi9cIFwgXCAgX18gXCBcIFxfXyBcIFwgIF9fXAogICAgXCBcX1wgXF9cIFwgXF9cIFxfXCBcX1wgXF9fX19fXCBcX19fX19cCiAgICAgXC9fL1wvXy8gIFwvXy9cL18vXC9fL1wvX19fX18vXC9fX19fXy8KIF9fX19fXyAgX18gIF9fICBfXyAgX18gICAgICBfX19fXyAgIF9fX19fXyAgX19fX19fCi9cICA9PSBcL1wgXC9cIFwvXCBcL1wgXCAgICAvXCAgX18tLi9cICBfX19cL1wgID09IFwKXCBcICBfXzxcIFwgXF9cIFwgXCBcIFwgXF9fX1wgXCBcL1wgXCBcICBfX1xcIFwgIF9fPAogXCBcX19fX19cIFxfX19fX1wgXF9cIFxfX19fX1wgXF9fX18tXCBcX19fX19cIFxfXCBcX1wKICBcL19fX19fL1wvX19fX18vXC9fL1wvX19fX18vXC9fX19fLyBcL19fX19fL1wvXy8gL18vCiAgICAgICAgIF9fX19fX19fX19fX19fX19fX19fX19fX19fX19fX19fX19fCiAgICAgICAgIFdpbmRvd3MgMTAgRGV2aWNlIFByb3Zpc2lvbmluZyBUb29sCiAgICAgICAgICoqKioqKioqKioqKioqKioqKioqKioqKioqKioqKioqKioq"
        Write-Host $([system.text.encoding]::UTF8.GetString([system.convert]::FromBase64String($welcomeScreen)))
        if (!(Test-Admin)) {
            throw "Exiting -- need admin right to execute"
        }
        #endregion
        #region set usb class
        Write-Host "`nSetting up configuration paths.." -ForegroundColor Yellow
        $usb = [ImageUSBClass]::new()
        #endregion
        #region get winPE / unpack to temp
        Write-Host "`nGetting WinPE media.." -ForegroundColor Yellow

        $winPEIsoFile = $null
        if (Test-Path -Path $winPEPath -ErrorAction SilentlyContinue) {
            # The path is a local file
            Write-Host "Found local WinPE ISO file." -ForegroundColor Cyan
            $winPEIsoFile = $winPEPath
        }
        else {
            # The path is a URL, so download it
            Write-Host "Local file not found, attempting to download from URL..." -ForegroundColor Cyan
            # This line calls a helper function from the module to download the file
            $winPEIsoFile = Get-RemoteFile -fileUri $winPEPath -destination $usb.downloadPath
        }

        # Now that we have the ISO path (either local or downloaded), expand it
        if ($winPEIsoFile) {
            Write-Host "Expanding WinPE ISO: $winPEIsoFile" -ForegroundColor Cyan
            Expand-Archive -LiteralPath $winPEIsoFile -DestinationPath $usb.WinPEPath -Force
        }
        else {
            throw "FATAL: Could not find or download the WinPE media from path: $winPEPath"
        }
        #endregion
        #region get wim from ISO
        Write-Host "`nGetting install.wim from windows media.." -ForegroundColor Yellow -NoNewline
        if (Test-Path -Path $windowsIsoPath -ErrorAction SilentlyContinue) {
            $dlFile = $windowsIsoPath
        }
        else {
            $dlFile = Get-RemoteFile -fileUri $windowsIsoPath -destination $usb.downloadPath
        }
        Get-WimFromIso -isoPath $dlFile -wimDestination $usb.WIMPath
        #endregion
        #region get image index from wim
        if ($imageIndex) {
            @{
                "ImageIndex" = $imageIndex
            } | ConvertTo-Json | Out-File "$($usb.downloadPath)\$($usb.dirName2)\imageIndex.json"
        }
        else {
            Write-Host "`nGetting image index from install.wim.." -ForegroundColor Yellow
            Get-ImageIndexFromWim -wimPath $usb.WIMFilePath -destination "$($usb.downloadPath)\$($usb.dirName2)"
        }
        #endregion
        #region get Autopilot config from azure
        if ($getAutopilotCfg) {
            Write-Host "`nGrabbing Autopilot config file from Azure.." -ForegroundColor Yellow
            Get-AutopilotPolicy -fileDestination $usb.downloadPath
        }
        #endregion
        #region choose and partition USB
        Write-Host "`nConfiguring USB.." -ForegroundColor Yellow
        if ($PsCmdlet.ParameterSetName -eq "Build") {
            $chooseDisk = Get-DiskToUse -diskNum $diskNum
        }
        else {
            $chooseDisk = Get-DiskToUse
        }
        Write-Host "`nDisk number " $diskNum " selected." -ForegroundColor Cyan
        $usb = Set-USBPartition -usbClass $usb -diskNum $chooseDisk
        #endregion
        #region Create and Inject StartNet.cmd, WinPE Components, and Drivers
        Write-Host "`nCustomizing WinPE image..." -ForegroundColor Yellow
        $mountDir = Join-Path $env:TEMP "Mount"
        if (!(Test-Path $mountDir)) { New-Item -Path $mountDir -ItemType Directory | Out-Null }
        $bootWim = Join-Path $usb.WinPEPath "sources\boot.wim"

        # Mount the WinPE boot.wim file
        Mount-WindowsImage -ImagePath $bootWim -Index 1 -Path $mountDir

        # Add required optional components for PowerShell and GUI support
        #$adkPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs"
        #$packages = @(
            #"WinPE-WMI.cab",
            #"WinPE-NetFx.cab",
            #"WinPE-Scripting.cab",
            #"WinPE-PowerShell.cab"
       # )
        #foreach ($package in $packages) {
            #Write-Host "Adding WinPE package: $package" -ForegroundColor Cyan
            #Add-WindowsPackage -Path $mountDir -PackagePath "$adkPath\$package"
        #}

        # Inject Drivers
        #Write-Host "Injecting drivers into WinPE image..." -ForegroundColor Yellow
        # --- IMPORTANT: Change this path to the folder containing your drivers ---
        #$driverPath = "C:\Drivers"
        #Add-WindowsDriver -Path $mountDir -Driver $driverPath -Recurse

        # Define the content for StartNet.cmd to auto-run the provisioning script
        $startNetContent = @"
@echo off
wpeinit
X:\scripts\pwsh\pwsh.exe -ExecutionPolicy Bypass -File "D:\scripts\Invoke-Provision.ps1"
"@

        # Write the new StartNet.cmd to the mounted image
        $startNetPath = Join-Path $mountDir "Windows\System32\StartNet.cmd"
        Set-Content -Path $startNetPath -Value $startNetContent

        # Save the changes and dismount the image
        Dismount-WindowsImage -Path $mountDir -Save
        #endregion
        #region write WinPE to USB
        Write-Host "`nWriting WinPE to USB.." -ForegroundColor Yellow -NoNewline
        Write-ToUSB -Path "$($usb.winPEPath)\*" -Destination "$($usb.drive):\"
        #endregion
        #region write Install.wim to USB
        if ($windowsIsoPath) {
            Write-Host "`nWriting Install.wim to USB.." -ForegroundColor Yellow -NoNewline
            Write-ToUSB -Path $usb.WIMPath -Destination "$($usb.drive2):\"
        }
        #endregion
        #region write Autopilot to USB
        if ($getAutopilotCfg) {
            Write-Host "`nWriting Autopilot to USB.." -ForegroundColor Yellow -NoNewline
            Write-ToUSB -Path "$($usb.downloadPath)\AutopilotConfigurationFile.json" -Destination "$($usb.drive):\scripts\"
        }
        #endregion
        #region Create drivers folder
        Write-Host "`nSetting up folder structures for Drivers.." -ForegroundColor Yellow -NoNewline
        New-Item -Path "$($usb.drive2):\Drivers" -ItemType Directory -Force | Out-Null
        #endregion
        #region download provision script and install to usb
        Write-Host "`nGrabbing provision script from GitHub.." -ForegroundColor Yellow
        Invoke-RestMethod -Method Get -Uri $script:provisionUrl -OutFile "$($usb.drive):\scripts\Invoke-Provision.ps1"
        #endregion
        #region download and apply powershell 7 to usb
        Write-Host "`nGrabbing PWSH 7.0.3.." -ForegroundColor Yellow
        Invoke-RestMethod -Method Get -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.0.3/PowerShell-7.0.3-win-x64.zip' -OutFile "$env:Temp\pwsh7.zip"
        Expand-Archive -path "$env:Temp\pwsh7.zip" -Destinationpath "$($usb.drive):\scripts\pwsh"
        #endregion download and apply powershell 7 to usb

        #region Copy PowerShell Modules to USB  <-- ADD THIS ENTIRE NEW SECTION
        Write-Host "`nCopying required PowerShell modules to USB.." -ForegroundColor Yellow
        $modulePath = ($env:PSModulePath -split ';')[0]
        $destination = "$($usb.drive):\scripts\pwsh\Modules"
        $modulesToCopy = @(
            "Microsoft.Graph.Authentication",
            "Microsoft.Graph.DeviceManagement",
            "Microsoft.Graph.Groups"
        )
        foreach ($module in $modulesToCopy) {
            $source = Join-Path $modulePath $module
            if (Test-Path $source) {
                    Write-Host "Copying module $module..." -ForegroundColor Cyan
                    Copy-Item -Path $source -Destination $destination -Recurse -Force
            }
            else {
                    Write-Warning "Could not find module $module at path $source"
            }
        }
        #endregion
        $completed = $true
    }
    catch {
        $errorMsg = $_.Exception.Message
    }
    finally {
        $sw.Stop()
        if ($errorMsg) {
            Write-Warning $errorMsg
        }
        else {
            if ($completed) {
                Write-Host "`nUSB Image built successfully..`nTime taken: $($sw.Elapsed)" -ForegroundColor Green
            }
            else {
                Write-Host "`nScript stopped before completion..`nTime taken: $($sw.Elapsed)" -ForegroundColor Green
            }
        }
    }
    #endregion
}
