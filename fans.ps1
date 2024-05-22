[CmdletBinding(DefaultParameterSetName = "All")]
Param (
    [Parameter(HelpMessage = "Victim hostname", Position = 0, Mandatory = $true)]
    [string[]] $Hostnames,

    [Parameter(HelpMessage = "Liftoff")]
    [switch] $Fans,

    [Parameter(HelpMessage = "Clean up leftovers (only needed in case of half-run script)")]
    [switch] $Cleanup
)

if (-not $env:cctk) {
    Write-Error -Message "cctk environment variable not found. Not continuing." -ErrorAction Stop
}

# Cleanup in case extra sessions exist
Remove-PSSession * -ErrorAction SilentlyContinue

# Create sessions
Write-Host Creating sessions...
$Sessions = New-PSSession $Hostnames
Get-PSSession

# Cleanup in case extra temp files exist
Invoke-Command -Session $Sessions -ScriptBlock { Remove-Item -Recurse C:\Temp\cctk } -ErrorAction SilentlyContinue

# Exit now if $Cleanup
if ($Cleanup) {
    Remove-PSSession *
    Exit
}

# Copy files
foreach ($Session in $Sessions) {
    Write-Host Copying files to $Session.ComputerName...
    Invoke-Command -Session $Session -ScriptBlock { New-Item -Path C:\Temp\cctk -ItemType Directory | Out-Null }
    Copy-Item -ToSession $Session $(($env:cctk) + '\*') -Destination C:\Temp\cctk\
}

# Set fans
Write-Host Setting fans...
if ($Fans) {
    Invoke-Command -Session $Sessions -ScriptBlock { C:\Temp\cctk\cctk.exe --FanCtrlOvrd=Enabled --ValSetupPwd=($env:cctkpwd) }
} Else {
    Invoke-Command -Session $Sessions -ScriptBlock { C:\Temp\cctk\cctk.exe --FanCtrlOvrd=Disabled --ValSetupPwd=($env:cctkpwd) }
}

# Cleanup
Write-Host Cleaning up...
Invoke-Command -Session $Sessions -ScriptBlock { Remove-Item -Recurse C:\Temp\cctk }
Remove-PSSession *