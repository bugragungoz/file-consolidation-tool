<#
.SYNOPSIS
Moves the files in a folder's subfolders up into the folder itself.

.DESCRIPTION
Consolidate-Files.ps1 finds every file in the subfolders of a folder and moves it into that
folder, so a tree such as Photos\2023\Trip\a.jpg ends up as Photos\a.jpg. It shows what it
found first and asks before it moves anything.

Hidden and system files and folders (such as desktop.ini or .git) stay where they are unless
-IncludeHidden is given, linked folders are never entered, and the script never works on a whole
drive or a system folder. When a name is already taken, -ConflictAction decides what happens.
-WhatIf lists every move without making it.

Run without parameters, the script asks for each choice. Every run writes a log next to the script
unless -NoLog is given.

.PARAMETER Path
The folder whose subfolders are emptied into it. Without it, the script asks for one.

.PARAMETER ExtensionFilter
Moves only files with these extensions, written as txt, .txt or *.txt, as a list or comma-separated.
Without it, every file is moved.

.PARAMETER ConflictAction
What to do when the folder already has a file with the same name: Rename (photo_1.jpg),
Overwrite, Skip, or Ask for each one (the default).

.PARAMETER RemoveEmptyDirectories
Deletes the subfolders the move left empty. Without it, the script asks in interactive mode and
keeps them when -Path is given.

.PARAMETER IncludeHidden
Also moves hidden and system files and the files in hidden folders.

.PARAMETER Force
Moves without asking for confirmation first.

.PARAMETER NoLog
Writes no log file.

.EXAMPLE
.\Consolidate-Files.ps1

Asks for the folder, the file types and what to do, step by step.

.EXAMPLE
.\Consolidate-Files.ps1 -Path "D:\Photos" -WhatIf

Lists every move it would make and changes nothing.

.EXAMPLE
.\Consolidate-Files.ps1 -Path "D:\Photos" -ExtensionFilter jpg,png -ConflictAction Rename

Moves only .jpg and .png files and numbers the ones whose name is taken.

.EXAMPLE
.\Consolidate-Files.ps1 -Path "D:\Downloads\Course" -ConflictAction Skip -RemoveEmptyDirectories -Force

Moves everything without asking, leaves files whose name is taken in place and deletes the
emptied subfolders.

.NOTES
Exit code 0 when every chosen file was moved, skipped or the run was cancelled; 1 when a file
could not be moved or the run stopped with an error.

.LINK
https://github.com/bugragungoz/file-consolidation-tool
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Position = 0, HelpMessage = "Target directory path where files will be consolidated.")]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) { return $true }
        if (Test-Path -LiteralPath $_ -PathType Container) {
            return $true
        } else {
            throw "Directory '$_' does not exist."
        }
    })]
    [string]$Path,

    [Parameter(HelpMessage = "File extensions to move, such as txt or .pdf. Leave empty for all files.")]
    [string[]]$ExtensionFilter,

    [Parameter(HelpMessage = "Remove empty directories after moving files.")]
    [switch]$RemoveEmptyDirectories,

    [Parameter(HelpMessage = "Skip all confirmation prompts.")]
    [switch]$Force,

    [Parameter(HelpMessage = "Conflict resolution strategy: Rename, Overwrite, Skip")]
    [ValidateSet('Rename', 'Overwrite', 'Skip', 'Ask')]
    [string]$ConflictAction = 'Ask',

    [Parameter(HelpMessage = "Disable logging to file.")]
    [switch]$NoLog,

    [Parameter(HelpMessage = "Also move hidden and system files, and the files in hidden folders.")]
    [switch]$IncludeHidden
)

# Initialize logging
$script:LogFile = $null
# The script's own file: it is never moved, even when it sits in a subfolder of the target.
$script:ScriptFile = $MyInvocation.MyCommand.Path
$script:ScriptStartTime = Get-Date
$script:ExitCode = 0

function Initialize-Logging {
    if ($NoLog) {
        Write-Verbose "Logging disabled by user"
        return
    }

    $scriptPath = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = Get-Location
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFileName = "FileConsolidation_$timestamp.log"
    $script:LogFile = Join-Path -Path $scriptPath -ChildPath $logFileName

    try {
        $header = @"
================================================================================
File Consolidation Tool - Log File
================================================================================
Start Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
PowerShell Version: $($PSVersionTable.PSVersion)
User: $env:USERNAME
Computer: $env:COMPUTERNAME
================================================================================

"@
        $header | Out-File -LiteralPath $script:LogFile -Encoding UTF8
        Write-Verbose "Log file created: $script:LogFile"
    } catch {
        Write-Warning "Could not create log file: $($_.Exception.Message)"
        $script:LogFile = $null
    }
}

function Write-LogEntry {
    param (
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    if ($null -eq $script:LogFile) { return }

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        $logEntry | Out-File -LiteralPath $script:LogFile -Append -Encoding UTF8
    } catch {
        # A failed log write must not stop the move; -Verbose shows it.
        Write-Verbose "Could not write to the log: $($_.Exception.Message)"
    }
}

# Welcome: the banner greets an interactive run; a run with -Path, often from a scheduled task or
# another script, prints one line instead.
function Show-Welcome {
    Write-LogEntry "Script started" -Level INFO
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        Write-Host "File Consolidation Tool" -ForegroundColor Green
        Write-Host ""
        return
    }

    Write-Host @"

@@@@@@@   @@@  @@@   @@@@@@@@  @@@@@@@    @@@@@@
@@@@@@@@  @@@  @@@  @@@@@@@@@  @@@@@@@@  @@@@@@@@
@@!  @@@  @@!  @@@  !@@        @@!  @@@  @@!  @@@
!@   @!@  !@!  @!@  !@!        !@!  @!@  !@!  @!@
@!@!@!@   @!@  !@!  !@! @!@!@  @!@!!@!   @!@!@!@!
!!!@!!!!  !@!  !!!  !!! !!@!!  !!@!@!    !!!@!!!!
!!:  !!!  !!:  !!!  :!!   !!:  !!: :!!   !!:  !!!
:!:  !:!  :!:  !:!  :!:   !::  :!:  !:!  :!:  !:!
 :: ::::  ::::: ::   ::: ::::  ::   :::  ::   :::
:: : ::    : :  :    :: :: :    :   : :   :   : :

"@ -ForegroundColor Green

    Write-Host ""
}

# Function to get directory from user (interactive mode)
function Get-TargetDirectory {
    while ($true) {
        # Explorer's "Copy as path" puts the path in quotes.
        $path = (Read-Host "Enter the target directory path").Trim().Trim('"')

        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-Warning "Path cannot be empty!"
            Write-LogEntry "User entered empty path" -Level WARNING
            continue
        }

        if (Test-Path -LiteralPath $path -PathType Container) {
            Write-LogEntry "Target directory selected: $path" -Level INFO
            return $path
        } else {
            Write-Warning "Directory does not exist!"
            Write-LogEntry "Invalid directory path: $path" -Level WARNING
            $retry = Read-Host "Try again? (Y/N)"
            if ($retry -ne 'Y' -and $retry -ne 'y') {
                Write-LogEntry "User cancelled directory selection" -Level INFO
                Write-Host "Operation cancelled."
                exit 0
            }
        }
    }
}

# Function to turn the path the user gave into the folder's full path, without a trailing
# separator: ".", "..\Data" and "C:\Data\" all name a folder, and the analysis compares each
# file's folder with this path to tell the files already in it from the ones in subfolders.
function Resolve-TargetPath {
    param (
        [string]$Path
    )

    $fullPath = (Get-Item -LiteralPath $Path -Force).FullName
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $root.Length) {
        $fullPath = $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }
    return $fullPath
}

# Function to list the files under a folder, split into the ones directly in it and the ones in
# its subfolders. Hidden and system files and folders are left out unless -IncludeHidden is given,
# and linked folders (junctions and symbolic links) are never entered: their files live elsewhere.
function Get-FolderContent {
    param (
        [string]$Path,
        [bool]$IncludeHidden
    )

    $hiddenOrSystem = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
    $content = @{
        Subdirectories = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
        RootFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        SubdirFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
        HiddenLeftOut = 0
        LinksLeftOut = 0
    }

    $rootFolder = Get-Item -LiteralPath $Path -Force
    $pending = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
    $pending.Push($rootFolder)
    while ($pending.Count -gt 0) {
        $folder = $pending.Pop()
        $isRoot = [object]::ReferenceEquals($folder, $rootFolder)
        $items = Get-ChildItem -LiteralPath $folder.FullName -Force -ErrorAction SilentlyContinue -ErrorVariable readErrors
        foreach ($readError in $readErrors) {
            Write-Warning "Could not read '$($folder.FullName)': $($readError.Exception.Message)"
            Write-LogEntry "Could not read '$($folder.FullName)': $($readError.Exception.Message)" -Level WARNING
        }

        foreach ($item in $items) {
            if (-not $IncludeHidden -and ($item.Attributes -band $hiddenOrSystem)) {
                # Files of the folder itself stay where they are anyway.
                if ($item.PSIsContainer -or -not $isRoot) { $content.HiddenLeftOut++ }
                continue
            }
            if ($item.PSIsContainer) {
                if ($item.LinkType -in @('Junction', 'SymbolicLink')) {
                    Write-Verbose "Not entering linked folder: $($item.FullName)"
                    $content.LinksLeftOut++
                    continue
                }
                $content.Subdirectories.Add($item)
                $pending.Push($item)
            } elseif ($isRoot) {
                $content.RootFiles.Add($item)
            } else {
                $content.SubdirFiles.Add($item)
            }
        }
    }
    return $content
}

# Function to tell whether a folder must never be flattened: a whole drive, the Windows folder,
# Program Files, ProgramData, the Users folder or a profile folder itself. Moving every file under
# one of them into it would wreck Windows, the installed programs or the user's folders.
function Test-ProtectedFolder {
    param (
        [string]$Path
    )

    $separators = [char[]]@('\', '/')
    $protected = @(
        [System.IO.Path]::GetPathRoot($Path)
        $env:SystemRoot
        $env:ProgramFiles
        ${env:ProgramFiles(x86)}
        $env:ProgramData
        $env:USERPROFILE
        $HOME
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($env:USERPROFILE) { $protected += Split-Path -Parent $env:USERPROFILE }

    $folder = $Path.TrimEnd($separators)
    foreach ($candidate in $protected) {
        if ([string]::Equals($folder, $candidate.TrimEnd($separators), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

# Function to analyze directory structure
function Get-DirectoryAnalysis {
    param (
        [string]$Path,
        [bool]$IncludeHidden
    )

    Write-Verbose "Analyzing directory structure at: $Path"
    Write-LogEntry "Starting directory analysis: $Path" -Level INFO

    $content = Get-FolderContent -Path $Path -IncludeHidden $IncludeHidden

    # The script and its log are never moved, even when they sit in a subfolder.
    $ownFiles = @($script:ScriptFile, $script:LogFile) | Where-Object { $_ }
    $subdirFiles = @($content.SubdirFiles | Where-Object { $ownFiles -notcontains $_.FullName })

    $fileTypes = $subdirFiles | Group-Object Extension | Sort-Object Count -Descending

    $analysis = @{
        TotalSubdirectories = $content.Subdirectories.Count
        TotalFiles = $content.RootFiles.Count + $content.SubdirFiles.Count
        RootFiles = $content.RootFiles.Count
        SubdirectoryFiles = $subdirFiles.Count
        HiddenLeftOut = $content.HiddenLeftOut
        LinksLeftOut = $content.LinksLeftOut
        FileTypes = $fileTypes
        SubdirFilesList = $subdirFiles
    }

    Write-Verbose "Analysis complete: $($analysis.SubdirectoryFiles) files in subdirectories"
    Write-LogEntry "Analysis complete - Subdirs: $($analysis.TotalSubdirectories), Files: $($analysis.TotalFiles), Subdir Files: $($analysis.SubdirectoryFiles), Hidden left out: $($analysis.HiddenLeftOut), Links left out: $($analysis.LinksLeftOut)" -Level INFO

    return $analysis
}

# Function to display analysis results
function Show-Analysis {
    param (
        [hashtable]$Analysis
    )

    Write-Host "`n================================================"
    Write-Host "DIRECTORY ANALYSIS RESULTS"
    Write-Host "================================================"
    Write-Host "Total subdirectories: $($Analysis.TotalSubdirectories)"
    Write-Host "Total files: $($Analysis.TotalFiles)"
    Write-Host "Files in root directory: $($Analysis.RootFiles)"
    Write-Host "Files in subdirectories: $($Analysis.SubdirectoryFiles)"
    if ($Analysis.HiddenLeftOut -gt 0) {
        Write-Host "Hidden or system items left out: $($Analysis.HiddenLeftOut) (-IncludeHidden moves them)"
    }
    if ($Analysis.LinksLeftOut -gt 0) {
        Write-Host "Linked folders not entered: $($Analysis.LinksLeftOut)"
    }

    if ($Analysis.FileTypes.Count -gt 0) {
        Write-Host "`nFile types in subdirectories:"
        foreach ($type in $Analysis.FileTypes) {
            $ext = if ([string]::IsNullOrWhiteSpace($type.Name)) { "(no extension)" } else { $type.Name }
            Write-Host "  $ext : $($type.Count) files"
        }
    }
    Write-Host "================================================`n"
}

# Function to get file type filter from user (interactive mode)
function Get-FileTypeFilter {

    Write-Host "File Type Selection:" -ForegroundColor Yellow
    Write-Host "1. Move ALL file types (default)" -ForegroundColor White
    Write-Host "2. Select specific file types" -ForegroundColor White

    $choice = Read-Host "`nEnter your choice (1 or 2)"

    if ($choice -eq '2') {
        Write-Host "`nEnter file extensions to move (comma-separated, e.g., txt, pdf, jpg)" -ForegroundColor Yellow
        Write-Host "Or press Enter to move all types" -ForegroundColor Gray
        $answer = Read-Host "Extensions"
        $extensions = ConvertTo-ExtensionList -Value $answer

        if ($extensions.Count -gt 0) {
            Write-LogEntry "User selected extension filter: $($extensions -join ', ')" -Level INFO
            return $extensions
        }
    }

    Write-LogEntry "User selected to move all file types" -Level INFO
    return @()
}

# Function to turn extensions written as "txt", ".txt" or "*.txt", alone or comma-separated, into
# ".txt". Through -File an array parameter arrives as one string, so commas are split here too.
function ConvertTo-ExtensionList {
    param (
        [string[]]$Value
    )

    [string[]]$extensions = @(
        $Value -split ',' |
            ForEach-Object { $_.Trim().TrimStart('*').TrimStart('.').ToLowerInvariant() } |
            Where-Object { $_ -ne '' } |
            ForEach-Object { ".$_" } |
            Select-Object -Unique
    )
    return ,$extensions
}

# Function to tell whether a destination name is already used, on disk or by this run
function Test-DestinationTaken {
    param (
        [string]$Path
    )

    return (Test-Path -LiteralPath $Path) -or $script:PlannedDestinations.Contains($Path)
}

# Function to handle file conflicts
function Resolve-FileConflict {
    param (
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$ConflictStrategy
    )

    # A name is taken if a file has it, or if an earlier move of this run was given it: under -WhatIf
    # nothing moves, and the preview must still number the second x.txt like the real run would.
    if (-not (Test-DestinationTaken -Path $DestinationPath)) {
        return @{
            Action = 'Move'
            Destination = $DestinationPath
        }
    }

    $fileName = [System.IO.Path]::GetFileName($SourcePath)
    Write-LogEntry "File conflict detected: $fileName" -Level WARNING

    # If strategy is Ask, prompt user for first conflict
    if ($ConflictStrategy -eq 'Ask') {
        Write-Warning "File conflict detected: $fileName already exists in destination."
        Write-Host "Choose action:" -ForegroundColor Yellow
        Write-Host "  (R)ename - Rename the file being moved" -ForegroundColor White
        Write-Host "  (O)verwrite - Replace existing file" -ForegroundColor White
        Write-Host "  (S)kip - Don't move this file" -ForegroundColor White
        Write-Host "  (A)ll Rename - Rename all conflicts" -ForegroundColor White
        Write-Host "  (W)rite All - Overwrite all conflicts" -ForegroundColor White
        Write-Host "  (N)one - Skip all conflicts" -ForegroundColor White

        do {
            $choice = (Read-Host "Your choice").ToUpper()
        } while ($choice -notin @('R', 'O', 'S', 'A', 'W', 'N'))

        switch ($choice) {
            'A' { $script:GlobalConflictAction = 'Rename'; $ConflictStrategy = 'Rename'; Write-LogEntry "User chose: Rename all conflicts" -Level INFO }
            'W' { $script:GlobalConflictAction = 'Overwrite'; $ConflictStrategy = 'Overwrite'; Write-LogEntry "User chose: Overwrite all conflicts" -Level INFO }
            'N' { $script:GlobalConflictAction = 'Skip'; $ConflictStrategy = 'Skip'; Write-LogEntry "User chose: Skip all conflicts" -Level INFO }
            'R' { $ConflictStrategy = 'Rename'; Write-LogEntry "User chose: Rename this file" -Level INFO }
            'O' { $ConflictStrategy = 'Overwrite'; Write-LogEntry "User chose: Overwrite this file" -Level INFO }
            'S' { $ConflictStrategy = 'Skip'; Write-LogEntry "User chose: Skip this file" -Level INFO }
        }
    }

    # Apply the strategy
    switch ($ConflictStrategy) {
        'Rename' {
            $directory = [System.IO.Path]::GetDirectoryName($DestinationPath)
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
            $extension = [System.IO.Path]::GetExtension($SourcePath)
            $counter = 1

            do {
                $newName = "${baseName}_${counter}${extension}"
                $newPath = Join-Path -Path $directory -ChildPath $newName
                $counter++
            } while (Test-DestinationTaken -Path $newPath)

            Write-Verbose "Renaming to: $newName"
            Write-LogEntry "Conflict resolved by renaming: $fileName -> $newName" -Level INFO
            return @{
                Action = 'Move'
                Destination = $newPath
            }
        }
        'Overwrite' {
            Write-Verbose "Overwriting existing file"
            Write-LogEntry "Conflict resolved by overwriting: $fileName" -Level WARNING
            return @{
                Action = 'Overwrite'
                Destination = $DestinationPath
            }
        }
        'Skip' {
            Write-Verbose "Skipping file"
            Write-LogEntry "Conflict resolved by skipping: $fileName" -Level INFO
            return @{
                Action = 'Skip'
                Destination = $null
            }
        }
    }
}

# Function to move files safely
function Move-FilesToRoot {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [string]$RootPath,
        [array]$Files,
        [array]$ExtensionFilter,
        [string]$ConflictStrategy
    )

    $movedCount = 0
    $skippedCount = 0
    $errorCount = 0

    Write-Verbose "Starting file move operation with $($Files.Count) files"
    Write-LogEntry "Starting file move operation - Total files to process: $($Files.Count)" -Level INFO
    Write-Host "`nStarting file move operation..."
    Write-Host "================================================"

    # Initialize global conflict action if using Ask strategy
    $script:GlobalConflictAction = $null
    $script:PlannedDestinations = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    # Filter files if extension filter is specified
    $filesToMove = if ($ExtensionFilter.Count -gt 0) {
        $Files | Where-Object { $_.Extension.ToLower() -in $ExtensionFilter }
    } else {
        $Files
    }

    $totalFiles = $filesToMove.Count
    Write-LogEntry "Files matching filter: $totalFiles" -Level INFO

    if ($totalFiles -eq 0) {
        Write-Warning "No files match the specified filter."
        Write-LogEntry "No files to move after applying filter" -Level WARNING
        return @{
            Moved = 0
            Skipped = 0
            Errors = 0
        }
    }

    $currentFile = 0

    foreach ($file in $filesToMove) {
        try {
            $currentFile++

            # Update progress bar
            $percentComplete = [math]::Round(($currentFile / $totalFiles) * 100, 2)
            $status = "Processing file $currentFile of $totalFiles"
            $currentActivity = "Moving: $($file.Name)"

            Write-Progress -Activity "File Consolidation" -Status $status -CurrentOperation $currentActivity -PercentComplete $percentComplete

            $destinationPath = Join-Path -Path $RootPath -ChildPath $file.Name

            # Use global conflict action if set, otherwise use parameter
            $currentStrategy = if ($script:GlobalConflictAction) { $script:GlobalConflictAction } else { $ConflictStrategy }

            # Handle conflicts
            $resolution = Resolve-FileConflict -SourcePath $file.FullName -DestinationPath $destinationPath -ConflictStrategy $currentStrategy

            if ($resolution.Action -eq 'Skip') {
                $skippedCount++
                Write-LogEntry "Skipped: $($file.Name)" -Level INFO
                continue
            }

            # -WhatIf prints this move and makes none; -Confirm asks about each file.
            if (-not $PSCmdlet.ShouldProcess($file.FullName, "Move to $($resolution.Destination)")) {
                if ($WhatIfPreference) {
                    [void]$script:PlannedDestinations.Add($resolution.Destination)
                    $movedCount++
                } else {
                    $skippedCount++
                    Write-LogEntry "Skipped at the user's request: $($file.Name)" -Level INFO
                }
                continue
            }

            # Move file with appropriate action
            if ($resolution.Action -eq 'Overwrite') {
                Move-Item -LiteralPath $file.FullName -Destination $resolution.Destination -Force -ErrorAction Stop
                Write-LogEntry "Moved (overwrite): $($file.FullName) -> $($resolution.Destination)" -Level INFO
            } else {
                Move-Item -LiteralPath $file.FullName -Destination $resolution.Destination -ErrorAction Stop
                Write-LogEntry "Moved: $($file.FullName) -> $($resolution.Destination)" -Level SUCCESS
            }

            [void]$script:PlannedDestinations.Add($resolution.Destination)
            $movedCount++

        } catch {
            Write-Error "Error moving file '$($file.Name)': $($_.Exception.Message)"
            Write-LogEntry "ERROR moving file '$($file.Name)': $($_.Exception.Message)" -Level ERROR
            $errorCount++
        }
    }

    # Clear progress bar
    Write-Progress -Activity "File Consolidation" -Completed

    # Write-Host: this function returns its counts, and anything written to the output would be
    # captured with them instead of reaching the screen.
    Write-Host "================================================"
    if ($WhatIfPreference) {
        Write-Host "Would move: $movedCount (nothing was changed)" -ForegroundColor Green
    } else {
        Write-Host "Moved:   $movedCount" -ForegroundColor Green
    }
    Write-Host "Skipped: $skippedCount"
    Write-Host "Failed:  $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { 'Red' } else { 'Gray' })
    Write-Host "================================================`n"

    Write-LogEntry "Move operation completed - Moved: $movedCount, Skipped: $skippedCount, Errors: $errorCount" -Level SUCCESS

    return @{
        Moved = $movedCount
        Skipped = $skippedCount
        Errors = $errorCount
    }
}

# Function to remove empty directories
function Remove-EmptyFolder {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [string]$Path,
        [bool]$AutoRemove = $false,
        [bool]$IncludeHidden = $false
    )

    Write-Verbose "Checking for empty subdirectories"
    Write-LogEntry "Checking for empty subdirectories" -Level INFO

    if (-not $AutoRemove) {
        $choice = Read-Host "Do you want to delete empty subdirectories? (Y/N)"
        if ($choice -ne 'Y' -and $choice -ne 'y') {
            Write-Verbose "User declined to remove empty directories"
            Write-LogEntry "User declined to remove empty directories" -Level INFO
            return
        }
        Write-LogEntry "User confirmed removal of empty directories" -Level INFO
    }

    $deletedCount = 0

    # The same folders the move looked in, deepest first: hidden and system folders (such as .git)
    # are left alone unless -IncludeHidden is given, and linked folders are never entered.
    $subdirs = (Get-FolderContent -Path $Path -IncludeHidden $IncludeHidden).Subdirectories |
               Sort-Object { $_.FullName.Split([System.IO.Path]::DirectorySeparatorChar).Count } -Descending

    $totalDirs = $subdirs.Count
    $currentDir = 0

    foreach ($dir in $subdirs) {
        try {
            $currentDir++

            # Update progress bar
            if ($totalDirs -gt 0) {
                $percentComplete = [math]::Round(($currentDir / $totalDirs) * 100, 2)
                Write-Progress -Activity "Cleaning Empty Directories" -Status "Processing directory $currentDir of $totalDirs" -CurrentOperation $dir.Name -PercentComplete $percentComplete
            }

            # Hidden files count as content. DirectoryInfo.Delete() without arguments deletes only an
            # empty folder, so a folder that could not be read is never deleted with its contents.
            $items = Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop

            if ($items.Count -eq 0 -and $PSCmdlet.ShouldProcess($dir.FullName, "Delete empty folder")) {
                $dir.Delete()
                Write-Verbose "Deleted empty directory: $($dir.Name)"
                Write-LogEntry "Deleted empty directory: $($dir.FullName)" -Level INFO
                $deletedCount++
            }
        } catch {
            Write-Error "Error deleting directory '$($dir.Name)': $($_.Exception.Message)"
            Write-LogEntry "ERROR deleting directory '$($dir.Name)': $($_.Exception.Message)" -Level ERROR
        }
    }

    # Clear progress bar
    Write-Progress -Activity "Cleaning Empty Directories" -Completed

    Write-Host "Total empty directories deleted: $deletedCount"
    Write-LogEntry "Empty directories removed: $deletedCount" -Level SUCCESS
}

# Main script execution
try {
    # Initialize logging
    Initialize-Logging

    # Show welcome banner
    Show-Welcome

    if ($null -ne $script:LogFile) {
        Write-Host "Log file: $script:LogFile" -ForegroundColor Gray
        Write-Host ""
    }

    # Get target directory (from parameter or user input)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $targetPath = Get-TargetDirectory
    } else {
        $targetPath = $Path
        Write-Verbose "Using provided path: $targetPath"
        Write-LogEntry "Using provided path: $targetPath" -Level INFO
    }
    $targetPath = Resolve-TargetPath -Path $targetPath
    if (Test-ProtectedFolder -Path $targetPath) {
        throw "'$targetPath' is a whole drive or a system folder. Choose a folder inside it."
    }

    # Analyze directory
    $analysis = Get-DirectoryAnalysis -Path $targetPath -IncludeHidden $IncludeHidden.IsPresent

    # Show analysis
    Show-Analysis -Analysis $analysis

    # Check if there are files to move
    if ($analysis.SubdirectoryFiles -eq 0) {
        Write-Warning "No files found in subdirectories. Nothing to move."
        Write-LogEntry "No files found in subdirectories" -Level WARNING
        exit 0
    }

    # Get file type filter (from parameter or user input)
    $extensions = ConvertTo-ExtensionList -Value $ExtensionFilter
    if ($PSBoundParameters.ContainsKey('ExtensionFilter') -and $extensions.Count -eq 0) {
        throw "-ExtensionFilter holds no extension. Give one such as txt or .pdf, or leave it out to move every file."
    }
    if ($extensions.Count -gt 0) {
        Write-Verbose "Using extension filter: $($extensions -join ', ')"
        Write-LogEntry "Using extension filter: $($extensions -join ', ')" -Level INFO
    } elseif ([string]::IsNullOrWhiteSpace($Path)) {
        # Interactive mode
        $extensions = Get-FileTypeFilter
    } else {
        # Automated mode - use all files
        Write-Verbose "No extension filter specified, processing all file types"
        Write-LogEntry "No extension filter specified, processing all file types" -Level INFO
    }

    # Ask before moving anything. ShouldProcess alone asks only when -Confirm is given, and
    # ShouldContinue takes Enter as Yes, so the question is a choice whose default is No. -Force
    # skips it, and -WhatIf needs no answer: it changes nothing and lists each move instead.
    if ($WhatIfPreference) {
        Write-LogEntry "WhatIf: listing the moves without making them" -Level INFO
    } elseif (-not $Force) {
        $question = "Move the files in the subfolders of '$targetPath' into that folder?"
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Move the files.'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Change nothing.')
        )
        if ($Host.UI.PromptForChoice('Confirm', $question, $choices, 1) -eq 0) {
            Write-LogEntry "User confirmed operation" -Level INFO
        } else {
            Write-Host "Operation cancelled."
            Write-LogEntry "Operation cancelled by user" -Level INFO
            exit 0
        }
    } else {
        Write-LogEntry "Operation forced by -Force parameter" -Level INFO
    }

    # Move files
    $result = Move-FilesToRoot -RootPath $targetPath -Files $analysis.SubdirFilesList -ExtensionFilter $extensions -ConflictStrategy $ConflictAction

    # Remove empty directories: with -RemoveEmptyDirectories, or when the user says so in
    # interactive mode. With a -Path the script runs unattended and never asks. A -WhatIf run moved
    # nothing, so it has nothing to clean up.
    if ($result.Moved -gt 0 -and -not $WhatIfPreference) {
        if ($RemoveEmptyDirectories) {
            Remove-EmptyFolder -Path $targetPath -AutoRemove $true -IncludeHidden $IncludeHidden.IsPresent
        } elseif ([string]::IsNullOrWhiteSpace($Path)) {
            Remove-EmptyFolder -Path $targetPath -AutoRemove $false -IncludeHidden $IncludeHidden.IsPresent
        }
    }

    # A file that could not be moved makes the run fail, so a scheduled task or another script can
    # tell; the files that were moved stay moved.
    if ($result.Errors -gt 0) {
        Write-Warning "$($result.Errors) file(s) could not be moved. The errors above say why."
        $script:ExitCode = 1
    } else {
        Write-Host "`nDone."
    }
    Write-Verbose "Summary: $($result.Moved) moved, $($result.Skipped) skipped, $($result.Errors) errors"

    # Write final summary to log
    $endTime = Get-Date
    $duration = $endTime - $script:ScriptStartTime
    Write-LogEntry "==================== OPERATION SUMMARY ====================" -Level INFO
    Write-LogEntry "Files moved: $($result.Moved)" -Level INFO
    Write-LogEntry "Files skipped: $($result.Skipped)" -Level INFO
    Write-LogEntry "Errors: $($result.Errors)" -Level INFO
    Write-LogEntry "Duration: $($duration.ToString('hh\:mm\:ss'))" -Level INFO
    Write-LogEntry "End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level INFO
    Write-LogEntry "==========================================================" -Level INFO
    if ($script:ExitCode -eq 0) {
        Write-LogEntry "Script completed successfully" -Level SUCCESS
    } else {
        Write-LogEntry "Script completed with errors" -Level ERROR
    }

    if ($null -ne $script:LogFile) {
        Write-Host "`nDetailed log saved to: $script:LogFile" -ForegroundColor Green
    }

} catch {
    $PSCmdlet.WriteError($_)
    Write-Verbose $_.ScriptStackTrace
    Write-LogEntry "FATAL ERROR: $($_.Exception.Message)" -Level ERROR
    Write-LogEntry "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
} finally {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        # Interactive mode - wait for keypress
        # Keeps the window of a "Run with PowerShell" start open. Hosts without a console to read
        # from, such as the ISE or redirected input, cannot wait for a key.
        try {
            Write-Host "`nPress any key to exit..." -ForegroundColor Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        } catch {
            Write-Verbose "Could not wait for a key: $($_.Exception.Message)"
        }
    }
}

exit $script:ExitCode
