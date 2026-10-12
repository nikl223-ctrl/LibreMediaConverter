#Requires -Version 7.2
<#
  Only for a PRIVATE GitHub repository used for personal Android testing.
  Downloads the user-provided game archive from their Google Drive with the
  existing private OAuth client. Nothing is checked into source control.
#>
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY_PRIVATE -ne "true") {
  throw "Original commercial assets will not be processed in a public repository."
}
foreach ($key in @("GOOGLE_CLIENT_ID","GOOGLE_CLIENT_SECRET","GOOGLE_REFRESH_TOKEN")) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($key))) {
    throw "The private repository is missing required secret $key."
  }
}
if (-not $env:GOOGLE_CLIENT_ID.StartsWith("160241343420-")) {
  throw "Wrong private OAuth client. Expected project prefix 160241343420."
}
$token = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -ContentType "application/x-www-form-urlencoded" -Body @{
  client_id = $env:GOOGLE_CLIENT_ID
  client_secret = $env:GOOGLE_CLIENT_SECRET
  refresh_token = $env:GOOGLE_REFRESH_TOKEN
  grant_type = "refresh_token"
}
$archive = Join-Path $env:RUNNER_TEMP "original_city.v"
$uri = "https://www.googleapis.com/drive/v3/files/1WWn0u7TG2-cwc2WZuLpPS7CNjTyCTv5u?alt=media&supportsAllDrives=true"
try {
  Invoke-WebRequest -Uri $uri -Headers @{ Authorization = "Bearer $($token.access_token)" } -OutFile $archive -TimeoutSec 900
  $size = (Get-Item -LiteralPath $archive).Length
  if ($size -ne 452795096) { throw "Unexpected city.v length: $size" }
  $out = "Ambulance2012Android/original_assets"
  python Ambulance2012Android/tools/prepare_private_game_assets.py --city $archive --out $out --vgmstream "$env:VGMSTREAM_CLI"
  if ($LASTEXITCODE -ne 0) { throw "Personal-use audio or material extraction failed." }
  if (-not (Test-Path "$out/siren.wav")) { throw "Missing original siren recording." }
  if (-not (Test-Path "$out/engine_idle.wav")) { throw "Missing original diesel recording." }
  if (-not (Test-Path "$out/rtw_exterior.webp")) { throw "Missing original vehicle texture." }
  Write-Host "PRIVATE_GAME_ASSETS_PASS: original siren, engine and RTW diffuse material decoded"
} finally {
  Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
}
