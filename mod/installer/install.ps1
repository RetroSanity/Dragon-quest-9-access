# Dragon Quest IX Access - installer.
# Puts the Access mod into your own copy of the Dragon Quest IX PC version (DQIX Enhanced):
#   1. finds your copy of the PC version (the folder with BUILD.bat in it), or asks where it is
#   2. adds the mod's part of the game's code to it (speech, and running the mod's script)
#   3. builds the game again with that part in it (the PC version's own BUILD.bat)
#   4. copies the mod into its own folder: "DQ9 access" in your Documents
# Run it again at any time: it only does what is not done yet. Your save and settings are not touched.
param([string]$Port = "")

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot                              # this installer folder
$ModSrc = Split-Path $Here -Parent                 # the mod's files (mod folder of the download, or DQ9 access itself)
$Docs = [Environment]::GetFolderPath('MyDocuments')
$ModDir = Join-Path $Docs 'DQ9 access'
$PatchDir = Join-Path $Here 'game-patch'
$PatchFile = Join-Path $PatchDir 'access-game.patch'

function Say([string]$t) { Write-Host $t }
function Stop-Install([string]$t) {
    Say ''
    Say "THE INSTALL STOPPED: $t"
    Say 'Nothing else was changed: your game, save and settings are as they were.'
    exit 1
}
function Read-Manifest {
    $m = @{ version = '0'; patch = 0 }
    $f = Join-Path $ModSrc 'manifest.txt'
    if (Test-Path $f) {
        foreach ($l in Get-Content $f) {
            if ($l -match '^version\s+(.+)$') { $m.version = $Matches[1].Trim() }
            elseif ($l -match '^patch\s+(\d+)') { $m.patch = [int]$Matches[1] }
        }
    }
    return $m
}

Say 'Dragon Quest IX Access - installer'
Say '=================================='
$man = Read-Manifest
Say "Mod version $($man.version)."

# ---------------------------------------------------------------- 1. the PC version
function Test-Port([string]$d) {
    return $d -and (Test-Path -LiteralPath (Join-Path $d 'BUILD.bat')) -and
           (Test-Path -LiteralPath (Join-Path $d 'runtime\frontend_sdl.c')) -and
           (Test-Path -LiteralPath (Join-Path $d 'tools\build-game.sh'))
}
function Find-Port {
    $saved = Join-Path $ModDir 'pc-port-path.txt'
    if (Test-Path $saved) { $p = (Get-Content $saved -TotalCount 1).Trim(); if (Test-Port $p) { return $p } }
    $found = @()
    foreach ($d in @((Join-Path $Docs 'DQIX-Enhanced'), (Join-Path $Docs 'dqix-enhanced'))) { if (Test-Port $d) { $found += (Resolve-Path -LiteralPath $d).Path } }
    if ($found.Count -eq 0) {
        Say 'Looking for your Dragon Quest IX PC version (this can take a minute)...'
        $roots = @($Docs, [Environment]::GetFolderPath('Desktop'), (Join-Path $env:USERPROFILE 'Downloads'), $env:USERPROFILE)
        $roots += (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -and (Test-Path $_.Root) } | ForEach-Object { $_.Root })
        foreach ($r in $roots | Select-Object -Unique) {
            if (-not (Test-Path -LiteralPath $r)) { continue }
            Get-ChildItem -LiteralPath $r -Filter 'BUILD.bat' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                ForEach-Object { if (Test-Port $_.DirectoryName) { $found += $_.DirectoryName } }
        }
        $found = $found | Select-Object -Unique
    }
    if ($found.Count -gt 1) {
        # the one played last (its game was changed last)
        $found = $found | Sort-Object { $e = Join-Path $_ 'game\dqix.exe'; if (Test-Path $e) { (Get-Item $e).LastWriteTime } else { [datetime]::MinValue } } -Descending
    }
    if ($found.Count -ge 1) { return @($found)[0] }
    return $null
}
if (-not (Test-Port $Port)) { $Port = Find-Port }
while (-not (Test-Port $Port)) {
    Say ''
    Say 'Your copy of the Dragon Quest IX PC version (DQIX Enhanced) was not found.'
    Say 'It is the folder with BUILD.bat and the "game" folder in it.'
    Say 'If you do not have it yet, set it up first: github.com/sackchief/dqix-enhanced'
    $Port = (Read-Host 'Type or paste the full path of that folder, or press Enter on its own to stop').Trim().Trim('"')
    if (-not $Port) { Stop-Install 'no PC version.' }
}
$Port = (Resolve-Path -LiteralPath $Port).Path
Say "Your PC version: $Port"

# ---------------------------------------------------------------- the game must be closed
while (Get-Process -Name dqix -ErrorAction SilentlyContinue) {
    Say ''
    Say 'Dragon Quest IX is running. Save your game, close it, then press Enter here.'
    [void](Read-Host)
}

# ---------------------------------------------------------------- 2. the mod's part of the game's code
function Get-Msys2 {
    $tmp = Join-Path $env:TEMP ("dq9-access-msys2-" + [guid]::NewGuid().ToString('N') + '.txt')
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Port 'tools\msys2-setup.ps1') -Out $tmp | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) { return $null }
    $root = (Get-Content $tmp -TotalCount 1).Trim()
    Remove-Item $tmp -ErrorAction SilentlyContinue
    return $root
}
function Invoke-Bash([string]$root, [string]$cmd) {
    $env:MSYSTEM = 'UCRT64'; $env:CHERE_INVOKING = '1'; $env:DQ9_PORT = $Port
    & (Join-Path $root 'usr\bin\bash.exe') -lc ('cd "$(cygpath -u "$DQ9_PORT")" || exit 1; ' + $cmd) | Out-Host
    return $LASTEXITCODE
}

$marker = Join-Path $Port 'dq9-access-patch.txt'
$applied = Join-Path $Port 'dq9-access-applied.patch'
$sdl = Get-Content -LiteralPath (Join-Path $Port 'runtime\frontend_sdl.c') -Raw
$hasHooks = $sdl -match 'access_init\(\)'
$have = 0
if ($hasHooks -and (Test-Path $marker)) { $have = [int]((Get-Content $marker -TotalCount 1).Trim()) }
$needBuild = $false

if (-not $hasHooks -or $have -lt $man.patch) {
    Say ''
    Say 'Adding the mod to the game''s code. Checking the build tools first (the PC version''s own)...'
    $msys = Get-Msys2
    if (-not $msys) { Stop-Install 'the build tools (MSYS2) are not ready. Run BUILD.bat in your PC version once, then run this again.' }
    if ((Invoke-Bash $msys 'pacman -S --noconfirm --needed patch >/dev/null 2>&1; command -v patch >/dev/null') -ne 0) {
        Stop-Install 'the "patch" tool could not be installed in the build tools (it needs the internet).'
    }
    $env:DQ9_PATCH = $PatchFile; $env:DQ9_APPLIED = $applied
    if ($hasHooks) {
        # an older version of the mod's code: take it out first
        if (-not (Test-Path $applied) -or (Invoke-Bash $msys 'patch -p1 -R --dry-run -s -i "$(cygpath -u "$DQ9_APPLIED")" >/dev/null && patch -p1 -R -s -i "$(cygpath -u "$DQ9_APPLIED")"') -ne 0) {
            Stop-Install 'the older version of the mod in the game''s code could not be taken out. Update the PC version (Help, Check for updates in the game), then run this again.'
        }
    }
    if ((Invoke-Bash $msys 'patch -p1 --forward --dry-run -s -i "$(cygpath -u "$DQ9_PATCH")" >/dev/null') -ne 0) {
        Stop-Install 'this version of the PC version is too different for the mod. Please report it (with the version of your PC version) on the mod''s GitHub page.'
    }
    [void](Invoke-Bash $msys 'patch -p1 --forward -s -i "$(cygpath -u "$DQ9_PATCH")"')
    # the mod's own files in the game's code (speech, running the script, Lua)
    Copy-Item -Path (Join-Path $PatchDir 'files\*') -Destination $Port -Recurse -Force
    Copy-Item -LiteralPath $PatchFile -Destination $applied -Force
    Set-Content -LiteralPath $marker -Value $man.patch -Encoding ASCII
    $needBuild = $true
    Say 'Done.'
} else {
    # same version: still make sure the mod's own files are the newest
    Copy-Item -Path (Join-Path $PatchDir 'files\*') -Destination $Port -Recurse -Force
}
if (-not (Test-Path (Join-Path $Port 'game\dqix.exe'))) { $needBuild = $true }
if (-not $needBuild) {
    # built without the mod (for example by an update of the PC version since)?
    $exe = Join-Path $Port 'game\dqix.exe'
    $bytes = [IO.File]::ReadAllBytes($exe)
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    if (-not $text.Contains('dq9-access.lua')) { $needBuild = $true }
}

# ---------------------------------------------------------------- 3. build the game again
if ($needBuild) {
    $backup = Join-Path $Port 'game\backup-before-access'
    if ((Test-Path (Join-Path $Port 'game\dqix.exe')) -and -not (Test-Path $backup)) {
        New-Item -ItemType Directory -Path $backup | Out-Null
        foreach ($f in 'dqix.exe', 'dqixcore.dll') { $s = Join-Path $Port "game\$f"; if (Test-Path $s) { Copy-Item $s $backup } }
    }
    Say ''
    Say 'Building the game again with the mod in it. This takes a few minutes; the text below shows how it is going.'
    Say ''
    $env:DQIX_NOPAUSE = '1'
    & cmd /c "`"$(Join-Path $Port 'BUILD.bat')`"" | Out-Host
    if ($LASTEXITCODE -ne 0) { Stop-Install 'the game could not be built (the text above says why).' }
}

# ---------------------------------------------------------------- 4. the mod's folder
Say ''
Say "Putting the mod in its folder: $ModDir"
if (-not (Test-Path $ModDir)) { New-Item -ItemType Directory -Path $ModDir | Out-Null }
$srcFull = (Resolve-Path -LiteralPath $ModSrc).Path.TrimEnd('\')
$dstFull = (Resolve-Path -LiteralPath $ModDir).Path.TrimEnd('\')
if ($srcFull -ne $dstFull) {
    Copy-Item -Path (Join-Path $ModSrc '*') -Destination $ModDir -Recurse -Force
    Set-Content -LiteralPath (Join-Path $ModDir 'version.txt') -Value $man.version -Encoding ASCII
}
# your marks and the names you have learned, from an older version of the mod (in the game's folder)
$oldPlaces = Join-Path $Port 'game\access\dq9-access-places.txt'
$newPlaces = Join-Path $ModDir 'dq9-access-places.txt'
if ((Test-Path $oldPlaces) -and -not (Test-Path $newPlaces)) { Copy-Item $oldPlaces $newPlaces }
Set-Content -LiteralPath (Join-Path $ModDir 'pc-port-path.txt') -Value $Port -Encoding UTF8

Say ''
Say 'FINISHED. Start Dragon Quest IX as usual (your shortcut, or dqix.exe in the game folder of your PC version).'
Say 'After a moment the mod says it is running. Press K in the game to hear its keys.'
Say 'The mod keeps itself up to date: when the game starts it gets the newest version from the internet.'
exit 0
