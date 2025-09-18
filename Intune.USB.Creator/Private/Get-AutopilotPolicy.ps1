#requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement, Microsoft.Graph.Groups

function Get-AutopilotPolicy {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        [System.IO.FileInfo]$FileDestination
    )
    try {
        if (!(Test-Path "$FileDestination\AutopilotConfigurationFile.json" -ErrorAction SilentlyContinue)) {
            # List only the specific sub-modules needed
            $modules = @(
                "Microsoft.Graph.Authentication",
                "Microsoft.Graph.DeviceManagement",
                "Microsoft.Graph.Groups"
            )
            if ($PSVersionTable.PSVersion.Major -eq 7) {
                $modules | ForEach-Object {
                    Import-Module $_ -UseWindowsPowerShell -ErrorAction SilentlyContinue 3>$null
                }
            }
            else {
                $modules | ForEach-Object {
                    Import-Module $_
                }
            }
        }
    }
    # Add a catch block for proper error handling
    catch {
        Write-Error "An error occurred in Get-AutopilotPolicy: $($_.Exception.Message)"
    }
}
#region Connect to Intune

$TenantId = "a5f8bf0a-3503-4872-bc1d-48390acb622c"
$ClientId = "f80f1165-3c77-40d8-8606-0f78430bd8c4"

Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes `
    "DeviceManagementServiceConfig.ReadWrite.All",
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementManagedDevices.ReadWrite.All"

Select-MgProfile -Name beta
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