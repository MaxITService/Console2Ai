#region Header and Configuration
# Script: Console2Ai.ps1
# Version: 3.4 (Production Ready - Remove last Invoke-Console2AiConversation block from Alt+S history)
# Author: [Your Name/Handle Here]
# Description: Provides functions to capture console history via Start-Transcript
#              and send it to an AI for assistance (command or conversation mode).
#              Includes Alt+C hotkey for quick AI command suggestions and
#              Alt+S hotkey for conversational AI interaction.
#              Automatically manages session transcripts.

# --- User Configuration ---
# Place these at the top for easy editing.

# Executable for the AI chat tool
$Global:Console2Ai_AIChatExecutable = "aichat.exe" # Used by both modes unless overridden below

# Configuration for Alt+C (Command Mode)
$Global:Console2Ai_CommandMode_AIChatExecutable = $Global:Console2Ai_AIChatExecutable # Or specify a different one
$Global:Console2Ai_CommandMode_AIPromptInstruction = "Please analyze the following console output history (focus on the last {0} lines if specified, otherwise the recent activity. Ignore any initial session headers or transcript metadata). The user's specific request is: '{1}'. Identify any issues or the user's likely goal based on both history and request, and suggest a PowerShell command to help. If the user request is a direct command instruction, fulfill it using the history as context. Console Output History:"

# Configuration for Alt+S (Conversation Mode)
$Global:Console2Ai_ConversationMode_AIChatExecutable = $Global:Console2Ai_AIChatExecutable # Or specify a different one
$Global:Console2Ai_ConversationMode_AIPromptInstruction = "You are in a conversational chat. Please analyze the following console output history (focus on the last {0} lines if specified, otherwise the recent activity. Ignore any initial session headers or transcript metadata) as context. The user's current query is: '{1}'. Respond to the user's query, using the console history for context if relevant. Avoid suggesting a command unless explicitly asked or it's the most natural answer. Focus on explanation and direct answers. Console Output History:"

# Default number of lines *from the end of the transcript* to consider for hotkeys if not specified
$Global:Console2Ai_DefaultLinesFromTranscriptForHotkey = 200

# --- Transcript Configuration ---
$Global:Console2Ai_TranscriptBaseDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) "Console2Ai\Transcripts"
$Global:Console2Ai_TranscriptMaxAgeDays = 2
$Global:Console2Ai_TranscriptCleanupLogFile = Join-Path ([Environment]::GetFolderPath('UserProfile')) "Console2Ai\Logs\TranscriptCleanup.log"

# --- Internal State ---
$Global:Console2Ai_CurrentTranscriptPath = $null
$Global:Console2Ai_TranscriptActive = $false # Indicates if the initial Start-Transcript in profile was successful

#endregion Header and Configuration

# --- Transcript Management Functions ---
function Invoke-Console2AiTranscriptCleanup {
    Write-Verbose "Console2Ai: Running transcript cleanup..."
    $baseDir = $Global:Console2Ai_TranscriptBaseDir
    $logFile = $Global:Console2Ai_TranscriptCleanupLogFile
    $maxDays = $Global:Console2Ai_TranscriptMaxAgeDays

    if (-not (Test-Path -Path $baseDir -PathType Container)) {
        Write-Verbose "Console2Ai: Transcript base directory '$baseDir' does not exist. Skipping cleanup."
        return
    }
    $logDir = Split-Path -Path $logFile -Parent
    if (-not (Test-Path -Path $logDir -PathType Container)) {
        try {
            New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Console2Ai: Created log directory '$logDir'."
        } catch {
            Write-Warning "Console2Ai: Failed to create log directory '$logDir'. Cleanup logging disabled. Error: $($_.Exception.Message)"
            $logFile = $null
        }
    }
    $cutoffDate = (Get-Date).AddDays(-$maxDays)
    Write-Verbose "Console2Ai: Cleaning transcripts older than $cutoffDate in '$baseDir'."
    try {
        $filesToClean = Get-ChildItem -Path $baseDir -Filter "Console2Ai_Transcript_*.txt" -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate }
        if ($null -eq $filesToClean -or $filesToClean.Count -eq 0) { # Check count for empty collection
            Write-Verbose "Console2Ai: No old transcript files found to clean."
            return
        }
        foreach ($file in $filesToClean) {
            $logTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            # Escape colon in variable output for Write-Host/Verbose/etc.
            $logMessagePrefix = "$logTimestamp - Attempting to delete old transcript '$($file.FullName)' (LastWrite`: $($file.LastWriteTime)):"
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                Write-Verbose "Console2Ai: Deleted old transcript: $($file.FullName)"
                if ($null -ne $logFile) { Add-Content -Path $logFile -Value "$logMessagePrefix Success" -Encoding UTF8 }
            } catch {
                Write-Warning "Console2Ai: Failed to delete old transcript '$($file.FullName)'. Error: $($_.Exception.Message)"
                if ($null -ne $logFile) { Add-Content -Path $logFile -Value "$logMessagePrefix FAILED - Error: $($_.Exception.Message)" -Encoding UTF8 }
            }
        }
    } catch {
        Write-Warning "Console2Ai: Error during transcript cleanup process: $($_.Exception.Message)"
        if ($null -ne $logFile) { Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR during cleanup: $($_.Exception.Message)" -Encoding UTF8 }
    }
    Write-Verbose "Console2Ai: Transcript cleanup finished."
}

# --- Core AI Interaction Functions (Transcript-Aware) ---
function Invoke-AIConsoleHelp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesFromTranscript = $Global:Console2Ai_DefaultLinesFromTranscriptForHotkey,
        [Parameter(Mandatory=$false)] [string]$UserPrompt = "User did not provide a specific prompt, analyze history for a command.",
        [Parameter(Mandatory=$false)] [string]$AIChatExecutable = $Global:Console2Ai_CommandMode_AIChatExecutable,
        [Parameter(Mandatory=$false)] [string]$AIPromptInstruction = $Global:Console2Ai_CommandMode_AIPromptInstruction
    )

    Write-Verbose "Invoke-AIConsoleHelp: Preparing context for AI command suggestion."
    if (-not $Global:Console2Ai_TranscriptActive -or [string]::IsNullOrWhiteSpace($Global:Console2Ai_CurrentTranscriptPath)) {
        Write-Warning "Invoke-AIConsoleHelp: Transcript is not configured or active for this session."
        return "ERROR: Transcript not active or path unknown."
    }

    $transcriptPath = $Global:Console2Ai_CurrentTranscriptPath
    $consoleHistory = ""
    $aiResult = "ERROR: AI execution did not produce a result."
    $transcriptWasStoppedByThisFunction = $false

    $linesCountForDisplay = if ($LinesFromTranscript -gt 0) { "$LinesFromTranscript lines" } else { "all lines" }
    $statusMessage = "AI Help ($linesCountForDisplay)..."

    $currentLine = $null; $currentCursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currentLine, [ref]$currentCursor)
    [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($statusMessage)

    try {
        if ($TRANSCRIPT) {
            try {
                Stop-Transcript -ErrorAction Stop
                $transcriptWasStoppedByThisFunction = $true
                Write-Verbose "Invoke-AIConsoleHelp: Stopped transcript '$transcriptPath' temporarily."
            } catch {
                Write-Warning "Invoke-AIConsoleHelp: Error stopping active transcript. Proceeding with caution. Error: $($_.Exception.Message)"
            }
        }

        if (Test-Path -Path $transcriptPath -PathType Leaf) {
            try {
                if ($LinesFromTranscript -gt 0) {
                    Write-Verbose "Invoke-AIConsoleHelp: Reading last $LinesFromTranscript lines from '$transcriptPath'."
                    $fileContentLines = Get-Content -Path $transcriptPath -ErrorAction Stop
                    $totalLinesInFile = $fileContentLines.Count
                    $startLineIndex = [Math]::Max(0, $totalLinesInFile - $LinesFromTranscript)
                    $consoleHistory = ($fileContentLines[$startLineIndex..($totalLinesInFile -1)]) -join [Environment]::NewLine
                } else {
                    Write-Verbose "Invoke-AIConsoleHelp: Reading entire transcript '$transcriptPath'."
                    $consoleHistory = Get-Content -Path $transcriptPath -Raw -ErrorAction Stop
                }
                Write-Verbose "Invoke-AIConsoleHelp: Read $($consoleHistory.Length) characters from transcript."

                # Remove transcript command headers
                $commandHeaderRegex = '(?m)^\*+\r?\nCommand start time: \d+\r?\n\*+\r?\n?' # Multiline mode, optional CR, optional final newline
                $consoleHistory = $consoleHistory -replace $commandHeaderRegex, ''
                Write-Verbose "Invoke-AIConsoleHelp: Removed transcript command headers."

            } catch {
                Write-Error "Invoke-AIConsoleHelp: Failed to read transcript file '$transcriptPath'. Error: $($_.Exception.Message)"
                $consoleHistory = "" # Ensure history is empty on error
            }
        } else {
            Write-Warning "Invoke-AIConsoleHelp: Transcript file '$transcriptPath' not found."
            $consoleHistory = ""
        }

        if ([string]::IsNullOrWhiteSpace($consoleHistory)) {
            Write-Warning "Invoke-AIConsoleHelp: No history captured (or only headers removed). AI might lack context."
        }

        $linesCountForPrompt = if ($LinesFromTranscript -gt 0) { $LinesFromTranscript } else { "all available" }
        $formattedInstruction = $AIPromptInstruction -f $linesCountForPrompt, $UserPrompt
        $fullAIPrompt = "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory"
        $fullAIPrompt = $fullAIPrompt.TrimEnd()
        Write-Verbose "Invoke-AIConsoleHelp: Full prompt for AI ($($fullAIPrompt.Length) chars): `n$($fullAIPrompt.Substring(0, [Math]::Min($fullAIPrompt.Length, 500)))..."

        $PreviousOutputEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        try {
            Write-Verbose "Invoke-AIConsoleHelp: Executing: $AIChatExecutable -e <prompt>"
            $aiResult = & $AIChatExecutable -e $fullAIPrompt
            Write-Verbose "Invoke-AIConsoleHelp: AI execution completed."
        } catch {
            Write-Error "Invoke-AIConsoleHelp: Failed to execute AI chat executable '$AIChatExecutable'."
            Write-Error $_.Exception.Message
            $aiResult = "ERROR: AI execution failed. $($_.Exception.Message)"
        } finally {
             [Console]::OutputEncoding = $PreviousOutputEncoding
        }
    } finally {
        if ($Global:Console2Ai_TranscriptActive) {
            if (-not $TRANSCRIPT) {
                Write-Verbose "Invoke-AIConsoleHelp: Transcript not running. Attempting to (re)start."
                try {
                    Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop | Out-Null
                    Write-Verbose "Invoke-AIConsoleHelp: Ensured transcript '$transcriptPath' is active."
                } catch {
                    Write-Error "Invoke-AIConsoleHelp: CRITICAL - Failed to (re)start transcript '$transcriptPath'! Error: $($_.Exception.Message)"
                    $Global:Console2Ai_TranscriptActive = $false
                }
            }
        } elseif ($transcriptWasStoppedByThisFunction -and -not $TRANSCRIPT) {
             Write-Warning "Invoke-AIConsoleHelp: Transcript was stopped by this function but global flag indicates it shouldn't be active. Attempting restart anyway."
             try { Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop | Out-Null } catch { Write-Error "Invoke-AIConsoleHelp: Failed to restart transcript that was stopped by function. Error: $($_.Exception.Message)" }
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
        if ($null -ne $currentLine) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($currentLine)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($currentCursor)
        }
    }
    return $aiResult
}

<#
.SYNOPSIS
  Initiates a conversational AI session using console transcript history as context.
.DESCRIPTION
  This function is called by the Alt+S hotkey. It temporarily stops transcription,
  gathers the user's query and transcript history (removing its own invocation from the history),
  formats a prompt for conversational AI, displays feedback, and then launches the AI executable,
  piping the prompt to its standard input. The AI executable takes over the console.
  Transcription is restarted when the AI exits.
.PARAMETER UserQuery
  The query typed by the user. Can also be specified as -UQ.
.PARAMETER LinesFromTranscript
  The number of console transcript lines from the end to include as context. Can also be specified as -LTQ.
.NOTES
  This function handles transcript stop/start around the AI execution.
  It attempts to remove the last command block from the history if it corresponds
  to this function's own invocation, providing cleaner context to the AI.
#>
function Invoke-Console2AiConversation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Alias('UQ')]
        [string]$UserQuery,

        [Parameter(Mandatory=$true)]
        [Alias('LTQ')]
        [int]$LinesFromTranscript
    )
    Write-Verbose "Invoke-Console2AiConversation: Preparing context for conversational AI."
    if (-not $Global:Console2Ai_TranscriptActive -or [string]::IsNullOrWhiteSpace($Global:Console2Ai_CurrentTranscriptPath)) {
        Write-Error "Invoke-Console2AiConversation: Transcript is not configured or active for this session."
        Write-Host "--- ERROR: Transcript not active. Cannot start AI conversation. ---" -ForegroundColor Red
        return
    }

    $transcriptPath = $Global:Console2Ai_CurrentTranscriptPath
    $consoleHistory = ""
    $aiExecutable = $Global:Console2Ai_ConversationMode_AIChatExecutable
    $transcriptWasStoppedByThisFunction = $false

    try {
        if ($TRANSCRIPT) {
            try {
                Stop-Transcript -ErrorAction Stop
                $transcriptWasStoppedByThisFunction = $true
                Write-Verbose "Invoke-Console2AiConversation: Stopped transcript '$transcriptPath' temporarily."
            } catch {
                Write-Warning "Invoke-Console2AiConversation: Error stopping active transcript. Error: $($_.Exception.Message)"
            }
        }

        if (Test-Path -Path $transcriptPath -PathType Leaf) {
            try {
                 if ($LinesFromTranscript -gt 0) {
                    Write-Verbose "Invoke-Console2AiConversation: Reading last $LinesFromTranscript lines from '$transcriptPath'."
                    $fileContentLines = Get-Content -Path $transcriptPath -ErrorAction Stop
                    $totalLinesInFile = $fileContentLines.Count
                    $startLineIndex = [Math]::Max(0, $totalLinesInFile - $LinesFromTranscript)
                    $consoleHistory = ($fileContentLines[$startLineIndex..($totalLinesInFile -1)]) -join [Environment]::NewLine
                } else {
                    Write-Verbose "Invoke-Console2AiConversation: Reading entire transcript '$transcriptPath'."
                    $consoleHistory = Get-Content -Path $transcriptPath -Raw -ErrorAction Stop
                }
                 Write-Verbose "Invoke-Console2AiConversation: Read $($consoleHistory.Length) characters from transcript."

                 # --- NEW v3.4: Remove the last command block if it's this function's call ---
                 $commandBlockHeaderPattern = '(?m)^\*+\r?\nCommand start time: \d+\r?\n\*+\r?\n?' # Pattern for the header itself
                 $matches = [regex]::Matches($consoleHistory, $commandBlockHeaderPattern)

                 if ($matches.Count -gt 0) {
                     $lastMatch = $matches[$matches.Count - 1]
                     # Find the text *after* the last header match
                     $textAfterLastHeader = $consoleHistory.Substring($lastMatch.Index + $lastMatch.Length)
                     # Find the first non-empty line of text after the header (should be the command)
                     # Use -split and Where-Object to handle potential blank lines after header
                     $firstLineAfterHeader = ($textAfterLastHeader -split '\r?\n' | Where-Object { $_ -match '\S' })[0]

                     # Check if the first line found contains the specific command name
                     if (($null -ne $firstLineAfterHeader) -and ($firstLineAfterHeader -match 'Invoke-Console2AiConversation')) {
                          Write-Verbose "Invoke-Console2AiConversation: Removing the last command block (current Invoke-Console2AiConversation call) from history."
                          # Truncate the history *before* the start index of the last matched header
                          $consoleHistory = $consoleHistory.Substring(0, $lastMatch.Index).TrimEnd()
                          Write-Verbose "Invoke-Console2AiConversation: History trimmed. New length: $($consoleHistory.Length)"
                     } else {
                          Write-Verbose "Invoke-Console2AiConversation: Last command block header found, but the following command wasn't Invoke-Console2AiConversation. Not removing."
                          if ($null -eq $firstLineAfterHeader) { Write-Verbose "Invoke-Console2AiConversation: Could not find command line after last header." }
                          else { Write-Verbose "Invoke-Console2AiConversation: Command found was: '$firstLineAfterHeader'" }
                     }
                 } else {
                     Write-Verbose "Invoke-Console2AiConversation: No command block headers found in the transcript history."
                 }
                 # --- END NEW v3.4 SECTION ---

                 # Remove *remaining* transcript command headers from the history being sent
                 $commandHeaderRegex = '(?m)^\*+\r?\nCommand start time: \d+\r?\n\*+\r?\n?' # Multiline mode, optional CR, optional final newline
                 $consoleHistory = $consoleHistory -replace $commandHeaderRegex, ''
                 Write-Verbose "Invoke-Console2AiConversation: Removed remaining transcript command headers."

            } catch {
                Write-Error "Invoke-Console2AiConversation: Failed to read or process transcript file '$transcriptPath'. Error: $($_.Exception.Message)"
                $consoleHistory = "" # Ensure history is empty on error
            }
        } else {
            Write-Warning "Invoke-Console2AiConversation: Transcript file '$transcriptPath' not found."
            $consoleHistory = ""
        }

        if ([string]::IsNullOrWhiteSpace($consoleHistory)) {
             Write-Warning "Invoke-Console2AiConversation: No history captured (or only headers removed). AI might lack context."
        }

        $linesCountForPrompt = if ($LinesFromTranscript -gt 0) { $LinesFromTranscript } else { "all available" }
        $formattedInstruction = $Global:Console2Ai_ConversationMode_AIPromptInstruction -f $linesCountForPrompt, $UserQuery
        $fullAIPromptForConversation = if ([string]::IsNullOrWhiteSpace($consoleHistory)) { $formattedInstruction } else { "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory" }
        $fullAIPromptForConversation = $fullAIPromptForConversation.TrimEnd()
        Write-Verbose "Invoke-Console2AiConversation: Full prompt for AI (stdin, $($fullAIPromptForConversation.Length) chars): `n$($fullAIPromptForConversation.Substring(0, [Math]::Min($fullAIPromptForConversation.Length, 500)))..."

        Write-Host "--- Starting AI Conversation ($aiExecutable)... ---" -ForegroundColor DarkCyan
        $PreviousOutputEncoding = $OutputEncoding # Store current $OutputEncoding
        $OutputEncoding = [System.Text.Encoding]::UTF8 # Set for piping
        $ConsoleOutputEncoding = [Console]::OutputEncoding # Store current Console encoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 # Set for external process output
        try {
            # Pipe the prompt to the AI executable's standard input
            $fullAIPromptForConversation | & $aiExecutable
            Write-Verbose "Invoke-Console2AiConversation: AI executable exited."
            Write-Host "--- AI Conversation Ended ---" -ForegroundColor DarkCyan
        } catch {
            Write-Error "Invoke-Console2AiConversation: Error executing AI chat '$aiExecutable'."
            Write-Error ($_.Exception.Message)
            Write-Host "--- AI session failed or ended with an error. ---" -ForegroundColor Red
        } finally {
            # Restore original encodings
            $OutputEncoding = $PreviousOutputEncoding
            [Console]::OutputEncoding = $ConsoleOutputEncoding
        }
    } finally {
        if ($Global:Console2Ai_TranscriptActive) {
            if (-not $TRANSCRIPT) {
                Write-Verbose "Invoke-Console2AiConversation: Transcript not running. Attempting to (re)start."
                try {
                    Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop | Out-Null
                    Write-Verbose "Invoke-Console2AiConversation: Ensured transcript '$transcriptPath' is active."
                } catch {
                    Write-Error "Invoke-Console2AiConversation: CRITICAL - Failed to (re)start transcript '$transcriptPath'! Error: $($_.Exception.Message)"
                    $Global:Console2Ai_TranscriptActive = $false
                }
            }
        } elseif ($transcriptWasStoppedByThisFunction -and -not $TRANSCRIPT) {
             Write-Warning "Invoke-Console2AiConversation: Transcript was stopped by this function but global flag indicates it shouldn't be active. Attempting restart anyway."
             try { Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop | Out-Null } catch { Write-Error "Invoke-Console2AiConversation: Failed to restart transcript that was stopped by function. Error: $($_.Exception.Message)" }
        }
    }
}

function Save-ConsoleHistoryLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesFromTranscript = 100,
        [Parameter(Mandatory=$false)] [string]$LogFilePath = ".\Console2Ai_ManualLog.txt"
    )
    Write-Verbose "Save-ConsoleHistoryLog: Attempting to save last $LinesFromTranscript lines from transcript to '$LogFilePath'."
    if (-not $Global:Console2Ai_TranscriptActive -or [string]::IsNullOrWhiteSpace($Global:Console2Ai_CurrentTranscriptPath)) {
        Write-Warning "Save-ConsoleHistoryLog: Transcript is not configured or active."
        return
    }

    $transcriptPath = $Global:Console2Ai_CurrentTranscriptPath
    $consoleHistory = ""
    $transcriptWasStoppedByThisFunction = $false

    try {
        if ($TRANSCRIPT) {
            try {
                Stop-Transcript -ErrorAction Stop
                $transcriptWasStoppedByThisFunction = $true
                Write-Verbose "Save-ConsoleHistoryLog: Stopped transcript '$transcriptPath' temporarily."
            } catch {
                Write-Warning "Save-ConsoleHistoryLog: Could not stop transcript. Error: $($_.Exception.Message)"
            }
        }

        if (Test-Path -Path $transcriptPath -PathType Leaf) {
            try {
                 if ($LinesFromTranscript -gt 0) {
                    $fileContentLines = Get-Content -Path $transcriptPath -ErrorAction Stop
                    $totalLinesInFile = $fileContentLines.Count
                    $startLineIndex = [Math]::Max(0, $totalLinesInFile - $LinesFromTranscript)
                    $consoleHistory = ($fileContentLines[$startLineIndex..($totalLinesInFile -1)]) -join [Environment]::NewLine
                } else {
                    $consoleHistory = Get-Content -Path $transcriptPath -Raw -ErrorAction Stop
                }

                 # Remove transcript command headers
                 $commandHeaderRegex = '(?m)^\*+\r?\nCommand start time: \d+\r?\n\*+\r?\n?'
                 $consoleHistory = $consoleHistory -replace $commandHeaderRegex, ''
                 Write-Verbose "Save-ConsoleHistoryLog: Removed transcript command headers before saving."

            } catch {
                Write-Error "Save-ConsoleHistoryLog: Failed to read transcript file '$transcriptPath'. Error: $($_.Exception.Message)"
                return
            }
        } else {
            Write-Warning "Save-ConsoleHistoryLog: Transcript file '$transcriptPath' not found."
            return
        }
        try {
            Set-Content -Path $LogFilePath -Value $consoleHistory -Encoding UTF8 -Force -ErrorAction Stop
            Write-Host "Save-ConsoleHistoryLog: Last $LinesFromTranscript lines (processed) from transcript saved to '$LogFilePath'." -ForegroundColor Green
        } catch {
            Write-Error "Save-ConsoleHistoryLog: Failed to save history to '$LogFilePath'."
            Write-Error $_.Exception.Message
        }
    } finally {
        if ($Global:Console2Ai_TranscriptActive) {
            if (-not $TRANSCRIPT) {
                Write-Verbose "Save-ConsoleHistoryLog: Transcript not running. Attempting to (re)start."
                try {
                    Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop | Out-Null
                    Write-Verbose "Save-ConsoleHistoryLog: Ensured transcript '$transcriptPath' is active."
                } catch {
                    Write-Error "Save-ConsoleHistoryLog: CRITICAL - Failed to (re)start transcript '$transcriptPath'! Error: $($_.Exception.Message)"
                    $Global:Console2Ai_TranscriptActive = $false
                }
            }
        } elseif ($transcriptWasStoppedByThisFunction -and -not $TRANSCRIPT) {
             Write-Warning "Save-ConsoleHistoryLog: Transcript was stopped by this function but global flag indicates it shouldn't be active. Attempting restart anyway."
             try { Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop | Out-Null } catch { Write-Error "Save-ConsoleHistoryLog: Failed to restart transcript that was stopped by function. Error: $($_.Exception.Message)" }
        }
    }
}
#endregion

# --- Initialization (Run on script load) ---
Write-Verbose "Console2Ai: Initializing..."
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$baseDir = $Global:Console2Ai_TranscriptBaseDir
if (-not (Test-Path -Path $baseDir -PathType Container)) {
    Write-Verbose "Console2Ai: Transcript base directory '$baseDir' does not exist. Attempting to create."
    try {
        New-Item -Path $baseDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Verbose "Console2Ai: Created transcript base directory '$baseDir'."
    } catch {
        Write-Error "Console2Ai: Failed to create transcript base directory '$baseDir'. Transcript functionality disabled. Error: $($_.Exception.Message)"
        return # Stop script execution if base dir fails
    }
}
Invoke-Console2AiTranscriptCleanup -ErrorAction SilentlyContinue
try {
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $uniqueFilename = "Console2Ai_Transcript_${timestamp}_PID$($PID).txt"
    $Global:Console2Ai_CurrentTranscriptPath = Join-Path $baseDir $uniqueFilename

    # Suppress the default "Transcript started..." message
    $ProgressPreference = 'SilentlyContinue' # Temporarily suppress progress for Start-Transcript
    Start-Transcript -Path $Global:Console2Ai_CurrentTranscriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop | Out-Null
    $ProgressPreference = 'Continue' # Restore preference

    $Global:Console2Ai_TranscriptActive = $true
    $shortLogName = Split-Path -Path $Global:Console2Ai_CurrentTranscriptPath -Leaf
    Write-Host "Console2Ai: Transcript active @ $shortLogName" -ForegroundColor Cyan
    Write-Verbose "Console2Ai: Transcript active flag set to true."
} catch {
    Write-Error "Console2Ai: Failed to start transcript '$($Global:Console2Ai_CurrentTranscriptPath)'. AI context will be unavailable. Error: $($_.Exception.Message)"
    $Global:Console2Ai_CurrentTranscriptPath = $null
    $Global:Console2Ai_TranscriptActive = $false
    $ProgressPreference = 'Continue' # Ensure preference is restored even on error
}
#endregion Initialization

# --- PSReadLine Hotkey Bindings ---
try {
    Write-Verbose "Console2Ai: Attempting to set PSReadLine key handlers..."
    Set-PSReadLineKeyHandler -Chord "alt+c" -ScriptBlock {
        param($key, $arg)
        $cmdLineStr = $null; $cursor = $null;
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$cmdLineStr, [ref]$cursor)

        $linesFromTranscript = $Global:Console2Ai_DefaultLinesFromTranscriptForHotkey
        $userPromptForAI = if ($null -ne $cmdLineStr) { $cmdLineStr.Trim() } else { "" }
        $lC = 0
        if (-not [string]::IsNullOrWhiteSpace($cmdLineStr)) {
            if ($cmdLineStr -match '^(\d{1,5})\s+(.+)$') {
                if ([int]::TryParse($matches[1],[ref]$lC) -and ($lC -ge 0 -and $lC -lt 100000)) {
                    $linesFromTranscript = $lC
                    $userPromptForAI = $matches[2].Trim()
                    Write-Verbose "Console2Ai (Alt+C): Parsed lines: $linesFromTranscript, prompt: '$userPromptForAI'"
                } else { Write-Verbose "Console2Ai (Alt+C): Invalid num in '$($matches[1])'. Using default lines."}
            } elseif ($cmdLineStr -match '^\d{1,5}$') {
                if ([int]::TryParse($cmdLineStr,[ref]$lC) -and ($lC -ge 0 -and $lC -lt 100000)) {
                    $linesFromTranscript = $lC
                    $userPromptForAI = "User provided only line count, analyze history for a command."
                    Write-Verbose "Console2Ai (Alt+C): Parsed lines: $linesFromTranscript, default prompt."
                } else { Write-Verbose "Console2Ai (Alt+C): Invalid num '$cmdLineStr'. Using default lines."}
            }
        }
        if ([string]::IsNullOrWhiteSpace($userPromptForAI)) { $userPromptForAI = "User did not provide a specific prompt, analyze history for a command." }

        $aiSuggestion = Invoke-AIConsoleHelp -LinesFromTranscript $linesFromTranscript -UserPrompt $userPromptForAI -ErrorAction SilentlyContinue

        if ($null -ne $aiSuggestion -and $aiSuggestion -notlike "ERROR:*") {
             [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
             [Microsoft.PowerShell.PSConsoleReadLine]::Insert($aiSuggestion)
        } elseif ($aiSuggestion -like "ERROR:*") {
            [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
            $errorMessage = "❌ Console2Ai (Cmd) Error: $aiSuggestion"
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($errorMessage)
        }
    }
    Set-PSReadLineKeyHandler -Chord "alt+s" -ScriptBlock {
        param($key, $arg)
        $commandLineStringFromRef = $null; $cursorOutputForRef = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$commandLineStringFromRef, [ref]$cursorOutputForRef)

        $linesFromTranscript = $Global:Console2Ai_DefaultLinesFromTranscriptForHotkey
        $userPromptForAI = if ($null -ne $commandLineStringFromRef) { $commandLineStringFromRef.Trim() } else { "" }
        $lC = 0
        if (-not [string]::IsNullOrWhiteSpace($commandLineStringFromRef)) {
            if ($commandLineStringFromRef -match '^(\d{1,5})\s+(.+)$') {
                if ([int]::TryParse($matches[1], [ref]$lC) -and ($lC -ge 0 -and $lC -lt 100000) ) {
                    $linesFromTranscript = $lC; $userPromptForAI = $matches[2].Trim()
                    Write-Verbose "Console2Ai (Alt+S): Parsed lines: $linesFromTranscript, prompt: '$userPromptForAI'"
                } else { Write-Verbose "Console2Ai (Alt+S): Invalid num in '$($matches[1])'. Using default lines."}
            } elseif ($commandLineStringFromRef -match '^\d{1,5}$') {
                if ([int]::TryParse($commandLineStringFromRef, [ref]$lC) -and ($lC -ge 0 -and $lC -lt 100000) ) {
                    $linesFromTranscript = $lC; $userPromptForAI = "User provided only line count. Please analyze history and respond generally."
                    Write-Verbose "Console2Ai (Alt+S): Parsed lines: $linesFromTranscript, default prompt."
                } else { Write-Verbose "Console2Ai (Alt+S): Invalid num '$commandLineStringFromRef'. Using default lines."}
            }
        }
        if ([string]::IsNullOrWhiteSpace($userPromptForAI)) { $userPromptForAI = "User's query is empty. Please analyze history and provide general assistance." }
        $escapedUserQuery = $userPromptForAI.Replace("'", "''") # Basic escaping for command line insertion
        # Use aliases in the generated command for consistency
        $commandToExecute = "Invoke-Console2AiConversation -UQ '$escapedUserQuery' -LTQ $linesFromTranscript"
        Write-Verbose "Console2Ai Hotkey (Alt+S): Inserting command: $commandToExecute"
        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($commandToExecute)
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
    Write-Verbose "Console2Ai: Hotkeys Alt+C (Command) and Alt+S (Conversation) registered successfully."
} catch {
    Write-Warning "Console2Ai: Failed to set PSReadLine key handlers. Hotkeys will not be available. Error: $($_.Exception.Message)"
}
#endregion PSReadLine Hotkey Bindings

Write-Verbose "Console2Ai: Script loaded."