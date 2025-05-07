#region Header and Configuration
# Script: Console2Ai.ps1
# Version: 2.8 (Alt+S redirects aichat output to file for debugging)
# (Configuration and other functions remain the same as v2.7)
# ... (Keep all previous code from #region Header and Configuration down to Save-ConsoleHistoryLog) ...
# --- User Configuration ---
$Global:Console2Ai_AIChatExecutable = "aichat.exe"
$Global:Console2Ai_CommandMode_AIChatExecutable = $Global:Console2Ai_AIChatExecutable
$Global:Console2Ai_CommandMode_AIPromptInstruction = "Please analyze the following console history (last {0} lines). The user's specific request is: '{1}'. Identify any issues or the user's likely goal based on both history and request, and suggest a single, concise PowerShell command to help. If the user request is a direct command instruction, fulfill it using the history as context. Console History:"
$Global:Console2Ai_ConversationMode_AIChatExecutable = $Global:Console2Ai_AIChatExecutable
$Global:Console2Ai_ConversationMode_AIPromptInstruction = "You are in a conversational chat. Please analyze the following console history (last {0} lines) as context. The user's current query is: '{1}'. Respond to the user's query, using the console history for context if relevant. Avoid suggesting a command unless explicitly asked or it's the most natural answer. Focus on explanation and direct answers. Console History:"
$Global:Console2Ai_DefaultLinesToCaptureForHotkey = 15

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

function Invoke-AIConsoleHelp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesToCapture = 15,
        [Parameter(Mandatory=$false)] [string]$UserPrompt = "User did not provide a specific prompt, analyze history.",
        [Parameter(Mandatory=$false)] [string]$AIChatExecutable = "aichat.exe",
        [Parameter(Mandatory=$false)] [string]$AIPromptInstruction = "Please analyze console history (last {0} lines). User request: '{1}'. Suggest PowerShell command. History:"
    )
    $hist = Get-ConsoleTextAbovePrompt -L $LinesToCapture -EA SilentlyContinue; if ([string]::IsNullOrWhiteSpace($hist)) { Write-Warning "Invoke-AIConsoleHelp: No history." }
    $fInst = $AIPromptInstruction -f $LinesToCapture, $UserPrompt; $fullPrompt = "$fInst$([Environment]::NewLine)$([Environment]::NewLine)$hist"
    Write-Verbose "Invoke-AIConsoleHelp: Prompt: `n$fullPrompt"; Write-Host "Invoke-AIConsoleHelp: Sending to AI ($AIChatExecutable)..."
    try { & $AIChatExecutable -e $fullPrompt } catch { Write-Error "Invoke-AIConsoleHelp: Failed: $($_.Exception.Message)" }
}

function Save-ConsoleHistoryLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] [int]$LinesToCapture = 15,
        [Parameter(Mandatory=$false)] [string]$LogFilePath = ".\log.txt"
    )
    $hist = Get-ConsoleTextAbovePrompt -L $LinesToCapture -EA SilentlyContinue; if ($null -eq $hist) { $hist = "" }
    try { Set-Content -Path $LogFilePath -Value $hist -Enc UTF8 -Force; Write-Host "Save-ConsoleHistoryLog: Saved to '$LogFilePath'." } catch { Write-Error "Save-ConsoleHistoryLog: Failed: $($_.Exception.Message)" }
}
#endregion Header and Configuration

# --- PSReadLine Hotkey Bindings ---
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # --- Alt+C: AI Command Suggestion Hotkey ---
    # (Remains the same as v2.7)
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
        
        $consoleHistory = Get-ConsoleTextAbovePrompt -LinesToCapture $linesToCapture -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($consoleHistory)) { $consoleHistory = "" }

        $formattedInstruction = $Global:Console2Ai_ConversationMode_AIPromptInstruction -f $linesToCapture, $userPromptForAI
        $fullAIPromptForConversation = if ([string]::IsNullOrWhiteSpace($consoleHistory)) { $formattedInstruction } else { "$formattedInstruction$([Environment]::NewLine)$([Environment]::NewLine)$consoleHistory" }
        $fullAIPromptForConversation = $fullAIPromptForConversation.TrimEnd()
        
        Write-Verbose "Console2Ai Hotkey (Alt+S): Full prompt for AI (stdin): `n$fullAIPromptForConversation"

        [Microsoft.PowerShell.PSConsoleReadLine]::DeleteLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert(" ") 
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine() 

        Write-Host "" 
        Write-Host "🗣️  Console2Ai (Conversation with AI)" -ForegroundColor Cyan
        Write-Host "   Sending your query: '$userPromptForAI'"
        Write-Host "   With context: Last $linesToCapture lines of console history."
        
        # --- MODIFICATION FOR DEBUGGING ---
        $tempOutputFile = Join-Path $env:TEMP "aichat_output_debug.txt"
        Write-Host "--- Starting AI session. Output will be redirected to '$tempOutputFile' ---" -ForegroundColor Yellow
        Write-Host "" 
        
        $PreviousOutputEncoding = $OutputEncoding 
        $OutputEncoding = [System.Text.Encoding]::UTF8 
        try {
            # Pipe the prompt and redirect STDOUT and STDERR to a file
            # Use *>&1 to merge stderr to stdout, then redirect stdout to file.
            # Or use separate redirections: > $tempOutputFile 2> $tempErrorFile
            $fullAIPromptForConversation | & $Global:Console2Ai_ConversationMode_AIChatExecutable *> $tempOutputFile
            
            Write-Host "--- AI process finished. Check '$tempOutputFile' for output. ---" -ForegroundColor Green
            if (Test-Path $tempOutputFile) {
                Write-Host "--- First few lines of '$tempOutputFile': ---"
                Get-Content $tempOutputFile -TotalCount 5 | ForEach-Object { Write-Host "FILE: $_" }
                Write-Host "--- End of preview ---"
            } else {
                Write-Host "Output file '$tempOutputFile' was not created." -ForegroundColor Red
            }

        } catch {
            Write-Error "Console2Ai Hotkey (Alt+S): Error executing AI chat '$($Global:Console2Ai_ConversationMode_AIChatExecutable)'."
            Write-Error ($_.Exception.Message) 
            Write-Host "--- AI session failed or ended with an error. ---" -ForegroundColor Red
        } finally {
            $OutputEncoding = $PreviousOutputEncoding 
            Write-Host "" 
        }
    }

    Write-Verbose "Console2Ai: Alt+C (Command Mode) and Alt+S (Conversation Mode) hotkeys registered."

} catch {
    Write-Warning "Console2Ai: Failed to set PSReadLine key handlers: $($_.Exception.Message)"
}
#endregion PSReadLine Hotkey Bindings