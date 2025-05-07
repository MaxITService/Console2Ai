#region Header and Configuration
# Script: Console2Ai.ps1
# Version: 2.4 (Production Ready - Corrected PSReadLine capture for both hotkeys)
# Author: [Your Name/Handle Here]
# Description: Provides functions to capture console history and send it to an AI
#              for assistance (command or conversation mode), or save it to a log.
#              Includes Alt+C hotkey for quick AI command suggestions and
#              Alt+S hotkey for conversational AI interaction.

# --- User Configuration ---
# Place these at the top for easy editing.

# Executable for the AI chat tool
$Global:Console2Ai_AIChatExecutable = "aichat.exe" # Used by both modes unless overridden below

# Configuration for Alt+C (Command Mode)
$Global:Console2Ai_CommandMode_AIChatExecutable = $Global:Console2Ai_AIChatExecutable # Or specify a different one
$Global:Console2Ai_CommandMode_AIPromptInstruction = "Please analyze the following console history (last {0} lines). The user's specific request is: '{1}'. Identify any issues or the user's likely goal based on both history and request, and suggest a single, concise PowerShell command to help. If the user request is a direct command instruction, fulfill it using the history as context. Console History:"

# Configuration for Alt+S (Conversation Mode)
$Global:Console2Ai_ConversationMode_AIChatExecutable = $Global:Console2Ai_AIChatExecutable # Or specify a different one
$Global:Console2Ai_ConversationMode_AIPromptInstruction = "You are in a conversational chat. Please analyze the following console history (last {0} lines) as context. The user's current query is: '{1}'. Respond to the user's query, using the console history for context if relevant. Avoid suggesting a command unless explicitly asked or it's the most natural answer. Focus on explanation and direct answers. Console History:"

# Default number of lines to capture for hotkeys if not specified in the prompt
$Global:Console2Ai_DefaultLinesToCaptureForHotkey = 15

#endregion Header and Configuration

# --- Helper Function: Get-ConsoleTextAbovePrompt ---
# (This function remains unchanged from v2.3 - it's already good)
function Get-ConsoleTextAbovePrompt {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [int]$LinesToCapture = 15, 
        [Parameter(Mandatory=$false)]
        [int]$CaptureWidth = -1 
    )
    $rawUI = $Host.UI.RawUI
    $cursorPos = $rawUI.CursorPosition
    $bufferSize = $rawUI.BufferSize
    $targetTopY = $cursorPos.Y - $LinesToCapture
    $actualTopY = [Math]::Max(0, $targetTopY)
    $actualBottomY = $cursorPos.Y - 1
    if ($cursorPos.Y -eq 0 -or $LinesToCapture -le 0 -or $actualTopY -gt $actualBottomY) {
        Write-Verbose "Get-ConsoleTextAbovePrompt: No lines to capture (CursorY=$($cursorPos.Y), LinesToCapture=$LinesToCapture, actualTopY=$actualTopY, actualBottomY=$actualBottomY)."
        return ""
    }
    $actualLeftX = 0
    $resolvedCaptureWidth = if ($CaptureWidth -lt 0 -or $CaptureWidth -gt $bufferSize.Width) { $bufferSize.Width } else { $CaptureWidth }
    $actualRightX = $actualLeftX + $resolvedCaptureWidth - 1
    $actualRightX = [Math]::Min($actualRightX, $bufferSize.Width - 1)
    if ($actualRightX -lt $actualLeftX -or $bufferSize.Width -eq 0) {
         Write-Verbose "Get-ConsoleTextAbovePrompt: Invalid capture width (Left=$actualLeftX, Right=$actualRightX, BufferWidth=$($bufferSize.Width), ResolvedCaptureWidth=$resolvedCaptureWidth). Nothing to capture."
        return ""
    }
    $rectangle = New-Object System.Management.Automation.Host.Rectangle $actualLeftX, $actualTopY, $actualRightX, $actualBottomY
    Write-Verbose "Get-ConsoleTextAbovePrompt: Capture parameters: Cursor(Y)=$($cursorPos.Y). Rect: L=$actualLeftX, T=$actualTopY, R=$actualRightX, B=$actualBottomY. BufferWidth: $($bufferSize.Width)"
    try { $bufferCells = $rawUI.GetBufferContents($rectangle) } catch { Write-Error "Get-ConsoleTextAbovePrompt: Error capturing buffer: $($_.Exception.Message)"; return "" }
    if ($null -eq $bufferCells) { Write-Verbose "Get-ConsoleTextAbovePrompt: GetBufferContents returned null."; return "" }
    $capturedTextBuilder = [System.Text.StringBuilder]::new()
    for ($row = 0; $row -lt $bufferCells.GetLength(0); $row++) {
        for ($col = 0; $col -lt $bufferCells.GetLength(1); $col++) { [void]$capturedTextBuilder.Append($bufferCells[$row, $col].Character) }
        if ($row -lt ($bufferCells.GetLength(0) - 1)) { [void]$capturedTextBuilder.Append([Environment]::NewLine) }
    }
    return $capturedTextBuilder.ToString().TrimEnd()
}

# --- Main Function 1: Invoke-AIConsoleHelp ---
# (This function remains unchanged from v2.3 - it's for programmatic use, not direct hotkey use)
function Invoke-AIConsoleHelp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesToCapture = 15,
        [Parameter(Mandatory=$false)] [string]$UserPrompt = "User did not provide a specific prompt, analyze history.",
        [Parameter(Mandatory=$false)] [string]$AIChatExecutable = "aichat.exe",
        [Parameter(Mandatory=$false)] [string]$AIPromptInstruction = "Please analyze the following console history (last {0} lines). The user's specific request is: '{1}'. Identify any issues or the user's likely goal based on both history and request, and suggest a single, concise PowerShell command to help. If the user request is a direct command instruction, fulfill it using the history as context. Console History:"
    )
    Write-Verbose "Invoke-AIConsoleHelp: Capturing $LinesToCapture lines."
    $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $LinesToCapture -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($consoleHistory)) { Write-Warning "Invoke-AIConsoleHelp: No console history captured." }
    $formattedInstruction = $AIPromptInstruction -f $LinesToCapture, $UserPrompt
    $fullAIPrompt = "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory"
    Write-Verbose "Invoke-AIConsoleHelp: Full prompt for AI: `n$fullAIPrompt"
    Write-Host "Invoke-AIConsoleHelp: Sending to AI ($AIChatExecutable)..."
    try { & $AIChatExecutable -e $fullAIPrompt } catch { Write-Error "Invoke-AIConsoleHelp: Failed to execute AI: $($_.Exception.Message)" }
}

# --- Main Function 2: Save-ConsoleHistoryLog ---
# (This function remains unchanged from v2.3)
function Save-ConsoleHistoryLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesToCapture = 15,
        [Parameter(Mandatory=$false)] [string]$LogFilePath = ".\log.txt"
    )
    Write-Verbose "Save-ConsoleHistoryLog: Capturing $LinesToCapture lines to '$LogFilePath'."
    $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $LinesToCapture -ErrorAction SilentlyContinue
    if ($null -eq $consoleHistory) { $consoleHistory = "" } 
    elseif ([string]::IsNullOrWhiteSpace($consoleHistory) -and $consoleHistory.Length -gt 0) { Write-Warning "Save-ConsoleHistoryLog: Captured history is whitespace only." }
    elseif ($consoleHistory.Length -eq 0) { Write-Warning "Save-ConsoleHistoryLog: Captured history is empty." }
    try { Set-Content -Path $LogFilePath -Value $consoleHistory -Encoding UTF8 -Force; Write-Host "Save-ConsoleHistoryLog: Saved to '$LogFilePath'." } catch { Write-Error "Save-ConsoleHistoryLog: Failed to save: $($_.Exception.Message)" }
}


# --- PSReadLine Hotkey Bindings ---
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # --- Alt+C: AI Command Suggestion Hotkey ---
    Set-PSReadLineKeyHandler -Chord "alt+c" -ScriptBlock {
        param($key, $arg)

        # Get current typed line using the reliable method
        $commandLineStringFromRef = $null 
        $cursorOutputForRef = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$commandLineStringFromRef, [ref]$cursorOutputForRef)
        
        $linesToCapture = $Global:Console2Ai_DefaultLinesToCaptureForHotkey 
        $userPromptForAI = if ($null -ne $commandLineStringFromRef) { $commandLineStringFromRef.Trim() } else { "" }
        
        if (-not [string]::IsNullOrWhiteSpace($commandLineStringFromRef)) {
            if ($commandLineStringFromRef -match '^(\d{1,4})\s+(.+)$') { # Number followed by text
                $numStr = $matches[1]
                if ([int]::TryParse($numStr, [ref]$linesToCaptureCandidate) -and ($linesToCaptureCandidate -gt 0) -and ($linesToCaptureCandidate -lt 2000) ) {
                    $linesToCapture = $linesToCaptureCandidate
                    $userPromptForAI = $matches[2].Trim()
                    Write-Verbose "Console2Ai Hotkey (Alt+C): Parsed: $linesToCapture lines, prompt: '$userPromptForAI'"
                } else {
                    Write-Verbose "Console2Ai Hotkey (Alt+C): Detected number '$numStr' but it's invalid/range. Using default $linesToCapture lines. Full line as prompt."
                }
            } elseif ($commandLineStringFromRef -match '^\d{1,4}$') { # Only a number
                $numStr = $commandLineStringFromRef
                if ([int]::TryParse($numStr, [ref]$linesToCaptureCandidate) -and ($linesToCaptureCandidate -gt 0) -and ($linesToCaptureCandidate -lt 2000) ) {
                    $linesToCapture = $linesToCaptureCandidate
                    $userPromptForAI = "User provided only line count, analyze history for a command." 
                    Write-Verbose "Console2Ai Hotkey (Alt+C): Parsed: $linesToCapture lines, default prompt."
                } else {
                    Write-Verbose "Console2Ai Hotkey (Alt+C): Detected number '$numStr' but it's invalid/range. Using default $linesToCapture lines. Treating number as prompt."
                }
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($userPromptForAI)) {
            $userPromptForAI = "User did not provide a specific prompt, analyze history for a command."
        }

        $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $linesToCapture -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($consoleHistory)) {
             Write-Warning "Console2Ai Hotkey (Alt+C): No console history was captured. AI might lack context."
             $consoleHistory = "" # Ensure it's an empty string, not null
        }

        # Clear current line and insert status message
        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine() # Or KillLine()
        $statusMessage = "⌛ Console2Ai (Cmd): Capturing $linesToCapture lines. Asking AI about: '$userPromptForAI'..."
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($statusMessage)

        $formattedInstruction = $Global:Console2Ai_CommandMode_AIPromptInstruction -f $linesToCapture, $userPromptForAI
        $fullAIPrompt = if ([string]::IsNullOrWhiteSpace($consoleHistory)) { $formattedInstruction } else { "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory" }
        $fullAIPrompt = $fullAIPrompt.TrimEnd()
        Write-Verbose "Console2Ai Hotkey (Alt+C): Full prompt for AI: `n$fullAIPrompt"

        try {
             $_new_suggestion = (& $Global:Console2Ai_CommandMode_AIChatExecutable -e $fullAIPrompt)
             [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine() # Clear status message
             [Microsoft.PowerShell.PSConsoleReadLine]::Insert($_new_suggestion)
        } catch {
             [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine() # Clear status message
             $errorMessage = "❌ Console2Ai (Cmd) AI Error: $($_.Exception.Message). Check '$($Global:Console2Ai_CommandMode_AIChatExecutable)' path/config."
             [Microsoft.PowerShell.PSConsoleReadLine]::Insert($errorMessage)
        }
        # No AcceptLine here, user gets suggestion in prompt and can edit/execute
    }

    # --- Alt+S: AI Conversation Mode Hotkey ---
    Set-PSReadLineKeyHandler -Chord "alt+s" -ScriptBlock {
        param($key, $arg) 

        # Get current typed line using the reliable method
        $commandLineStringFromRef = $null
        $cursorOutputForRef = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$commandLineStringFromRef, [ref]$cursorOutputForRef)

        $linesToCapture = $Global:Console2Ai_DefaultLinesToCaptureForHotkey
        $userPromptForAI = if ($null -ne $commandLineStringFromRef) { $commandLineStringFromRef.Trim() } else { "" }
        
        if (-not [string]::IsNullOrWhiteSpace($commandLineStringFromRef)) {
            if ($commandLineStringFromRef -match '^(\d{1,4})\s+(.+)$') { # Number followed by text
                $numStr = $matches[1]
                if ([int]::TryParse($numStr, [ref]$linesToCaptureCandidate) -and ($linesToCaptureCandidate -gt 0) -and ($linesToCaptureCandidate -lt 2000) ) {
                    $linesToCapture = $linesToCaptureCandidate
                    $userPromptForAI = $matches[2].Trim()
                    Write-Verbose "Console2Ai Hotkey (Alt+S): Parsed: $linesToCapture lines, prompt: '$userPromptForAI'"
                } else {
                    Write-Verbose "Console2Ai Hotkey (Alt+S): Detected number '$numStr' but it's invalid/range. Using default $linesToCapture lines. Full line as prompt."
                }
            } elseif ($commandLineStringFromRef -match '^\d{1,4}$') { # Only a number
                $numStr = $commandLineStringFromRef
                if ([int]::TryParse($numStr, [ref]$linesToCaptureCandidate) -and ($linesToCaptureCandidate -gt 0) -and ($linesToCaptureCandidate -lt 2000) ) {
                    $linesToCapture = $linesToCaptureCandidate
                    $userPromptForAI = "User provided only line count. Please analyze history and respond generally." 
                    Write-Verbose "Console2Ai Hotkey (Alt+S): Parsed: $linesToCapture lines, default prompt."
                } else {
                    Write-Verbose "Console2Ai Hotkey (Alt+S): Detected number '$numStr' but it's invalid/range. Using default $linesToCapture lines. Treating number as prompt."
                }
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($userPromptForAI)) {
            $userPromptForAI = "User's query is empty or was just a line count. Please analyze history and provide general assistance or ask for clarification."
        }
        
        $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $linesToCapture -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($consoleHistory)) {
             Write-Warning "Console2Ai Hotkey (Alt+S): No console history was captured or it's empty. AI might lack context."
             $consoleHistory = "" # Ensure it's an empty string, not null
        }

        $formattedInstruction = $Global:Console2Ai_ConversationMode_AIPromptInstruction -f $linesToCapture, $userPromptForAI
        $fullAIPromptForConversation = if ([string]::IsNullOrWhiteSpace($consoleHistory)) { $formattedInstruction } else { "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory" }
        $fullAIPromptForConversation = $fullAIPromptForConversation.TrimEnd()
        
        Write-Verbose "Console2Ai Hotkey (Alt+S): Full prompt being prepared for AI (via stdin): `n$fullAIPromptForConversation"

        # Prepare PSReadLine for external command and new prompt
        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert(" ") # Benign content
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine() # Submit benign content, get new prompt line

        # Display feedback messages AFTER AcceptLine, so they appear cleanly
        Write-Host "" # Newline for separation
        Write-Host "🗣️  Console2Ai (Conversation with AI)" -ForegroundColor Cyan
        Write-Host "   Sending your query: '$userPromptForAI'"
        Write-Host "   With context: Last $linesToCapture lines of console history."
        Write-Host "--- Starting AI session with $($Global:Console2Ai_ConversationMode_AIChatExecutable)... (Press Ctrl+C to interrupt AI if needed) ---" -ForegroundColor Green
        Write-Host "" 
        
        try {
            Invoke-Command -ScriptBlock {
                param($promptContent, $executablePath)
                $PreviousOutputEncoding = $OutputEncoding 
                $OutputEncoding = [System.Text.Encoding]::UTF8 
                try {
                    $promptContent | & $executablePath
                } finally {
                    $OutputEncoding = $PreviousOutputEncoding 
                }
            } -ArgumentList $fullAIPromptForConversation, $Global:Console2Ai_ConversationMode_AIChatExecutable
            
        } catch {
            Write-Error "Console2Ai Hotkey (Alt+S): Error during execution of AI chat executable '$($Global:Console2Ai_ConversationMode_AIChatExecutable)'."
            Write-Error ($_.Exception.Message)
            Write-Host "--- AI session failed or ended with an error. ---" -ForegroundColor Red
        } finally {
            Write-Host "" # Ensure a clean line after AI finishes or errors
            # PSReadLine should redraw the prompt automatically.
        }
    }

    Write-Verbose "Console2Ai: Alt+C (Command Mode) and Alt+S (Conversation Mode) hotkeys registered."

} catch {
    Write-Warning "Console2Ai: Failed to set PSReadLine key handlers. PSReadLine might not be available or an error occurred: $($_.Exception.Message)"
}
#endregion PSReadLine Hotkey Bindings