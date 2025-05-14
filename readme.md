# Console2Ai - PowerShell AI Assistant

[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Hits](https://hits.sh/github.com/MaxITService/Console2Ai.svg?style=flat)](https://hits.sh/github.com/MaxITService/Console2Ai/)

Console2Ai is a PowerShell script that captures your console screen buffer content and sends it to an AI assistant. It uses [`aichat`](https://github.com/sigoden/aichat) as the backend for AI processing.

---

# ⚠️ Important Note

> *— But I’ve seen products like **Warp**, **Codex CLI**, **Terminal Beta**, **Azure AIShell**, or **VS Code GitHub Copilot** do exactly the same!*

**There are similarities, but it's Not Exactly like this.** I’ve checked all these products, and technically, **none of them work with your past console screen buffer**—not a single one!

Let me explain:  
If you’re using Windows Terminal and suddenly realize you want to use an AI tool, here’s the catch:  
With those other products, if you didn’t start them at the beginning of your session, you have to manually “spin them up” first (except for warp, it has a button for it). Their seamless experience only works if you planned to use them from the start.

**This script is different:**  
- **You don’t need to prepare or restart your session - in any PowerShell window, anywhere where you can load your profile, you can use your past context AFTER you realized you need it.**
- **Just press a single key and starts supplying context to AI backend tool - it's script's single purpose.**  
- **No need for large agent system prompts, thus super cheap**  
- **No need to feed unneeded interactions to inference - only after you realized you need them, on a portion you need them**
- **Starts at the speed of inference, super fast.**
- **Price is your API token usage. (Hello warp)**
- **FOSS**
- **Windows terminal experience if you like it**

In short: **You get immediate, context-aware AI assistance, right when you need it—even if you decide to use it in the middle of your work. No setup, no waiting, no planning ahead.**

---


## Core Functionality

![Demo GIF](Promo/Gif_Demo.gif)


-   **Console Buffer to AI Prompt:** The main feature is capturing text from your PowerShell console buffer (the last N lines, you specify, 180 by default) and sending it directly to the AI as part of the prompt. This provides context from your recent commands and their output. You are unfortunately limited to what you see on screen. To capture more, you need to: in settings of your PowerShell profile, disable "Scroll to input when typing" and make window as big as possible and use Ctrl + Mousewheel to change scaling, the more you see, the more will be captured.
-   **Alt+C Hotkey:** Quick access to AI command suggestion with a simple keyboard shortcut. (What you typed as prompt will be REPLACED with ready to press enter command)
-   **Alt+S Hotkey:** Instantly start a conversational AI session with your console history and current query.
-   **Context Control:** Specify how many lines of console history (1-1999) to include in the AI prompt. Simply type a number before prompt and let it go! like "50 explain the last few commands and suggest an optimization" - number will be automatically picked up and parsed into console history line count.
-   **Session Logging:** Save your recent console lines to a text file for reference.

When you press Alt+C, the script analyzes your current input line, captures the specified number of console history lines, and sends everything to `aichat`. The AI response then replaces your current input line in the console.
Aichat is free and open source application.

## 📋 Prerequisites

Before you begin, ensure you have the following:

1.  **PowerShell:** Version 5.1 or higher. PowerShell 7+ is recommended for the best `PSReadLine` experience.
2.  **`aichat` by sigoden:** This is the AI chat client Console2Ai uses.
    -   **Installation:** Visit the [`aichat` GitHub releases page](https://github.com/sigoden/aichat/releases) and download the appropriate binary for your operating system (e.g., `aichat-*--x86_64-pc-windows-msvc.zip
`).
    -   **Link to repo if you need help:** [https://github.com/sigoden/aichat](https://github.com/sigoden/aichat)

## 🛠️ Installation & Configuration

Follow these steps to get Console2Ai up and running:

1.  **Install and Configure `aichat`**
    a.  **Download `aichat`:**
        Grab the latest release from [here](https://github.com/sigoden/aichat/releases). For Windows, you'll likely want the `...windows-x86_64.exe` file.

    b.  **Add `aichat` to your PATH:**
        For Console2Ai to find `aichat.exe`, it needs to be in your system's PATH.
        -   Create a dedicated folder for CLI tools, e.g., `C:\Tools\bin`
        -   Rename the downloaded `aichat` executable to `aichat.exe` and move it to this folder.
        -   Add this folder to your PATH. You can do this via PowerShell:

**For User PATH :**

```powershell
$CurrentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
$AichatPath = "C:\Tools\bin" # Change this to your actual folder
if (-not ($CurrentUserPath -split ';' -contains $AichatPath)) {
    [System.Environment]::SetEnvironmentVariable("Path", "$CurrentUserPath;$AichatPath", "User")
    Write-Host "Added '$AichatPath' to User PATH. Please restart PowerShell."
} else {
    Write-Host "'$AichatPath' is already in User PATH."
}
```

**For System PATH (requires Admin, affects all users):**



```powershell
$SystemPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$AichatPath = "C:\Tools\bin" # Change this to your actual folder
if (-not ($SystemPath -split ';' -contains $AichatPath)) {
    [System.Environment]::SetEnvironmentVariable("Path", "$SystemPath;$AichatPath", "Machine")
    Write-Host "Added '$AichatPath' to System PATH. Please restart PowerShell."
} else {
    Write-Host "'$AichatPath' is already in System PATH."
}
```

**Verify:** Open a *new* PowerShell terminal and type `aichat --version`. You should see the version information.

**c. Configure `aichat` Model & API Key:**
        `aichat` needs to know which AI model to use and requires an API key for that service (e.g., OpenAI, OpenRouter, Ollama, Gemini, etc.).
        Follow the detailed configuration instructions on the [aichat configuration example](https://github.com/sigoden/aichat/blob/main/config.example.yaml).
        Create or edit a `config.yaml` file. For Windows, this file is located at: `C:\Users\Username\AppData\Roaming\aichat\config.yaml` (replace `Username` with your Windows username).
        You can quickly open this folder by typing `explorer %APPDATA%\aichat` in PowerShell.
        You don't need to have everything, here is my config that works:
        Example configuration for OpenRouter with Claude:
        
        model: openrouter:anthropic/claude-3.7-sonnet
        clients:
        - type: openai-compatible
          name: openrouter
          api_base: https://openrouter.ai/api/v1
          api_key: sk-or-v1-a96_YOUR_API_KEY
        
Test `aichat` from your terminal after configuration:

        aichat "What is PowerShell?"
        
This will make sure the base application for this script is working.

2.  **Install `Console2Ai.ps1`**
    1.  Download `Console2Ai.ps1` from this repository and place it in a convenient folder (e.g., `C:\Users\YourUser\Documents\PowerShell\Scripts\Console2Ai.ps1` or `C:\Scripts\Console2Ai.ps1`).

    2.  Open your PowerShell profile for editing:
        ```powershell
        notepad $PROFILE
        ```

    3.  Copy and paste the following snippet into your profile (adjust the path as needed):
        ```powershell
        # Import-Module PSReadLine  # Uncomment if needed
        . C:\Users\YourUser\Documents\PowerShell\Scripts\Console2Ai.ps1  # Adjust path if needed
        ```

    4.  Save the profile and **restart PowerShell**.

## 🚀 How to Use Console2Ai

Once installed, you have a few ways to interact with Console2Ai:

1.  **The `Alt+C` Hotkey (Command Suggestion)** 🔥
    This is the quickest way to get AI assistance for command suggestions!

    a.  **Standard Query:**
        Type your question, command fragment, or error message into the PowerShell prompt.

        
        PS C:\> Get-ChildItem -Path C:\NonExistentFolder -Recurse # You see an error after this
        PS C:\> Retry with correct path # Now press Alt+C   


    It will send this to `aichat`, and replace your query with the AI's suggested command or explanation.

    b.  **Specify Line Count for History:** ✨
        If you want to provide more or less context from your console history:
        -   Start your typed line with a number (1-1999) followed by a space, then your query.

            
             ... lots of previous output ...
            PS C:\> 50 explain the last few commands and suggest an optimization # Press Alt+S
            
    Console2Ai will capture the last 50 lines of history along with your query.
    If you only type a number (e.g., `30`) and press `Alt+C`, it will use that many lines of history and a generic prompt for the AI.

2.  **The `Alt+S` Hotkey (Conversational Chat)** 💬
    Start a conversational AI session with your console history as context and your current query. Unlike Alt+C, Alt+S is focused on back-and-forth conversation, not just command suggestions.

    -   **How it works:**
        -   Type your question or message into the PowerShell prompt.
        -   Press `Alt+S`.
        -   Console2Ai will capture the last 180 lines of console history (by default) plus your typed query, then open a conversational AI session using `aichat`.
        -   The AI will reply conversationally, focusing on explanations, troubleshooting, or general answers (not just commands).
    -   **Example Usage:**
        -   To ask why your script is running slowly, type your query and press `Alt+S`:
            ```powershell
            PS C:\> from this dir, which files are needed for funciton and which are temporary files? # Press Alt+S
            ```
            This will start a response from AI including recent console history as context.
        -   To specify a different number of history lines (e.g., 40) works with both Alt+C and Alt+S:
            ```powershell
            PS C:\> 40 ok, all files you mentioned - delete them with Regex # Press Alt+C
    -   Under the hood, Alt+S calls the `Invoke-Console2AiConversation` function. And Alt+C calls `Invoke-AIConsoleHelp` function.

3.  **Using the PowerShell Functions** ⚙️
    Console2Ai also provides standard PowerShell functions if you prefer:

    a.  **`Invoke-AIConsoleHelp`**
        Manually trigger AI assistance.

        
        # Get help based on the last 180 lines of console history
        Invoke-AIConsoleHelp

        # Get help with more context and a specific prompt
        Invoke-AIConsoleHelp -LinesToCapture 25 -UserPrompt "What does this error mean and how to fix it?"
        

    b.  **`Invoke-Console2AiConversation`**
        Manually start a conversational AI session (same as Alt+S):
        
        Invoke-Console2AiConversation -UserQuery "Explain this error" -LinesToCapture 20
        

    c.  **`Save-ConsoleHistoryLog`** 💾
        Save recent console output to a file.
        
        # Save the last 180 lines to .\log.txt (if your window is big enough)
        Save-ConsoleHistoryLog

        # Save the last 30 lines to a custom file
        Save-ConsoleHistoryLog -LinesToCapture 30 -LogFilePath "C:\temp\session_details.txt"
        

4.  **Getting Help Within PowerShell** ❓
    You can use PowerShell's built-in help system:
    
        Get-Help Invoke-AIConsoleHelp -Full
        Get-Help Invoke-Console2AiConversation -Full
        Get-Help Save-ConsoleHistoryLog -Full
    

## 🔧 Customization (Optional)

You can modify `Console2Ai.ps1` directly to change:

-   **`$Global:Console2Ai_AIChatExecutable`**: If `aichat.exe` is named differently or you want to use a full path.
-   **`$Global:Console2Ai_CommandMode_AIPromptInstruction`**: The default instruction template sent to the AI for Alt+C (command suggestion).
-   **`$Global:Console2Ai_ConversationMode_AIPromptInstruction`**: The default instruction template sent to the AI for Alt+S (conversational chat).
-   **`$Global:Console2Ai_MaxLinesForHotkeyParse`**: The maximum number of console history lines you can specify for Alt+C/Alt+S hotkeys (default: 1999). Change this if you want to allow more or fewer lines to be parsed from the prompt.

## Troubleshooting

### Alt+C doesn't work

-   Ensure PSReadLine module is loaded. (It usually is by default in modern PowerShell).
-   Check your PowerShell profile (`$PROFILE`) to ensure `Console2Ai.ps1` is being dot-sourced correctly and after PSReadLine might be imported.
-   Ensure no other Alt+C binding is overriding it.

### AI Errors (❌ Console2Ai AI Error...)

-   Verify `aichat.exe` is in your PATH and working (`aichat --version`).
-   Check your `aichat` configuration (`%APPDATA%\aichat\config.yaml`). Is the model correct? Is your API key valid and correctly configured (e.g., `OPENAI_API_KEY` environment variable)?
-   Check your internet connection.

### "No console history was captured"

-   This can happen if the console buffer is empty or very short (e.g., right after `Clear-Host` or `cls`). The functions will still try to work with any typed user prompt.

## License

Do whatever you want just mention me if you can

## Promo (My other stuff!)
Check out my Free Extension for Web AI chats to quickly reuse your prompts:

[![Check out my Free Extension for Web AI chats to quickly reuse your prompts](https://github.com/MaxITService/ChatGPT-Quick-Buttons-for-your-text/raw/master/Promo/promo440_280.png)](https://chromewebstore.google.com/detail/oneclickprompts/iiofmimaakhhoiablomgcjpilebnndbf?authuser=1)

[OneClickPrompts on Chrome Web Store](https://chromewebstore.google.com/detail/oneclickprompts/iiofmimaakhhoiablomgcjpilebnndbf?authuser=1)

[it is open source](https://github.com/MaxITService/ChatGPT-Quick-Buttons-for-your-text)

https://www.reddit.com/user/lvvy/ reddit
