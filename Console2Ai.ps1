#region Header and Configuration
# Script: Console2Ai.ps1
# Version: 2.13 (Production Ready - Bug fix for line count, cleaner output)
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
$Global:Console2Ai_CommandMode_AIPromptInstruction = "Please analyze the following console history (last {0} lines). The user's specific request is: '{1}'. Identify any issues or the user's likely goal based on both history and request, and suggest PowerShell command to help. If the user request is a direct command instruction, fulfill it using the history as context. Console History:"

# Configuration for Alt+S (Conversation Mode)
$Global:Console2Ai_ConversationMode_AIChatExecutable = $Global:Console2Ai_AIChatExecutable # Or specify a different one
$Global:Console2Ai_ConversationMode_AIPromptInstruction = "You are in a conversational chat. Please analyze the following console history (last {0} lines) as context. The user's current query is: '{1}'. Respond to the user's query, using the console history for context if relevant. Avoid suggesting a command unless explicitly asked or it's the most natural answer. Focus on explanation and direct answers. Console History:"

# Default number of lines to capture for hotkeys if not specified in the prompt
$Global:Console2Ai_DefaultLinesToCaptureForHotkey = 15

#endregion Header and Configuration

# --- Helper Function: Get-ConsoleTextAbovePrompt ---
<#
.SYNOPSIS
  Captures text from the console buffer above the current prompt.
.DESCRIPTION
  This internal helper function reads a specified number of lines from the console
  buffer directly above the current cursor position. It's used to provide
  context to the AI.
.PARAMETER LinesToCapture
  The number of lines to capture upwards from the prompt. Defaults to 15.
.PARAMETER CaptureWidth
  The width of the capture. -1 means full buffer width. Defaults to -1.
.OUTPUTS
  System.String
  The captured text, with lines separated by NewLine characters. Returns an empty
  string if no lines can be captured or an error occurs.
.NOTES
  This function uses low-level $Host.UI.RawUI calls.
#>
function Get-ConsoleTextAbovePrompt {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesToCapture = 15, 
        [Parameter(Mandatory=$false)] [int]$CaptureWidth = -1 
    )
    $rawUI = $Host.UI.RawUI; $cursorPos = $rawUI.CursorPosition; $bufferSize = $rawUI.BufferSize
    $targetTopY = $cursorPos.Y - $LinesToCapture; $actualTopY = [Math]::Max(0, $targetTopY); $actualBottomY = $cursorPos.Y - 1
    if ($cursorPos.Y -eq 0 -or $LinesToCapture -le 0 -or $actualTopY -gt $actualBottomY) { Write-Verbose "Get-ConsoleTextAbovePrompt: No lines to capture (Y=$($cursorPos.Y), LCap=$LinesToCapture, T=$actualTopY, B=$actualBottomY)."; return "" }
    $actualLeftX = 0; $resolvedCaptureWidth = if ($CaptureWidth -lt 0 -or $CaptureWidth -gt $bufferSize.Width) { $bufferSize.Width } else { $CaptureWidth }
    $actualRightX = $actualLeftX + $resolvedCaptureWidth - 1; $actualRightX = [Math]::Min($actualRightX, $bufferSize.Width - 1)
    if ($actualRightX -lt $actualLeftX -or $bufferSize.Width -eq 0) { Write-Verbose "Get-ConsoleTextAbovePrompt: Invalid capture width (L=$actualLeftX, R=$actualRightX, BufW=$($bufferSize.Width), ResW=$resolvedCaptureWidth)."; return "" }
    $rectangle = New-Object System.Management.Automation.Host.Rectangle $actualLeftX, $actualTopY, $actualRightX, $actualBottomY
    Write-Verbose "Get-ConsoleTextAbovePrompt: Rect: L=$actualLeftX, T=$actualTopY, R=$actualRightX, B=$actualBottomY. BufW: $($bufferSize.Width)"
    try { $bufferCells = $rawUI.GetBufferContents($rectangle) } catch { Write-Error "Get-ConsoleTextAbovePrompt: Error capturing buffer: $($_.Exception.Message)"; return "" }
    if ($null -eq $bufferCells) { Write-Verbose "Get-ConsoleTextAbovePrompt: GetBufferContents returned null."; return "" }
    $sb = [System.Text.StringBuilder]::new(); for ($r = 0; $r -lt $bufferCells.GetLength(0); $r++) { for ($c = 0; $c -lt $bufferCells.GetLength(1); $c++) { [void]$sb.Append($bufferCells[$r, $c].Character) } if ($r -lt ($bufferCells.GetLength(0) - 1)) { [void]$sb.Append([Environment]::NewLine) } }
    return $sb.ToString().TrimEnd()
}

# --- Main Function 1: Invoke-AIConsoleHelp (for Alt+C like behavior, or programmatic use) ---
<#
.SYNOPSIS
  Captures recent console output and sends it to an AI chat for assistance, expecting a command suggestion.
.DESCRIPTION
  This function captures a specified number of lines from the console buffer immediately
  preceding the current prompt. It then formats this text into a larger prompt for an
  AI assistant (e.g., aichat.exe using the -e parameter) and executes the AI tool.
  The AI is instructed to analyze the console history, identify problems or user intent,
  and suggest a relevant PowerShell command.
.PARAMETER LinesToCapture
  The number of lines to capture from the console history. Defaults to 15.
.PARAMETER UserPrompt
  Optional additional text to guide the AI.
.PARAMETER AIChatExecutable
  The path or name of the AI chat executable. Defaults to the global configuration.
.PARAMETER AIPromptInstruction
  The instructional text for the AI. Defaults to the global command mode configuration.
.EXAMPLE
  Invoke-AIConsoleHelp -LinesToCapture 10 -UserPrompt "How do I fix this permission error?"
  # Captures 10 lines and sends them to the AI for a command suggestion.
.NOTES
  This function is typically used by the Alt+C hotkey which inserts the AI's response
  back into the command line. It assumes the AI executable supports a parameter like -e
  for direct query and single response.
#>
function Invoke-AIConsoleHelp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesToCapture = $Global:Console2Ai_DefaultLinesToCaptureForHotkey,
        [Parameter(Mandatory=$false)] [string]$UserPrompt = "User did not provide a specific prompt, analyze history for a command.",
        [Parameter(Mandatory=$false)] [string]$AIChatExecutable = $Global:Console2Ai_CommandMode_AIChatExecutable,
        [Parameter(Mandatory=$false)] [string]$AIPromptInstruction = $Global:Console2Ai_CommandMode_AIPromptInstruction
    )
    Write-Verbose "Invoke-AIConsoleHelp: Capturing $LinesToCapture lines for AI command suggestion."
    $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $LinesToCapture -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($consoleHistory)) { Write-Warning "Invoke-AIConsoleHelp: No console history captured. AI might lack context." }
    $formattedInstruction = $AIPromptInstruction -f $LinesToCapture, $UserPrompt
    $fullAIPrompt = "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory"
    $fullAIPrompt = $fullAIPrompt.TrimEnd()
    Write-Verbose "Invoke-AIConsoleHelp: Full prompt for AI: `n$fullAIPrompt"
    Write-Host "Invoke-AIConsoleHelp: Sending to AI ($AIChatExecutable) for command suggestion..." -ForegroundColor DarkCyan
    try { 
        # Return the output directly so Alt+C can use it
        return (& $AIChatExecutable -e $fullAIPrompt)
    } catch { 
        Write-Error "Invoke-AIConsoleHelp: Failed to execute AI chat executable '$AIChatExecutable'."
        Write-Error $_.Exception.Message 
        return "ERROR: AI execution failed."
    }
}

# --- Main Function 2: Save-ConsoleHistoryLog ---
<#
.SYNOPSIS
  Saves recent console output to a log file.
.DESCRIPTION
  This function captures a specified number of lines from the console buffer immediately
  preceding the current prompt and saves this text to a specified log file.
.PARAMETER LinesToCapture
  The number of lines to capture from the console history. Defaults to 15.
.PARAMETER LogFilePath
  The path to the log file where the console history will be saved. Defaults to ".\Console2Ai_Log.txt".
.EXAMPLE
  Save-ConsoleHistoryLog -LinesToCapture 20 -LogFilePath "C:\temp\my_console_log.txt"
.NOTES
  The log file is saved with UTF-8 encoding.
#>
function Save-ConsoleHistoryLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesToCapture = 15,
        [Parameter(Mandatory=$false)] [string]$LogFilePath = ".\Console2Ai_Log.txt" 
    )
    Write-Verbose "Save-ConsoleHistoryLog: Attempting to capture $LinesToCapture lines to save to log file '$LogFilePath'."
    $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $LinesToCapture -ErrorAction SilentlyContinue
    if ($null -eq $consoleHistory) { $consoleHistory = "" } 
    try { 
        Set-Content -Path $LogFilePath -Value $consoleHistory -Encoding UTF8 -Force
        Write-Host "Save-ConsoleHistoryLog: Last $LinesToCapture console lines (or available history) saved to '$LogFilePath'." -ForegroundColor Green
    } catch { 
        Write-Error "Save-ConsoleHistoryLog: Failed to save console history to '$LogFilePath'."
        Write-Error $_.Exception.Message 
    }
}

# --- Helper Function for Alt+S Conversation ---
<#
.SYNOPSIS
  Initiates a conversational AI session with console history context.
.DESCRIPTION
  This function is called by the Alt+S hotkey. It gathers the user's query and
  console history, formats a prompt for conversational AI, displays feedback,
  and then launches the AI executable, piping the prompt to its standard input.
  The AI executable is expected to take over the console for an interactive session.
.PARAMETER UserQuery
  The query typed by the user. Can also be specified as -UQ.
.PARAMETER UQ
  Alias for -UserQuery. The query typed by the user.
.PARAMETER LinesToCapture
  The number of console history lines to include as context. Can also be specified as -LTQ.
.PARAMETER LTQ
  Alias for -LinesToCapture. The number of console history lines to include as context.
.NOTES
  This function is not typically called directly by the user, but via the Alt+S hotkey.
  It handles the setup and execution of the conversational AI tool.
#>
function Invoke-Console2AiConversation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Alias('UQ')]
        [string]$UserQuery,

        [Parameter(Mandatory=$true)]
        [Alias('LTQ')]
        [int]$LinesToCapture
    )

    $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $LinesToCapture -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($consoleHistory)) { $consoleHistory = "" } # Ensure empty string, not null

    $formattedInstruction = $Global:Console2Ai_ConversationMode_AIPromptInstruction -f $LinesToCapture, $UserQuery
    $fullAIPromptForConversation = if ([string]::IsNullOrWhiteSpace($consoleHistory)) { $formattedInstruction } else { "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory" }
    $fullAIPromptForConversation = $fullAIPromptForConversation.TrimEnd()
    
    Write-Verbose "Invoke-Console2AiConversation: Full prompt for AI (stdin): `n$fullAIPromptForConversation"

    # Display concise feedback
    Write-Host "User message: '$UserQuery'  With context: Last $LinesToCapture lines of console" -ForegroundColor DarkCyan
    Write-Host "--- Starting AI session ($($Global:Console2Ai_ConversationMode_AIChatExecutable))... ---" -ForegroundColor DarkCyan
    # No Write-Host "" here, let aichat.exe control the next line.
            
    $PreviousOutputEncoding = $OutputEncoding 
    $OutputEncoding = [System.Text.Encoding]::UTF8 
    try {
        # Pipe the prompt directly to the executable
        $fullAIPromptForConversation | & $Global:Console2Ai_ConversationMode_AIChatExecutable
    } catch {
        Write-Error "Invoke-Console2AiConversation: Error executing AI chat '$($Global:Console2Ai_ConversationMode_AIChatExecutable)'."
        Write-Error ($_.Exception.Message) 
        Write-Host "--- AI session failed or ended with an error. ---" -ForegroundColor Red
    } finally {
        $OutputEncoding = $PreviousOutputEncoding 
        # No Write-Host "" here, to avoid an extra line if aichat exited cleanly.
        # The next PowerShell prompt will provide separation.
    }
}
#endregion

# --- PSReadLine Hotkey Bindings ---
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # --- Alt+C: AI Command Suggestion Hotkey ---
    Set-PSReadLineKeyHandler -Chord "alt+c" -ScriptBlock {
        param($key, $arg)
        $cmdLineStr = $null; $cursor = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$cmdLineStr, [ref]$cursor)
        
        $linesToCapture = $Global:Console2Ai_DefaultLinesToCaptureForHotkey
        $userPromptForAI = if ($null -ne $cmdLineStr) { $cmdLineStr.Trim() } else { "" }
        $lC = 0 # Declare $lC for TryParse [ref]

        if (-not [string]::IsNullOrWhiteSpace($cmdLineStr)) {
            if ($cmdLineStr -match '^(\d{1,4})\s+(.+)$') { # Number followed by text
                if ([int]::TryParse($matches[1],[ref]$lC) -and ($lC -gt 0 -and $lC -lt 2000)) { 
                    $linesToCapture = $lC; $userPromptForAI = $matches[2].Trim() 
                    Write-Verbose "Console2Ai (Alt+C): Parsed $linesToCapture lines, prompt: '$userPromptForAI'"
                } else { Write-Verbose "Console2Ai (Alt+C): Invalid num in '$($matches[1])'. Default lines."}
            } elseif ($cmdLineStr -match '^\d{1,4}$') { # Only a number
                if ([int]::TryParse($cmdLineStr,[ref]$lC) -and ($lC -gt 0 -and $lC -lt 2000)) { 
                    $linesToCapture = $lC; $userPromptForAI = "User provided only line count, analyze history for a command." 
                    Write-Verbose "Console2Ai (Alt+C): Parsed $linesToCapture lines, default prompt."
                } else { Write-Verbose "Console2Ai (Alt+C): Invalid num '$cmdLineStr'. Default lines."}
            }
        }
        if ([string]::IsNullOrWhiteSpace($userPromptForAI)) { $userPromptForAI = "User did not provide a specific prompt, analyze history for a command." }
        
        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
        $statusMsg = "⌛ Console2Ai (Cmd): Asking AI about '$userPromptForAI' (context: $linesToCapture lines)..."
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($statusMsg)
        
        # Call the main function to get the AI suggestion
        $aiSuggestion = Invoke-AIConsoleHelp -LinesToCapture $linesToCapture -UserPrompt $userPromptForAI -ErrorAction SilentlyContinue
        
        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine() # Clear status message
        if ($aiSuggestion -notlike "ERROR:*") {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($aiSuggestion) 
        } else {
            $errorMessage = "❌ Console2Ai (Cmd) AI Error. Check verbose output or logs. ($aiSuggestion)"
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($errorMessage)
        }
    }

    # --- Alt+S: AI Conversation Mode Hotkey ---
    Set-PSReadLineKeyHandler -Chord "alt+s" -ScriptBlock {
        param($key, $arg) 

        $commandLineStringFromRef = $null; $cursorOutputForRef = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$commandLineStringFromRef, [ref]$cursorOutputForRef)

        $linesToCapture = $Global:Console2Ai_DefaultLinesToCaptureForHotkey
        $userPromptForAI = if ($null -ne $commandLineStringFromRef) { $commandLineStringFromRef.Trim() } else { "" }
        $lC = 0 # Declare $lC for TryParse [ref]
        
        if (-not [string]::IsNullOrWhiteSpace($commandLineStringFromRef)) {
            if ($commandLineStringFromRef -match '^(\d{1,4})\s+(.+)$') { # Number followed by text
                if ([int]::TryParse($matches[1], [ref]$lC) -and ($lC -gt 0 -and $lC -lt 2000) ) { 
                    $linesToCapture = $lC; $userPromptForAI = $matches[2].Trim() 
                    Write-Verbose "Console2Ai (Alt+S): Parsed $linesToCapture lines, prompt: '$userPromptForAI'"
                } else { Write-Verbose "Console2Ai (Alt+S): Invalid num in '$($matches[1])'. Default lines."}
            } elseif ($commandLineStringFromRef -match '^\d{1,4}$') { # Only a number
                if ([int]::TryParse($commandLineStringFromRef, [ref]$lC) -and ($lC -gt 0 -and $lC -lt 2000) ) { 
                    $linesToCapture = $lC; $userPromptForAI = "User provided only line count. Please analyze history and respond generally." 
                    Write-Verbose "Console2Ai (Alt+S): Parsed $linesToCapture lines, default prompt."
                } else { Write-Verbose "Console2Ai (Alt+S): Invalid num '$commandLineStringFromRef'. Default lines."}
            }
        }
        if ([string]::IsNullOrWhiteSpace($userPromptForAI)) { $userPromptForAI = "User's query is empty. Please analyze history and provide general assistance." }
        
        $escapedUserQuery = $userPromptForAI.Replace("'", "''") # Escape for command string
        $commandToExecute = "Invoke-Console2AiConversation -UQ '$escapedUserQuery' -LTQ $linesToCapture"
        
        Write-Verbose "Console2Ai Hotkey (Alt+S): Inserting command: $commandToExecute"

        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($commandToExecute) 
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine() 
    }

    Write-Verbose "Console2Ai: Hotkeys Alt+C (Command) and Alt+S (Conversation) registered."
    Write-Verbose "Console2Ai: Verbose logging enabled for hotkey actions."

} catch {
    Write-Warning "Console2Ai: Failed to set PSReadLine key handlers: $($_.Exception.Message)"
}
#endregion PSReadLine Hotkey Bindings