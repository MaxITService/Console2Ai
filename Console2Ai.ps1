#region Console2Ai - PowerShell Console Assistant with AI Integration
# Script: Console2Ai.ps1
# Version: 2.1 (Production Ready - Profile Integration)
# Author: [Your Name/Handle Here]
# Description: Provides functions to capture console history and send it to an AI
#              for assistance, or save it to a log. Includes an Alt+C hotkey
#              for quick AI interaction via PSReadLine.

# --- Helper Function: Get-ConsoleTextAbovePrompt ---
# Captures text from the console buffer above the current prompt.
function Get-ConsoleTextAbovePrompt {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [int]$LinesToCapture = 15, # Number of lines to capture upwards from the prompt

        [Parameter(Mandatory=$false)]
        [int]$CaptureWidth = -1 # Width of the capture. -1 means full buffer width.
    )

    # Get the RawUI for low-level console access
    $rawUI = $Host.UI.RawUI
    # Get current cursor position and buffer size
    $cursorPos = $rawUI.CursorPosition
    $bufferSize = $rawUI.BufferSize

    # 1. Calculate Y-coordinates
    $targetTopY = $cursorPos.Y - $LinesToCapture
    $actualTopY = [Math]::Max(0, $targetTopY)
    $actualBottomY = $cursorPos.Y - 1

    if ($cursorPos.Y -eq 0 -or $LinesToCapture -le 0 -or $actualTopY -gt $actualBottomY) {
        Write-Verbose "Get-ConsoleTextAbovePrompt: No lines to capture (CursorY=$($cursorPos.Y), LinesToCapture=$LinesToCapture, actualTopY=$actualTopY, actualBottomY=$actualBottomY)."
        return "" # Return an empty string
    }

    # 2. Calculate X-coordinates (width)
    $actualLeftX = 0
    $resolvedCaptureWidth = if ($CaptureWidth -lt 0 -or $CaptureWidth -gt $bufferSize.Width) {
        $bufferSize.Width
    } else {
        $CaptureWidth
    }
    $actualRightX = $actualLeftX + $resolvedCaptureWidth - 1
    $actualRightX = [Math]::Min($actualRightX, $bufferSize.Width - 1)

    if ($actualRightX -lt $actualLeftX -or $bufferSize.Width -eq 0) {
         Write-Verbose "Get-ConsoleTextAbovePrompt: Invalid capture width (Left=$actualLeftX, Right=$actualRightX, BufferWidth=$($bufferSize.Width), ResolvedCaptureWidth=$resolvedCaptureWidth). Nothing to capture."
        return ""
    }

    # 3. Create the Rectangle object
    $rectangle = New-Object System.Management.Automation.Host.Rectangle `
        $actualLeftX, $actualTopY, $actualRightX, $actualBottomY

    Write-Verbose "Get-ConsoleTextAbovePrompt: Capture parameters: Cursor(Y)=$($cursorPos.Y). Rect: L=$actualLeftX, T=$actualTopY, R=$actualRightX, B=$actualBottomY. BufferWidth: $($bufferSize.Width)"

    # 4. Capture the buffer contents
    try {
        $bufferCells = $rawUI.GetBufferContents($rectangle)
    } catch {
        Write-Error "Get-ConsoleTextAbovePrompt: Error capturing buffer: $($_.Exception.Message)"
        return "" # Return an empty string on error
    }
     if ($null -eq $bufferCells) {
        Write-Verbose "Get-ConsoleTextAbovePrompt: GetBufferContents returned null. The capture area might be invalid or empty."
        return ""
    }
    
    # 5. Assemble the text from BufferCell objects
    $capturedTextBuilder = [System.Text.StringBuilder]::new()
    for ($row = 0; $row -lt $bufferCells.GetLength(0); $row++) {
        for ($col = 0; $col -lt $bufferCells.GetLength(1); $col++) {
            [void]$capturedTextBuilder.Append($bufferCells[$row, $col].Character)
        }
        if ($row -lt ($bufferCells.GetLength(0) - 1)) {
            [void]$capturedTextBuilder.Append([Environment]::NewLine)
        }
    }
    return $capturedTextBuilder.ToString()
}


# --- Main Function 1: Invoke-AIConsoleHelp ---
<#
.SYNOPSIS
  Captures recent console output and sends it to an AI chat for assistance.
.DESCRIPTION
  This function captures a specified number of lines from the console buffer immediately
  preceding the current prompt. It then formats this text into a larger prompt for an
  AI assistant (e.g., aichat.exe) and executes the AI tool. The AI is instructed to
  analyze the console history, identify problems or user intent, and suggest a
  relevant PowerShell command.
  NOTE: The primary way to use this functionality is via the Alt+C hotkey, which offers
  more interactive features like specifying line count directly in the prompt.
.PARAMETER LinesToCapture
  The number of lines to capture from the console history. Defaults to 15.
.PARAMETER UserPrompt
  Optional additional text to guide the AI, similar to what you'd type before pressing Alt+C.
.PARAMETER AIChatExecutable
  The path or name of the AI chat executable. Defaults to "aichat.exe".
.PARAMETER AIPromptInstruction
  The instructional text to prepend to the captured console output when forming the
  prompt for the AI. Placeholders: {0} = line count, {1} = user prompt text.
.EXAMPLE
  Invoke-AIConsoleHelp -LinesToCapture 10 -UserPrompt "How do I fix this permission error?"
  # Captures 10 lines and sends them to "aichat.exe" with a specific user prompt.
.EXAMPLE
  # After some console activity, type:
  Invoke-AIConsoleHelp
  # This will capture the last 15 lines and send them to the AI.
.NOTES
  Ensure the AI chat executable is in your PATH or provide a full path.
  This function is part of the Console2Ai script.
#>
function Invoke-AIConsoleHelp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [int]$LinesToCapture = 15,

        [Parameter(Mandatory=$false)]
        [string]$UserPrompt = "User did not provide a specific prompt, analyze history.",

        [Parameter(Mandatory=$false)]
        [string]$AIChatExecutable = "aichat.exe", # Default AI executable

        [Parameter(Mandatory=$false)]
        [string]$AIPromptInstruction = "Please analyze the following console history (last {0} lines). The user's specific request is: '{1}'. Identify any issues or the user's likely goal based on both history and request, and suggest a single, concise PowerShell command to help. If the user request is a direct command instruction, fulfill it using the history as context. Console History:"
    )

    Write-Verbose "Invoke-AIConsoleHelp: Attempting to capture $LinesToCapture lines for AI assistance."
    $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $LinesToCapture -ErrorAction SilentlyContinue
    
    if ([string]::IsNullOrWhiteSpace($consoleHistory)) {
        Write-Warning "Invoke-AIConsoleHelp: No console history was captured, or captured history is empty. AI might lack context."
        # Proceeding, as AI might still work based on UserPrompt alone.
    }

    # Format the instruction part of the prompt
    $formattedInstruction = $AIPromptInstruction -f $LinesToCapture, $UserPrompt

    $fullAIPrompt = "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory"

    Write-Verbose "Invoke-AIConsoleHelp: Full prompt for AI: `n$fullAIPrompt"
    Write-Host "Invoke-AIConsoleHelp: Sending the last $LinesToCapture lines (and user prompt) to AI ($AIChatExecutable)..."

    try {
        # Execute the AI chat executable. Assumes it takes prompt with -e
        & $AIChatExecutable -e $fullAIPrompt
    } catch {
        Write-Error "Invoke-AIConsoleHelp: Failed to execute AI chat executable '$AIChatExecutable'."
        Write-Error $_.Exception.Message
    }
}


# --- Main Function 2: Save-ConsoleHistoryLog ---
<#
.SYNOPSIS
  Saves recent console output to a log file.
.DESCRIPTION
  This function captures a specified number of lines from the console buffer immediately
  preceding the current prompt and saves this text to a specified log file.
  By default, it saves the last 15 lines to "log.txt" in the current directory.
.PARAMETER LinesToCapture
  The number of lines to capture from the console history. Defaults to 15.
.PARAMETER LogFilePath
  The path to the log file where the console history will be saved.
.EXAMPLE
  Save-ConsoleHistoryLog
  # Saves the last 15 lines of console output to ".\log.txt".
.EXAMPLE
  Save-ConsoleHistoryLog -LinesToCapture 20 -LogFilePath "C:\temp\my_console_log.txt"
  # Saves the last 20 lines to a custom file path.
.NOTES
  The log file is saved with UTF-8 encoding.
  This function is part of the Console2Ai script.
#>
function Save-ConsoleHistoryLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [int]$LinesToCapture = 15,

        [Parameter(Mandatory=$false)]
        [string]$LogFilePath = ".\log.txt" # Default log file path
    )

     Write-Verbose "Save-ConsoleHistoryLog: Attempting to capture $LinesToCapture lines to save to log file '$LogFilePath'."
    $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $LinesToCapture -ErrorAction SilentlyContinue

    if ($null -eq $consoleHistory) {
        $consoleHistory = "" # Ensure it's a string for Set-Content
    }
    try {
        Set-Content -Path $LogFilePath -Value $consoleHistory -Encoding UTF8 -Force
        Write-Host "Save-ConsoleHistoryLog: Last $LinesToCapture console lines (or available history) saved to '$LogFilePath'."
        Write-Verbose "Save-ConsoleHistoryLog: Captured content length: $($consoleHistory.Length) characters."
    } catch {
        Write-Error "Save-ConsoleHistoryLog: Failed to save console history to '$LogFilePath'."
        Write-Error $_.Exception.Message
    }
}


# --- PSReadLine Hotkey Binding for AI Help (Alt+C) ---
# This section attempts to set up the Alt+C hotkey.
# It should be placed in your PowerShell profile after PSReadLine is imported.
# Example: Import-Module PSReadLine; . C:\path\to\Console2Ai.ps1
try {
    # Ensure UTF-8 output in this session for AI interaction
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # Configuration for the hotkey (can be customized by user if they edit the script)
    $Console2Ai_Hotkey_AIChatExecutable = "aichat.exe"
    $Console2Ai_Hotkey_AIPromptInstruction = "Please analyze the following console history (last {0} lines). The user's specific request is: '{1}'. Identify any issues or the user's likely goal based on both history and request, and suggest a single, concise PowerShell command to help. If the user request is a direct command instruction, fulfill it using the history as context. Console History:"

    Set-PSReadLineKeyHandler -Chord "alt+c" -ScriptBlock {
        param($key, $arg) # Standard parameters for PSReadLine script blocks

        $currentLine = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$currentLine, [ref]$null)

        $linesToCapture = 15 # Default line count
        $userPromptForAI = $currentLine # Default prompt is the whole line
        
        # Try to parse line count override (e.g., "30 get help with this error")
        if ($null -ne $currentLine -and $currentLine -match '^(\d{1,4})\s+(.*)') {
            $numStr = $matches[1]
            if ([int]::TryParse($numStr, [ref]$null) -and ([int]$numStr -gt 0) -and ([int]$numStr -lt 2000) ) {
                 $linesToCapture = [int]$numStr
                 $userPromptForAI = $matches[2]
                 Write-Verbose "Console2Ai Hotkey: Detected line count override: $linesToCapture"
            } else {
                 Write-Verbose "Console2Ai Hotkey: Detected number '$numStr' but it's invalid (not 1-1999). Using default 15 lines."
            }
        } elseif ($null -ne $currentLine -and $currentLine -match '^\d{1,4}$') {
             $numStr = $currentLine
             if ([int]::TryParse($numStr, [ref]$null) -and ([int]$numStr -gt 0) -and ([int]$numStr -lt 2000) ) {
                 $linesToCapture = [int]$numStr
                 $userPromptForAI = "User provided only line count, analyze history."
                 Write-Verbose "Console2Ai Hotkey: Detected line count override: $linesToCapture (no specific prompt text)"
             }
        }

        # Capture console history
        $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $linesToCapture -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($consoleHistory)) {
             Write-Warning "Console2Ai Hotkey: No console history was captured. AI might lack context."
        }

        # Provide feedback in the prompt line
        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
        $statusMessage = "⌛ Console2Ai: Capturing $linesToCapture lines. Asking AI about: '$userPromptForAI'..."
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($statusMessage)

        # Formulate the full prompt for the AI
        $formattedInstruction = $Console2Ai_Hotkey_AIPromptInstruction -f $linesToCapture, $userPromptForAI
        $fullAIPrompt = "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory"
        Write-Verbose "Console2Ai Hotkey: Full prompt for AI: `n$fullAIPrompt"

        # Call AI and replace prompt line
        try {
             $_new = (& $Console2Ai_Hotkey_AIChatExecutable -e $fullAIPrompt)
             [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
             [Microsoft.PowerShell.PSConsoleReadLine]::Insert($_new)
        } catch {
             [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
             $errorMessage = "❌ Console2Ai AI Error: $($_.Exception.Message). Check '$Console2Ai_Hotkey_AIChatExecutable' path/config."
             [Microsoft.PowerShell.PSConsoleReadLine]::Insert($errorMessage)
        }
    }
    # Optional: A silent confirmation that the hotkey was set, good for profile loading.
    # Write-Verbose "Console2Ai: Alt+C hotkey registered successfully."
} catch {
    Write-Warning "Console2Ai: Failed to set PSReadLine key handler for Alt+C. PSReadLine might not be available or an error occurred: $($_.Exception.Message)"
}

#endregion Console2Ai - PowerShell Console Assistant with AI Integration