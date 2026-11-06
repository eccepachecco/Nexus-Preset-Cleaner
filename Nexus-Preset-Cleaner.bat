@echo off
setlocal
:: ===========================================================================
::  NEXUS PRESET CLEANER  -  single-file tool (.bat launcher + PowerShell)
::  VERSION 1.0  -  open source, 100% offline, never deletes (moves to _INVALID)
::  ---------------------------------------------------------------------------
::  WHAT IT DOES
::    You drag a freshly-downloaded preset pack (a folder that contains many
::    sub-folders of .fxp presets) onto this file. The tool installs those
::    folders into your Nexus\Presets, figures out which presets reference
::    sample libraries you DON'T have installed (the ones that trigger
::    "the expansion product is unknown"), and moves those broken presets
::    into an _INVALID folder so they stop cluttering your browser.
::
::  HOW THE LAUNCHER WORKS (this batch part)
::    Writing into C:\Program Files needs admin rights, so this batch extracts
::    the PowerShell script (everything below the marker line) into a temp
::    file and relaunches it AS ADMINISTRATOR, passing along the folder you
::    dropped. You will see ONE UAC prompt.
:: ===========================================================================

set "SELF=%~f0"
set "DROP=%~1"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $all=Get-Content -LiteralPath $env:SELF -Raw; $m='#=== POWER'+'SHELL ==='; $ps=$all.Substring($all.IndexOf($m)+$m.Length); $tmp=Join-Path $env:TEMP ('NexusCleaner_'+[guid]::NewGuid().ToString('N')+'.ps1'); [IO.File]::WriteAllText($tmp,$ps); if($env:DROP){[IO.File]::WriteAllText($tmp+'.arg',$env:DROP)}; Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$tmp)"

exit /b
#=== POWERSHELL ===
# ===========================================================================
#  NEXUS PRESET CLEANER  -  PowerShell worker (runs elevated)
# ===========================================================================
param([string]$DroppedPath)
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  Small UI helpers
# ---------------------------------------------------------------------------
function Line { Write-Host ("-" * 70) }
function Title($t) { Write-Host ""; Line; Write-Host "  $t"; Line }
function Fail($msg) {
    Write-Host ""
    Write-Host "ERROR: $msg" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press ENTER to close"
    exit 1
}

# ---------------------------------------------------------------------------
#  Constants and core helpers
# ---------------------------------------------------------------------------
# Factory ROM library prefixes. These ship identically with every Nexus
# install, so we treat them as "always installed" and never test them.
$ROM = @("EA-C5-6E-E0", "A3-71-D7-82")

# Reads one .fxp and returns:
#   .Analyzable      $true if it uses the 8860-style format (has the marker)
#   .ActivePrefixes  the distinct 4-byte library prefixes of its ACTIVE layers
#
# Format reminder:
#   Each layer's sample reference is the 8 bytes right after the marker
#   3C 2F 9A 00 00 00.  Of those 8 bytes the first 4 are the LIBRARY id and
#   the last 4 are the sample. A reference ending in 00 00 00 is an EMPTY /
#   placeholder layer (off) and is ignored - only "active" layers matter.
function Get-PresetInfo([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $active = @{}
    $hasMarker = $false
    for ($i = 0; $i -le $bytes.Length - 14; $i++) {
        if ($bytes[$i]   -eq 0x3C -and $bytes[$i+1] -eq 0x2F -and $bytes[$i+2] -eq 0x9A -and
            $bytes[$i+3] -eq 0x00 -and $bytes[$i+4] -eq 0x00 -and $bytes[$i+5] -eq 0x00) {
            $hasMarker = $true
            $ref = [BitConverter]::ToString($bytes, $i + 6, 8)   # e.g. "EA-C5-6E-E0-6C-75-F2-14"
            # ignore placeholder/off layers (sample part = ...-00-00-00)
            if ($ref -notmatch '00-00-00$') {
                $prefix = ($ref -split '-')[0..3] -join '-'      # first 4 bytes = library
                $active[$prefix] = $true
            }
            $i += 13   # jump past this record
        }
    }
    return [pscustomobject]@{
        Analyzable     = $hasMarker
        ActivePrefixes = @($active.Keys)
    }
}

# Returns a folder name that does not collide inside $parent, adding " (2)",
# " (3)"... if needed. Never overwrites anything.
function Get-FreeName([string]$parent, [string]$desired) {
    if (-not (Test-Path -LiteralPath (Join-Path $parent $desired))) { return $desired }
    $n = 2
    while (Test-Path -LiteralPath (Join-Path $parent "$desired ($n)")) { $n++ }
    return "$desired ($n)"
}

# Same as Get-FreeName but for files: inserts the counter before the extension
# so "preset.fxp" becomes "preset (2).fxp" instead of "preset.fxp (2)".
function Get-FreeFileName([string]$parent, [string]$desired) {
    if (-not (Test-Path -LiteralPath (Join-Path $parent $desired))) { return $desired }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($desired)
    $ext  = [System.IO.Path]::GetExtension($desired)
    $n = 2
    while (Test-Path -LiteralPath (Join-Path $parent "$base ($n)$ext")) { $n++ }
    return "$base ($n)$ext"
}

# ===========================================================================
#  PHASE 1 - INPUT: resolve the dropped pack folder and find its "leaf"
#  folders (the ones that DIRECTLY contain .fxp files), at any depth.
# ===========================================================================
Title "NEXUS PRESET CLEANER"

if (-not $DroppedPath) {
    $argFile = $PSCommandPath + '.arg'
    if (Test-Path -LiteralPath $argFile) {
        $DroppedPath = (Get-Content -LiteralPath $argFile -Raw -Encoding UTF8).Trim()
        Remove-Item -LiteralPath $argFile -Force
    }
}
if (-not $DroppedPath) {
    Write-Host "Tip: next time you can just DRAG the pack folder onto this file."
    $DroppedPath = Read-Host "Paste the full path to the downloaded pack folder"
}
if (-not (Test-Path -LiteralPath $DroppedPath -PathType Container)) {
    Fail "That is not a folder: $DroppedPath"
}

# Collect every folder that directly contains at least one .fxp.
# (Including the dropped folder itself, in case the presets sit at the top.)
$leaves = New-Object System.Collections.Generic.List[string]
if (@(Get-ChildItem -LiteralPath $DroppedPath -Filter *.fxp -File -ErrorAction SilentlyContinue).Count -gt 0) {
    $leaves.Add($DroppedPath)
}
foreach ($d in Get-ChildItem -LiteralPath $DroppedPath -Recurse -Directory -ErrorAction SilentlyContinue) {
    if (@(Get-ChildItem -LiteralPath $d.FullName -Filter *.fxp -File -ErrorAction SilentlyContinue).Count -gt 0) {
        $leaves.Add($d.FullName)
    }
}
if ($leaves.Count -eq 0) { Fail "No .fxp presets found inside that folder." }
Write-Host ""
Write-Host "Found $($leaves.Count) preset folder(s) to install."

# ===========================================================================
#  PHASE 2 - QUESTIONS: Nexus path and optional folder prefix.
# ===========================================================================

# --- Nexus path (validated: must exist AND contain a Presets sub-folder) ---
$presetsRoot = $null
while (-not $presetsRoot) {
    Write-Host ""
    Write-Host "I need to know where Nexus is installed on your computer."
    Write-Host "It's usually:  C:\Program Files\Nexus"
    $answer = Read-Host "If that's correct, just press ENTER. If not, type the full path to your Nexus folder (including the name of the Nexus folder)"
    if (-not $answer) { $answer = "C:\Program Files\Nexus" }
    $answer = $answer.Trim('"').TrimEnd('\')
    $candidate = Join-Path $answer "Presets"
    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $presetsRoot = $candidate
    } else {
        Write-Host "I can't find a 'Presets' folder there - that doesn't look like your Nexus folder. Let's try again." -ForegroundColor Yellow
    }
}

# --- Optional prefix so the new folders stay grouped (default: none) ---
$prefix = ""
$invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
$prefixDone = $false
while (-not $prefixDone) {
    Write-Host ""
    Write-Host "Do you want to add a short prefix to these folders so they stay grouped"
    Write-Host "together and don't get mixed in with your factory and other Nexus folders?"
    Write-Host "A good choice is ""zz"", which keeps them neatly at the bottom of the list in Nexus."
    $p = Read-Host "Type the prefix you'd like to use, or just press ENTER to leave the folder names unchanged"
    if (-not $p) { $prefixDone = $true; break }
    $bad = $false
    foreach ($c in $invalidChars) { if ($p.Contains($c)) { $bad = $true; break } }
    if ($bad) {
        Write-Host "That prefix contains characters that are not allowed in folder names. Please try again." -ForegroundColor Yellow
    } else {
        $prefix = $p
        $prefixDone = $true
    }
}

# ===========================================================================
#  PHASE 3 - INSTALL: copy each leaf folder into Nexus\Presets (flattened to
#  the top level). We record exactly which folders we create - that recorded
#  list IS our working scope, so we never touch anything else.
# ===========================================================================
Title "Installing the pack into Nexus..."
$scope = @()   # objects: { Name = folder name in Presets ; Path = full path }
foreach ($leafPath in $leaves) {
    $leafName = Split-Path $leafPath -Leaf
    if ($prefix -ne "") { $desired = "$prefix $leafName" } else { $desired = $leafName }
    $finalName = Get-FreeName $presetsRoot $desired      # avoid collisions, never overwrite
    $dest = Join-Path $presetsRoot $finalName
    New-Item -ItemType Directory -Path $dest | Out-Null
    # Copy the leaf's own files (presets + any extras). Nexus ignores non-.fxp,
    # and we copy only direct files so nested sub-leaves are not duplicated.
    Get-ChildItem -LiteralPath $leafPath -File | Copy-Item -Destination $dest -Force
    $scope += [pscustomobject]@{ Name = $finalName; Path = $dest }
}
Write-Host "Installed $($scope.Count) folder(s) into:  $presetsRoot"

# ===========================================================================
#  PHASE 4 - LOAD MEMORY: the persistent whitelist of libraries already known
#  to be installed (kept in Documents\Nexus Cleaner\whitelist.txt).
# ===========================================================================
$docs = [Environment]::GetFolderPath('MyDocuments')
$cfgDir = Join-Path $docs "Nexus Cleaner"
if (-not (Test-Path -LiteralPath $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir | Out-Null }
$whitelistFile = Join-Path $cfgDir "whitelist.txt"
$whitelist = @{}
if (Test-Path -LiteralPath $whitelistFile) {
    foreach ($l in Get-Content -LiteralPath $whitelistFile) {
        $t = $l.Trim()
        if ($t -ne "") { $whitelist[$t] = $true }
    }
}
# "known installed" = factory ROM + everything confirmed in past runs.
$known = @{}
foreach ($r in $ROM) { $known[$r] = $true }
foreach ($k in $whitelist.Keys) { $known[$k] = $true }

# ===========================================================================
#  While the slow part runs, explain what's going on.
# ===========================================================================
$explain = @'

  While I work, let me explain why the "expansion product is unknown"
  error happens - and how I fix it.

  Every preset points to a sample library inside your Nexus\Samples folder.
  If a preset points to a library you don't have installed, it can't load
  its sound, so Nexus mutes it and shows that message.

  - Why do you have to test a few presets by hand in Nexus?
    Because I can't open FL Studio and play them myself - only you can hear
    whether a preset actually sounds. You tell me which ones fail, I do the rest.

  - Why is testing about 20 enough for a pack of 2000 presets?
    Because many presets share the same library. The moment one of them
    fails, I know every preset that uses that same library will fail too -
    so I move all of them to the _INVALID folder at once.

'@
Write-Host $explain

# ===========================================================================
#  PHASE 5 - SCAN: read every installed preset and collect its active library
#  prefixes. Presets with no marker are "not analyzable" -> left untouched.
# ===========================================================================
Title "Scanning presets..."
$presets = @()   # { File ; Folder ; Analyzable ; Active(@prefixes) }
foreach ($s in $scope) {
    foreach ($f in Get-ChildItem -LiteralPath $s.Path -Filter *.fxp -File) {
        $info = Get-PresetInfo $f.FullName
        $presets += [pscustomobject]@{
            File       = $f.FullName
            Folder     = $s.Name
            Name       = $f.BaseName
            Analyzable = $info.Analyzable
            Active     = $info.ActivePrefixes
        }
    }
}
$analyzable = @($presets | Where-Object { $_.Analyzable })
Write-Host "Read $($presets.Count) presets ($($analyzable.Count) in a format I can analyze)."

# All distinct active prefixes, and which of them we don't yet know.
$allPrefixes = @{}
foreach ($p in $analyzable) { foreach ($pf in $p.Active) { $allPrefixes[$pf] = $true } }
$unknowns = @($allPrefixes.Keys | Where-Object { -not $known.ContainsKey($_) })

# "Opaque" folders: those holding presets we could NOT analyze (unknown format,
# e.g. the encrypted 1416-byte "NEXU 01 03" presets whose library reference is
# not stored in plaintext). We can't read their library refs, so Plan B tests
# them at the folder level instead of silently keeping them as "working".
$opaque = @{}   # folder name -> list of its non-analyzable preset objects
foreach ($p in $presets) {
    if (-not $p.Analyzable) {
        if (-not $opaque.ContainsKey($p.Folder)) { $opaque[$p.Folder] = New-Object System.Collections.Generic.List[object] }
        $opaque[$p.Folder].Add($p)
    }
}

# ===========================================================================
#  PHASE 6 - CALIBRATE: build ONE test list, then ask the user to play it.
#    (a) ANALYZABLE format: one isolated preset per unknown library prefix
#        (a preset whose ONLY unknown active layer is that library).
#    (b) UNKNOWN format (Plan B): a few representatives per "opaque" folder -
#        presets we can't read byte-wise. A downloaded pack folder is normally
#        a single expansion, so if its samples aren't installed EVERY preset in
#        it is muted; we test a few and, if they ALL fail, treat the whole
#        folder as that one uninstalled expansion.
# ===========================================================================
$notInstalled  = @{}   # library prefixes confirmed missing (analyzable format)
$brokenFolders = @{}   # opaque folder names confirmed missing (Plan B)
$fTotal = @{}          # opaque folder -> how many of its presets were tested
$fFail  = @{}          # opaque folder -> how many of those were muted
$tests  = @()          # unified test list: { Kind ; Key ; Folder ; Name ; File }

# (a) one clean isolated test preset per unknown library prefix
foreach ($u in $unknowns) {
    $chosen = $null
    foreach ($p in $analyzable) {
        $unknownActive = @($p.Active | Where-Object { -not $known.ContainsKey($_) })
        if ($unknownActive.Count -eq 1 -and $unknownActive[0] -eq $u) { $chosen = $p; break }
    }
    if ($chosen) {
        $tests += [pscustomobject]@{ Kind='prefix'; Key=$u; Folder=$chosen.Folder; Name=$chosen.Name; File=$chosen.File }
    }
}

# (b) a fixed number of representatives per opaque folder, spread evenly across
# it (always includes the first and last). More samples = better odds of
# noticing a folder that is NOT a single expansion (mixed results -> we don't
# move it). We test min($repCount, folder size) - can't test more than exist.
$repCount = 6
foreach ($folder in $opaque.Keys) {
    $items = $opaque[$folder]
    $c = $items.Count
    if ($c -le $repCount) {
        $picks = @($items)
    } else {
        $idxs = @()
        for ($k = 0; $k -lt $repCount; $k++) { $idxs += [int][math]::Round($k * ($c - 1) / ($repCount - 1)) }
        $picks = @(@($idxs | Select-Object -Unique) | ForEach-Object { $items[$_] })
    }
    foreach ($it in $picks) {
        $tests += [pscustomobject]@{ Kind='folder'; Key=$folder; Folder=$it.Folder; Name=$it.Name; File=$it.File }
    }
}

if ($tests.Count -gt 0) {
        # Sort the test list alphabetically by Folder/Preset and number it.
        $tests = @($tests | Sort-Object Folder, Name)

        # Copy the test presets into one easy-to-find temporary folder.
        $calibDir = Join-Path $presetsRoot "_CALIBRATION (temp)"
        if (Test-Path -LiteralPath $calibDir) { Remove-Item -LiteralPath $calibDir -Recurse -Force }
        New-Item -ItemType Directory -Path $calibDir | Out-Null
        for ($i = 0; $i -lt $tests.Count; $i++) {
            Copy-Item -LiteralPath $tests[$i].File -Destination (Join-Path $calibDir ("{0:D3} - {1}.fxp" -f ($i+1), $tests[$i].Name)) -Force
        }

        Title "I need you to test $($tests.Count) preset(s)"
        Write-Host "1) Restart FL Studio so Nexus sees the new folders."
        Write-Host "2) In Nexus, open the folder  '_CALIBRATION (temp)'  and play each preset below."
        Write-Host "3) Note the NUMBER of every preset that does NOT sound (shows the error / is muted)."
        Write-Host ""
        for ($i = 0; $i -lt $tests.Count; $i++) {
            Write-Host ("   {0,3}.  {1} / {2}" -f ($i+1), $tests[$i].Folder, $tests[$i].Name)
        }
        Write-Host ""

        # Read + validate the failing numbers (space separated).
        $failNums = $null
        while ($null -eq $failNums) {
            $raw = Read-Host "Enter the numbers that do NOT play, separated by spaces (or press ENTER if they all play)"
            if (-not $raw -or $raw.Trim() -eq "") { $failNums = @(); break }
            $tmp = @(); $ok = $true
            foreach ($tok in ($raw -split '\s+' | Where-Object { $_ -ne "" })) {
                if ($tok -match '^\d+$' -and [int]$tok -ge 1 -and [int]$tok -le $tests.Count) {
                    $tmp += [int]$tok
                } else {
                    Write-Host "  '$tok' is not a valid number from the list. Please re-enter the whole line." -ForegroundColor Yellow
                    $ok = $false; break
                }
            }
            if ($ok) { $failNums = $tmp }
        }

        # Deduce results. Prefix tests feed the library whitelist; folder tests
        # (Plan B) are tallied per folder - a folder counts as missing only if
        # EVERY one of its tested presets was muted.
        for ($i = 0; $i -lt $tests.Count; $i++) {
            $t = $tests[$i]
            $failed = ($failNums -contains ($i + 1))
            if ($t.Kind -eq 'prefix') {
                if ($failed) {
                    $notInstalled[$t.Key] = $true
                } else {
                    $known[$t.Key] = $true
                    $whitelist[$t.Key] = $true       # remember it for next time
                }
            } else {
                if (-not $fTotal.ContainsKey($t.Key)) { $fTotal[$t.Key] = 0; $fFail[$t.Key] = 0 }
                $fTotal[$t.Key]++
                if ($failed) { $fFail[$t.Key]++ }
            }
        }
        foreach ($folder in @($fTotal.Keys)) {
            if ($fFail[$folder] -eq $fTotal[$folder]) { $brokenFolders[$folder] = $true }
        }
        # Save the updated whitelist (library prefixes only; opaque folders can't
        # be remembered because we never learn their real library id).
        Set-Content -LiteralPath $whitelistFile -Value (@($whitelist.Keys) | Sort-Object) -Encoding UTF8

        # Remove the temporary calibration folder.
        Remove-Item -LiteralPath $calibDir -Recurse -Force
}
else {
    Write-Host ""
    Write-Host "Nothing new to test - I already know every library this pack uses,"
    Write-Host "and every preset is in a format I can read."
}

# ===========================================================================
#  PHASE 7 - CLASSIFY + QUARANTINE (move, never delete).
#    INVALID = uses at least one library confirmed NOT installed.
#    kept    = everything else (incl. non-analyzable presets).
#
#  The broken presets are moved FLAT into _INVALID (NOT into a sub-folder per
#  pack): Nexus only browses one level deep, so presets nested two levels down
#  wouldn't show up and you couldn't play them to double-check. To keep track
#  of where each one came from we write a plain-text index (_source-folders.txt)
#  inside _INVALID. Nexus ignores .txt files, so it stays out of the way.
# ===========================================================================
Title "Sorting presets..."
$invalidRoot  = Join-Path $presetsRoot "_INVALID"
$countInvalid = 0
$origin       = @{}   # original pack folder -> list of file names (for the index)

foreach ($p in $presets) {
    # Decide if this preset is confirmed broken:
    #   analyzable  -> it uses a library we confirmed is NOT installed
    #   unknown fmt -> its whole folder was confirmed missing by Plan B
    $broken = $false
    if ($p.Analyzable) {
        if (@($p.Active | Where-Object { $notInstalled.ContainsKey($_) }).Count -gt 0) { $broken = $true }
    } elseif ($brokenFolders.ContainsKey($p.Folder)) {
        $broken = $true
    }
    if (-not $broken) { continue }

    if (-not (Test-Path -LiteralPath $invalidRoot)) { New-Item -ItemType Directory -Path $invalidRoot -Force | Out-Null }
    # flat move into _INVALID; only renamed if a same-named file is already there
    $finalLeaf = Get-FreeFileName $invalidRoot (Split-Path $p.File -Leaf)
    Move-Item -LiteralPath $p.File -Destination (Join-Path $invalidRoot $finalLeaf) -Force
    if (-not $origin.ContainsKey($p.Folder)) { $origin[$p.Folder] = New-Object System.Collections.Generic.List[string] }
    $origin[$p.Folder].Add($finalLeaf)
    $countInvalid++
}

# Write the index that records the original pack folder of each moved preset.
if ($countInvalid -gt 0) {
    $idx = New-Object System.Collections.Generic.List[string]
    $idx.Add("These presets were moved here because they need a sample library you don't have installed.")
    $idx.Add("They are kept FLAT (all in one folder) so you can load them in Nexus to double-check.")
    $idx.Add("Below is the pack folder each one originally came from, in case you want to put any back.")
    $idx.Add("")
    foreach ($folder in ($origin.Keys | Sort-Object)) {
        $idx.Add("[$folder]")
        foreach ($file in ($origin[$folder] | Sort-Object)) { $idx.Add("    $file") }
        $idx.Add("")
    }
    Set-Content -LiteralPath (Join-Path $invalidRoot "_source-folders.txt") -Value $idx -Encoding UTF8
}

# ===========================================================================
#  PHASE 8 - FINAL REPORT
# ===========================================================================
# Split kept presets into "verified" (confirmed to play) and "could not verify"
# (unknown format we couldn't read and couldn't settle with a folder test).
$total = $presets.Count
$verified = 0
$unverified = 0
$mixedFolders = @{}
foreach ($p in $presets) {
    if ($p.Analyzable) {
        if (@($p.Active | Where-Object { $notInstalled.ContainsKey($_) }).Count -gt 0) { continue }   # moved
        $allKnown = $true
        foreach ($pf in $p.Active) { if (-not $known.ContainsKey($pf)) { $allKnown = $false; break } }
        if ($allKnown) { $verified++ } else { $unverified++ }
    } else {
        if ($brokenFolders.ContainsKey($p.Folder)) { continue }                                        # moved
        if ($fTotal.ContainsKey($p.Folder) -and $fFail[$p.Folder] -eq 0) {
            $verified++                                   # folder tested, every rep played
        } else {
            $unverified++                                 # mixed results, or not tested
            if ($fTotal.ContainsKey($p.Folder) -and $fFail[$p.Folder] -gt 0) { $mixedFolders[$p.Folder] = $true }
        }
    }
}

Title "DONE"
Write-Host ("   Presets in this pack:        {0}" -f $total)
Write-Host ("   Moved to _INVALID:           {0}   (confirmed muted - library not installed)" -f $countInvalid)
Write-Host ("   Kept - verified they play:   {0}" -f $verified)
if ($unverified -gt 0) {
    Write-Host ("   Kept - could NOT verify:     {0}   (unknown preset format - see note below)" -f $unverified)
}
Write-Host ""
if ($unverified -gt 0) {
    Write-Host "NOTE: I couldn't read the internal format of $unverified preset(s), so I can't"
    Write-Host "promise they work. Play a few of them in Nexus; if they are muted they need an"
    Write-Host "expansion you don't have installed, and you can move them out yourself."
    if ($mixedFolders.Count -gt 0) {
        Write-Host "These folders gave MIXED results (some played, some didn't), so I left them"
        Write-Host "untouched for you to check by hand:"
        foreach ($f in ($mixedFolders.Keys | Sort-Object)) { Write-Host "    $f" }
    }
    Write-Host ""
}
if ($countInvalid -gt 0) {
    Write-Host "The _INVALID folder is inside your Nexus\Presets folder, with all broken"
    Write-Host "presets together so you can load them in Nexus and double-check."
    Write-Host "(_source-folders.txt inside it lists where each one originally came from.)"
    Write-Host "Once you're happy, just delete the _INVALID folder."
}
Write-Host ""
Write-Host "I've saved a file called  whitelist.txt  in your  Documents\Nexus Cleaner  folder."
Write-Host "It remembers the expansion libraries you DO have installed and that work, so the next"
Write-Host "time you clean a pack that uses those same libraries, I'll already know they'll work"
Write-Host "and won't make you test those presets again. (Delete that file to start fresh.)"
Write-Host ""
Read-Host "Press ENTER to close"
