# File Consolidation Tool

A PowerShell script that moves the files in a folder's subfolders up into the folder itself. Point it
at a folder such as `D:\Photos` and every file in `D:\Photos\2023\Trip`, `D:\Photos\2024` and so on
ends up directly in `D:\Photos`. It shows what it found and asks before it moves anything.

```text
Before                          After
D:\Photos                       D:\Photos
├── 2023                        ├── IMG_0001.jpg
│   └── Trip                    ├── IMG_0001_1.jpg   the second IMG_0001.jpg, renamed
│       ├── IMG_0001.jpg        └── IMG_0002.jpg
│       └── IMG_0002.jpg
└── 2024                        The emptied folders 2023, 2023\Trip and
    └── IMG_0001.jpg            2024 are deleted if you choose.
```

## Usage

You need Windows 10 or 11. Windows PowerShell 5.1 comes with them; PowerShell 7 works as well.

1. Download [`Consolidate-Files.ps1`](Consolidate-Files.ps1): open the file and click **Download raw file**.
2. Right-click the Start button and open **Terminal** (on Windows 10: **Windows PowerShell**).
3. Run the script from the folder you saved it to:

   ```powershell
   powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\Consolidate-Files.ps1"
   ```

   `-ExecutionPolicy Bypass` lets this one run start; it changes no setting on your computer.
4. The script asks for the folder, shows what is in its subfolders, asks which file types to move and
   asks once more before it moves them. If a name is already taken, it asks what to do. At the end it
   offers to delete the subfolders the move left empty.

```text
Enter the target directory path: D:\Photos
...
Files in subdirectories: 3

File types in subdirectories:
  .jpg : 3 files
...
Enter your choice (1 or 2): 1

Confirm
Move the files in the subfolders of 'D:\Photos' into that folder?
[Y] Yes  [N] No  [?] Help (default is "N"): Y
```

To see what would happen without changing anything, add `-Path` and `-WhatIf`: the script lists every
move it would make, with the new names of files whose name is taken.

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\Consolidate-Files.ps1" -Path "D:\Photos" -WhatIf
```

### Parameters

With `-Path`, the script asks no questions except the confirmation before it moves (skip it with
`-Force`) and, with the default `-ConflictAction Ask`, what to do when a name is taken.

| Parameter | What it does |
| --- | --- |
| `-Path` | The folder to consolidate. Without it, the script asks. |
| `-ExtensionFilter` | Moves only these file types: `jpg`, `.jpg` or `*.jpg`, several separated by commas (`jpg,png`). Without it, every file is moved. |
| `-ConflictAction` | When a file with the same name is already in the folder: `Rename` (`photo_1.jpg`), `Overwrite`, `Skip`, or `Ask` for each one (the default). |
| `-RemoveEmptyDirectories` | Deletes the subfolders the move left empty. |
| `-IncludeHidden` | Also moves hidden and system files, and the files in hidden folders. |
| `-Force` | Moves without the confirmation question. |
| `-NoLog` | Writes no log file. |
| `-WhatIf` | Lists every move and changes nothing. |
| `-Confirm` | Asks before each file is moved and each empty folder is deleted. |

### Examples

Run these from the folder the script is in (`cd $HOME\Downloads` first).

```powershell
# Only photos; number the ones whose name is taken
powershell -ExecutionPolicy Bypass -File .\Consolidate-Files.ps1 -Path "D:\Photos" -ExtensionFilter jpg,png -ConflictAction Rename

# Everything, no questions: keep files whose name is taken where they are, delete the emptied folders
powershell -ExecutionPolicy Bypass -File .\Consolidate-Files.ps1 -Path "D:\Downloads\Course" -ConflictAction Skip -RemoveEmptyDirectories -Force
```

`Get-Help .\Consolidate-Files.ps1 -Full` shows the same help in PowerShell.

## What it leaves alone

- **Files already in the folder** stay where they are; only files in subfolders move.
- **Hidden and system files and folders**, such as `desktop.ini`, `Thumbs.db` or a `.git` folder,
  stay unless you give `-IncludeHidden`. The analysis says how many it left out.
- **Linked folders** (junctions and symbolic links) are never entered: their files live elsewhere.
- **The script and its log** are never moved, even when they are in a subfolder.
- **Whole drives and system folders**: the script refuses `C:\`, the Windows folder, Program Files,
  ProgramData, `C:\Users` and a profile folder such as `C:\Users\you`. Choose a folder inside them.

Moves are not undone automatically. Every run writes a log next to the script,
`FileConsolidation_<date>_<time>.log`, that lists each file's old and new path; try `-WhatIf` first on
a folder that matters. The script ends with exit code 0, or 1 when a file could not be moved (for
example because a program has it open) or the run stopped with an error.

## Tests

The tests run the script on temporary folders with [Pester](https://pester.dev) 5:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester ./tests
```

GitHub Actions runs them, with PSScriptAnalyzer, in Windows PowerShell 5.1 and PowerShell 7 for every
push to master and every pull request.

## License

[MIT](LICENSE)

This script was developed with assistance from an AI model: Claude 4.5 Sonnet.

It was later revised and updated with Claude Opus 5.5.
