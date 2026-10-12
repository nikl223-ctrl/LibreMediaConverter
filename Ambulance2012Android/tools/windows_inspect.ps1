#Requires -Version 7.2
<#
.SYNOPSIS
Windows-only, non-executing inventory of Rettungswagen-Simulator 2012 shared in Drive.
The worker NEVER executes, installs, modifies, commits or republishes the game binaries.
It reads binary magic, PE architecture, SHA-256 and file lengths. Artifacts contain ONLY a JSON report.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$source = 'https://drive.google.com/drive/folders/1ddUvXS4sHtkEt8-4Wi4sOofu3JmWWcYm'
$working = Join-Path $env:RUNNER_TEMP 'vision-source-audit'
$reportDir = Join-Path $env:GITHUB_WORKSPACE 'Ambulance2012Android/port-audit/report'
New-Item -ItemType Directory -Force -Path $working, $reportDir | Out-Null
$files = @(
  @{ name='bin9/rtws_app.exe';           id='11cmItpDqxzzLBkx7KkDCfTLfAW9GBS0u'; expectedBytes=296448;    role='Windows game launcher' },
  @{ name='bin9/plugins/rtws_gamedll.vPlugin'; id='1g1qgYNvIsE0n4DqDQceV4uLOhQFQLs5p'; expectedBytes=1001472; role='Native game code plug-in' },
  @{ name='bin9/Vision90.dll';           id='1ryfR2_gJlsYYzzQuIpqE2o4HVpBfxKrn'; expectedBytes=1376768; role='Vision Engine Windows runtime' },
  @{ name='data/city.v';                 id='1WWn0u7TG2-cwc2WZuLpPS7CNjTyCTv5u'; expectedBytes=452795096; role='Proprietary game resource archive' }
)
$results = [System.Collections.Generic.List[object]]::new()
$failed = 0

function Get-MagicAndPE([string]$path) {
  $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  try {
    $reader = [IO.BinaryReader]::new($stream)
    try {
      $head = $reader.ReadBytes(48)
      $hex = ([BitConverter]::ToString($head)).Replace('-', ' ')
      $ascii = -join ($head | ForEach-Object { if($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' } })
      $format = 'unknown'
      $architecture = $null
      if ($head.Length -ge 2 -and $head[0] -eq 0x4d -and $head[1] -eq 0x5a) {
        $format = 'Windows Portable Executable (MZ)'
        $stream.Seek(0x3c,[IO.SeekOrigin]::Begin) | Out-Null
        $offset = $reader.ReadInt32()
        if($offset -gt 0 -and $offset -lt [Math]::Min($stream.Length-6,1048576)) {
          $stream.Seek($offset,[IO.SeekOrigin]::Begin) | Out-Null
          if($reader.ReadUInt32() -eq 0x00004550) {
            $machine = $reader.ReadUInt16()
            $architecture = switch($machine) {
              0x014c {'x86 (32-bit)'}
              0x8664 {'x64 (64-bit)'}
              0xaa64 {'ARM64'}
              default { 'PE machine 0x{0:x4}' -f $machine }
            }
          }
        }
      }
      return @{ format=$format; architecture=$architecture; headerHex=$hex; headerAscii=$ascii }
    } finally { $reader.Dispose() }
  } finally { $stream.Dispose() }
}

function Add-FileResult([hashtable]$entry) {
  $target = Join-Path $working ($entry.name -replace '/','_')
  $uri = 'https://www.googleapis.com/drive/v3/files/{0}?alt=media&supportsAllDrives=true' -f $entry.id
  Write-Host ("Downloading safely for inspection: {0} ({1} bytes)" -f $entry.name, $entry.expectedBytes)
  $downloaded = $false
  for($attempt=1;$attempt -le 3 -and -not $downloaded;$attempt++) {
    try {
      Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -OutFile $target -TimeoutSec 900 -MaximumRedirection 5 | Out-Null
      $downloaded = $true
    } catch {
      Write-Warning ("Download failed for {0} on attempt {1}: {2}" -f $entry.name, $attempt, $_.Exception.Message)
      if($attempt -lt 3) { Start-Sleep -Seconds (3 * $attempt) }
    }
  }
  if(-not $downloaded) {
    $script:failed++
    $results.Add(@{name=$entry.name; role=$entry.role; driveFileId=$entry.id; result='download unavailable via repo OAuth credentials'})
    return
  }
  try {
    $size = (Get-Item -LiteralPath $target).Length
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
    $magic = Get-MagicAndPE $target
    if($entry.name -eq 'data/city.v') {
      python Ambulance2012Android/tools/inspect_city.py --input $target --out (Join-Path $reportDir 'city-archive-analysis.json')
      if($LASTEXITCODE -ne 0) { Write-Warning 'Archive analysis could not complete; base metadata is still collected' }
    }
    $matched = $size -eq $entry.expectedBytes
    if(-not $matched) { $script:failed++; Write-Warning ('Size mismatch: ' + $entry.name) }
    $results.Add(@{
      name=$entry.name; role=$entry.role; driveFileId=$entry.id;
      result='inspected'; actualBytes=$size; expectedBytes=$entry.expectedBytes;
      sizeVerified=$matched; sha256=$sha;
      fileFormat=$magic.format; peArchitecture=$magic.architecture;
      first48BytesHex=$magic.headerHex; first48BytesAscii=$magic.headerAscii
    })
    Write-Host ("Inspected {0}: {1} bytes; format={2}; architecture={3}" -f $entry.name,$size,$magic.format,$magic.architecture)
  } finally {
    Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
  }
}

try {
  foreach($n in @('GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','GOOGLE_REFRESH_TOKEN')) {
    if([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($n))) {
      throw "Missing GitHub secret: $n (no file downloaded)"
    }
  }
  # Enforce the user's existing, private OAuth application: NEVER rclone shared public client.
  if(-not $env:GOOGLE_CLIENT_ID.StartsWith('160241343420-')) {
    throw 'Private Google OAuth client mismatch. Expected project 160241343420. Stop rather than falling back to a public client.'
  }
  $tokenResponse = Invoke-RestMethod -Method Post -Uri 'https://oauth2.googleapis.com/token' -ContentType 'application/x-www-form-urlencoded' -Body @{
    client_id=$env:GOOGLE_CLIENT_ID
    client_secret=$env:GOOGLE_CLIENT_SECRET
    refresh_token=$env:GOOGLE_REFRESH_TOKEN
    grant_type='refresh_token'
  }
  if (-not $tokenResponse.access_token) { throw 'Could not refresh a Drive access token.' }
  $headers = @{ Authorization = ('Bearer ' + $tokenResponse.access_token) }
  foreach($file in $files) { Add-FileResult $file }
} catch {
  $script:failed++
  Write-Warning ("Windows inspection stopped: " + $_.Exception.Message)
}

$summary = @{
  auditVersion = 1
  createdUtc = [DateTime]::UtcNow.ToString('o')
  sourceFolderUrl = $source
  examinedOn = 'GitHub Actions windows-2022 worker'
  binaryExecution = 'none'
  binaryPublication = 'none'
  files = $results.ToArray()
  sourceFilesPresent = $false
  gameEngine = 'Havok Vision Engine 9-era native Windows installation; source not supplied'
  androidConversion = 'NOT a drop-in conversion. Executables/DLLs require original source and an Android-capable engine, or a legally permitted ground-up reimplementation.'
  nextStep = 'Provide the actual project/source code, matching engine version and rights to port and redistribute its data. The city.v format must also be documented or licensed for extraction.'
  errors = $failed
}
$out = Join-Path $reportDir 'windows-vision-audit.json'
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $out -Encoding utf8
Write-Host ("Audit report saved: " + $out)
Write-Host ("Source code detected: NO. Port-ready Android game: NO. Errors: " + $failed)
if($failed -gt 0) { exit 1 }
exit 0
