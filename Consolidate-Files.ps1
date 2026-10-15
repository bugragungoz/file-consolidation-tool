# File Consolidation Script
# Author: Bugra
# Description: Moves files from subdirectories to main directory with safety checks

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

    [Parameter(HelpMessage = "File extensions to move (e.g., '.txt','.pdf'). Leave empty for all files.")]
    [string[]]$ExtensionFilter,

    [Parameter(HelpMessage = "Remove empty directories after moving files.")]
    [switch]$RemoveEmptyDirectories,

    [Parameter(HelpMessage = "Skip all confirmation prompts.")]
    [switch]$Force,

    [Parameter(HelpMessage = "Conflict resolution strategy: Rename, Overwrite, Skip")]
    [ValidateSet('Rename', 'Overwrite', 'Skip', 'Ask')]
    [string]$ConflictAction = 'Ask',

    [Parameter(HelpMessage = "Disable logging to file.")]
    [switch]$NoLog
)

# Initialize logging
$script:LogFile = $null
$script:ScriptStartTime = Get-Date

function Initialize-Logging {
    if ($NoLog) {
        Write-Verbose "Logging disabled by user"
        return
    }
    
    $scriptPath = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
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
        $header | Out-File -FilePath $script:LogFile -Encoding UTF8
        Write-Verbose "Log file created: $script:LogFile"
    } catch {
        Write-Warning "Could not create log file: $($_.Exception.Message)"
        $script:LogFile = $null
    }
}

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    
    if ($null -eq $script:LogFile) { return }
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        $logEntry | Out-File -FilePath $script:LogFile -Append -Encoding UTF8
    } catch {
        # Silently fail if logging doesn't work
    }
}

# ASCII Art Welcome
function Show-Welcome {
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
    Write-Log "Script started" -Level INFO
}

# Function to get directory from user (interactive mode)
function Get-TargetDirectory {
    while ($true) {
        $path = Read-Host "Enter the target directory path"
        
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-Warning "Path cannot be empty!"
            Write-Log "User entered empty path" -Level WARNING
            continue
        }
        
        if (Test-Path -LiteralPath $path -PathType Container) {
            Write-Log "Target directory selected: $path" -Level INFO
            return $path
        } else {
            Write-Warning "Directory does not exist!"
            Write-Log "Invalid directory path: $path" -Level WARNING
            $retry = Read-Host "Try again? (Y/N)"
            if ($retry -ne 'Y' -and $retry -ne 'y') {
                Write-Log "User cancelled directory selection" -Level INFO
                throw "Operation cancelled by user."
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

# Function to analyze directory structure (optimized)
function Get-DirectoryAnalysis {
    param (
        [string]$Path
    )
    
    Write-Verbose "Analyzing directory structure at: $Path"
    Write-Log "Starting directory analysis: $Path" -Level INFO
    
    # Single call to Get-ChildItem for better performance
    $allItems = Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    
    $subdirs = $allItems | Where-Object { $_.PSIsContainer }
    $allFiles = $allItems | Where-Object { -not $_.PSIsContainer }
    $rootFiles = Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction SilentlyContinue
    $subdirFiles = $allFiles | Where-Object { $_.DirectoryName -ne $Path }
    
    $fileTypes = $subdirFiles | Group-Object Extension | Sort-Object Count -Descending
    
    $analysis = @{
        TotalSubdirectories = $subdirs.Count
        TotalFiles = $allFiles.Count
        RootFiles = $rootFiles.Count
        SubdirectoryFiles = $subdirFiles.Count
        FileTypes = $fileTypes
        SubdirFilesList = $subdirFiles
    }
    
    Write-Verbose "Analysis complete: $($analysis.SubdirectoryFiles) files in subdirectories"
    Write-Log "Analysis complete - Subdirs: $($analysis.TotalSubdirectories), Files: $($analysis.TotalFiles), Subdir Files: $($analysis.SubdirectoryFiles)" -Level INFO
    
    return $analysis
}

# Function to display analysis results
function Show-Analysis {
    param (
        [hashtable]$Analysis
    )
    
    Write-Output "`n================================================"
    Write-Output "DIRECTORY ANALYSIS RESULTS"
    Write-Output "================================================"
    Write-Output "Total subdirectories: $($Analysis.TotalSubdirectories)"
    Write-Output "Total files: $($Analysis.TotalFiles)"
    Write-Output "Files in root directory: $($Analysis.RootFiles)"
    Write-Output "Files in subdirectories: $($Analysis.SubdirectoryFiles)"
    
    if ($Analysis.FileTypes.Count -gt 0) {
        Write-Output "`nFile types in subdirectories:"
        foreach ($type in $Analysis.FileTypes) {
            $ext = if ([string]::IsNullOrWhiteSpace($type.Name)) { "(no extension)" } else { $type.Name }
            Write-Output "  $ext : $($type.Count) files"
        }
    }
    Write-Output "================================================`n"
}

# Function to get file type filter from user (interactive mode)
function Get-FileTypeFilter {
    param (
        [hashtable]$Analysis
    )
    
    Write-Host "File Type Selection:" -ForegroundColor Yellow
    Write-Host "1. Move ALL file types (default)" -ForegroundColor White
    Write-Host "2. Select specific file types" -ForegroundColor White
    
    $choice = Read-Host "`nEnter your choice (1 or 2)"
    
    if ($choice -eq '2') {
        Write-Host "`nEnter file extensions to move (comma-separated, e.g., .txt,.pdf,.jpg)" -ForegroundColor Yellow
        Write-Host "Or press Enter to move all types" -ForegroundColor Gray
        $input = Read-Host "Extensions"
        
        if (-not [string]::IsNullOrWhiteSpace($input)) {
            $extensions = $input -split ',' | ForEach-Object { $_.Trim().ToLower() }
            Write-Log "User selected extension filter: $($extensions -join ', ')" -Level INFO
            return $extensions
        }
    }
    
    Write-Log "User selected to move all file types" -Level INFO
    return @()
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
    Write-Log "File conflict detected: $fileName" -Level WARNING
    
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
            'A' { $script:GlobalConflictAction = 'Rename'; $ConflictStrategy = 'Rename'; Write-Log "User chose: Rename all conflicts" -Level INFO }
            'W' { $script:GlobalConflictAction = 'Overwrite'; $ConflictStrategy = 'Overwrite'; Write-Log "User chose: Overwrite all conflicts" -Level INFO }
            'N' { $script:GlobalConflictAction = 'Skip'; $ConflictStrategy = 'Skip'; Write-Log "User chose: Skip all conflicts" -Level INFO }
            'R' { $ConflictStrategy = 'Rename'; Write-Log "User chose: Rename this file" -Level INFO }
            'O' { $ConflictStrategy = 'Overwrite'; Write-Log "User chose: Overwrite this file" -Level INFO }
            'S' { $ConflictStrategy = 'Skip'; Write-Log "User chose: Skip this file" -Level INFO }
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
            Write-Log "Conflict resolved by renaming: $fileName -> $newName" -Level INFO
            return @{
                Action = 'Move'
                Destination = $newPath
            }
        }
        'Overwrite' {
            Write-Verbose "Overwriting existing file"
            Write-Log "Conflict resolved by overwriting: $fileName" -Level WARNING
            return @{
                Action = 'Overwrite'
                Destination = $DestinationPath
            }
        }
        'Skip' {
            Write-Verbose "Skipping file"
            Write-Log "Conflict resolved by skipping: $fileName" -Level INFO
            return @{
                Action = 'Skip'
                Destination = $null
            }
        }
    }
}

# Function to move files safely
function Move-FilesToRoot {
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
    Write-Log "Starting file move operation - Total files to process: $($Files.Count)" -Level INFO
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
    Write-Log "Files matching filter: $totalFiles" -Level INFO
    
    if ($totalFiles -eq 0) {
        Write-Warning "No files match the specified filter."
        Write-Log "No files to move after applying filter" -Level WARNING
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
                Write-Log "Skipped: $($file.Name)" -Level INFO
                continue
            }

            # -WhatIf prints this move and makes none; -Confirm asks about each file.
            if (-not $PSCmdlet.ShouldProcess($file.FullName, "Move to $($resolution.Destination)")) {
                if ($WhatIfPreference) {
                    [void]$script:PlannedDestinations.Add($resolution.Destination)
                    $movedCount++
                } else {
                    $skippedCount++
                    Write-Log "Skipped at the user's request: $($file.Name)" -Level INFO
                }
                continue
            }
            
            # Move file with appropriate action
            if ($resolution.Action -eq 'Overwrite') {
                Move-Item -LiteralPath $file.FullName -Destination $resolution.Destination -Force -ErrorAction Stop
                Write-Log "Moved (overwrite): $($file.FullName) -> $($resolution.Destination)" -Level INFO
            } else {
                Move-Item -LiteralPath $file.FullName -Destination $resolution.Destination -ErrorAction Stop
                Write-Log "Moved: $($file.FullName) -> $($resolution.Destination)" -Level SUCCESS
            }
            
            [void]$script:PlannedDestinations.Add($resolution.Destination)
            $movedCount++
            
        } catch {
            Write-Error "Error moving file '$($file.Name)': $($_.Exception.Message)"
            Write-Log "ERROR moving file '$($file.Name)': $($_.Exception.Message)" -Level ERROR
            $errorCount++
        }
    }
    
    # Clear progress bar
    Write-Progress -Activity "File Consolidation" -Completed
    
    # Write-Host, not Write-Output: this function returns its counts, and anything written to the
    # output would be captured with them instead of reaching the screen.
    Write-Host "================================================"
    if ($WhatIfPreference) {
        Write-Host "Would move: $movedCount (nothing was changed)" -ForegroundColor Green
    } else {
        Write-Host "Moved:   $movedCount" -ForegroundColor Green
    }
    Write-Host "Skipped: $skippedCount"
    Write-Host "Failed:  $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { 'Red' } else { 'Gray' })
    Write-Host "================================================`n"
    
    Write-Log "Move operation completed - Moved: $movedCount, Skipped: $skippedCount, Errors: $errorCount" -Level SUCCESS
    
    return @{
        Moved = $movedCount
        Skipped = $skippedCount
        Errors = $errorCount
    }
}

# Function to remove empty directories
function Remove-EmptyDirectories {
    param (
        [string]$Path,
        [bool]$AutoRemove = $false
    )
    
    Write-Verbose "Checking for empty subdirectories"
    Write-Log "Checking for empty subdirectories" -Level INFO
    
    if (-not $AutoRemove) {
        $choice = Read-Host "Do you want to delete empty subdirectories? (Y/N)"
        if ($choice -ne 'Y' -and $choice -ne 'y') {
            Write-Verbose "User declined to remove empty directories"
            Write-Log "User declined to remove empty directories" -Level INFO
            return
        }
        Write-Log "User confirmed removal of empty directories" -Level INFO
    }
    
    $deletedCount = 0
    
    # Get all subdirectories, sorted by depth (deepest first)
    $subdirs = Get-ChildItem -LiteralPath $Path -Directory -Recurse -Force -ErrorAction SilentlyContinue | 
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
            
            $items = Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue
            
            if ($items.Count -eq 0) {
                Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop
                Write-Verbose "Deleted empty directory: $($dir.Name)"
                Write-Log "Deleted empty directory: $($dir.FullName)" -Level INFO
                $deletedCount++
            }
        } catch {
            Write-Error "Error deleting directory '$($dir.Name)': $($_.Exception.Message)"
            Write-Log "ERROR deleting directory '$($dir.Name)': $($_.Exception.Message)" -Level ERROR
        }
    }
    
    # Clear progress bar
    Write-Progress -Activity "Cleaning Empty Directories" -Completed
    
    Write-Output "Total empty directories deleted: $deletedCount"
    Write-Log "Empty directories removed: $deletedCount" -Level SUCCESS
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
        Write-Log "Using provided path: $targetPath" -Level INFO
    }
    $targetPath = Resolve-TargetPath -Path $targetPath
    
    # Analyze directory
    $analysis = Get-DirectoryAnalysis -Path $targetPath
    
    # Show analysis
    Show-Analysis -Analysis $analysis
    
    # Check if there are files to move
    if ($analysis.SubdirectoryFiles -eq 0) {
        Write-Warning "No files found in subdirectories. Nothing to move."
        Write-Log "No files found in subdirectories" -Level WARNING
        exit 0
    }
    
    # Get file type filter (from parameter or user input)
    if ($null -eq $ExtensionFilter -or $ExtensionFilter.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            # Interactive mode
            $extensionFilter = Get-FileTypeFilter -Analysis $analysis
        } else {
            # Automated mode - use all files
            $extensionFilter = @()
            Write-Verbose "No extension filter specified, processing all file types"
            Write-Log "No extension filter specified, processing all file types" -Level INFO
        }
    } else {
        $extensionFilter = $ExtensionFilter | ForEach-Object { $_.ToLower() }
        Write-Verbose "Using extension filter: $($extensionFilter -join ', ')"
        Write-Log "Using extension filter: $($extensionFilter -join ', ')" -Level INFO
    }
    
    # Ask before moving anything. ShouldProcess alone asks only when -Confirm is given, so the
    # question goes through ShouldContinue. -Force skips it, and -WhatIf needs no answer: it
    # changes nothing and lists each move instead.
    if ($WhatIfPreference) {
        Write-Log "WhatIf: listing the moves without making them" -Level INFO
    } elseif (-not $Force) {
        $question = "Move the files in the subfolders of '$targetPath' into that folder?"
        if ($PSCmdlet.ShouldContinue($question, "Confirm")) {
            Write-Log "User confirmed operation" -Level INFO
        } else {
            Write-Host "Operation cancelled."
            Write-Log "Operation cancelled by user" -Level INFO
            exit 0
        }
    } else {
        Write-Log "Operation forced by -Force parameter" -Level INFO
    }
    
    # Move files
    $result = Move-FilesToRoot -RootPath $targetPath -Files $analysis.SubdirFilesList -ExtensionFilter $extensionFilter -ConflictStrategy $ConflictAction
    
    # Remove empty directories: with -RemoveEmptyDirectories, or when the user says so in
    # interactive mode. With a -Path the script runs unattended and never asks. A -WhatIf run moved
    # nothing, so it has nothing to clean up.
    if ($result.Moved -gt 0 -and -not $WhatIfPreference) {
        if ($RemoveEmptyDirectories) {
            Remove-EmptyDirectories -Path $targetPath -AutoRemove $true
        } elseif ([string]::IsNullOrWhiteSpace($Path)) {
            Remove-EmptyDirectories -Path $targetPath -AutoRemove $false
        }
    }
    
    Write-Output "`nOperation completed successfully!"
    Write-Verbose "Summary: $($result.Moved) moved, $($result.Skipped) skipped, $($result.Errors) errors"
    
    # Write final summary to log
    $endTime = Get-Date
    $duration = $endTime - $script:ScriptStartTime
    Write-Log "==================== OPERATION SUMMARY ====================" -Level INFO
    Write-Log "Files moved: $($result.Moved)" -Level INFO
    Write-Log "Files skipped: $($result.Skipped)" -Level INFO
    Write-Log "Errors: $($result.Errors)" -Level INFO
    Write-Log "Duration: $($duration.ToString('hh\:mm\:ss'))" -Level INFO
    Write-Log "End Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level INFO
    Write-Log "==========================================================" -Level INFO
    Write-Log "Script completed successfully" -Level SUCCESS
    
    if ($null -ne $script:LogFile) {
        Write-Host "`nDetailed log saved to: $script:LogFile" -ForegroundColor Green
    }
    
} catch {
    Write-Error "FATAL ERROR: $($_.Exception.Message)"
    Write-Verbose $_.ScriptStackTrace
    Write-Log "FATAL ERROR: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
} finally {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        # Interactive mode - wait for keypress
        Write-Host "`nPress any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}
