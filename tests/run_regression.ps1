param([Parameter(Mandatory=$true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$logPath = Join-Path $projectRoot 'tmp/regression.log'
$testData = Join-Path $projectRoot 'tmp/test_userdata'
New-Item -ItemType Directory -Path $testData -Force | Out-Null
$previousAppData = $env:APPDATA
try {
    $env:APPDATA = $testData
    & $GodotPath --headless --path $projectRoot --log-file $logPath res://tests/regression.tscn --quit-after 6000
    $runExitCode = $LASTEXITCODE
    $log = Get-Content -LiteralPath $logPath -Raw
    if ($runExitCode -ne 0 -or $log -match 'SCRIPT ERROR|ERROR:' -or $log -notmatch 'REGRESSION: \d+ checks, 0 failures') {
        throw "Regression failed or did not complete. See $logPath"
    }
    # Save/restore must survive a real process restart, so each phase is a separate Godot process.
    foreach ($phase in @('write', 'verify')) {
        $phaseLog = Join-Path $projectRoot "tmp/save_restart_$phase.log"
        & $GodotPath --headless --path $projectRoot --log-file $phaseLog res://tests/save_restart.tscn --quit-after 3000 -- "--phase=$phase"
        $phaseExitCode = $LASTEXITCODE
        $phaseText = Get-Content -LiteralPath $phaseLog -Raw
        if ($phaseExitCode -ne 0 -or $phaseText -match 'SCRIPT ERROR|ERROR:' -or $phaseText -notmatch "SAVE_RESTART ${phase}: \d+ checks, 0 failures") {
            throw "Save restart phase '$phase' failed or did not complete. See $phaseLog"
        }
    }
} finally {
    $env:APPDATA = $previousAppData
}
