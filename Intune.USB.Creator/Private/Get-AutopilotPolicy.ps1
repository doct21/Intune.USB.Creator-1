function Get-AutopilotPolicy {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        [System.IO.FileInfo]$FileDestination
    )
    try {
        # 1. Force a new connection to Microsoft Graph
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Connect-MgGraph -Scopes "DeviceManagementServiceConfig.Read.All"

        # 2. Get all available Autopilot profiles
        Write-Host "Getting available Autopilot profiles..." -ForegroundColor Cyan
        $profiles = Get-MgBetaDeviceManagementWindowsAutopilotDeploymentProfile

        if (!$profiles) { throw "No Autopilot profiles were found." }

        # 3. Let the user choose a profile if there are multiple
        $selectedProfile = if ($profiles.Count -gt 1) {
            $profiles | Out-GridView -Title "Select an Autopilot Profile" -PassThru
        } else {
            $profiles
        }
        if (!$selectedProfile) { throw "No Autopilot profile was selected." }

        # 4. Convert the selected profile object directly to JSON
        Write-Host "Saving profile '$($selectedProfile.DisplayName)'..." -ForegroundColor Cyan
        $jsonString = $selectedProfile | ConvertTo-Json -Depth 5

        # 5. Save the JSON to the file
        $filePath = Join-Path $FileDestination.FullName "AutopilotConfigurationFile.json"
        Set-Content -Path $filePath -Value $jsonString
        Write-Host "Successfully saved Autopilot profile to $filePath" -ForegroundColor Green
    }
    catch {
        Write-Error "An error occurred in Get-AutopilotPolicy: $($_.Exception.Message)"
    }
}