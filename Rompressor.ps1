# ---------------------------
# Folder Picker GUI for $source
# ---------------------------
Add-Type -AssemblyName System.Windows.Forms

$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = "Select the folder containing the archives and ROM files"
$dialog.ShowNewFolderButton = $false
$dialog.SelectedPath = "D:\Emulation\Roms"

if ($dialog.ShowDialog() -eq "OK") {
    $source = $dialog.SelectedPath
} else {
    Write-Host "No folder selected. Exiting."
    exit
}

# ---------------------------
# Paths and 7-Zip
# ---------------------------
$temp      = "D:\Emulation\Roms\Temp"
$sevenZip  = "C:\Program Files\7-Zip\7z.exe"

# All archive extensions 7z can read EXCEPT .7z
$archiveExts = @("*.zip","*.rar","*.tar","*.gz","*.bz2","*.xz","*.lzma","*.cab","*.wim")

# Raw ROM file extensions to compress directly
$romExtensions = @(
    ".iso", ".rvz", ".wbfs", ".bin", ".cue", ".gcm", ".dol",
    ".sfc", ".smc", ".nes", ".fds",
    ".3ds", ".nds", ".cia",
    ".gba", ".gbc", ".gb",
    ".n64", ".z64", ".v64",
    ".chd"
)

# Ensure temp folder exists
New-Item -ItemType Directory -Force -Path $temp | Out-Null

# ---------------------------
# Helper: Folder size in GB
# ---------------------------
function Get-FolderSizeGB($path) {
    if (Test-Path $path) {
        $bytes = (Get-ChildItem -Recurse -Force $path | Measure-Object -Property Length -Sum).Sum
        return [Math]::Round($bytes / 1GB, 2)
    } else {
        return 0
    }
}

# Capture initial source size before any changes
$initialSourceSizeGB = Get-FolderSizeGB $source

# ---------------------------
# Capture a fixed list of files recursively
# ---------------------------
$filesToProcess = Get-ChildItem $source -File -Recurse

# Filter out .7z files immediately
$filesToProcess = $filesToProcess | Where-Object { $_.Extension.ToLower() -ne ".7z" }

# Total work count for progress bar
$totalWork = $filesToProcess.Count
$workDone  = 0

# ---------------------------
# Counters
# ---------------------------
$totalArchives      = 0
$convertedArchives  = 0

$totalRoms          = 0
$convertedRoms      = 0

$skipped7z          = 0

# ---------------------------
# Process everything
# ---------------------------
foreach ($file in $filesToProcess) {

    $ext = $file.Extension.ToLower()
    $name = $file.BaseName
    $full = $file.FullName
    $dir  = $file.DirectoryName

    # Update progress bar
    $workDone++
    $percent = [int](($workDone / $totalWork) * 100)
    Write-Progress -Activity "Normalizing ROM Library" -Status "$percent% complete" -PercentComplete $percent

    # Skip .7z (already filtered, but double safety)
    if ($ext -eq ".7z") {
        $skipped7z++
        continue
    }

    # ---------------------------
    # Archive processing
    # ---------------------------
    $isArchive = $false
    foreach ($pattern in $archiveExts) {
        if ($file.Name -like $pattern) {
            $isArchive = $true
            break
        }
    }

    if ($isArchive) {
        $totalArchives++

        Write-Host "Processing archive: $($file.Name)"

        # Clear temp folder
        Remove-Item "$temp\*" -Recurse -Force -ErrorAction SilentlyContinue

        # Extract archive -> temp
        & $sevenZip x $full "-o$temp" -y > $null 2>&1

        # Create new .7z archive in SAME folder
        $outputArchive = Join-Path $dir ($name + ".7z")
        & $sevenZip a -t7z $outputArchive "$temp\*" -mx=9 -mmt=on -y > $null 2>&1

        # Delete original archive
        Remove-Item $full -Force

        Write-Host "Converted archive -> $outputArchive"
        $convertedArchives++
        continue
    }

    # ---------------------------
    # ROM file processing
    # ---------------------------
    if ($romExtensions -contains $ext) {

        $totalRoms++

        Write-Host "Processing ROM file: $($file.Name)"

        # Clear temp folder
        Remove-Item "$temp\*" -Recurse -Force -ErrorAction SilentlyContinue

        # Copy ROM file into temp
        Copy-Item $full -Destination $temp -Force

        # Create new .7z archive in SAME folder
        $outputArchive = Join-Path $dir ($name + ".7z")
        & $sevenZip a -t7z $outputArchive (Join-Path $temp $file.Name) -mx=9 -mmt=on -y > $null 2>&1

        # Delete original ROM file
        Remove-Item $full -Force

        Write-Host "Converted ROM -> $outputArchive"
        $convertedRoms++
        continue
    }
}

# ---------------------------
# Summary + Folder Sizes
# ---------------------------
$finalSourceSizeGB = Get-FolderSizeGB $source
$spaceSavedGB      = [Math]::Round(($initialSourceSizeGB - $finalSourceSizeGB), 2)

Write-Host ""
Write-Host "==================== Summary ===================="
Write-Host "Source folder:       $source"
Write-Host ""
Write-Host "Archives found:      $totalArchives"
Write-Host "Archives converted:  $convertedArchives"
Write-Host ""
Write-Host "ROM files found:     $totalRoms"
Write-Host "ROMs converted:      $convertedRoms"
Write-Host ""
Write-Host "Initial size:        $initialSourceSizeGB GB"
Write-Host "Final size:          $finalSourceSizeGB GB"
Write-Host "Space saved:         $spaceSavedGB GB"
Write-Host "=================================================="
