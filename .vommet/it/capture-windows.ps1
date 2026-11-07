# Microphone capture test (#78) on the Windows build. VB-CABLE (installed by
# the workflow) is the only audio device: what plays to "CABLE Input" comes out
# of the "CABLE Output" microphone. A speech-like signal loops into it.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $here "..\..\it-out"
New-Item -ItemType Directory -Force -Path $out | Out-Null

Get-CimInstance Win32_SoundDevice | Format-Table Name, Status | Out-String | Write-Host

$results = Join-Path (Resolve-Path $out) "capture-results.txt"
Remove-Item -ErrorAction SilentlyContinue $results
$wav = Join-Path $env:RUNNER_TEMP "capture-signal.wav"
# Real (synthesized) speech, not make_signal.py's warble: WebRTC's noise
# suppression, on in the app, learns a looping synthetic signal as noise
# within minutes (measured 0.019, then 0.0006 on the same build). Windows'
# built-in SAPI voice renders it; 48 kHz mono 16-bit.
Add-Type -AssemblyName System.Speech
$tts = New-Object System.Speech.Synthesis.SpeechSynthesizer
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(48000,
  [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
  [System.Speech.AudioFormat.AudioChannel]::Mono)
$tts.SetOutputToWaveFile($wav, $fmt)
$tts.Speak(("This is the Vommet microphone capture test. One, two, three, four, five. " +
  "The quick brown fox jumps over the lazy dog, and the five boxing wizards jump quickly. " +
  "Testing, testing. Can you hear me now? Good. Let us count again: six, seven, eight, nine, ten."))
$tts.Dispose()
Write-Host "speech: $((Get-Item $wav).Length) bytes"
pip install --quiet sounddevice numpy
# Environment control first: does audio played to CABLE Input come out of the
# CABLE Output microphone at all (independent of the app)?
python (Join-Path $here "cable_audio.py") check $wav 2>&1 | Tee-Object -Variable envcheck | Write-Host
$envcheck | Where-Object { "$_" -match "^CAPTURE env" } | Add-Content -Path $results

Push-Location (Join-Path $here "..\..\commet")
$rc = 1
$player = $null
try {
  # A release build of a plain entry point (integration_test/capture_probe.dart):
  # the debug build's Rust link fails on MSVC (LNK1201), and release builds
  # leave out the integration_test plugin, so no test framework here.
  flutter build windows --release -t integration_test/capture_probe.dart `
    --dart-define=CAPTURE_LOG=$results 2>&1 | Tee-Object -FilePath (Join-Path $out "capture-windows.log")
  if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }
  # commet.exe upstream, vommet.exe with the fork's branding: take whichever.
  $exe = (Get-ChildItem "build\windows\x64\runner\Release\*.exe" | Select-Object -First 1).FullName
  if (-not $exe) { throw "no .exe in the release build" }
  # Start the signal only now, not before the long build.
  $player = Start-Process python -PassThru -WindowStyle Hidden -ArgumentList @(
    (Join-Path $here "cable_audio.py"), "loop", $wav)
  Start-Sleep -Seconds 2
  $probe = Start-Process -FilePath $exe -PassThru
  $null = $probe.Handle  # else ExitCode can read empty after the wait
  if (-not $probe.WaitForExit(120000)) {
    Stop-Process -Id $probe.Id -Force
    Add-Content -Path $results -Value "CAPTURE FAIL probe timed out after 120 s"
  } else {
    $rc = $probe.ExitCode
  }
} catch {
  Write-Host "::error title=Windows capture::$_"
} finally {
  Pop-Location
  if ($player) { Stop-Process -Id $player.Id -ErrorAction SilentlyContinue }
}
# Annotations are readable without a token, unlike job logs (annotate.sh).
function Enc([string[]]$l) { ($l -join "`n").Replace("%", "%25").Replace("`r", "%0D").Replace("`n", "%0A") }
$log = Join-Path $out "capture-windows.log"
$res = if (Test-Path $results) { Get-Content $results } else { @() }
if ($res) { Write-Host "::notice title=Windows capture results::$(Enc $res)" }
# The probe's own verdict decides: Flutter's exit() can end in a crash code
# on Windows after a clean run.
if ($rc -ne 0 -and ($res -match "CAPTURE PASS")) { $rc = 0 }
# A pass must show its own verdict: guards against a skipped or empty run.
if ($rc -eq 0 -and -not ($res -match "CAPTURE PASS")) {
  Write-Host "::error title=Windows capture::exit 0 but no CAPTURE PASS line; treating as failure"
  $rc = 1
}
if (Test-Path $log) {
  if ($rc -ne 0) {
    $tail = Get-Content $log | Where-Object { $_.Trim() } | Select-Object -Last 60 |
      ForEach-Object { if ($_.Length -gt 300) { $_.Substring(0, 300) } else { $_ } }
    Write-Host "::error title=Windows capture failed (exit $rc)::$(Enc $tail)"
  }
}
exit $rc
