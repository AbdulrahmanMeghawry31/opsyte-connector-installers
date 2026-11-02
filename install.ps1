<#
  Installs the site connector on a Windows machine at a customer's site (R15j) as a Windows service (WinSW).

    powershell -ExecutionPolicy Bypass -File install.ps1 -Api https://<api host> -Code XXXX-XXXX
    powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall [-Purge]

  The pairing code comes from the app (Config -> Connectors -> Add connector) and works once. The token is kept in
  %ProgramData%\SiteConnector\edge\connector.json, readable by SYSTEM and Administrators only. The program talks to
  the platform over HTTPS only and updates itself from signed releases.

  Not tested on the Linux development box: try it on a Windows 10/11 or Server 2019+ machine first.
#>
param(
  [string]$Api = "",
  [string]$Code = "",
  [string]$Zip = "",
  [string]$InstallDir = "$env:ProgramFiles\SiteConnector",
  [switch]$Uninstall,
  [switch]$Purge
)
$ErrorActionPreference = "Stop"
$Data = Join-Path $env:ProgramData "SiteConnector\edge"
$Service = Join-Path $InstallDir "site-connector-service.exe"

function Say($m) { Write-Host $m -ForegroundColor Cyan }

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this in an elevated PowerShell (as Administrator)." }

if ($Uninstall) {
  if (Test-Path $Service) { & $Service stop | Out-Null; & $Service uninstall | Out-Null }
  Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
  if ($Purge) { Remove-Item -Recurse -Force (Split-Path $Data) -ErrorAction SilentlyContinue }
  Say "Removed. Revoke or remove the connector in the app too."
  exit 0
}

if (-not $Api.StartsWith("https://")) { throw "Give the API address: -Api https://<api host>" }
$Api = $Api.TrimEnd("/")
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

New-Item -ItemType Directory -Force -Path $InstallDir, $Data | Out-Null
# Only SYSTEM and Administrators may read the data folder (the token is a credential)
icacls (Split-Path $Data) /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null

$State = Join-Path $Data "connector.json"
if ((Test-Path $State) -and ((Get-Content $State -Raw) -match '"token"')) {
  Say "Already paired (keeping $State)"
} else {
  if (-not $Code) { throw "Give the pairing code from the app: -Code XXXX-XXXX" }
  $Code = ($Code -replace '[^A-Za-z0-9-]', '')
  Say "Pairing with $Api"
  $body = @{ code = $Code; host = @{ os = "windows"; install = "windows"; hostname = $env:COMPUTERNAME } } | ConvertTo-Json -Compress
  try {
    $reply = Invoke-RestMethod -Method Post -Uri "$Api/api/v1/connectors/pair" -ContentType "application/json" -Body $body
  } catch { throw "The code was not accepted (it works once and expires after a day): issue a new one in the app." }
  $d = if ($reply.data) { $reply.data } else { $reply }
  @{ token = $d.token; connectorId = $d.connectorId; releasePublicKey = $d.releasePublicKey; apiUrl = $Api } | ConvertTo-Json | Set-Content -Encoding UTF8 $State
  Say "Paired as connector $($d.connectorId)"
}
$token = (Get-Content $State -Raw | ConvertFrom-Json).token
$headers = @{ Authorization = "Bearer $token" }

if (-not $Zip) {
  Say "Downloading the newest release"
  $rel = Invoke-RestMethod -Uri "$Api/api/v1/edge/releases/latest" -Headers $headers
  $r = if ($rel.data) { $rel.data } else { $rel }
  if (-not $r.configured) { throw "The platform publishes no release yet: $($r.reason)" }
  $manifest = $r.manifest | ConvertFrom-Json
  $art = $manifest.artifacts | Where-Object { $_.platform -eq "windows" -and $_.name.EndsWith(".zip") } | Select-Object -First 1
  if (-not $art) { throw "The release has no Windows package" }
  $Zip = Join-Path $env:TEMP $art.name
  Invoke-WebRequest -Uri "$Api$($art.url)" -Headers $headers -OutFile $Zip
  $sha = (Get-FileHash -Algorithm SHA256 $Zip).Hash.ToLower()
  if ($sha -ne $art.sha256.ToLower()) { Remove-Item $Zip; throw "The download does not match the release manifest" }
  $Version = $manifest.version
} else {
  $Version = [IO.Path]::GetFileNameWithoutExtension($Zip) -replace '^site-connector-', '' -replace '-windows$', ''
}

$Target = Join-Path $InstallDir "versions\$Version"
Remove-Item -Recurse -Force $Target -ErrorAction SilentlyContinue
Expand-Archive -Path $Zip -DestinationPath $Target
Set-Content -NoNewline -Encoding ASCII (Join-Path $InstallDir "current-version.txt") $Version
# The service wrapper and its definition come with the package
Copy-Item (Join-Path $Target "site-connector\service\site-connector-service.exe") $Service -Force
$xml = Get-Content (Join-Path $Target "site-connector\service\site-connector-service.xml") -Raw
$xml = $xml.Replace('<!-- EDGE_API_URL is written here by install.ps1 -->', "<env name=`"EDGE_API_URL`" value=`"$Api`"/>")
Set-Content -Encoding UTF8 (Join-Path $InstallDir "site-connector-service.xml") $xml
Copy-Item (Join-Path $Target "site-connector\service\run.cmd") (Join-Path $InstallDir "run.cmd") -Force

if (-not (Get-Service SiteConnector -ErrorAction SilentlyContinue)) { & $Service install | Out-Null }
& $Service restart | Out-Null
Say "Installed. It shows as Online in the app within a minute (logs: $InstallDir\*.log)."
