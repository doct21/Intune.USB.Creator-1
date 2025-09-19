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

    try {
        if (!(Test-Admin)) {
            throw "Exiting -- need admin right to execute"
        }

        Write-Host "`nSetting up configuration paths.." -ForegroundColor Yellow
        $usb = [ImageUSBClass]::new()

        Write-Host "`nGetting install.wim from windows media.." -ForegroundColor Yellow
        if (Test-Path -Path $windowsIsoPath -ErrorAction SilentlyContinue) {
            $dlFile = $windowsIsoPath
        }
        else {
            $dlFile = Get-RemoteFile -fileUri $windowsIsoPath -destination $usb.downloadPath
        }
        Get-WimFromIso -isoPath $dlFile -wimDestination $usb.WIMPath

        if ($imageIndex) {
            @{ "ImageIndex" = $imageIndex } | ConvertTo-Json | Out-File "$($usb.downloadPath)\$($usb.dirName2)\imageIndex.json"
        }
        else {
            Write-Host "`nGetting image index from install.wim.." -ForegroundColor Yellow
            Get-ImageIndexFromWim -wimPath $usb.WIMFilePath -destination "$($usb.downloadPath)\$($usb.dirName2)"
        }

        if ($getAutopilotCfg) {
            Write-Host "`nGrabbing Autopilot config file from Azure.." -ForegroundColor Yellow
            Get-AutopilotPolicy -fileDestination $usb.downloadPath
        }

        Write-Host "`nConfiguring USB.." -ForegroundColor Yellow
        if ($PsCmdlet.ParameterSetName -eq "Build") {
            $chooseDisk = Get-DiskToUse -diskNum $diskNum
        }
        else {
            $chooseDisk = Get-DiskToUse
        }
        Write-Host "`nDisk number " $diskNum " selected." -ForegroundColor Cyan
        $usb = Set-USBPartition -usbClass $usb -diskNum $chooseDisk

        Write-Host "`nWriting WinPE to USB.." -ForegroundColor Yellow -NoNewline
        # THIS IS THE KEY CHANGE: We now use the pre-built folder
        Write-ToUSB -Path "C:\CustomWinPE\media\*" -Destination "$($usb.drive):\"

        if ($windowsIsoPath) {
            Write-Host "`nWriting Install.wim to USB.." -ForegroundColor Yellow -NoNewline
            Write-ToUSB -Path $usb.WIMPath -Destination "$($usb.drive2):\"
        }

        if ($getAutopilotCfg) {
            Write-Host "`nWriting Autopilot to USB.." -ForegroundColor Yellow -NoNewline
            Write-ToUSB -Path "$($usb.downloadPath)\AutopilotConfigurationFile.json" -Destination "$($usb.drive):\scripts\"
        }

        Write-Host "`nSetting up folder structures for Drivers.." -ForegroundColor Yellow -NoNewline
        New-Item -Path "$($usb.drive2):\Drivers" -ItemType Directory -Force | Out-Null

        Write-Host "`nCopying provision script to USB.." -ForegroundColor Yellow
        Copy-Item -Path $script:provisionUrl -Destination "$($usb.drive):\scripts\Invoke-Provision.ps1" -Force

        Write-Host "`nGrabbing PWSH 7.0.3.." -ForegroundColor Yellow
        Invoke-RestMethod -Method Get -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.0.3/PowerShell-7.0.3-win-x64.zip' -OutFile "$env:Temp\pwsh7.zip"
        Expand-Archive -path "$env:Temp\pwsh7.zip" -Destinationpath "$($usb.drive):\scripts\pwsh"

        Write-Host "`nUSB Image built successfully!" -ForegroundColor Green
    }
    catch {
        Write-Error $_.Exception.Message
    }
}