# File Consolidation Tool

A PowerShell script to consolidate files from nested subdirectories into a single root directory with intelligent conflict resolution and safety features.

## Features

- **Interactive and Automated Modes**: Run with parameters or in interactive mode for guided operation
- **File Type Filtering**: Choose to move all files or filter by specific extensions
- **Conflict Resolution**: Multiple strategies for handling duplicate file names (Rename, Overwrite, Skip, or Ask)
- **Safety First**: Confirmation prompts and `-WhatIf` support to preview changes
- **Progress Tracking**: Real-time progress bars for large operations
- **Empty Directory Cleanup**: Optional removal of empty subdirectories after file moves
- **Detailed Analysis**: Pre-operation directory structure analysis

## Requirements

- Windows PowerShell 5.1 or later
- PowerShell Core 7.0+ (cross-platform)
- Appropriate file system permissions for the target directory

## Installation

1. Download the script:
   ```powershell
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bugragungoz/file-consolidation-tool/main/Consolidate-Files.ps1" -OutFile "Consolidate-Files.ps1"
   ```

2. Or clone the repository:
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

## Common Use Cases

- Flattening deeply nested download folders
- Consolidating photo collections from multiple subdirectories
- Organizing scattered document files
- Cleaning up project directories after extraction
- Merging files from multiple folder structures

## Troubleshooting

**Issue**: "Access Denied" errors  
**Solution**: Run PowerShell as Administrator or check file permissions

**Issue**: Script execution blocked  
**Solution**: Set execution policy: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

**Issue**: Files not moving  
**Solution**: Check that files aren't open in another program, use `-Verbose` flag for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Author

**Bugra Güngöz** ([@bugragungoz](https://github.com/bugragungoz))

Created with PowerShell for efficient file management tasks.

## Changelog

- Initial release with core functionality
- Interactive and automated modes
- Multiple conflict resolution strategies
- Progress tracking and empty directory cleanup


