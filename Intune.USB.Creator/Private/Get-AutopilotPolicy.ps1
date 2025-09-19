function Get-AutopilotPolicy {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        [System.IO.FileInfo]$FileDestination
    )
    try {
        # 1. Force a new connection to Microsoft Graph with required permissions
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        # Note: We've added "Organization.Read.All" to get the Tenant ID
        Connect-MgGraph -Scopes "DeviceManagementServiceConfig.Read.All", "Organization.Read.All"

        # 2. Get all available Autopilot profiles from your tenant
        Write-Host "Getting available Autopilot profiles..." -ForegroundColor Cyan
        $profiles = Get-MgBetaDeviceManagementWindowsAutopilotDeploymentProfile

        if (!$profiles) {
            throw "No Autopilot profiles were found in your tenant."
        }

        # 3. If there are multiple profiles, pop up a window to let you choose one
        $selectedProfile = $null
        if ($profiles.Count -gt 1) {
            Write-Host "Multiple Autopilot profiles found. Please choose one:"
            $selectedProfile = $profiles | Out-GridView -Title "Select an Autopilot Profile" -PassThru
        }
        else {
            $selectedProfile = $profiles
        }

        if (!$selectedProfile) {
            throw "No Autopilot profile was selected."
        }

        # 4. Manually build the JSON object with the required structure
        Write-Host "Building Autopilot JSON for profile: $($selectedProfile.DisplayName)" -ForegroundColor Cyan
        $tenantId = (Get-MgOrganization).Id
        $jsonObject = [PSCustomObject]@{
            CloudAssignedTenantId = $tenantId
            CloudAssignedAutopilotProfile = $selectedProfile
        }

        # 5. Convert the custom object to a JSON string
        # The -Depth parameter ensures all nested properties are included
        $jsonString = $jsonObject | ConvertTo-Json -Depth 10

        # 6. Save the JSON to the specified file
        $filePath = Join-Path $FileDestination.FullName "AutopilotConfigurationFile.json"
        Set-Content -Path $filePath -Value $jsonString
        Write-Host "Successfully saved Autopilot profile to $filePath" -ForegroundColor Green
    }
    catch {
        Write-Error "An error occurred in Get-AutopilotPolicy: $($_.Exception.Message)"
    }
}

$TenantId = "a5f8bf0a-3503-4872-bc1d-48390acb622c"
$ClientId = "f80f1165-3c77-40d8-8606-0f78430bd8c4"

Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes `
    "DeviceManagementServiceConfig.ReadWrite.All",
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementManagedDevices.ReadWrite.All"


#endregion#endregion Connect to Intune
{            #region Get policies
     {

            {

            $apPolicies = Get-AutopilotProfile
            if (!($apPolicies)) {
                Write-Warning "No Autopilot policies found.."
            }
            else {
                if ($apPolicies.count -gt 1) {
                    Write-Host "Multiple Autopilot policies found - select the correct one.." -ForegroundColor Cyan
                    $selectedPolicy = $apPolicies | Select-Object displayName | Out-GridView -passthru
                    $apPol = $apPolicies | Where-Object {$_.displayName -eq $selectedPolicy.displayName}
                }
                else {
                    Write-Host "Policy found - saving to $FileDestination.." -ForegroundColor Cyan
                    $apPol = $apPolicies
                }
                $apPol | ConvertTo-AutopilotConfigurationJSON | Out-File "$FileDestination\AutopilotConfigurationFile.json" -Encoding ascii -Force
                Write-Host "Autopilot profile selected: " -ForegroundColor Cyan -NoNewline
                Write-Host "$($apPol.displayName)" -ForegroundColor Green
            }
            #endregion Get policies
        }
        else {
            Write-Host "Autopilot Configuration file found locally: $FileDestination\AutopilotConfigurationFile.json" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning $_
    }
    finally {
        if ($PSVersionTable.PSVersion.Major -eq 7) {
            @(
                "WindowsAutoPilotIntune",
                "Microsoft.Graph.Intune"
            ) | ForEach-Object {
                Remove-Module $_ -ErrorAction SilentlyContinue 3>$null
            }
        }
    }
}