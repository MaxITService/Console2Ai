#region Header and Configuration
# Script: Console2Ai.ps1
# Version: 3.0 (Production Ready - Transcript-based context)
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
$Global:Console2Ai_CommandMode_AIPromptInstruction = "Please analyze the following console history transcript (focus on the last {0} lines if specified, otherwise the recent activity). The user's specific request is: '{1}'. Identify any issues or the user's likely goal based on both history and request, and suggest a PowerShell command to help. If the user request is a direct command instruction, fulfill it using the history as context. Console History Transcript:"

# Configuration for Alt+S (Conversation Mode)
$Global:Console2Ai_ConversationMode_AIChatExecutable = $Global:Console2Ai_AIChatExecutable # Or specify a different one
$Global:Console2Ai_ConversationMode_AIPromptInstruction = "You are in a conversational chat. Please analyze the following console history transcript (focus on the last {0} lines if specified, otherwise the recent activity) as context. The user's current query is: '{1}'. Respond to the user's query, using the console history for context if relevant. Avoid suggesting a command unless explicitly asked or it's the most natural answer. Focus on explanation and direct answers. Console History Transcript:"

# Default number of lines *from the end of the transcript* to consider for hotkeys if not specified
$Global:Console2Ai_DefaultLinesFromTranscriptForHotkey = 200

# --- Transcript Configuration ---
# Base directory for storing transcript files
$Global:Console2Ai_TranscriptBaseDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) "Console2Ai\Transcripts"
# Max age in days for transcript files before cleanup
$Global:Console2Ai_TranscriptMaxAgeDays = 2
# Log file for recording transcript cleanup actions
$Global:Console2Ai_TranscriptCleanupLogFile = Join-Path ([Environment]::GetFolderPath('UserProfile')) "Console2Ai\Logs\TranscriptCleanup.log"

# --- Internal State ---
# Path to the active transcript file for the current session (set during initialization)
$Global:Console2Ai_CurrentTranscriptPath = $null
# Flag to track if transcript was successfully started for this session
$Global:Console2Ai_TranscriptActive = $false

#endregion Header and Configuration

# --- Transcript Management Functions ---

<#
.SYNOPSIS
  Cleans up old Console2Ai transcript files.
.DESCRIPTION
  This internal function checks the transcript directory for files older than the
  configured maximum age and deletes them. Deletion actions (success or failure)
  are logged to the specified cleanup log file.
.NOTES
  Called automatically during script initialization. Uses global configuration variables.
#>
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
            $logFile = $null # Disable logging if directory fails
        }
    }

    $cutoffDate = (Get-Date).AddDays(-$maxDays)
    Write-Verbose "Console2Ai: Cleaning transcripts older than $cutoffDate in '$baseDir'."

    try {
        $filesToClean = Get-ChildItem -Path $baseDir -Filter "Console2Ai_Transcript_*.txt" -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cutoffDate }

        if ($null -eq $filesToClean -or $filesToClean.Count -eq 0) {
            Write-Verbose "Console2Ai: No old transcript files found to clean."
            return
        }

        foreach ($file in $filesToClean) {
            $logTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $logMessagePrefix = "$logTimestamp - Attempting to delete old transcript '$($file.FullName)' (LastWrite: $($file.LastWriteTime)):"
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                Write-Verbose "Console2Ai: Deleted old transcript: $($file.FullName)"
                if ($logFile) { Add-Content -Path $logFile -Value "$logMessagePrefix Success" -Encoding UTF8 }
            } catch {
                Write-Warning "Console2Ai: Failed to delete old transcript '$($file.FullName)'. Error: $($_.Exception.Message)"
                if ($logFile) { Add-Content -Path $logFile -Value "$logMessagePrefix FAILED - Error: $($_.Exception.Message)" -Encoding UTF8 }
            }
        }
    } catch {
        Write-Warning "Console2Ai: Error during transcript cleanup process: $($_.Exception.Message)"
        if ($logFile) { Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR during cleanup: $($_.Exception.Message)" -Encoding UTF8 }
    }
    Write-Verbose "Console2Ai: Transcript cleanup finished."
}

# --- Core AI Interaction Functions (Transcript-Aware) ---

<#
.SYNOPSIS
  Captures recent console transcript content and sends it to an AI chat for assistance, expecting a command suggestion.
.DESCRIPTION
  This function temporarily stops transcription, reads content from the current session's
  transcript file, formats it with a user prompt for an AI assistant, and executes the AI tool.
  The AI is instructed to analyze the transcript history and suggest a relevant PowerShell command.
  Transcription is automatically restarted afterwards.
.PARAMETER LinesFromTranscript
  The number of lines from the *end* of the transcript to provide as context. Defaults to global config. -1 means attempt to read the whole file (can be large).
.PARAMETER UserPrompt
  Optional additional text to guide the AI.
.PARAMETER AIChatExecutable
  The path or name of the AI chat executable. Defaults to the global configuration.
.PARAMETER AIPromptInstruction
  The instructional text for the AI. Defaults to the global command mode configuration.
.OUTPUTS
  System.String
  The AI's suggested command or response. Returns an error message string on failure.
.NOTES
  This function is typically used by the Alt+C hotkey. It handles transcript stop/start.
#>
function Invoke-AIConsoleHelp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesFromTranscript = $Global:Console2Ai_DefaultLinesFromTranscriptForHotkey,
        [Parameter(Mandatory=$false)] [string]$UserPrompt = "User did not provide a specific prompt, analyze history for a command.",
        [Parameter(Mandatory=$false)] [string]$AIChatExecutable = $Global:Console2Ai_CommandMode_AIChatExecutable,
        [Parameter(Mandatory=$false)] [string]$AIPromptInstruction = $Global:Console2Ai_CommandMode_AIPromptInstruction
    )

    Write-Verbose "Invoke-AIConsoleHelp: Preparing to get transcript context for AI command suggestion."

    if (-not $Global:Console2Ai_TranscriptActive -or [string]::IsNullOrWhiteSpace($Global:Console2Ai_CurrentTranscriptPath)) {
        Write-Warning "Invoke-AIConsoleHelp: Transcript does not appear to be active or path is missing for this session."
        return "ERROR: Transcript not active or path unknown."
    }

    $transcriptPath = $Global:Console2Ai_CurrentTranscriptPath
    $consoleHistory = ""
    $transcriptWasRunning = $false
    $aiResult = "ERROR: AI execution did not produce a result." # Default error

    # Display status message using PSReadLine *before* stopping transcript
    $currentLine = $null; $currentCursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currentLine, [ref]$currentCursor)
    [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("Invoke-AIConsoleHelp: Reading transcript & sending to AI ($AIChatExecutable)...")

    try {
        # --- Stop Transcript & Read Content ---
        try {
            Get-Transcript # Check if running, throws if not
            Stop-Transcript -ErrorAction Stop
            $transcriptWasRunning = $true
            Write-Verbose "Invoke-AIConsoleHelp: Stopped transcript '$transcriptPath' temporarily."
        } catch {
            # Transcript wasn't running (unexpected) or error stopping. Log it.
            Write-Warning "Invoke-AIConsoleHelp: Could not stop transcript (might not have been running). Attempting to read file anyway. Error: $($_.Exception.Message)"
            $transcriptWasRunning = $false # Assume it wasn't running if we hit an error here
        }

        if (Test-Path -Path $transcriptPath -PathType Leaf) {
            try {
                if ($LinesFromTranscript -gt 0) {
                    Write-Verbose "Invoke-AIConsoleHelp: Reading last $LinesFromTranscript lines from '$transcriptPath'."
                    # Use -TotalCount for efficiency if available, otherwise fallback
                    if ((Get-Command Get-Content).Parameters.ContainsKey('Tail')) {
                         $consoleHistory = (Get-Content -Path $transcriptPath -Tail $LinesFromTranscript -Raw -ErrorAction Stop)
                    } else {
                         # Fallback for older PowerShell versions
                         $allLines = Get-Content -Path $transcriptPath -ReadCount 0 -ErrorAction Stop
                         $startLine = [Math]::Max(0, $allLines.Count - $LinesFromTranscript)
                         $consoleHistory = ($allLines[$startLine..($allLines.Count - 1)]) -join [Environment]::NewLine
                    }

                } else {
                    Write-Verbose "Invoke-AIConsoleHelp: Reading entire transcript '$transcriptPath'."
                    $consoleHistory = Get-Content -Path $transcriptPath -Raw -ErrorAction Stop
                }
                Write-Verbose "Invoke-AIConsoleHelp: Read $($consoleHistory.Length) characters from transcript."
            } catch {
                Write-Error "Invoke-AIConsoleHelp: Failed to read transcript file '$transcriptPath'. Error: $($_.Exception.Message)"
                $consoleHistory = "" # Ensure empty string on read failure
            }
        } else {
            Write-Warning "Invoke-AIConsoleHelp: Transcript file '$transcriptPath' not found."
            $consoleHistory = ""
        }

        # --- Prepare and Execute AI ---
        if ([string]::IsNullOrWhiteSpace($consoleHistory)) {
            Write-Warning "Invoke-AIConsoleHelp: No transcript history captured. AI might lack context."
        }

        $linesCountForPrompt = if ($LinesFromTranscript -gt 0) { $LinesFromTranscript } else { "all available" }
        $formattedInstruction = $AIPromptInstruction -f $linesCountForPrompt, $UserPrompt
        $fullAIPrompt = "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory"
        $fullAIPrompt = $fullAIPrompt.TrimEnd()

        Write-Verbose "Invoke-AIConsoleHelp: Full prompt for AI ($($fullAIPrompt.Length) chars): `n$($fullAIPrompt.Substring(0, [Math]::Min($fullAIPrompt.Length, 500)))..." # Log beginning of prompt

        # Ensure UTF-8 output for the AI process
        $PreviousOutputEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        try {
            # Execute the AI command and capture the output
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
        # --- Restart Transcript ---
        if ($transcriptWasRunning) {
            try {
                Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop
                Write-Verbose "Invoke-AIConsoleHelp: Restarted transcript '$transcriptPath'."
            } catch {
                Write-Error "Invoke-AIConsoleHelp: CRITICAL - Failed to restart transcript '$transcriptPath'! Manual restart might be needed. Error: $($_.Exception.Message)"
                $Global:Console2Ai_TranscriptActive = $false # Mark as inactive if restart fails
            }
        }

        # --- Restore PSReadLine State ---
        # Clear the status message
        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
        # Restore original line or insert result
        if ($currentLine -ne $null) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($currentLine)
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($currentCursor)
        }
    }

    # Return the AI result (which might be an error string)
    return $aiResult
}


<#
.SYNOPSIS
  Initiates a conversational AI session using console transcript history as context.
.DESCRIPTION
  This function is called by the Alt+S hotkey. It temporarily stops transcription,
  gathers the user's query and transcript history, formats a prompt for conversational AI,
  displays feedback, and then launches the AI executable, piping the prompt to its standard input.
  The AI executable takes over the console. Transcription is restarted when the AI exits.
.PARAMETER UserQuery
  The query typed by the user.
.PARAMETER LinesFromTranscript
  The number of console transcript lines from the end to include as context.
.NOTES
  This function handles transcript stop/start around the AI execution.
#>
function Invoke-Console2AiConversation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$UserQuery,

        [Parameter(Mandatory=$true)]
        [int]$LinesFromTranscript
    )

    Write-Verbose "Invoke-Console2AiConversation: Preparing transcript context for conversational AI."

    if (-not $Global:Console2Ai_TranscriptActive -or [string]::IsNullOrWhiteSpace($Global:Console2Ai_CurrentTranscriptPath)) {
        Write-Error "Invoke-Console2AiConversation: Transcript does not appear to be active or path is missing for this session."
        # Write directly to host as AI won't run
        Write-Host "--- ERROR: Transcript not active. Cannot start AI conversation. ---" -ForegroundColor Red
        return
    }

    $transcriptPath = $Global:Console2Ai_CurrentTranscriptPath
    $consoleHistory = ""
    $transcriptWasRunning = $false
    $aiExecutable = $Global:Console2Ai_ConversationMode_AIChatExecutable

    try {
        # --- Stop Transcript & Read Content ---
        try {
            Get-Transcript # Check if running
            Stop-Transcript -ErrorAction Stop
            $transcriptWasRunning = $true
            Write-Verbose "Invoke-Console2AiConversation: Stopped transcript '$transcriptPath' temporarily."
        } catch {
            Write-Warning "Invoke-Console2AiConversation: Could not stop transcript (might not have been running). Attempting to read file anyway. Error: $($_.Exception.Message)"
            $transcriptWasRunning = $false
        }

        if (Test-Path -Path $transcriptPath -PathType Leaf) {
            try {
                 if ($LinesFromTranscript -gt 0) {
                    Write-Verbose "Invoke-Console2AiConversation: Reading last $LinesFromTranscript lines from '$transcriptPath'."
                     if ((Get-Command Get-Content).Parameters.ContainsKey('Tail')) {
                         $consoleHistory = (Get-Content -Path $transcriptPath -Tail $LinesFromTranscript -Raw -ErrorAction Stop)
                     } else {
                         $allLines = Get-Content -Path $transcriptPath -ReadCount 0 -ErrorAction Stop
                         $startLine = [Math]::Max(0, $allLines.Count - $LinesFromTranscript)
                         $consoleHistory = ($allLines[$startLine..($allLines.Count - 1)]) -join [Environment]::NewLine
                     }
                } else {
                    Write-Verbose "Invoke-Console2AiConversation: Reading entire transcript '$transcriptPath'."
                    $consoleHistory = Get-Content -Path $transcriptPath -Raw -ErrorAction Stop
                }
                 Write-Verbose "Invoke-Console2AiConversation: Read $($consoleHistory.Length) characters from transcript."
            } catch {
                Write-Error "Invoke-Console2AiConversation: Failed to read transcript file '$transcriptPath'. Error: $($_.Exception.Message)"
                $consoleHistory = ""
            }
        } else {
            Write-Warning "Invoke-Console2AiConversation: Transcript file '$transcriptPath' not found."
            $consoleHistory = ""
        }

        # --- Prepare Prompt and Execute AI ---
        if ([string]::IsNullOrWhiteSpace($consoleHistory)) {
             Write-Warning "Invoke-Console2AiConversation: No transcript history captured. AI might lack context."
        }

        $linesCountForPrompt = if ($LinesFromTranscript -gt 0) { $LinesFromTranscript } else { "all available" }
        $formattedInstruction = $Global:Console2Ai_ConversationMode_AIPromptInstruction -f $linesCountForPrompt, $UserQuery
        $fullAIPromptForConversation = if ([string]::IsNullOrWhiteSpace($consoleHistory)) { $formattedInstruction } else { "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory" }
        $fullAIPromptForConversation = $fullAIPromptForConversation.TrimEnd()

        Write-Verbose "Invoke-Console2AiConversation: Full prompt for AI (stdin, $($fullAIPromptForConversation.Length) chars): `n$($fullAIPromptForConversation.Substring(0, [Math]::Min($fullAIPromptForConversation.Length, 500)))..."

        # Display concise feedback before launching AI
        Write-Host "--- Starting AI Conversation ($aiExecutable)... ---" -ForegroundColor DarkCyan
        # AI tool will typically clear screen or print its own header

        $PreviousOutputEncoding = $OutputEncoding # Store current pipeline encoding
        $OutputEncoding = [System.Text.Encoding]::UTF8 # Ensure pipeline uses UTF8 for stdin
        $ConsoleOutputEncoding = [Console]::OutputEncoding # Store console encoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 # Ensure console uses UTF8 for AI output

        try {
            # Pipe the prompt directly to the executable's standard input
            $fullAIPromptForConversation | & $aiExecutable
            Write-Verbose "Invoke-Console2AiConversation: AI executable exited."
            # Add a separator after the AI finishes cleanly
            Write-Host "--- AI Conversation Ended ---" -ForegroundColor DarkCyan

        } catch {
            Write-Error "Invoke-Console2AiConversation: Error executing AI chat '$aiExecutable'."
            Write-Error ($_.Exception.Message)
            Write-Host "--- AI session failed or ended with an error. ---" -ForegroundColor Red
        } finally {
            # Restore encodings
            $OutputEncoding = $PreviousOutputEncoding
            [Console]::OutputEncoding = $ConsoleOutputEncoding
        }

    } finally {
        # --- Restart Transcript ---
        if ($transcriptWasRunning) {
            try {
                Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop
                Write-Verbose "Invoke-Console2AiConversation: Restarted transcript '$transcriptPath'."
            } catch {
                Write-Error "Invoke-Console2AiConversation: CRITICAL - Failed to restart transcript '$transcriptPath'! Manual restart might be needed. Error: $($_.Exception.Message)"
                $Global:Console2Ai_TranscriptActive = $false # Mark as inactive
            }
        }
        # The next PowerShell prompt will provide visual separation after the AI session.
    }
}

# --- Deprecated/Optional Function: Save-ConsoleHistoryLog ---
<#
.SYNOPSIS
  Saves recent console transcript output to a separate log file.
.DESCRIPTION
  This function reads a specified number of lines from the end of the current session's
  transcript file and saves this text to a specified log file. Transcription is
  briefly paused and restarted during this process.
.PARAMETER LinesFromTranscript
  The number of lines from the end of the transcript to save. Defaults to 100.
.PARAMETER LogFilePath
  The path to the log file where the transcript excerpt will be saved. Defaults to ".\Console2Ai_ManualLog.txt".
.EXAMPLE
  Save-ConsoleHistoryLog -LinesFromTranscript 50 -LogFilePath "C:\temp\my_session_log.txt"
.NOTES
  The primary log is the transcript file itself. This provides a way to snapshot recent activity.
#>
function Save-ConsoleHistoryLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesFromTranscript = 100,
        [Parameter(Mandatory=$false)] [string]$LogFilePath = ".\Console2Ai_ManualLog.txt"
    )
    Write-Verbose "Save-ConsoleHistoryLog: Attempting to save last $LinesFromTranscript lines from transcript to '$LogFilePath'."

    if (-not $Global:Console2Ai_TranscriptActive -or [string]::IsNullOrWhiteSpace($Global:Console2Ai_CurrentTranscriptPath)) {
        Write-Warning "Save-ConsoleHistoryLog: Transcript does not appear to be active or path is missing."
        return
    }

    $transcriptPath = $Global:Console2Ai_CurrentTranscriptPath
    $consoleHistory = ""
    $transcriptWasRunning = $false

    try {
         # --- Stop Transcript & Read Content ---
        try {
            Get-Transcript # Check if running
            Stop-Transcript -ErrorAction Stop
            $transcriptWasRunning = $true
            Write-Verbose "Save-ConsoleHistoryLog: Stopped transcript '$transcriptPath' temporarily."
        } catch {
            Write-Warning "Save-ConsoleHistoryLog: Could not stop transcript (might not have been running). Error: $($_.Exception.Message)"
            $transcriptWasRunning = $false
        }

        if (Test-Path -Path $transcriptPath -PathType Leaf) {
            try {
                 if ($LinesFromTranscript -gt 0) {
                     if ((Get-Command Get-Content).Parameters.ContainsKey('Tail')) {
                         $consoleHistory = (Get-Content -Path $transcriptPath -Tail $LinesFromTranscript -Raw -ErrorAction Stop)
                     } else {
                         $allLines = Get-Content -Path $transcriptPath -ReadCount 0 -ErrorAction Stop
                         $startLine = [Math]::Max(0, $allLines.Count - $LinesFromTranscript)
                         $consoleHistory = ($allLines[$startLine..($allLines.Count - 1)]) -join [Environment]::NewLine
                     }
                } else { # Should not happen with default, but handle -1 or 0
                    $consoleHistory = Get-Content -Path $transcriptPath -Raw -ErrorAction Stop
                }
            } catch {
                Write-Error "Save-ConsoleHistoryLog: Failed to read transcript file '$transcriptPath'. Error: $($_.Exception.Message)"
                # Do not proceed to save if read failed
                return
            }
        } else {
            Write-Warning "Save-ConsoleHistoryLog: Transcript file '$transcriptPath' not found."
             # Do not proceed to save if file not found
            return
        }

        # --- Save Content ---
        try {
            Set-Content -Path $LogFilePath -Value $consoleHistory -Encoding UTF8 -Force -ErrorAction Stop
            Write-Host "Save-ConsoleHistoryLog: Last $LinesFromTranscript lines (or available history) from transcript saved to '$LogFilePath'." -ForegroundColor Green
        } catch {
            Write-Error "Save-ConsoleHistoryLog: Failed to save transcript history to '$LogFilePath'."
            Write-Error $_.Exception.Message
        }

    } finally {
         # --- Restart Transcript ---
        if ($transcriptWasRunning) {
            try {
                Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop
                Write-Verbose "Save-ConsoleHistoryLog: Restarted transcript '$transcriptPath'."
            } catch {
                Write-Error "Save-ConsoleHistoryLog: CRITICAL - Failed to restart transcript '$transcriptPath'! Manual restart might be needed. Error: $($_.Exception.Message)"
                $Global:Console2Ai_TranscriptActive = $false # Mark as inactive
            }
        }
    }
}
#endregion

# --- Initialization (Run on script load) ---
Write-Verbose "Console2Ai: Initializing..."
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 1. Ensure Base Transcript Directory Exists
$baseDir = $Global:Console2Ai_TranscriptBaseDir
if (-not (Test-Path -Path $baseDir -PathType Container)) {
    Write-Verbose "Console2Ai: Transcript base directory '$baseDir' does not exist. Attempting to create."
    try {
        New-Item -Path $baseDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Verbose "Console2Ai: Created transcript base directory '$baseDir'."
    } catch {
        Write-Error "Console2Ai: Failed to create transcript base directory '$baseDir'. Transcript functionality disabled. Error: $($_.Exception.Message)"
        # Do not proceed with transcript start if base dir fails
        return # Stop further initialization related to transcripts
    }
}

# 2. Run Transcript Cleanup
Invoke-Console2AiTranscriptCleanup -ErrorAction SilentlyContinue # Log errors internally

# 3. Start New Transcript for this Session
try {
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $uniqueFilename = "Console2Ai_Transcript_${timestamp}_PID$($PID).txt"
    $Global:Console2Ai_CurrentTranscriptPath = Join-Path $baseDir $uniqueFilename

    Start-Transcript -Path $Global:Console2Ai_CurrentTranscriptPath -Append -IncludeInvocationHeader -Force -ErrorAction Stop
    $Global:Console2Ai_TranscriptActive = $true
    Write-Host "Console2Ai: Transcript started for this session: $($Global:Console2Ai_CurrentTranscriptPath)" -ForegroundColor Cyan
    Write-Verbose "Console2Ai: Transcript active flag set to true."

} catch {
    Write-Error "Console2Ai: Failed to start transcript '$($Global:Console2Ai_CurrentTranscriptPath)'. AI context will be unavailable. Error: $($_.Exception.Message)"
    $Global:Console2Ai_CurrentTranscriptPath = $null # Ensure path is null if start failed
    $Global:Console2Ai_TranscriptActive = $false
}

#endregion Initialization

# --- PSReadLine Hotkey Bindings ---
try {
    Write-Verbose "Console2Ai: Attempting to set PSReadLine key handlers..."

    # --- Alt+C: AI Command Suggestion Hotkey ---
    Set-PSReadLineKeyHandler -Chord "alt+c" -ScriptBlock {
        param($key, $arg)
        $cmdLineStr = $null; $cursor = $null;
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$cmdLineStr, [ref]$cursor)

        $linesFromTranscript = $Global:Console2Ai_DefaultLinesFromTranscriptForHotkey
        $userPromptForAI = if ($null -ne $cmdLineStr) { $cmdLineStr.Trim() } else { "" }
        $lC = 0 # Declare $lC for TryParse [ref]

        # Parse input like "<num_lines> <prompt>" or just "<num_lines>"
        if (-not [string]::IsNullOrWhiteSpace($cmdLineStr)) {
            if ($cmdLineStr -match '^(\d{1,5})\s+(.+)$') { # Number followed by text (increased max lines)
                if ([int]::TryParse($matches[1],[ref]$lC) -and ($lC -gt 0 -and $lC -lt 100000)) {
                    $linesFromTranscript = $lC; $userPromptForAI = $matches[2].Trim()
                    Write-Verbose "Console2Ai (Alt+C): Parsed $linesFromTranscript lines from transcript, prompt: '$userPromptForAI'"
                } else { Write-Verbose "Console2Ai (Alt+C): Invalid num in '$($matches[1])'. Using default lines."}
            } elseif ($cmdLineStr -match '^\d{1,5}$') { # Only a number
                if ([int]::TryParse($cmdLineStr,[ref]$lC) -and ($lC -gt 0 -and $lC -lt 100000)) {
                    $linesFromTranscript = $lC; $userPromptForAI = "User provided only line count, analyze history for a command."
                    Write-Verbose "Console2Ai (Alt+C): Parsed $linesFromTranscript lines from transcript, default prompt."
                } else { Write-Verbose "Console2Ai (Alt+C): Invalid num '$cmdLineStr'. Using default lines."}
            }
            # If neither pattern matched, $userPromptForAI remains the full $cmdLineStr
        }

        if ([string]::IsNullOrWhiteSpace($userPromptForAI)) { $userPromptForAI = "User did not provide a specific prompt, analyze history for a command." }

        # Call the main function (handles status messages, transcript stop/start, AI call)
        $aiSuggestion = Invoke-AIConsoleHelp -LinesFromTranscript $linesFromTranscript -UserPrompt $userPromptForAI -ErrorAction SilentlyContinue

        # Check if we have a meaningful result (Invoke-AIConsoleHelp handles restoring the line)
        if ($null -ne $aiSuggestion -and $aiSuggestion -notlike "ERROR:*") {
             # Clear the original prompt line that was restored by Invoke-AIConsoleHelp
             [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
             # Insert the AI suggestion
             [Microsoft.PowerShell.PSConsoleReadLine]::Insert($aiSuggestion)
        } elseif ($aiSuggestion -like "ERROR:*") {
            # Clear the original prompt line that was restored by Invoke-AIConsoleHelp
            [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
            # Insert error message
            $errorMessage = "❌ Console2Ai (Cmd) Error: $aiSuggestion"
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($errorMessage)
        }
        # If $aiSuggestion is null or empty (unexpected), the original line remains.
    }

    # --- Alt+S: AI Conversation Mode Hotkey ---
    Set-PSReadLineKeyHandler -Chord "alt+s" -ScriptBlock {
        param($key, $arg)

        $commandLineStringFromRef = $null; $cursorOutputForRef = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$commandLineStringFromRef, [ref]$cursorOutputForRef)

        $linesFromTranscript = $Global:Console2Ai_DefaultLinesFromTranscriptForHotkey
        $userPromptForAI = if ($null -ne $commandLineStringFromRef) { $commandLineStringFromRef.Trim() } else { "" }
        $lC = 0 # Declare $lC for TryParse [ref]

        # Parse input like "<num_lines> <prompt>" or just "<num_lines>"
        if (-not [string]::IsNullOrWhiteSpace($commandLineStringFromRef)) {
            if ($commandLineStringFromRef -match '^(\d{1,5})\s+(.+)$') { # Number followed by text
                if ([int]::TryParse($matches[1], [ref]$lC) -and ($lC -gt 0 -and $lC -lt 100000) ) {
                    $linesFromTranscript = $lC; $userPromptForAI = $matches[2].Trim()
                    Write-Verbose "Console2Ai (Alt+S): Parsed $linesFromTranscript lines from transcript, prompt: '$userPromptForAI'"
                } else { Write-Verbose "Console2Ai (Alt+S): Invalid num in '$($matches[1])'. Using default lines."}
            } elseif ($commandLineStringFromRef -match '^\d{1,5}$') { # Only a number
                if ([int]::TryParse($commandLineStringFromRef, [ref]$lC) -and ($lC -gt 0 -and $lC -lt 100000) ) {
                    $linesFromTranscript = $lC; $userPromptForAI = "User provided only line count. Please analyze history and respond generally."
                    Write-Verbose "Console2Ai (Alt+S): Parsed $linesFromTranscript lines from transcript, default prompt."
                } else { Write-Verbose "Console2Ai (Alt+S): Invalid num '$commandLineStringFromRef'. Using default lines."}
            }
             # If neither pattern matched, $userPromptForAI remains the full $commandLineStringFromRef
        }

        if ([string]::IsNullOrWhiteSpace($userPromptForAI)) { $userPromptForAI = "User's query is empty. Please analyze history and provide general assistance." }

        # Escape single quotes in the user query for the command string
        $escapedUserQuery = $userPromptForAI.Replace("'", "''")
        # Construct the command to execute Invoke-Console2AiConversation
        $commandToExecute = "Invoke-Console2AiConversation -UserQuery '$escapedUserQuery' -LinesFromTranscript $linesFromTranscript"

        Write-Verbose "Console2Ai Hotkey (Alt+S): Inserting command: $commandToExecute"

        # Replace the current line with the command and execute it
        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($commandToExecute)
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine() # Execute the inserted command
    }

    Write-Verbose "Console2Ai: Hotkeys Alt+C (Command) and Alt+S (Conversation) registered successfully."

} catch {
    Write-Warning "Console2Ai: Failed to set PSReadLine key handlers. Hotkeys will not be available. Error: $($_.Exception.Message)"
}
#endregion PSReadLine Hotkey Bindings

Write-Verbose "Console2Ai: Script loaded."