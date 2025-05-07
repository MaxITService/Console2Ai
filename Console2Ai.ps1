#region Header and Configuration
# Script: Console2Ai.ps1
# Version: 2.12 (Alt+S delegates to helper function for cleaner execution)
# (Configuration and other functions remain the same)
# --- User Configuration ---
$Global:Console2Ai_AIChatExecutable = "aichat.exe"
$Global:Console2Ai_CommandMode_AIChatExecutable = $Global:Console2Ai_AIChatExecutable
$Global:Console2Ai_CommandMode_AIPromptInstruction = "Please analyze the following console history (last {0} lines). The user's specific request is: '{1}'. Identify any issues or the user's likely goal based on both history and request, and suggest a single, concise PowerShell command to help. If the user request is a direct command instruction, fulfill it using the history as context. Console History:"
$Global:Console2Ai_ConversationMode_AIChatExecutable = $Global:Console2Ai_AIChatExecutable
$Global:Console2Ai_ConversationMode_AIPromptInstruction = "You are in a conversational chat. Please analyze the following console history (last {0} lines) as context. The user's current query is: '{1}'. Respond to the user's query, using the console history for context if relevant. Avoid suggesting a command unless explicitly asked or it's the most natural answer. Focus on explanation and direct answers. Console History:"
$Global:Console2Ai_DefaultLinesToCaptureForHotkey = 15

#endregion Header and Configuration

# --- Helper Function: Get-ConsoleTextAbovePrompt ---
# (Unchanged)
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

# --- Main Function 1: Invoke-AIConsoleHelp (for Alt+C like behavior) ---
# (Unchanged)
function Invoke-AIConsoleHelp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesToCapture = 15,
        [Parameter(Mandatory=$false)] [string]$UserPrompt = "User did not provide a specific prompt, analyze history.",
        [Parameter(Mandatory=$false)] [string]$AIChatExecutable = "aichat.exe", # Default AI executable for this function
        [Parameter(Mandatory=$false)] [string]$AIPromptInstruction = "Please analyze the following console history (last {0} lines). The user's specific request is: '{1}'. Identify any issues or the user's likely goal based on both history and request, and suggest a single, concise PowerShell command to help. If the user request is a direct command instruction, fulfill it using the history as context. Console History:"
    )
    Write-Verbose "Invoke-AIConsoleHelp: Attempting to capture $LinesToCapture lines for AI assistance."
    $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $LinesToCapture -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($consoleHistory)) { Write-Warning "Invoke-AIConsoleHelp: No console history was captured, or captured history is empty. AI might lack context." }
    $formattedInstruction = $AIPromptInstruction -f $LinesToCapture, $UserPrompt
    $fullAIPrompt = "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory"
    Write-Verbose "Invoke-AIConsoleHelp: Full prompt for AI: `n$fullAIPrompt"
    Write-Host "Invoke-AIConsoleHelp: Sending the last $LinesToCapture lines (and user prompt) to AI ($AIChatExecutable)..."
    try { & $AIChatExecutable -e $fullAIPrompt } catch { Write-Error "Invoke-AIConsoleHelp: Failed to execute AI chat executable '$AIChatExecutable'."; Write-Error $_.Exception.Message }
}

# --- Main Function 2: Save-ConsoleHistoryLog ---
# (Unchanged)
function Save-ConsoleHistoryLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesToCapture = 15,
        [Parameter(Mandatory=$false)] [string]$LogFilePath = ".\log.txt" # Default log file path
    )
    Write-Verbose "Save-ConsoleHistoryLog: Attempting to capture $LinesToCapture lines to save to log file '$LogFilePath'."
    $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $LinesToCapture -ErrorAction SilentlyContinue
    if ($null -eq $consoleHistory) { $consoleHistory = "" } 
    try { Set-Content -Path $LogFilePath -Value $consoleHistory -Encoding UTF8 -Force; Write-Host "Save-ConsoleHistoryLog: Last $LinesToCapture console lines (or available history) saved to '$LogFilePath'." } catch { Write-Error "Save-ConsoleHistoryLog: Failed to save console history to '$LogFilePath'."; Write-Error $_.Exception.Message }
}

# --- NEW Helper Function for Alt+S Conversation ---
function Invoke-Console2AiConversation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$UserQuery,

        [Parameter(Mandatory=$true)]
        [int]$LinesToCapture
    )

    $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $LinesToCapture -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($consoleHistory)) { $consoleHistory = "" }

    $formattedInstruction = $Global:Console2Ai_ConversationMode_AIPromptInstruction -f $LinesToCapture, $UserQuery
    $fullAIPromptForConversation = if ([string]::IsNullOrWhiteSpace($consoleHistory)) { $formattedInstruction } else { "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory" }
    $fullAIPromptForConversation = $fullAIPromptForConversation.TrimEnd()
    
    Write-Verbose "Invoke-Console2AiConversation: Full prompt for AI (stdin): `n$fullAIPromptForConversation"

    # Display feedback messages
    Write-Host "" 
    Write-Host "🗣️  Console2Ai (Conversation with AI)" -ForegroundColor Cyan
    Write-Host "   Sending your query: '$UserQuery'"
    Write-Host "   With context: Last $LinesToCapture lines of console history."
    Write-Host "--- Starting AI session with $($Global:Console2Ai_ConversationMode_AIChatExecutable)... (Press Ctrl+C to interrupt AI if needed) ---" -ForegroundColor Green
    Write-Host "" 
            
    $PreviousOutputEncoding = $OutputEncoding 
    $OutputEncoding = [System.Text.Encoding]::UTF8 
    try {
        $fullAIPromptForConversation | & $Global:Console2Ai_ConversationMode_AIChatExecutable
    } catch {
        Write-Error "Invoke-Console2AiConversation: Error executing AI chat '$($Global:Console2Ai_ConversationMode_AIChatExecutable)'."
        Write-Error ($_.Exception.Message) 
        Write-Host "--- AI session failed or ended with an error. ---" -ForegroundColor Red
    } finally {
        $OutputEncoding = $PreviousOutputEncoding 
        Write-Host "" 
    }
}
#endregion

# --- PSReadLine Hotkey Bindings ---
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # --- Alt+C: AI Command Suggestion Hotkey ---
    # (Remains the same)
    Set-PSReadLineKeyHandler -Chord "alt+c" -ScriptBlock {
        param($key, $arg)
        $cmdLineStr = $null; $cursor = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$cmdLineStr, [ref]$cursor)
        $lines = $Global:Console2Ai_DefaultLinesToCaptureForHotkey; $prompt = if ($null -ne $cmdLineStr) { $cmdLineStr.Trim() } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($cmdLineStr)) {
            if ($cmdLineStr -match '^(\d{1,4})\s+(.+)$') { if ([int]::TryParse($matches[1],[ref]$lC) -and ($lC -gt 0 -and $lC -lt 2000)) { $lines = $lC; $prompt = $matches[2].Trim() } }
            elseif ($cmdLineStr -match '^\d{1,4}$') { if ([int]::TryParse($cmdLineStr,[ref]$lC) -and ($lC -gt 0 -and $lC -lt 2000)) { $lines = $lC; $prompt = "User provided only line count, analyze history for a command." } }
        }
        if ([string]::IsNullOrWhiteSpace($prompt)) { $prompt = "User did not provide a specific prompt, analyze history for a command." }
        $hist = Get-ConsoleTextAbovePrompt -L $lines -EA SilentlyContinue; if ([string]::IsNullOrWhiteSpace($hist)) { $hist = "" }
        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine(); $statusMsg = "⌛ Console2Ai (Cmd): $lines lines. AI for: '$prompt'..."; [Microsoft.PowerShell.PSConsoleReadLine]::Insert($statusMsg)
        $fInst = $Global:Console2Ai_CommandMode_AIPromptInstruction -f $lines, $prompt; $fullPrompt = if ([string]::IsNullOrWhiteSpace($hist)) { $fInst } else { "$fInst$([Environment]::NewLine)$([Environment]::NewLine)$hist" }; $fullPrompt = $fullPrompt.TrimEnd()
        try { $newCmd = (& $Global:Console2Ai_CommandMode_AIChatExecutable -e $fullPrompt); [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine(); [Microsoft.PowerShell.PSConsoleReadLine]::Insert($newCmd) }
        catch { [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine(); $errMsg = "❌ Console2Ai (Cmd) AI Error: $($_.Exception.Message)."; [Microsoft.PowerShell.PSConsoleReadLine]::Insert($errMsg) }
    }

    # --- Alt+S: AI Conversation Mode Hotkey ---
    Set-PSReadLineKeyHandler -Chord "alt+s" -ScriptBlock {
        param($key, $arg) 

        $commandLineStringFromRef = $null; $cursorOutputForRef = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$commandLineStringFromRef, [ref]$cursorOutputForRef)

        $linesToCapture = $Global:Console2Ai_DefaultLinesToCaptureForHotkey
        $userPromptForAI = if ($null -ne $commandLineStringFromRef) { $commandLineStringFromRef.Trim() } else { "" }
        
        # (Parsing logic remains the same)
        if (-not [string]::IsNullOrWhiteSpace($commandLineStringFromRef)) {
            if ($commandLineStringFromRef -match '^(\d{1,4})\s+(.+)$') {
                if ([int]::TryParse($matches[1], [ref]$lC) -and ($lC -gt 0 -and $lC -lt 2000) ) { $linesToCapture = $lC; $userPromptForAI = $matches[2].Trim() }
            } elseif ($commandLineStringFromRef -match '^\d{1,4}$') {
                if ([int]::TryParse($commandLineStringFromRef, [ref]$lC) -and ($lC -gt 0 -and $lC -lt 2000) ) { $linesToCapture = $lC; $userPromptForAI = "User provided only line count. Please analyze history and respond generally." }
            }
        }
        if ([string]::IsNullOrWhiteSpace($userPromptForAI)) { $userPromptForAI = "User's query is empty. Please analyze history and provide general assistance." }
        
        # Escape single quotes in userPromptForAI for embedding in a command string
        $escapedUserQuery = $userPromptForAI.Replace("'", "''")

        # Construct the command to call our helper function
        $commandToExecute = "Invoke-Console2AiConversation -UserQuery '$escapedUserQuery' -LinesToCapture $linesToCapture"
        
        Write-Verbose "Console2Ai Hotkey (Alt+S): Inserting command: $commandToExecute"

        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($commandToExecute) 
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine() # This submits the Invoke-Console2AiConversation command
    }

    Write-Verbose "Console2Ai: Alt+C (Command Mode) and Alt+S (Conversation Mode) hotkeys registered."

} catch {
    Write-Warning "Console2Ai: Failed to set PSReadLine key handlers: $($_.Exception.Message)"
}
#endregion PSReadLine Hotkey Bindings