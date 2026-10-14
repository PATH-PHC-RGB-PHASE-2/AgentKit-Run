<#
KaderKita AgentKit — peluncur PowerShell (Windows PowerShell 5.1 dan PowerShell 7 di Windows/macOS/Linux).

Pemakaian online (skrip dari repo publik AgentKit-Run):
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/PATH-PHC-RGB-PHASE-2/AgentKit-Run/refs/heads/main/agent_kit.ps1))) <PROJECT> <COMMAND> [opsi]

  PROJECT : Backend | CMS | Mobile
  COMMAND : build | apply | verify | status | help
  Opsi    : sama dengan agent_kit.sh (--root, --target, --agentkit, --local, --base-url, --dry-run, --overwrite, --note, --force)

Peluncur ini menjalankan agent_kit.sh memakai bash dari Git for Windows (Git Bash), WSL, atau bash sistem,
sehingga perilaku build/apply/verify/status identik di semua sistem operasi.
Data patch ada di repo privat AgentKit. Token dicari otomatis: $env:AGENTKIT_TOKEN / GITHUB_TOKEN / GH_TOKEN,
`gh auth token`, lalu kredensial github.com di Git Credential Manager.
#>
param(
  [Parameter(Position = 0)][string]$Project,
  [Parameter(Position = 1)][string]$Command,
  [Parameter(Position = 2, ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'
# Skrip (publik) dan data (privat) ada di dua repo berbeda.
$DefaultRunBase = 'https://raw.githubusercontent.com/PATH-PHC-RGB-PHASE-2/AgentKit-Run/refs/heads/main'
$DefaultBase = 'https://raw.githubusercontent.com/PATH-PHC-RGB-PHASE-2/AgentKit/refs/heads/master'
$RunBase = if ($env:AGENTKIT_RUN_URL) { $env:AGENTKIT_RUN_URL.TrimEnd('/') } else { $DefaultRunBase }
$Base = if ($env:AGENTKIT_BASE_URL) { $env:AGENTKIT_BASE_URL.TrimEnd('/') } else { $DefaultBase }
if ($null -eq $Rest) { $Rest = @() }

# --base-url di argumen = sumber data (dipakai untuk memutuskan pencarian token)
for ($i = 0; $i -lt $Rest.Count - 1; $i++) {
  if ($Rest[$i] -eq '--base-url') { $Base = $Rest[$i + 1].TrimEnd('/') }
}

function Find-Bash {
  if ($env:AGENTKIT_BASH -and (Test-Path $env:AGENTKIT_BASH)) { return $env:AGENTKIT_BASH }
  $onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
  if ($onWindows) {
    $candidates = @()
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
      # ...\Git\cmd\git.exe atau ...\Git\mingw64\bin\git.exe -> ...\Git\bin\bash.exe
      $gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
      $candidates += (Join-Path $gitRoot 'bin\bash.exe')
      $candidates += (Join-Path (Split-Path $gitRoot -Parent) 'bin\bash.exe')
    }
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe') }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe') }
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    $wsl = Get-Command bash -ErrorAction SilentlyContinue   # WSL (C:\Windows\System32\bash.exe)
    if ($wsl) { return $wsl.Source }
    throw 'bash tidak ditemukan. Pasang Git for Windows (menyertakan Git Bash) atau WSL2, atau set $env:AGENTKIT_BASH.'
  }
  $b = Get-Command bash -ErrorAction SilentlyContinue
  if ($b) { return $b.Source }
  throw 'bash tidak ditemukan di PATH.'
}

function Get-AgentKitToken {
  # AGENTKIT_TOKEN / GITHUB_TOKEN / GH_TOKEN, lalu (hanya untuk sumber GitHub) `gh auth token`,
  # lalu kredensial github.com yang tersimpan di git (Git Credential Manager). Tanpa prompt.
  foreach ($v in @($env:AGENTKIT_TOKEN, $env:GITHUB_TOKEN, $env:GH_TOKEN)) { if ($v) { return $v } }
  if ($Base -notmatch '^https://(raw\.githubusercontent\.com|api\.github\.com)/') { return $null }
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if ($gh) {
    $t = (& $gh.Source auth token --hostname github.com 2>$null)
    if ($LASTEXITCODE -eq 0 -and $t) { return ([string]$t).Trim() }
  }
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) {
    $old = @{ GIT_TERMINAL_PROMPT = $env:GIT_TERMINAL_PROMPT; GCM_INTERACTIVE = $env:GCM_INTERACTIVE; GIT_ASKPASS = $env:GIT_ASKPASS }
    $env:GIT_TERMINAL_PROMPT = '0'; $env:GCM_INTERACTIVE = 'never'; $env:GIT_ASKPASS = $null
    try {
      $out = "protocol=https`nhost=github.com`n`n" | & $git.Source -c credential.interactive=false credential fill 2>$null
      foreach ($line in @($out)) { if ($line -like 'password=*') { return $line.Substring(9) } }
    } catch { } finally { foreach ($k in $old.Keys) { Set-Item -Path "env:$k" -Value $old[$k] -ErrorAction SilentlyContinue } }
  }
  return $null
}

function Get-AgentKitScript {
  # Dijalankan sebagai berkas (mis. AgentKit-Run/agent_kit.ps1): pakai agent_kit.sh di sebelahnya.
  # Mode lokal: cari agent_kit.sh di folder AgentKit-Run. Selain itu: unduh dari repo publik.
  $local = @()
  if ($PSCommandPath) { $local += (Join-Path (Split-Path $PSCommandPath -Parent) 'agent_kit.sh') }
  if ($env:AGENTKIT_SOURCE -eq 'local' -or $Rest -contains '--local') {
    if ($env:AGENTKIT_ROOT) { $local += (Join-Path $env:AGENTKIT_ROOT 'AgentKit-Run/agent_kit.sh') }
    $local += (Join-Path (Get-Location) 'AgentKit-Run/agent_kit.sh')
    $local += (Join-Path (Get-Location) '../AgentKit-Run/agent_kit.sh')
    $local += (Join-Path (Get-Location) 'agent_kit.sh')
  }
  foreach ($p in $local) { if (Test-Path $p) { return (Resolve-Path $p).Path } }
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("agent_kit_" + [guid]::NewGuid().ToString('N') + '.sh')
  # Repo AgentKit-Run publik: unduh tanpa token (token hanya untuk data di repo privat).
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri "$RunBase/agent_kit.sh"
  } catch {
    throw "Tidak bisa mengunduh $RunBase/agent_kit.sh ($($_.Exception.Message))."
  }
  $content = if ($resp.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($resp.Content) } else { [string]$resp.Content }
  # Simpan dengan akhir baris LF (bash menolak CRLF).
  [System.IO.File]::WriteAllText($tmp, ($content -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
  return $tmp
}

$bash = Find-Bash
$script:AkToken = Get-AgentKitToken
$shPath = Get-AgentKitScript
$downloaded = $shPath.StartsWith([System.IO.Path]::GetTempPath())
$scriptArg = $shPath -replace '\\', '/'
if ($bash -match 'System32\\bash\.exe$') {
  # WSL: ubah path Windows menjadi /mnt/<drive>/...
  $scriptArg = (& $bash -c "wslpath -a '$scriptArg'").Trim()
}

$argsList = @($scriptArg)
if ($Project) { $argsList += $Project }
if ($Command) { $argsList += $Command }
$argsList += $Rest

# Teruskan token ke agent_kit.sh (juga ke WSL lewat WSLENV) tanpa mencetaknya.
$prevToken = $env:AGENTKIT_TOKEN; $prevWslEnv = $env:WSLENV
if ($script:AkToken) {
  $env:AGENTKIT_TOKEN = $script:AkToken
  $env:WSLENV = (@($env:WSLENV, 'AGENTKIT_TOKEN/u', 'AGENTKIT_BASE_URL/u') | Where-Object { $_ }) -join ':'
}
try {
  & $bash @argsList
  $code = $LASTEXITCODE
} finally {
  $env:AGENTKIT_TOKEN = $prevToken; $env:WSLENV = $prevWslEnv
}
if ($downloaded) { Remove-Item $shPath -ErrorAction SilentlyContinue }
$global:LASTEXITCODE = $code
# Dijalankan sebagai berkas .ps1: teruskan kode keluar. Dijalankan lewat iwr | scriptblock: jangan menutup sesi.
if ($PSCommandPath) { exit $code }
