<#
.SYNOPSIS
    Repackage Sparx Systems' "MCP Server for Enterprise Architect" as a native
    Windows ARM64 MSI.

.DESCRIPTION
    This script takes a copy of the OFFICIAL Sparx MSI that you supply, swaps the native
    x86/x64 .NET apphost (MCP3.exe) for a freshly-minted native arm64 apphost, and rebuilds
    the installer for Windows on ARM64 (Arm64 MSI Template, correct EA add-in registration
    for both 32-bit and 64-bit EA). No Sparx binaries are distributed with this project;
    they are harvested at build time from the MSI you provide.

    See README.md for background and prerequisites.

.PARAMETER SourceMsi
    Path to the official Sparx MSI (the x64 one is recommended; x86 also works - the managed
    payload is identical). Download it from https://www.sparxsystems.jp/en/MCP/

.PARAMETER OutDir
    Where to write the resulting MCP_EA_arm64.msi. Default: .\dist

.PARAMETER KeepWork
    Keep the intermediate .\build working folder (for inspection/debugging).

.PARAMETER SkipSignatureCheck
    Skip the Authenticode check of the source MSI. Sparx publishes no checksums, so the
    official MSI's signature is the only integrity link in the chain - only skip this if
    Sparx has changed its code-signing certificate and the check rejects a genuine MSI.

.PARAMETER AllowFallbackDefaults
    Build even when the product/COM details could not be detected from the source MSI
    (hardcoded v2.7.1-era defaults are used instead). Without this switch the build stops,
    because undetected values usually mean Sparx restructured the installer and the output
    would be mis-versioned or mis-registered.

.EXAMPLE
    .\build.ps1 -SourceMsi "$HOME\Downloads\MCP_EA_x64.msi"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceMsi,

    [string]$OutDir,

    [switch]$KeepWork,

    [switch]$SkipSignatureCheck,

    [switch]$AllowFallbackDefaults
)

$ErrorActionPreference = 'Stop'
$repo = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $OutDir) { $OutDir = Join-Path $repo 'dist' }
# Absolutize a relative -OutDir against the CALLER's cwd now: later steps switch the cwd
# (Push-Location $repo around WiX), which would otherwise scatter a relative path between
# the caller's directory and the repo root. Path.Combine keeps rooted paths unchanged
# (Join-Path 'C:\a' 'C:\b' would yield 'C:\a\C:\b' on Windows PowerShell 5.1).
$OutDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).ProviderPath, $OutDir))
$outMsi = Join-Path $OutDir 'MCP_EA_arm64.msi'
$work  = Join-Path $repo 'build'
$extract = Join-Path $work 'msi_extract'
$payload = Join-Path $work 'payload'

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

function Get-PEMachine([string]$file) {
    $fs = [System.IO.File]::OpenRead($file)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0x3C; $peoff = $br.ReadInt32(); $fs.Position = $peoff
        $null = $br.ReadUInt32(); $m = $br.ReadUInt16()
        switch ($m) { 0x14c { 'x86' } 0x8664 { 'x64' } 0xAA64 { 'ARM64' } 0x1c0 { 'ARM' } default { ('0x{0:X}' -f $m) } }
    } finally { $fs.Close() }
}

# Managed (.NET) PE detection: a non-zero COM-descriptor data directory (index 14) means a
# CLR header is present; native images have none. AnyCPU IL reports machine=x86, so the
# machine field alone cannot distinguish portable IL from a native x86 binary.
function Test-PEManaged([string]$file) {
    $fs = [System.IO.File]::OpenRead($file)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0x3C; $peoff = $br.ReadInt32()
        $fs.Position = $peoff + 24                            # optional header
        $magic = $br.ReadUInt16()                             # 0x10B = PE32, 0x20B = PE32+
        $ddOff = if ($magic -eq 0x20B) { 224 } else { 208 }   # COM descriptor entry offset
        $fs.Position = $peoff + 24 + $ddOff
        return ($br.ReadUInt32() -ne 0)
    } finally { $fs.Close() }
}

# Minimal read-only MSI table query via the Windows Installer COM API.
# Returns rows as PSCustomObjects with fields F1, F2, ... (in SELECT column order).
function Get-MsiRows([string]$msi, [string]$sql) {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db   = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($msi, 0))
    $view = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @($sql))
    $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
    $rows = New-Object System.Collections.ArrayList
    while ($true) {
        $rec = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
        if ($null -eq $rec) { break }
        $c = $rec.GetType().InvokeMember('FieldCount', 'GetProperty', $null, $rec, $null)
        $o = [ordered]@{}
        for ($i = 1; $i -le $c; $i++) { $o["F$i"] = [string]$rec.GetType().InvokeMember('StringData', 'GetProperty', $null, $rec, @($i)) }
        [void]$rows.Add([pscustomobject]$o)
    }
    return $rows
}

# ---------------------------------------------------------------- prerequisites
Write-Step 'Checking prerequisites'
if (-not (Test-Path $SourceMsi)) { throw "Source MSI not found: $SourceMsi" }
$SourceMsi = (Resolve-Path $SourceMsi).ProviderPath  # raw filesystem path (handles UNC, no provider prefix)
Write-Host "Source MSI : $SourceMsi"

# Sparx publishes no checksums, so the official MSI's Authenticode signature is the ONLY
# integrity link from Sparx to the (unsigned) MSI this script produces - verify it before
# msiexec parses the file. Match the signer on 'Sparx Systems' (not the full subject or a
# thumbprint) so a routine certificate renewal doesn't break the check.
if (-not $SkipSignatureCheck) {
    $sig = Get-AuthenticodeSignature -FilePath $SourceMsi
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Sparx Systems') {
        $subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '(unsigned)' }
        throw "Source MSI failed Authenticode verification (status: $($sig.Status); signer: $subject). Download the official MSI from https://www.sparxsystems.jp/en/MCP/ - or, if Sparx has changed its code-signing certificate, re-run with -SkipSignatureCheck."
    }
    Write-Host "Signature  : $($sig.Status) ($($sig.SignerCertificate.Subject))"
} else {
    Write-Warning 'Source MSI signature check SKIPPED (-SkipSignatureCheck): the input is unverified and the unsigned output MSI will inherit whatever it contains.'
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "The .NET SDK (9.0+) is required but 'dotnet' was not found on PATH. Install from https://dotnet.microsoft.com/download/dotnet/9.0"
}
# Resolve the SDK from the repo root (not the caller's cwd): global.json discovery walks up
# from the cwd, so a pin somewhere above the caller could otherwise select a different SDK
# than the apphost build (also run from the repo root) will actually use.
Push-Location $repo
try { $sdkVer = (dotnet --version) } finally { Pop-Location }
if ([int]($sdkVer -split '\.')[0] -lt 9) {
    throw ".NET SDK 9.0+ is required to mint the arm64 apphost (found $sdkVer). Install from https://dotnet.microsoft.com/download/dotnet/9.0"
}
Write-Host "dotnet SDK : $sdkVer"

# WiX is pinned via the local tool manifest (.config/dotnet-tools.json) so we never
# disturb any global WiX install and avoid the WiX v7 OSMF EULA gate.
Write-Step 'Restoring WiX (local dotnet tool, pinned in .config/dotnet-tools.json)'
Push-Location $repo
try {
    dotnet tool restore | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "dotnet tool restore failed (exit $LASTEXITCODE) - WiX 5.0.2 could not be restored. Check network/NuGet feed access (the first run must download the wix package)." }
} finally { Pop-Location }

# ---------------------------------------------------------------- clean work dir
Write-Step 'Preparing working directory'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $extract, $payload, $OutDir | Out-Null
# Drop any MSI from an earlier run NOW: if this build fails partway, a leftover
# dist\MCP_EA_arm64.msi would otherwise let 'msiexec /i dist\...' (run as a separate
# step per the README) silently install yesterday's build.
if (Test-Path $outMsi) { Remove-Item $outMsi -Force }

# ---------------------------------------------------------------- extract MSI
Write-Step 'Extracting payload from the Sparx MSI (administrative install, no system changes)'
$adminLog = Join-Path $work 'admin_extract.log'
$p = Start-Process msiexec -Wait -PassThru -ArgumentList @(
    '/a', "`"$SourceMsi`"", '/qn', "TARGETDIR=`"$extract`"", '/l*v', "`"$adminLog`""
)
if ($p.ExitCode -ne 0) { throw "msiexec administrative extract failed (exit $($p.ExitCode)). See $adminLog" }

$serverDir = Get-ChildItem $extract -Recurse -Directory -Filter 'MCP_Server' | Select-Object -First 1
$addinDir  = Get-ChildItem $extract -Recurse -Directory -Filter 'MCP_Addin'  | Select-Object -First 1
if (-not $serverDir -or -not $addinDir) { throw "Could not locate MCP_Server / MCP_Addin in the extracted MSI. Is this the correct Sparx MCP installer?" }
Write-Host "Server dir : $($serverDir.FullName)"
Write-Host "Add-in dir : $($addinDir.FullName)"

# ---------------------------------------------------------------- detect version-specific values
Write-Step 'Detecting product/COM details from the source MSI'
# Every value detected below has a hardcoded v2.7.1-era default. Track which defaults get
# used and refuse to build on a fallback (unless -AllowFallbackDefaults): a detection miss
# usually means Sparx restructured the installer, and silently stamping stale values would
# mis-version the MSI or break the COM add-in registration.
$fallbacks = @()
$ver = '2.7.1'
try {
    # Property table: F1=Property, F2=Value. Single-quoted on purpose: in a double-quoted
    # string PowerShell eats the backquotes (its escape character) before Windows Installer
    # ever sees them, so the MSI SQL identifier quoting would silently disappear.
    $row = @(Get-MsiRows $SourceMsi 'SELECT `Property`,`Value` FROM Property') | Where-Object { $_.F1 -eq 'ProductVersion' } | Select-Object -First 1
    if ($row) { $ver = $row.F2 } else { $fallbacks += 'ProductVersion' }
} catch { Write-Warning "Property table query failed: $($_.Exception.Message)"; $fallbacks += 'ProductVersion' }

# Registry table (SELECT *): F1=Registry, F2=Root, F3=Key, F4=Name, F5=Value, F6=Component
$reg = @()
try { $reg = @(Get-MsiRows $SourceMsi "SELECT * FROM Registry") } catch { Write-Warning "Registry table query failed: $($_.Exception.Message)" }
# ProgId: the DEFAULT value (empty Name) of the actual discovery key, not just any row
# whose key mentions EAAddins - row order in 'SELECT *' is undefined.
$progId = ($reg | Where-Object { $_.F3 -match '(?i)Sparx Systems\\EAAddins' -and [string]::IsNullOrEmpty($_.F4) } | Select-Object -First 1).F5
if (-not $progId) { $progId = 'MCP_EA.Main'; $fallbacks += 'ProgId' }
$asmRow = $reg | Where-Object { $_.F4 -eq 'Assembly' -and $_.F5 -match ',\s*Version=' } | Select-Object -First 1
$addinAssembly = if ($asmRow) { $asmRow.F5 } else { $fallbacks += 'AddinAssembly'; 'MCP_EA, Version=1.7.1.0, Culture=neutral, PublicKeyToken=null' }
# CLSID: only accept a GUID whose registration carries the detected ProgId as its value,
# so a second COM class in a future installer can never be picked up by accident.
$clsidRow = $reg | Where-Object { $_.F3 -match 'CLSID\\(\{[0-9A-Fa-f\-]+\})' -and $_.F5 -eq $progId } | Select-Object -First 1
$clsid = if ($clsidRow -and $clsidRow.F3 -match '(\{[0-9A-Fa-f\-]+\})') { $Matches[1] } else { $fallbacks += 'Clsid'; '{E21767D7-E7D5-3BBC-8E51-D6393C7BA3EF}' }
$asmVer = if ($addinAssembly -match 'Version=([\d\.]+)') { $Matches[1] } else { $fallbacks += 'AddinAsmVersion'; '1.7.1.0' }

if ($fallbacks) {
    Write-Warning ("Could not detect {0} from the source MSI - using hardcoded v2.7.1-era defaults. The output may be mis-versioned or mis-registered (new Sparx installer layout?)." -f ($fallbacks -join ', '))
    if (-not $AllowFallbackDefaults) { throw 'Refusing to build with fallback defaults (re-run with -AllowFallbackDefaults to override).' }
}

Write-Host "ProductVersion  : $ver"
Write-Host "Add-in ProgId   : $progId"
Write-Host "Add-in CLSID    : $clsid"
Write-Host "Add-in Assembly : $addinAssembly"
Write-Host "Add-in AsmVer   : $asmVer"

# ---------------------------------------------------------------- mint arm64 apphost
Write-Step 'Minting native arm64 .NET apphost (MCP3.exe)'
$apphostProj = Join-Path $repo 'apphost\MCP3.csproj'
# Build into a fresh per-run folder under the (already cleaned) work dir: a deterministic
# output path means a stale MCP3.exe from an earlier run can never mask a failed build.
$apphostOut = Join-Path $work 'apphost'
# Build from the repo root so SDK resolution matches the prerequisite check above,
# regardless of where the script was invoked from.
Push-Location $repo
try {
    dotnet build $apphostProj -c Release -r win-arm64 --nologo -v quiet -o $apphostOut | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "arm64 apphost build failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }
$armExe = Get-Item (Join-Path $apphostOut 'MCP3.exe') -ErrorAction SilentlyContinue
if (-not $armExe) { throw "arm64 apphost build did not produce MCP3.exe" }
if ((Get-PEMachine $armExe.FullName) -ne 'ARM64') { throw "Minted apphost is not ARM64 (got $(Get-PEMachine $armExe.FullName))" }
Write-Host "arm64 apphost : $($armExe.FullName)"

# ---------------------------------------------------------------- assemble payload
Write-Step 'Assembling arm64 payload (Sparx managed binaries + arm64 apphost)'
Copy-Item $serverDir.FullName (Join-Path $payload 'MCP_Server') -Recurse
Copy-Item $addinDir.FullName  (Join-Path $payload 'MCP_Addin')  -Recurse
Copy-Item $armExe.FullName    (Join-Path $payload 'MCP_Server\MCP3.exe') -Force

# Sweep EVERY PE in the payload, not just MCP3.exe: if a future Sparx release ships a
# native x64/x86 binary, the 'native ARM64' MSI would build green but fail at runtime
# with BadImageFormat/DllNotFound errors. Portable managed IL is fine; the only native
# binary allowed is the arm64 apphost minted above.
$peCount = 0
Get-ChildItem $payload -Recurse -Include *.dll, *.exe -File | ForEach-Object {
    $peCount++
    $m = Get-PEMachine $_.FullName
    $managed = Test-PEManaged $_.FullName
    $rel = $_.FullName.Substring($payload.Length + 1)
    if (-not $managed -and $m -ne 'ARM64') {
        throw "Native $m binary '$rel' in the payload - this Sparx release has a non-portable dependency the ARM64 package cannot run. The tooling needs updating for this layout."
    }
    if ($managed -and $m -notin @('x86', 'ARM64')) {
        Write-Warning "Managed but platform-specific ($m) assembly '$rel' - it may not load in an arm64 process."
    }
}
if ((Get-PEMachine (Join-Path $payload 'MCP_Server\MCP3.exe')) -ne 'ARM64') { throw 'Payload MCP3.exe is not ARM64' }
Write-Host "payload PE check : $peCount binaries OK (portable IL or arm64-native)"

# The harvested runtimeconfig.json is the authoritative statement of which .NET runtime
# the product needs. The minted apphost is forward-compatible (hostfxr resolves the
# framework from this file), so a Sparx move off .NET 9 would build and run fine while
# the README/badge/SDK guidance silently went stale - surface it instead.
$rtVer = $null
$rtCfgPath = Join-Path $payload 'MCP_Server\MCP3.runtimeconfig.json'
if (Test-Path $rtCfgPath) {
    try {
        $fw = (Get-Content $rtCfgPath -Raw | ConvertFrom-Json).runtimeOptions.framework
        if ($fw) { $rtVer = $fw.version }
    } catch {}
}
if ($rtVer) {
    Write-Host "Target runtime : .NET $rtVer (the install machine needs the matching arm64 runtime)"
    if ($rtVer -notmatch '^9\.') {
        Write-Warning "Sparx now targets .NET $rtVer (no longer 9.x). Update README.md (badge + Prerequisites), apphost/MCP3.csproj <TargetFramework>, and the SDK guidance in build.ps1."
    }
} else {
    Write-Warning 'Could not read MCP_Server\MCP3.runtimeconfig.json from the payload - unable to confirm which .NET runtime the target machine needs.'
}

# ---------------------------------------------------------------- build MSI
Write-Step 'Building the ARM64 MSI with WiX'
$wxs    = Join-Path $repo 'src\MCP_EA_arm64.wxs'
$wixArgs = @(
    'tool', 'run', 'wix', 'build', $wxs,
    '-arch', 'arm64',
    '-d', "ProductVersion=$ver",
    '-d', "ProgId=$progId",
    '-d', "Clsid=$clsid",
    '-d', "AddinAssembly=$addinAssembly",
    '-d', "AddinAsmVersion=$asmVer",
    '-d', "PayloadDir=$payload",
    '-o', $outMsi
)
Push-Location $repo
try { & dotnet @wixArgs } finally { Pop-Location }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outMsi)) { throw "WiX build failed (exit $LASTEXITCODE)" }

# ---------------------------------------------------------------- verify + finish
$template = '(unverified)'
try {
    $inst2 = New-Object -ComObject WindowsInstaller.Installer
    $si = $inst2.GetType().InvokeMember('SummaryInformation', 'GetProperty', $null, $inst2, @("$outMsi", 0))
    $template = [string]$si.GetType().InvokeMember('Property', 'GetProperty', $null, $si, @([int]7))
} catch { Write-Warning "Could not read summary info for verification: $($_.Exception.Message)" }

if (-not $KeepWork) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }

Write-Step 'Done'
Write-Host ("Output : {0}" -f $outMsi) -ForegroundColor Green
Write-Host ("Size   : {0:N0} bytes" -f (Get-Item $outMsi).Length)
Write-Host ("Template (platform;lang) : {0}" -f $template)
if ($rtVer) { Write-Host ("Runtime needed on target : .NET {0} (arm64)" -f $rtVer) }
if ($template -notmatch 'Arm64') { Write-Warning "Expected an Arm64 Template - double-check the build." }
Write-Host "`nInstall with:  msiexec /i `"$outMsi`""
