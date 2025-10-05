# File Consolidation Script
# Moves files from subdirectories to main directory with safety checks

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Position = 0, HelpMessage = "Target directory path where files will be consolidated.")]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) { return $true }
        if (Test-Path -Path $_ -PathType Container) {
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

    [Parameter(HelpMessage = "Conflict resolution strategy: Rename, Overwrite, Skip, Ask")]
    [ValidateSet('Rename', 'Overwrite', 'Skip', 'Ask')]
    [string]$ConflictAction = 'Ask'
)

# Display welcome banner
function Show-Welcome {
    Write-Host @"

 _____ _ _         ____                      _ _     _       _   _             
|  ___(_) | ___   / ___|___  _ __  ___  ___ | (_) __| | __ _| |_(_) ___  _ __  
| |_  | | |/ _ \ | |   / _ \| '_ \/ __|/ _ \| | |/ _\` |/ _\` | __| |/ _ \| '_ \ 
|  _| | | |  __/ | |__| (_) | | | \__ \ (_) | | | (_| | (_| | |_| | (_) | | | |
|_|   |_|_|\___|  \____\___/|_| |_|___/\___/|_|_|\__,_|\__,_|\__|_|\___/|_| |_|
                                                                                
  PowerShell File Consolidation Tool

"@ -ForegroundColor Cyan

    Write-Host "================================================" -ForegroundColor Yellow
    Write-Host ""
}

# Get target directory from user in interactive mode
function Get-TargetDirectory {
    while ($true) {
        $path = Read-Host "Enter the target directory path"
        
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-Warning "Path cannot be empty!"
            continue
        }
        
        if (Test-Path -Path $path -PathType Container) {
            return $path
        } else {
            Write-Warning "Directory does not exist!"
            $retry = Read-Host "Try again? (Y/N)"
            if ($retry -ne 'Y' -and $retry -ne 'y') {
                throw "Operation cancelled by user."
            }
        }
    }
}

# Analyze directory structure
function Get-DirectoryAnalysis {
    param (
        [string]$Path
    )
    
    Write-Verbose "Analyzing directory structure at: $Path"
    
    # Single call to Get-ChildItem for better performance
    $allItems = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    
    $subdirs = $allItems | Where-Object { $_.PSIsContainer }
    $allFiles = $allItems | Where-Object { -not $_.PSIsContainer }
    $rootFiles = Get-ChildItem -Path $Path -File -Force -ErrorAction SilentlyContinue
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
    
    return $analysis
}

# Display analysis results
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

# Get file type filter from user in interactive mode
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
            return $extensions
        }
    }
    
    return @()
}

# Handle file naming conflicts
function Resolve-FileConflict {
    param (
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$ConflictStrategy
    )
    
    if (-not (Test-Path -Path $DestinationPath)) {
        return @{
            Action = 'Move'
            Destination = $DestinationPath
        }
    }
    
    $fileName = [System.IO.Path]::GetFileName($SourcePath)
    
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
            'A' { $script:GlobalConflictAction = 'Rename'; $ConflictStrategy = 'Rename' }
            'W' { $script:GlobalConflictAction = 'Overwrite'; $ConflictStrategy = 'Overwrite' }
            'N' { $script:GlobalConflictAction = 'Skip'; $ConflictStrategy = 'Skip' }
            'R' { $ConflictStrategy = 'Rename' }
            'O' { $ConflictStrategy = 'Overwrite' }
            'S' { $ConflictStrategy = 'Skip' }
        }
    }
    
    # Apply the selected strategy
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
            } while (Test-Path -Path $newPath)
            
            Write-Verbose "Renaming to: $newName"
            return @{
                Action = 'Move'
                Destination = $newPath
            }
        }
        'Overwrite' {
            Write-Verbose "Overwriting existing file"
            return @{
                Action = 'Overwrite'
                Destination = $DestinationPath
            }
        }
        'Skip' {
            Write-Verbose "Skipping file"
            return @{
                Action = 'Skip'
                Destination = $null
            }
        }
    }
}

# Move files to root directory with progress tracking
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
    Write-Output "`nStarting file move operation..."
    Write-Output "================================================"
    
    # Initialize global conflict action for batch operations
    $script:GlobalConflictAction = $null
    
    # Filter files if extension filter is specified
    $filesToMove = if ($ExtensionFilter.Count -gt 0) {
        $Files | Where-Object { $_.Extension.ToLower() -in $ExtensionFilter }
    } else {
        $Files
    }
    
    $totalFiles = $filesToMove.Count
    
    if ($totalFiles -eq 0) {
        Write-Warning "No files match the specified filter."
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
                continue
            }
            
            # Move file with appropriate action
            if ($resolution.Action -eq 'Overwrite') {
                Move-Item -Path $file.FullName -Destination $resolution.Destination -Force -ErrorAction Stop
            } else {
                Move-Item -Path $file.FullName -Destination $resolution.Destination -ErrorAction Stop
            }
            
            $movedCount++
            
        } catch {
            Write-Error "Error moving file '$($file.Name)': $($_.Exception.Message)"
            $errorCount++
        }
    }
    
    # Clear progress bar
    Write-Progress -Activity "File Consolidation" -Completed
    
    Write-Output "================================================"
    Write-Output "Files moved successfully: $movedCount"
    Write-Output "Files skipped: $skippedCount"
    if ($errorCount -gt 0) {
        Write-Warning "Files with errors: $errorCount"
    } else {
        Write-Output "Files with errors: 0"
    }
    Write-Output "================================================`n"
    
    return @{
        Moved = $movedCount
        Skipped = $skippedCount
        Errors = $errorCount
    }
}

# Remove empty subdirectories
function Remove-EmptyDirectories {
    param (
        [string]$Path,
        [bool]$AutoRemove = $false
    )
    
    Write-Verbose "Checking for empty subdirectories"
    
    if (-not $AutoRemove) {
        $choice = Read-Host "Do you want to delete empty subdirectories? (Y/N)"
        if ($choice -ne 'Y' -and $choice -ne 'y') {
            Write-Verbose "User declined to remove empty directories"
            return
        }
    }
    
    $deletedCount = 0
    
    # Get all subdirectories, sorted by depth (deepest first)
    $subdirs = Get-ChildItem -Path $Path -Directory -Recurse -Force -ErrorAction SilentlyContinue | 
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
            
            $items = Get-ChildItem -Path $dir.FullName -Force -ErrorAction SilentlyContinue
            
            if ($items.Count -eq 0) {
                Remove-Item -Path $dir.FullName -Force -ErrorAction Stop
                Write-Verbose "Deleted empty directory: $($dir.Name)"
                $deletedCount++
            }
        } catch {
            Write-Error "Error deleting directory '$($dir.Name)': $($_.Exception.Message)"
        }
    }
    
    # Clear progress bar
    Write-Progress -Activity "Cleaning Empty Directories" -Completed
    
    Write-Output "Total empty directories deleted: $deletedCount"
}

# Main script execution
try {
    # Show welcome banner
    Show-Welcome
    
    # Get target directory (from parameter or user input)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $targetPath = Get-TargetDirectory
    } else {
        $targetPath = $Path
        Write-Verbose "Using provided path: $targetPath"
    }
    
    # Analyze directory
    $analysis = Get-DirectoryAnalysis -Path $targetPath
    
    # Show analysis
    Show-Analysis -Analysis $analysis
    
    # Check if there are files to move
    if ($analysis.SubdirectoryFiles -eq 0) {
        Write-Warning "No files found in subdirectories. Nothing to move."
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
        }
    } else {
        $extensionFilter = $ExtensionFilter | ForEach-Object { $_.ToLower() }
        Write-Verbose "Using extension filter: $($extensionFilter -join ', ')"
    }
    
    # Confirm operation (unless -Force is used)
    if (-not $Force) {
        Write-Warning "This operation will move files from subdirectories to the root directory."
        
        if ($PSCmdlet.ShouldProcess($targetPath, "Move files from subdirectories to root")) {
            # User confirmed
        } else {
            Write-Output "Operation cancelled."
            exit 0
        }
    }
    
    # Move files
    $result = Move-FilesToRoot -RootPath $targetPath -Files $analysis.SubdirFilesList -ExtensionFilter $extensionFilter -ConflictStrategy $ConflictAction
    
    # Remove empty directories
    if ($result.Moved -gt 0) {
        Remove-EmptyDirectories -Path $targetPath -AutoRemove:$RemoveEmptyDirectories
    }
    
    Write-Output "`nOperation completed successfully!"
    Write-Verbose "Summary: $($result.Moved) moved, $($result.Skipped) skipped, $($result.Errors) errors"
    
} catch {
    Write-Error "FATAL ERROR: $($_.Exception.Message)"
    Write-Verbose $_.ScriptStackTrace
    exit 1
} finally {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        # Interactive mode - wait for keypress
        Write-Host "`nPress any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

