using module 'classes\ImageUSB.psm1'

#region Get public and private function definition files.
$Public  = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue)
# This line points to the local script file within your project directory
$script:provisionUrl = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-Provision\Invoke-Provision.ps1'
#endregion
#region Dot source the files
foreach ($import in @($Public + $Private))
{
    try
    {
        . $import.FullName
    }
    catch
    {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}
#endregion
Export-ModuleMember -Function $Public.BaseName