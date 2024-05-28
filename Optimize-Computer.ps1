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

.PARAMETER CCTKPath
Specifies the path to the folder containing CCTK. This can be a path on the local computer or a network share. An environment variable may be used instead.

.PARAMETER CCTKPass
The password to use with CCTK. This should be the BIOS password on the target (Dell) systems.

.EXAMPLE
.\Optimize-Computer.ps1 -Fans -CCTK C:\cctk\ remote-hostname
Sets the fans to full speed on remote-hostname. Note the path to CCTK is required for this operation.

.LINK
Source: https://github.com/AidanRB/Optimize-Computer
CCTK: https://www.dell.com/support/kbdoc/en-us/000134806/how-to-install-use-dell-client-configuration-toolkit
#>

Param (
    [switch] $Fans,

    [switch] $FillStorage,

    [switch] $Cores,

    [switch] $Sleep,

    [switch] $USB,

    [switch] $Battery,

    [switch] $Sound,

    [switch] $Storage,

    [switch] $Camera,

    [switch] $Filter,

    [switch] $Cleanup,

    [string] $CCTKPath = $env:cctk,

    [string] $CCTKPass = $env:cctkpass,

    [Parameter(Mandatory, HelpMessage = "Target hosts", Position = 0, ValueFromRemainingArguments)]
    [string[]] $ComputerName
)

# Cleanup in case extra sessions exist
Remove-PSSession * -ErrorAction SilentlyContinue

# Create sessions
Write-Host -ForegroundColor Blue Creating sessions...
$Sessions = New-PSSession $ComputerName

# Show created sessions
Write-Host -ForegroundColor Green -NoNewline Created sessions:
(Get-PSSession).ForEach({ Write-Host -NoNewline " $($_.ComputerName)" })
Write-Host

# Create hashtable of computers
$Computers = @{}
$Sessions | ForEach-Object { $Computers.Add($_, $()) }

# Cleanup in case old temp files exist
Invoke-Command -Session $Sessions -ScriptBlock { Remove-Item -Recurse C:\Temp\cctk } -ErrorAction SilentlyContinue

# Exit now if $Cleanup
if ($Cleanup) {
    Remove-PSSession *
    Exit
}

# Detect Dell computers and copy CCTK if we know where it is
if ($CCTKPath) {
    # Check to see what targets are Dell
    # Create "copy" of $Computers to allow modifying $Computers while iterating
    foreach ($Computer in $($Computers.GetEnumerator())) {
        # Run Get-CimInstance on the target computer to find and check the manufacturer
        if (Invoke-Command -Session $Computer.Key -ScriptBlock { (Get-CimInstance win32_computersystem).Manufacturer -like "Dell*" }) {
            # Add "Dell" to the original $Computers entry for this computer
            $Computers[$Computer.Key] += "Dell"
        }
    }

    # Show Dell computers
    Write-Host -ForegroundColor Green -NoNewline Identified Dell computers:
    ($Computers | Where-Object Values -Match "Dell").GetEnumerator().ForEach({ Write-Host -NoNewline " $($_.Key.ComputerName)" })
    Write-Host

    Write-Host -ForegroundColor Blue -NoNewline Copying CCTK:

    # Copy CCTK in parallel to each Dell computer
    ($Computers | Where-Object Values -Match "Dell").GetEnumerator() | ForEach-Object -Parallel {
        Write-Host -NoNewline " $($_.Key.ComputerName)"
        Invoke-Command -Session $_.Key -ScriptBlock { New-Item -Path C:\Temp\cctk -ItemType Directory -ErrorAction SilentlyContinue | Out-Null }
        Copy-Item -ToSession $_.Key $(($env:cctk) + '\*') -Destination C:\Temp\cctk\
    }
    Write-Host
}

# Set fans
Write-Host -ForegroundColor Blue Setting fans...
if ($Fans) {
    Invoke-Command -Session $Sessions -ScriptBlock {
        param($CCTKPass)
        C:\Temp\cctk\cctk.exe --FanCtrlOvrd=Enabled --ValSetupPwd=$CCTKPass
    } -ArgumentList $CCTKPass
}
Else {
    Invoke-Command -Session $Sessions -ScriptBlock {
        param($CCTKPass)
        C:\Temp\cctk\cctk.exe --FanCtrlOvrd=Disabled --ValSetupPwd=$CCTKPass
    } -ArgumentList $CCTKPass
}

# Cleanup
Write-Host -ForegroundColor Blue Cleaning up...
Invoke-Command -Session $Sessions -ScriptBlock { Remove-Item -Recurse C:\Temp\cctk }
Remove-PSSession *