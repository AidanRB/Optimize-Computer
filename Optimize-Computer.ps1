<#
.SYNOPSIS
Optimizes the performance and workflow of computers on your network.

.DESCRIPTION
The Optimize-Computer script connects to and configures devices on your local network.

Connections are established using PowerShell sessions and your client admin credentials.

Many features are specific to Dell machines, as they require CCTK, Dell's client configuration toolkit. This allows the script to manipulate BIOS settings from Windows. In order for this to be possible, the path to CCTK must be provided. This path can be a network share or a local folder. It can either be provided as an environment variable "cctk" or through the -CCTK parameter.

To undo the script's optimizations, simply run it with no optimization flags. To undo Dell specific optimizations, the -Dell flag must be passed as well.

.PARAMETER ComputerName
Target hostnames. Multiple computers may be passed.

.PARAMETER Fans
Sets the fans to full speed on Dell desktops.

.PARAMETER FillStorage
Creates a file in C:\Users\Public\Downloads occupying most of the disk's remaining space.

.PARAMETER Cores
Sets the processor to only use one core in the BIOS on Dell systems.

.PARAMETER Sleep
Disables sleep. Currently only works on Dell systems.

.PARAMETER USB
Disables all USB and Thunderbolt ports on Dell systems.

.PARAMETER Battery
Causes the battery to remain between 50% and 55% while plugged in on Dell laptops.

.PARAMETER Sound
Disables audio. Currently only works on Dell systems.

.PARAMETER Storage
Disables storage devices in the BIOS on Dell systems. Takes effect on reboot.

.PARAMETER Camera
Disables the camera and microphone on Dell laptops.

.PARAMETER Filter
Enables a reminder to clean the dust filter every 15 days on Dell desktops.

.PARAMETER Cleanup
Deletes left over files, like CCTK. This should happen automatically and is only necessary if execution of the script is interrupted.

.PARAMETER Dell
Specifies the targets must have Dell specific optimizations removed. Only has an effect with no optimization flags.

.PARAMETER CCTK
Specifies the path to the folder containing CCTK. This can be a path on the local computer or a network share. An environment variable may be used instead.

.EXAMPLE
.\Optimize-Computer.ps1 -Fans -CCTK C:\cctk\ remote-hostname
Sets the fans to full speed on remote-hostname. Note the path to CCTK is required for this operation.

.LINK
Source: https://github.com/AidanRB/Optimize-Computer
CCTK: https://www.dell.com/support/kbdoc/en-us/000134806/how-to-install-use-dell-client-configuration-toolkit
#>

Param (
    [Parameter()]
    [switch] $Fans,

    [Parameter()]
    [switch] $FillStorage,

    [Parameter()]
    [switch] $Cores,

    [Parameter()]
    [switch] $Sleep,

    [Parameter()]
    [switch] $USB,

    [Parameter()]
    [switch] $Battery,

    [Parameter()]
    [switch] $Sound,

    [Parameter()]
    [switch] $Storage,

    [Parameter()]
    [switch] $Camera,

    [Parameter()]
    [switch] $Filter,

    [Parameter()]
    [switch] $Cleanup,

    [Parameter()]
    [switch] $Dell = $Fans -or $Cores -or $Sleep -or $USB -or $Battery -or $Sound -or $Storage -or $Camera -or $Filter,

    [Parameter()]
    [string] $CCTK = $env:cctk,

    [Parameter(HelpMessage = "Target hosts", Mandatory, ValueFromRemainingArguments)]
    [string[]] $ComputerName
)

if ($Dell -and -not $CCTK) {
    Write-Error -Message "Path to CCTK not found. See help." -ErrorAction Stop
}

# Cleanup in case extra sessions exist
Remove-PSSession * -ErrorAction SilentlyContinue

# Create sessions
Write-Host Creating sessions...
$Sessions = New-PSSession $ComputerName
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