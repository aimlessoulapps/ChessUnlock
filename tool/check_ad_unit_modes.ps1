param([string]$Dart = 'dart')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    function Invoke-DartChecked([string[]]$ToolArgs) {
        & $Dart @ToolArgs
        if ($LASTEXITCODE -ne 0) { throw "Ad-unit compiler-mode check failed ($LASTEXITCODE)" }
    }
    $probe = 'test/ad_unit_mode_probe.dart'
    $qaFlags = @(
        '-DCHESSUNLOCK_TEST_ADS=true',
        '-DCHESSUNLOCK_REWARDED_AD_UNIT_ID=ca-app-pub-3940256099942544/5224354917',
        '-DCHESSUNLOCK_ANDROID_REWARDED_AD_UNIT_ID=ca-app-pub-3940256099942544/5224354917',
        '-DCHESSUNLOCK_IOS_REWARDED_AD_UNIT_ID=ca-app-pub-3940256099942544/1712485313'
    )
    $liveFlags = @(
        '-DCHESSUNLOCK_TEST_ADS=false',
        '-DCHESSUNLOCK_REWARDED_AD_UNIT_ID=ca-app-pub-8108010703558411/1847579539',
        '-DCHESSUNLOCK_ANDROID_REWARDED_AD_UNIT_ID=ca-app-pub-8108010703558411/1847579539',
        '-DCHESSUNLOCK_IOS_REWARDED_AD_UNIT_ID=ca-app-pub-8108010703558411/5800977815'
    )
    foreach ($mode in @('debug', 'profile', 'release')) {
        $modeFlags = @(
            "-Ddart.vm.product=$($mode -eq 'release')".Replace('True', 'true').Replace('False', 'false'),
            "-Ddart.vm.profile=$($mode -eq 'profile')".Replace('True', 'true').Replace('False', 'false')
        )
        Invoke-DartChecked ($modeFlags + @($probe, $mode))
        Invoke-DartChecked ($modeFlags + $qaFlags + @($probe, $mode))
        Invoke-DartChecked ($modeFlags + $liveFlags + @($probe, $mode))
    }
    # The product-mode policy must work with assertions removed and tree shaking.
    $outputDirectory = Join-Path $projectRoot 'build/ad-unit-checks'
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    $outputFile = Join-Path $outputDirectory 'release-probe.exe'
    Invoke-DartChecked (@('compile', 'exe', '-Ddart.vm.product=true', '-Ddart.vm.profile=false') +
        $qaFlags + @($probe, '-o', $outputFile))
    & $outputFile release
    if ($LASTEXITCODE -ne 0) { throw 'AOT release ad-unit check failed' }
    Write-Output 'PASS: 9 VM configurations and AOT release with conflicting QA overrides.'
} finally {
    Pop-Location
}
