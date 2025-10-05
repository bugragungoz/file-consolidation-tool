# File Consolidation Tool

A PowerShell script to consolidate files from nested subdirectories into a single root directory with intelligent conflict resolution and safety features.

## Common Use Cases

- Flattening deeply nested download folders
- Consolidating photo collections from multiple subdirectories
- Organizing scattered document files
- Cleaning up project directories after extraction
- Merging files from multiple folder structures

## Features

- **Interactive and Automated Modes**: Run with parameters or in interactive mode for guided operation
- **File Type Filtering**: Choose to move all files or filter by specific extensions
- **Conflict Resolution**: Multiple strategies for handling duplicate file names (Rename, Overwrite, Skip, or Ask)
- **Safety First**: Confirmation prompts and `-WhatIf` support to preview changes
- **Progress Tracking**: Real-time progress bars for large operations
- **Empty Directory Cleanup**: Optional removal of empty subdirectories after file moves
- **Detailed Analysis**: Pre-operation directory structure analysis
- **Comprehensive Logging**: Automatic log file generation with detailed operation history

## Installation

### Step 1: Enable Script Execution (First Time Only)

If this is your first time running PowerShell scripts, you need to enable script execution:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Press `Y` when prompted to confirm.

### Step 2: Download the Script

**Option A: Direct Download**
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bugragungoz/file-consolidation-tool/master/Consolidate-Files.ps1" -OutFile "Consolidate-Files.ps1"
```

Verify the download:
```powershell
Get-Item "Consolidate-Files.ps1"
```

**Option B: Clone Repository**
```powershell
git clone https://github.com/bugragungoz/file-consolidation-tool.git
cd file-consolidation-tool
```

## Usage

### Interactive Mode

Simply run the script without parameters for a guided experience:

```powershell
.\Consolidate-Files.ps1
```

The script will:
1. Prompt for the target directory
2. Analyze the directory structure
3. Display file statistics
4. Ask for file type preferences
5. Request confirmation before making changes
6. Handle conflicts interactively

### Automated Mode

Use parameters for unattended operation:

```powershell
# Move all files, rename conflicts, auto-remove empty directories
.\Consolidate-Files.ps1 -Path "C:\MyFolder" -ConflictAction Rename -RemoveEmptyDirectories -Force

# Move only specific file types
.\Consolidate-Files.ps1 -Path "C:\MyFolder" -ExtensionFilter ".jpg",".png",".gif" -ConflictAction Skip

# Preview changes without making them (WhatIf)
.\Consolidate-Files.ps1 -Path "C:\MyFolder" -WhatIf
```

## Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `-Path` | String | Target directory path to consolidate | Interactive prompt |
| `-ExtensionFilter` | String[] | File extensions to move (e.g., ".txt", ".pdf") | All files |
| `-ConflictAction` | String | How to handle conflicts: `Rename`, `Overwrite`, `Skip`, `Ask` | `Ask` |
| `-RemoveEmptyDirectories` | Switch | Automatically remove empty directories | `$false` |
| `-Force` | Switch | Skip confirmation prompts | `$false` |
| `-NoLog` | Switch | Disable logging to file | `$false` |
| `-WhatIf` | Switch | Preview changes without executing | `$false` |
| `-Verbose` | Switch | Show detailed operation information | `$false` |

## Examples

### Example 1: Consolidate All Files

```powershell
.\Consolidate-Files.ps1 -Path "D:\Downloads\Projects"
```

Moves all files from subdirectories to `D:\Downloads\Projects`, prompting for conflict resolution.

### Example 2: Move Specific File Types

```powershell
.\Consolidate-Files.ps1 -Path "C:\Photos" -ExtensionFilter ".jpg",".jpeg",".png" -ConflictAction Rename
```

Moves only image files, automatically renaming any conflicts.

### Example 3: Clean Operation

```powershell
.\Consolidate-Files.ps1 -Path "C:\Workspace" -RemoveEmptyDirectories -Force -ConflictAction Skip
```

Moves files, skips conflicts, removes empty directories, no prompts.

### Example 4: Safe Preview

```powershell
.\Consolidate-Files.ps1 -Path "C:\ImportantFiles" -WhatIf -Verbose
```

Shows what would happen without making any changes.

## Troubleshooting

**Issue**: Script execution blocked ("running scripts is disabled on this system")  
**Solution**: Enable script execution (see Step 1 in Installation section above)

**Issue**: "Access Denied" errors  
**Solution**: Run PowerShell as Administrator or check file permissions

**Issue**: Files not moving  
**Solution**: Check that files aren't open in another program, use `-Verbose` flag for details

## Conflict Resolution Strategies

When a file with the same name already exists in the destination:

- **Rename**: Appends a number to the filename (e.g., `document.txt` becomes `document_1.txt`)
- **Overwrite**: Replaces the existing file with the new one
- **Skip**: Leaves the existing file and doesn't move the new one
- **Ask**: Prompts for a decision on each conflict (with options to apply to all)

## Safety Features

- **Validation**: Ensures the target directory exists before proceeding
- **Error Handling**: Gracefully handles permission errors and locked files
- **Confirmation Prompts**: Requires user approval before making changes (unless `-Force` is used)
- **WhatIf Support**: Preview mode to see changes before executing
- **Progress Tracking**: Visual feedback during long operations

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Author

**Bugra Güngöz** ([@bugragungoz](https://github.com/bugragungoz))

Developed with Claude 4.5 Sonnet AI for efficient PowerShell-based file management.
