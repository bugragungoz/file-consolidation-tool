#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

# Runs Consolidate-Files.ps1 the way a user does, in a separate PowerShell process of the same
# edition (Windows PowerShell 5.1 or PowerShell 7), on folders made under Pester's TestDrive.
# A separate process captures everything the script prints, prompts included, and its exit code.

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Consolidate-Files.ps1'
    $script:Shell = (Get-Process -Id $PID).Path
    $script:OnWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'

    function Invoke-Consolidation {
        param([string[]]$Arguments, [string]$WorkingDirectory = $TestDrive)
        Push-Location -LiteralPath $WorkingDirectory
        try {
            $output = & $script:Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:ScriptPath @Arguments 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
        }
        finally {
            Pop-Location
        }
    }

    # Makes files (with their name as content) under a new folder and returns the folder's path.
    function New-Tree {
        param([string]$Name, [string[]]$Files)
        $root = Join-Path $TestDrive $Name
        foreach ($file in $Files) {
            $path = Join-Path $root $file
            [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
            [System.IO.File]::WriteAllText($path, $file)
        }
        return $root
    }

    # The files under a folder, as relative paths with / separators, in ordinal order (the same on
    # every system and culture: "x.txt" before "x_1.txt").
    function Get-RelativeFile {
        param([string]$Root)
        [string[]]$files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            ForEach-Object { $_.FullName.Substring($Root.Length + 1).Replace('\', '/') }
        [System.Array]::Sort($files, [System.StringComparer]::Ordinal)
        return $files
    }
}

Describe 'Consolidate-Files.ps1' {
    Context 'Moving files' {
        It 'moves every file from the subfolders into the folder' {
            $root = New-Tree 'basic' 'root.txt', 'a/one.txt', 'a/b/two.txt'

            $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            Get-RelativeFile $root | Should -Be @('one.txt', 'root.txt', 'two.txt')
        }

        It 'shows how many files it moved, skipped and could not move' {
            $root = New-Tree 'summary' 'a/one.txt', 'b/two.txt'

            $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename'

            $run.Output | Should -Match 'Moved:\s+2\b'
            $run.Output | Should -Match 'Skipped:\s+0\b'
            $run.Output | Should -Match 'Failed:\s+0\b'
        }

        It 'moves files whose names hold [ and ]' {
            $root = New-Tree 'brackets' 'a/photo [1].jpg', 'b [old]/scan.pdf'

            $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            Get-RelativeFile $root | Should -Be @('photo [1].jpg', 'scan.pdf')
        }

        It 'leaves the files of the folder itself alone when the path is relative' {
            $root = New-Tree 'relative' 'keep.txt', 'a/moved.txt'

            $run = Invoke-Consolidation '-Path', '.', '-Force', '-NoLog', '-ConflictAction', 'Rename' -WorkingDirectory $root

            $run.ExitCode | Should -Be 0 -Because $run.Output
            Get-RelativeFile $root | Should -Be @('keep.txt', 'moved.txt')
        }

        It 'leaves the files of the folder itself alone when the path ends with a separator' {
            $root = New-Tree 'trailing' 'keep.txt', 'a/moved.txt'

            $run = Invoke-Consolidation '-Path', ($root + [System.IO.Path]::DirectorySeparatorChar), '-Force', '-NoLog', '-ConflictAction', 'Rename'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            Get-RelativeFile $root | Should -Be @('keep.txt', 'moved.txt')
        }

        It 'never moves the script itself' {
            $root = New-Tree 'self' 'a/data.txt'
            $copy = Join-Path $root 'tools/Consolidate-Files.ps1'
            New-Item -ItemType Directory -Path (Split-Path -Parent $copy) | Out-Null
            Copy-Item -LiteralPath $script:ScriptPath -Destination $copy

            $output = & $script:Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $copy -Path $root -Force -NoLog -ConflictAction Rename 2>&1

            $LASTEXITCODE | Should -Be 0 -Because ($output | Out-String)
            Get-RelativeFile $root | Should -Be @('data.txt', 'tools/Consolidate-Files.ps1')
        }
    }

    Context 'Name conflicts' {
        It 'Rename numbers each file whose name is taken' {
            $root = New-Tree 'rename' 'x.txt', 'a/x.txt', 'b/x.txt'

            Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename' | Out-Null

            Get-RelativeFile $root | Should -Be @('x.txt', 'x_1.txt', 'x_2.txt')
            Get-Content -LiteralPath (Join-Path $root 'x.txt') | Should -Be 'x.txt'
        }

        It 'Skip leaves the file in its subfolder' {
            $root = New-Tree 'skip' 'x.txt', 'a/x.txt'

            $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Skip'

            Get-RelativeFile $root | Should -Be @('a/x.txt', 'x.txt')
            $run.Output | Should -Match 'Skipped:\s+1\b'
        }

        It 'Overwrite replaces the file in the folder' {
            $root = New-Tree 'overwrite' 'x.txt', 'a/x.txt'

            Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Overwrite' | Out-Null

            Get-RelativeFile $root | Should -Be @('x.txt')
            Get-Content -LiteralPath (Join-Path $root 'x.txt') | Should -Be 'a/x.txt'
        }
    }

    Context 'Asking first' {
        It 'asks before moving anything unless -Force is given' {
            $root = New-Tree 'confirm' 'a/one.txt'

            # A non-interactive PowerShell cannot answer the question, so the script must stop.
            $run = Invoke-Consolidation '-Path', $root, '-NoLog', '-ConflictAction', 'Rename'

            $run.ExitCode | Should -Not -Be 0
            Get-RelativeFile $root | Should -Be @('a/one.txt')
        }

        It 'does not ask about empty folders when a path is given' {
            $root = New-Tree 'noprompt' 'a/one.txt'

            $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            Test-Path -LiteralPath (Join-Path $root 'a') | Should -BeTrue
        }

        It '-WhatIf changes nothing and lists every move, numbering taken names' {
            $root = New-Tree 'whatif' 'a/x.txt', 'b/x.txt'

            $run = Invoke-Consolidation '-Path', $root, '-NoLog', '-ConflictAction', 'Rename', '-WhatIf'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            Get-RelativeFile $root | Should -Be @('a/x.txt', 'b/x.txt')
            $run.Output | Should -Match 'What if:.*x\.txt'
            $run.Output | Should -Match 'What if:.*x_1\.txt'
        }
    }

    Context 'Choosing files' {
        It 'accepts extensions written as txt, .txt or *.txt, also comma-separated in one argument' {
            $root = New-Tree 'filter' 'a/one.txt', 'a/two.TXT', 'a/three.md', 'a/four.pdf', 'a/five.log'

            # Through -File an array parameter takes one argument, so the values come comma-separated.
            $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename', '-ExtensionFilter', 'txt,*.md,.pdf'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            Get-RelativeFile $root | Should -Be @('a/five.log', 'four.pdf', 'one.txt', 'three.md', 'two.TXT')
        }

        It 'stops instead of moving every file when -ExtensionFilter holds no extension' {
            $root = New-Tree 'nofilter' 'a/one.txt'

            $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename', '-ExtensionFilter', ' , '

            $run.ExitCode | Should -Be 1
            Get-RelativeFile $root | Should -Be @('a/one.txt')
        }

        It 'leaves hidden files where they are unless -IncludeHidden is given' {
            $root = New-Tree 'hidden' 'a/.secret', 'a/visible.txt'
            if ($script:OnWindows) {
                $item = Get-Item -LiteralPath (Join-Path $root 'a/.secret') -Force
                $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Hidden
            }

            Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename' | Out-Null
            Get-RelativeFile $root | Should -Be @('a/.secret', 'visible.txt')

            Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename', '-IncludeHidden' | Out-Null
            Get-RelativeFile $root | Should -Be @('.secret', 'visible.txt')
        }

        It 'leaves hidden folders such as .git alone, also when removing empty folders' {
            $root = New-Tree 'hiddenfolder' 'project/.git/HEAD', 'project/readme.md'
            New-Item -ItemType Directory -Path (Join-Path $root 'project/.git/refs/tags') | Out-Null
            if ($script:OnWindows) {
                $item = Get-Item -LiteralPath (Join-Path $root 'project/.git') -Force
                $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Hidden
            }

            $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename', '-RemoveEmptyDirectories'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            Get-RelativeFile $root | Should -Be @('project/.git/HEAD', 'readme.md')
            Test-Path -LiteralPath (Join-Path $root 'project/.git/refs/tags') | Should -BeTrue
        }

        It 'does not enter linked folders, whose files live elsewhere' {
            $outside = New-Tree 'linktarget' 'secret.txt'
            $empty = Join-Path $TestDrive 'emptytarget'
            New-Item -ItemType Directory -Path $empty | Out-Null
            $root = New-Tree 'links' 'a/one.txt'
            # A junction needs no administrator rights on Windows; elsewhere a symbolic link does the same.
            $linkType = if ($script:OnWindows) { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $linkType -Path (Join-Path $root 'link') -Value $outside | Out-Null
            New-Item -ItemType $linkType -Path (Join-Path $root 'emptylink') -Value $empty | Out-Null

            $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename', '-RemoveEmptyDirectories'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            Test-Path -LiteralPath (Join-Path $outside 'secret.txt') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $root 'secret.txt') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root 'one.txt') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $root 'emptylink') | Should -BeTrue
        }

        It 'leaves system files such as desktop.ini where they are' -Skip:(-not $script:OnWindows) {
            $root = New-Tree 'system' 'a/desktop.ini', 'a/visible.txt'
            $item = Get-Item -LiteralPath (Join-Path $root 'a/desktop.ini') -Force
            $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::System

            Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename' | Out-Null

            Get-RelativeFile $root | Should -Be @('a/desktop.ini', 'visible.txt')
        }
    }

    Context 'Cleaning up and reporting' {
        It '-RemoveEmptyDirectories removes the folders it emptied and keeps the others' {
            $root = New-Tree 'cleanup' 'a/b/one.txt', 'c/.keep'

            $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename', '-RemoveEmptyDirectories'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            Test-Path -LiteralPath (Join-Path $root 'a') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root 'c') | Should -BeTrue
        }

        It 'exits with code 1 when a file could not be moved' -Skip:(-not $script:OnWindows) {
            $root = New-Tree 'locked' 'a/locked.txt', 'a/free.txt'
            $stream = [System.IO.File]::Open((Join-Path $root 'a/locked.txt'), 'Open', 'Read', 'None')
            try {
                $run = Invoke-Consolidation '-Path', $root, '-Force', '-NoLog', '-ConflictAction', 'Rename'
            }
            finally {
                $stream.Dispose()
            }

            $run.ExitCode | Should -Be 1
            $run.Output | Should -Match 'Failed:\s+1\b'
            Get-RelativeFile $root | Should -Be @('a/locked.txt', 'free.txt')
        }
    }
}
