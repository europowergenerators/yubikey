#Requires -Version 7.0
#Requires -RunAsAdministrator

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

$pivToEnable = $Host.UI.PromptForChoice('PIV re-enable', 'You want te re-enable PIV, for ICT use?', @('&Yes', '&No'), 1)

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

    if($pivToEnable -eq 0) {
        $ModesCollection["PIV"] = '--enable'
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

# Personal Identity Verification (PIV)
#
# PIV is a hardware and protocol standard for authenticating individual persons to a computersystem.
# The most basic form of PIV, for the mindset of an administrator, is as follows;
#   - There exist secured devices that have storage slots (similar to registers) for crypthographic keys
#   - The protocol defines a fixed set of functions for cryptographically signing and encrypting data
#   - Security is provided through the use of PIN/PUK/Management secrets
#     The PIN and PUK are 8 bytes (characters) long, the management secret is a DES-key of 24 bytes
#
# Yubikey extension to the PIV standard;
#   - Management key can also be an AES key of 32 bytes
#   - Functionality can be secured through secondary action; "Touching the key"
#     The PIV standard doesn't define any second factor besides entering the PIN code
#   - The management key can be 'managed' by the yubikey itself, protected by the PIN
#     Activating this functionality is done by the project 'PIVSetupPinOnly'.
#     The owner of the key has to _only remember the PIN_ of his security key in this mode.
#   - The Yubikey has 20 legacy storage slots. These are kept for backwards compatibility.
#     Age can use any of these legacy slots to store assymetric encryption key material
#
# The PIN and Management secrets are bound to the owner of the key.
# The PUK secret is kept by the administrator.
#
# The management key is used to do maintenance on the key, like creating new secrets, importing
# private keys/certificates.
if($pivToEnable -eq 0) {
    $ConnectedKeys | `
    ForEach-Object { $i = 0; } {        
    $i++;
    $DeviceSerial = $_
    
    Step -Description 'Initiating PIV reset' ([ordered]@{
        'Key' = "$DeviceSerial [$i]"
    })
    & $YKCli --device $DeviceSerial piv reset
    Result ([ordered]@{
            'Key'        = "$DeviceSerial [$i]"
            'PIV Reset' = (& { If ($?) { 'OK' } Else { 'Failure' } })
        })
    }

    $ConnectedKeys | `
    Foreach-Object { $i = 0; } {
    $i++;
    $DeviceSerial = $_
    
    $DefaultAccess = [System.Collections.ArrayList]@(
        '--pin', '123456',
        '--management-key', '010203040506070801020304050607080102030405060708'
    )

    # Retry count of 1 means there are no retries
    & $YKCli --device $DeviceSerial piv access set-retries 3 1 --force @DefaultAccess
    Result ([ordered]@{
            'Key'            = "$DeviceSerial [$i]"
            'PIV PIN RETRIES' = (& { If ($?) { 'OK' } Else { 'Failure' } })
        })

    # Lock out PUK code by providing a wrong PUK
    & $YKCli --device $DeviceSerial piv access change-puk --puk 000000 --new-puk 000000
    Result ([ordered]@{
            'Key'            = "$DeviceSerial [$i]"
            'PUK LOCKOUT' = (& { If (-not $?) { 'OK' } Else { 'Failure' } })
        })

    # Put key into PIN-Protected mode.
    # This generates a new management key and protects it with the PIN. This way the management key
    # is uniquely set and automatically unlocked when running management functions.
    # The owner only needs to remember its PIN code
    & dotnet run --project '.\PIVSetupPinOnly' -- $DeviceSerial
    Result ([ordered]@{
            'Key'            = "$DeviceSerial [$i]"
            'PIV PIN-PROTECTED-MODE' = (& { If ($?) { 'OK' } Else { 'Failure' } })
        })
    }

    # Change PIN from default
    & $YKCli --device $DeviceSerial piv access change-pin --pin 123456
    Result ([ordered]@{
            'Key'            = "$DeviceSerial [$i]"
            'PIV PIN' = (& { If ($?) { 'OK' } Else { 'Failure' } })
        })
}

Write-Host @DONE 'Finished!'
# NOTE; Wait is required because the elevated powershell window doesn't persist after
# script exit!
Wait