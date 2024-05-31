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

class ComputerProperties {
    [string] $ComputerName
    [System.Management.Automation.Runspaces.PSSession] $Session
    [bool] $Dell
    [string[]] $DellCapabilities
    [string] $DellCommand

    ComputerProperties([string] $ComputerName) {
        $this.ComputerName = $ComputerName
    }

    ComputerProperties([string] $ComputerName, [System.Management.Automation.Runspaces.PSSession] $Session) {
        $this.ComputerName = $ComputerName
        $this.Session = $Session
    }
}

class DellOption {
    [string] $Enabling = $false
    [scriptblock] $DellCheck
    [string[]] $EnableCommand
    [string[]] $DisableCommand
}

$DellOptions = @{
    "Fans"    = [DellOption]@{
        Enabling       = $Fans
        DellCheck      = { $_ -match "FanCtrlOvrd" }
        EnableCommand  = "FanCtrlOvrd=Enabled"
        DisableCommand = "FanCtrlOvrd=Disabled"
    }

    "Cores"   = [DellOption]@{
        Enabling       = $Cores
        DellCheck      = { $_ -match "CpuCore" -or $_ -match "MultipleAtomCores" -or $_ -match "LogicProc" }
        EnableCommand  = "CpuCore=1", "MultipleAtomCores=1", "LogicProc=Disabled"
        DisableCommand = "CpuCore=CoresAll", "MultipleAtomCores=CoresAll", "LogicProc=Enabled"
    }

    "Sleep"   = [DellOption]@{
        Enabling       = $Sleep
        DellCheck      = { $_ -match "BlockSleep" }
        EnableCommand  = "BlockSleep=Enabled"
        DisableCommand = "BlockSleep=Disabled"
    }

    "USB"     = [DellOption]@{
        Enabling       = $USB
        DellCheck      = { $_ -match "^UsbPorts" -or $_ -match "^ThunderboltPorts" }
        EnableCommand  = "UsbPortsFront=Disabled", "UsbPortsRear=Disabled", "UsbPortsExternal=Disabled", "ThunderboltPorts=Disabled"
        DisableCommand = "UsbPortsFront=Enabled", "UsbPortsRear=Enabled", "UsbPortsExternal=Enabled", "ThunderboltPorts=Enabled"
    }

    "Battery" = [DellOption]@{
        Enabling       = $Battery
        DellCheck      = { $_ -match "PrimaryBattChargeCfg" }
        EnableCommand  = "PrimaryBattChargeCfg=Custom:5-55"
        DisableCommand = "PrimaryBattChargeCfg=Adaptive"
    }

    "Sound"   = [DellOption]@{
        Enabling       = $Sound
        DellCheck      = { $_ -match "IntegratedAudio" -or $_ -match "InternalSpeaker" }
        EnableCommand  = "IntegratedAudio=Disabled", "InternalSpeaker=Disabled"
        DisableCommand = "IntegratedAudio=Enabled", "InternalSpeaker=Enabled"
    }

    "Storage" = [DellOption]@{
        Enabling       = $Storage
        DellCheck      = { $_ -match "^M2PcieSsd" -or $_ -match "^Sata" }
        EnableCommand  = "M2PcieSsd0=Disabled", "M2PcieSsd1=Disabled", "Sata0=Disabled", "Sata1=Disabled", "Sata2=Disabled", "Sata3=Disabled"
        DisableCommand = "M2PcieSsd0=Enabled", "M2PcieSsd1=Enabled", "Sata0=Enabled", "Sata1=Enabled", "Sata2=Enabled", "Sata3=Enabled"
    }

    "Camera"  = [DellOption]@{
        Enabling       = $Camera
        DellCheck      = { $_ -match "Camera" -or $_ -match "Microphone" }
        EnableCommand  = "Camera=Disabled", "Microphone=Disabled"
        DisableCommand = "Camera=Enabled", "Microphone=Enabled"
    }

    "Filter"  = [DellOption]@{
        Enabling       = $Filter
        DellCheck      = { $_ -match "DustFilter" }
        EnableCommand  = "DustFilter=15days"
        DisableCommand = "DustFilter=Disabled"
    }
}

# Create sessions
Write-Host -ForegroundColor Blue Creating sessions...
$Sessions = New-PSSession $ComputerName

# Show created sessions
Write-Host -ForegroundColor Green -NoNewline Created sessions:
$Sessions.ForEach({ Write-Host -NoNewline " $($_.ComputerName)" })
Write-Host

# Create hashtable of computers
$Computers = @{}
$Sessions | ForEach-Object { $Computers.Add($_.ComputerName, (New-Object -TypeName ComputerProperties -ArgumentList $_.ComputerName, $_)) }

# Cleanup in case old temp files exist
Invoke-Command -Session $Sessions -ScriptBlock { Remove-Item -Recurse C:\Temp\cctk } -ErrorAction SilentlyContinue

# Exit now if $Cleanup
if ($Cleanup) {
    # Remove all sessions if cleanup is requested
    Remove-PSSession *
    Exit
}

# Detect Dell computers and copy CCTK if we know where it is
if ($CCTKPath) {
    # Check to see what targets are Dell
    foreach ($Session in $Sessions) {
        if (Invoke-Command -Session $Session -ScriptBlock { (Get-CimInstance win32_computersystem).Manufacturer -like "Dell*" }) {
            $Computers[$Session.ComputerName].Dell = $true
        }
    }

    # Show Dell computers
    Write-Host -ForegroundColor Green -NoNewline Identified Dell computers:
    ($Computers | Where-Object { $_.Values.Dell }).GetEnumerator().ForEach({ Write-Host -NoNewline " $($_.Key)" })
    Write-Host

    Write-Host -ForegroundColor Blue -NoNewline Copying CCTK:

    # Copy CCTK in parallel to each Dell computer
    ($Computers | Where-Object { $_.Values.Dell }).GetEnumerator() | ForEach-Object -Parallel {
        Write-Host -NoNewline " $($_.Key)"
        Invoke-Command -Session $_.Value.Session -ScriptBlock {
            New-Item -Path C:\Temp\cctk -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        }
        Copy-Item -ToSession $_.Value.Session $(($env:cctk) + '\*') -Destination C:\Temp\cctk\
    }
    Write-Host

    # Get available BIOS settings
    Write-Host -ForegroundColor Blue -NoNewline Detecting capabilities...
    ($Computers | Where-Object { $_.Values.Dell }).GetEnumerator() | ForEach-Object -Parallel {
        $_.Value.DellCapabilities = (Invoke-Command -Session $_.Value.Session -ScriptBlock {
                c:\Temp\cctk\cctk.exe
            }).Split().Where({ $_ -match '--' }).Split('--').Where({ $_ -notmatch '\*' -and $_ -ne '' -and $_ -notmatch 'option\[=argument\]' }) | Sort-Object
        Write-Host -ForegroundColor Green -NoNewline " $($_.Key)"
    }
    Write-Host
}

foreach ($Computer in $Computers.GetEnumerator()) {
    $Computer.Value.DellCommand = ""
    foreach ($Option in $DellOptions.GetEnumerator()) {
        if ($Option.Value.Enabling -eq $true -and ($Computer.Value.DellCapabilities | Where-Object -FilterScript $Option.Value.DellCheck)) {
            foreach ($Command in $Option.Value.EnableCommand) {
                if ($Command.Split('=')[0] -in $Computer.Value.DellCapabilities) {
                    $Computer.Value.DellCommand += "--$Command "
                }
            }
        }
    }
    Write-Host -ForegroundColor Green -NoNewline "Configuring $($Computer.Key): "
    Write-Host $($Computer.Value.DellCommand)

    # Invoke-Command -Session $Computer.Value.Session -ScriptBlock {
    #     param($CCTKPass, $DellCommand)
    #     C:\Temp\cctk\cctk.exe $DellCommand --ValSetupPwd=$CCTKPass
    # } -ArgumentList $CCTKPass, $Computer.Value.DellCommand
}

# Cleanup
Write-Host -ForegroundColor Blue Cleaning up...
Invoke-Command -Session $Sessions -ScriptBlock { Remove-Item -Recurse C:\Temp\cctk }
$Sessions | Remove-PSSession