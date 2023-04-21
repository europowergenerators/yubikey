$INFO = @{'ForegroundColor' = 'White' }
$USER = @{'ForegroundColor' = 'Yellow' }
$DONE = @{'ForegroundColor' = 'Green' }
function Wait {
    param (
        [Parameter(Position = 0, Mandatory = $false)] [string] $Description
    )
    if ($PSBoundParameters.ContainsKey('Description')) {
        Read-Host -Prompt $Description
    }
    else {
        Read-Host -Prompt 'Press enter to go to the next step'
    }
}

function Result {
    param (
        [Parameter(Position = 0, Mandatory = $true)] [System.Collections.IDictionary] $StepDetails
    )

    $StepDetails.GetEnumerator() | ForEach-Object {
        Write-Host @INFO -NoNewline ($_.Key + ': ')
        Write-Host @DONE $_.Value
    }
}

function Step {
    param (
        [Parameter(Position = 0, Mandatory = $true)] [System.Collections.IDictionary] $StepDetails,
        [Parameter(Mandatory = $false)] [string] $Description
    )

    if ($Description) {
        Write-Host @INFO $Description
    }

    $StepDetails.GetEnumerator() | ForEach-Object {
        Write-Host @INFO -NoNewline ($_.Key + ': ')
        Write-Host @USER $_.Value
    }
}

Function Start-RunAsAdministrator() {
    $CurrentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($CurrentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-host "Script is running with Administrator privileges!"
    }
    else {
        #Create a new Elevated process to Start PowerShell
        $ElevatedProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell";
        $ElevatedProcess.Arguments = "& '" + $script:MyInvocation.MyCommand.Path + "'" 
        $ElevatedProcess.Verb = "runas"
        [System.Diagnostics.Process]::Start($ElevatedProcess) | Out-Null
 
        # Exit from the current, unelevated, process
        Write-Host @global:USER 'Launched administrator powershell process.'
        Exit 
    }
}

Start-RunAsAdministrator

$YubiKeyManagerLocation = 'C:\Program Files\Yubico\YubiKey Manager\ykman.exe'
if (!(Test-Path -Path $YubiKeyManagerLocation -PathType Leaf)) {
    Write-Host @USER 'The Yubikey Manager program is not found at the default installation location! Install the application before continuing'
    exit 1
}
$YKCli = $YubiKeyManagerLocation

$ConnectedKeys = @(& $YKCli list --serials)
if ($ConnectedKeys.Length -eq 0) {
    Write-Host @USER 'No keys detected, exiting..'
    exit 2
}

# ERROR; FIDO reset only works with 1 key currently connected!
if($ConnectedKeys.Length -gt 1) {
    Write-Host @INFO 'Only 1 key can be reset at one time.'
    Write-Host @USER 'Remove all keys but 1 and restart the script. Exiting..'
    exit 2
}

Result ([ordered]@{
        'Number of connected keys' = $ConnectedKeys.Length
    })
Wait 'Press enter to see details of all connected keys'

$ConnectedKeys | `
    ForEach-Object {
    & $YKCli --device $_ info | `
        Select-String -Pattern ':' -SimpleMatch | `
        Out-String
} | `
    Write-Host
Wait 'Press enter to start the reset process for _all_ connected keys'

$ConnectedKeys | `
    ForEach-Object { $i = 0; } {        
    $DeviceSerial = $_
        
    # WARN; Do _not_ lock the application configuration with a code. Lock code-loss is NON-RECOVERABLE.
    #
    # NOTE; ykman config mode is a legacy mode, use the specific interface modes for more granular control.
    #
        
    $ModesCollection = @{
        'OTP'     = '--disable'
        'OATH'    = '--disable'
        'PIV'     = '--disable'
        'OPENPGP' = '--disable'
        'HSMAUTH' = '--disable'
        'U2F'     = '--enable'
        'FIDO2'   = '--enable'
    }
        
    $InterfaceCollection = @('usb', 'nfc')
        
    $InterfaceCollection | ForEach-Object {
        $Interface = $_
            
        $ModesCollection.GetEnumerator() | ForEach-Object {
            $Mode = $_.Key
            $Status = $_.Value
            # eg [..] config usb --disable OTP --force
            & $YKCli --device $DeviceSerial config $Interface $Status $Mode --force
        }
    }             
}
Result ([ordered]@{
        'Interfaces reset' = 'Done'
    })

$ConnectedKeys | `
    ForEach-Object { $i = 0; } {        
    $i++;
    $DeviceSerial = $_
    
    Step -Description 'Initiating FIDO reset' ([ordered]@{
        'Key' = "$DeviceSerial [$i]"
    })
    & $YKCli --device $DeviceSerial fido reset
    Result ([ordered]@{
            'Key'        = "$DeviceSerial [$i]"
            'FIDO Reset' = (& { If ($?) { 'OK' } Else { 'Failure' } })
        })
}

$ConnectedKeys | `
    Foreach-Object { $i = 0; } {
    $i++;
    $DeviceSerial = $_
        
    & $YKCli --device $DeviceSerial fido access change-pin
    Result ([ordered]@{
            'Key'            = "$DeviceSerial [$i]"
            'FIDO PIN' = (& { If ($?) { 'OK' } Else { 'Failure' } })
        })
}

Write-Host @DONE 'Finished!'
# NOTE; Wait is required because the elevated powershell window doesn't persist after
# script exit!
Wait