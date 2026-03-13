# --- Auto-elevate ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "Elevating..."
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# --- Logging (script directory) ---
$ScriptDir = Split-Path -Path $PSCommandPath -Parent
$LogPath   = Join-Path $ScriptDir "BitLocker-Remediation.log"
function Log ($msg) {
    Add-Content -Path $LogPath -Value ("[$(Get-Date -Format s)] $msg")
}

# --- Helpers: deterministic waits ---
function Wait-ForTpmReady {
    param(
        [int]$TimeoutSeconds = 90,
        [int]$IntervalSeconds = 3
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $tpm = Get-Tpm
        if ($tpm.TpmPresent -and $tpm.TpmReady) { return $true }
        Start-Sleep -Seconds $IntervalSeconds
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Wait-ForProtectionOn {
    param(
        [string]$MountPoint = 'C:',
        [int]$TimeoutSeconds = 120,
        [int]$IntervalSeconds = 3
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $v = Get-BitLockerVolume -MountPoint $MountPoint
        if ($v.ProtectionStatus -eq 'On') { return $true }
        Start-Sleep -Seconds $IntervalSeconds
    } while ((Get-Date) -lt $deadline)
    return $false
}

# --- MAIN SCRIPT ---
try {
    Log "Running elevated as $(whoami)"

    # 0) Quick state snapshot
    $vol = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
    Log "Initial: Prot=$($vol.ProtectionStatus) Vol=$($vol.VolumeStatus) %Enc=$($vol.EncryptionPercentage) Method=$($vol.EncryptionMethod)"

    # 1) Ensure Recovery Password exists (this is the only thing we escrow to Entra)
    $rp = $vol.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword' | Select-Object -First 1
    if (-not $rp) {
        Log "No Recovery Password found. Adding one..."
        $added = Add-BitLockerKeyProtector -MountPoint 'C:' -RecoveryPasswordProtector -ErrorAction Stop
        $rp = $added.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword' | Select-Object -First 1
        Log "Added Recovery Password protector: $($rp.KeyProtectorId)"
    } else {
        Log "Recovery Password exists: $($rp.KeyProtectorId)"
    }

    # 2) Escrow Recovery Password to Entra
    Log "Escrowing Recovery Password $($rp.KeyProtectorId) to Entra ID..."
    BackupToAAD-BitLockerKeyProtector -MountPoint 'C:' -KeyProtectorId $rp.KeyProtectorId -ErrorAction Stop
    Log "Escrow completed."

    # 3) Ensure we have a startup protector (TPM or TPM+PIN)
    $tpmProt = (Get-BitLockerVolume -MountPoint 'C:').KeyProtector |
               Where-Object { $_.KeyProtectorType -in @('Tpm','TpmPin') } |
               Select-Object -First 1

    if (-not $tpmProt) {
        Log "No TPM-based startup protector found. Checking TPM state..."
        $tpm = Get-Tpm
        if (-not $tpm.TpmPresent) { throw "TPM not present. Enable vTPM/firmware TPM and rerun." }

        if (-not $tpm.TpmReady) {
            Log "TPM not ready. Initializing TPM..."
            Initialize-Tpm | Out-Null

            Log "Waiting for TPM to report Ready..."
            if (-not (Wait-ForTpmReady -TimeoutSeconds 90 -IntervalSeconds 3)) {
                throw "TPM did not become ready within the timeout."
            }
            Log "TPM is Ready."
        } else {
            Log "TPM is present and ready."
        }

        # Add TPM (swap to -TpmPinProtector if you require a PIN; gather $Pin as SecureString)
        Log "Adding TPM protector..."
        Add-BitLockerKeyProtector -MountPoint 'C:' -TpmProtector -ErrorAction Stop | Out-Null

        # Re-fetch to confirm
        $tpmProt = (Get-BitLockerVolume -MountPoint 'C:').KeyProtector |
                   Where-Object { $_.KeyProtectorType -in @('Tpm','TpmPin') } |
                   Select-Object -First 1

        if ($tpmProt) {
            Log "TPM protector added: $($tpmProt.KeyProtectorId)"
        } else {
            throw "Failed to add TPM protector."
        }
    } else {
        Log "TPM protector already present: $($tpmProt.KeyProtectorId)"
    }

    # 4) Ensure protection is ON (resume if suspended)
    $vol = Get-BitLockerVolume -MountPoint 'C:'
    if ($vol.ProtectionStatus -ne 'On') {
        Log "Protection currently $($vol.ProtectionStatus). Resuming BitLocker..."
        Resume-BitLocker -MountPoint 'C:' -ErrorAction Stop

        Log "Waiting for ProtectionStatus to become On..."
        if (-not (Wait-ForProtectionOn -MountPoint 'C:' -TimeoutSeconds 120 -IntervalSeconds 3)) {
            # Final read for diagnostics
            $vol = Get-BitLockerVolume -MountPoint 'C:'
            throw "Protection did not become On in time. Current: Prot=$($vol.ProtectionStatus) Vol=$($vol.VolumeStatus) %Enc=$([int]$vol.EncryptionPercentage)"
        }
    }

    # 5) Final snapshot
    $vol = Get-BitLockerVolume -MountPoint 'C:'
    Log "Final: Prot=$($vol.ProtectionStatus) Vol=$($vol.VolumeStatus) %Enc=$([int]$vol.EncryptionPercentage) Method=$($vol.EncryptionMethod)"

    Log "BitLocker remediation succeeded."
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    exit 1
}