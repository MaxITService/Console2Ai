# Console2Ai - PowerShell AI Assistant

[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Console2Ai is a PowerShell script that captures your console buffer content and sends it to an AI assistant. It uses [`aichat`](https://github.com/sigoden/aichat) as the backend for AI processing.

## Core Functionality

* **Console Buffer to AI Prompt:** The main feature is capturing text from your PowerShell console buffer (the last N line, you specify, 15 by default) and sending it directly to the AI as part of the prompt. This provides context from your recent commands and their output.
* **Alt+C Hotkey:** Quick access to AI command suggestion with a simple keyboard shortcut. (What you typed as prompt will be REPLACED with ready to press enter command)
* **Alt+S Hotkey:** Instantly start a conversational AI session with your console history and current query.
* **Context Control:** Specify how many lines of console history (1-1999) to include in the AI prompt. Simply typr a number before prompt and let it go! like "50 explain the last few commands and suggest an optimization" - number will be automatically picked up and parsed into console history line count.
* **Session Logging:** Save your recent console lines to a text file for reference.

When you press Alt+C, the script analyzes your current input line, captures the specified number of console history lines, and sends everything to `aichat`. The AI response then replaces your current input line in the console.

## 📋 Prerequisites

Before you begin, ensure you have the following:

1. **PowerShell:** Version 5.1 or higher. PowerShell 7+ is recommended for the best `PSReadLine` experience.
2. **`aichat` by sigoden:** This is the AI chat client Console2Ai uses.
   * **Installation:** Visit the [`aichat` GitHub releases page](https://github.com/sigoden/aichat/releases) and download the appropriate binary for your operating system (e.g., `aichat-*-windows-x86_64.exe`).
   * **Link:** [https://github.com/sigoden/aichat?tab=readme-ov-file](https://github.com/sigoden/aichat?tab=readme-ov-file)

## 🛠️ Installation & Configuration

Follow these steps to get Console2Ai up and running:

### 1. Install and Configure `aichat`

   a. **Download `aichat`:**
      Grab the latest release from [here](https://github.com/sigoden/aichat/releases). For Windows, you'll likely want the `...windows-x86_64.exe` file.

   b. **Add `aichat` to your PATH:**
      For Console2Ai to find `aichat.exe`, it needs to be in your system's PATH.
      *Create a dedicated folder for CLI tools, e.g., `C:\Tools\bin`.
      * Rename the downloaded `aichat` executable to `aichat.exe` and move it to this folder.
      * Add this folder to your PATH. You can do this via PowerShell:

       For User PATH (recommended, no admin rights needed):

           $CurrentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
           $AichatPath = "C:\Tools\bin" # Change this to your actual folder
           if (-not ($CurrentUserPath -split ';' -contains $AichatPath)) {
               [System.Environment]::SetEnvironmentVariable("Path", "$CurrentUserPath;$AichatPath", "User")
               Write-Host "Added '$AichatPath' to User PATH. Please restart PowerShell."
           } else {
               Write-Host "'$AichatPath' is already in User PATH."
           }

       For System PATH (requires Admin, affects all users):

           $SystemPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
           $AichatPath = "C:\Tools\bin" # Change this to your actual folder
           if (-not ($SystemPath -split ';' -contains $AichatPath)) {
              [System.Environment]::SetEnvironmentVariable("Path", "$SystemPath;$AichatPath", "Machine")
              Write-Host "Added '$AichatPath' to System PATH. Please restart PowerShell."
           } else {
              Write-Host "'$AichatPath' is already in System PATH."
           }

      * **Verify:** Open a *new* PowerShell terminal and type `aichat --version`. You should see the version information.

   c.  **Configure `aichat` Model & API Key:**
       `aichat` needs to know which AI model to use and requires an API key for that service (e.g., OpenAI, OpenRouter, Ollama, Gemini, etc.).
       *Follow the detailed configuration instructions on the [aichat configuration example](https://github.com/sigoden/aichat/blob/main/config.example.yaml).
       * Create/edit a `config.yaml` file. For Windows, this file is located at: `C:\Users\Username\AppData\Roaming\aichat\config.yaml` (replace Username with your Windows username).
       *   You can quickly open this folder by typing `explorer %APPDATA%\aichat` in PowerShell.

       *   **Example configuration for OpenRouter with Claude:**

            model: openrouter:anthropic/claude-3.7-sonnet
            clients:
            - type: openai-compatible
              name: openrouter
              api_base: https://openrouter.ai/api/v1
              api_key: sk-or-v1-a96_YOUR_API_KEY
   
       *   Test `aichat` from your terminal after configuration: `aichat "What is PowerShell?"`
       *   This will make sure base application for this script is ok

### 2. Install `Console2Ai.ps1`

1. Download `Console2Ai.ps1` from this repository and place it in a convenient folder (e.g., `C:\Users\YourUser\Documents\PowerShell\Scripts\Console2Ai.ps1` or `C:\Scripts\Console2Ai.ps1`).

2. Open your PowerShell profile for editing:

    notepad $PROFILE

3. Copy and paste the following snippet into your profile (adjust the path as needed):

       # Import-Module PSReadLine -ErrorAction SilentlyContinue  # Uncomment if needed
       . C:\Users\YourUser\Documents\PowerShell\Scripts\Console2Ai.ps1  # Adjust path if needed

4. Save the profile and **restart PowerShell**.

## 🚀 How to Use Console2Ai

Once installed, you have a few ways to interact with Console2Ai:

### 1. The `Alt+C` Hotkey (Command Suggestion) 🔥

This is the quickest way to get AI assistance for command suggestions!

   a.  **Standard Query:**
       Type your question, command fragment, or error message into the PowerShell prompt.
       ```powershell
       PS C:\> Get-ChildItem -Path C:\NonExistentFolder -Recurse # You see an error after this
       PS C:\> How do I handle 'cannot find path' errors in Get-ChildItem? # Now press Alt+C
       ```
       Console2Ai will capture the last 15 lines of console history (by default) plus your typed query ("How do I handle..."). It will then show a status message like:

    ⌛ Console2Ai (Cmd): Asking AI about 'How do I handle 'cannot find path' errors in Get-ChildItem?' (context: 15 lines)...

It will send this to `aichat`, and replace your query with the AI's suggested command or explanation.

   b.  **Specify Line Count for History:** ✨
       If you want to provide more or less context from your console history:
       *   Start your typed line with a number (1-1999) followed by a space, then your query.

            PS C:\> # ... lots of previous output ...
            PS C:\> 50 explain the last few commands and suggest an optimization # Press Alt+C
       Console2Ai will capture the last 50 lines of history along with your query.
       *   If you only type a number (e.g., `30`) and press `Alt+C`, it will use that many lines of history and a generic prompt for the AI.

### 2. The `Alt+S` Hotkey (Conversational Chat) 💬

Start a conversational AI session with your console history as context and your current query. Unlike Alt+C, Alt+S is focused on back-and-forth conversation, not just command suggestions.

* **How it works:**

    * Type your question or message into the PowerShell prompt.
    * Press `Alt+S`.
    * Console2Ai will capture the last 15 lines of console history (by default) plus your typed query, then open a conversational AI session using `aichat`.
    * The AI will reply conversationally, focusing on explanations, troubleshooting, or general answers (not just commands).

**Example:**

    PS C:\> Why is my script running slowly? # Press Alt+S

* This will start a chat session with the AI, including recent console history as context.
* You can also specify how many lines of history to include:

    PS C:\> 40 What are some ways to optimize this script? # Press Alt+S

* Under the hood, Alt+S calls the `Invoke-Console2AiConversation` function.

### 3. Using the PowerShell Functions ⚙️

Console2Ai also provides standard PowerShell functions if you prefer:

   a.  **`Invoke-AIConsoleHelp`**

       Manually trigger AI assistance.

           # Get help based on the last 15 lines of console history
           Invoke-AIConsoleHelp

           # Get help with more context and a specific prompt
           Invoke-AIConsoleHelp -LinesToCapture 25 -UserPrompt "What does this error mean and how to fix it?"

   b.  **`Invoke-Console2AiConversation`**

       Manually start a conversational AI session (same as Alt+S):

           Invoke-Console2AiConversation -UserQuery "Explain this error" -LinesToCapture 20

   c.  **`Save-ConsoleHistoryLog`** 💾

       Save recent console output to a file.

           # Save the last 15 lines to .\log.txt
           Save-ConsoleHistoryLog

           # Save the last 30 lines to a custom file
           Save-ConsoleHistoryLog -LinesToCapture 30 -LogFilePath "C:\temp\session_details.txt"

### 4. Getting Help Within PowerShell ❓

You can use PowerShell's built-in help system:

    Get-Help Invoke-AIConsoleHelp -Full
    Get-Help Invoke-Console2AiConversation -Full
    Get-Help Save-ConsoleHistoryLog -Full

## 🔧 Customization (Optional)

You can modify Console2Ai.ps1 directly to change:

* **$Global:Console2Ai_AIChatExecutable**: If `aichat.exe` is named differently or you want to use a full path.
* **$Global:Console2Ai_CommandMode_AIPromptInstruction**: The default instruction template sent to the AI for Alt+C (command suggestion).
* **$Global:Console2Ai_ConversationMode_AIPromptInstruction**: The default instruction template sent to the AI for Alt+S (conversational chat).
* **$Global:Console2Ai_MaxLinesForHotkeyParse**: The maximum number of console history lines you can specify for Alt+C/Alt+S hotkeys (default: 1999). Change this if you want to allow more or fewer lines to be parsed from the prompt.

## Troubleshooting

### Alt+C doesn't work

* Ensure PSReadLine module is loaded. (It usually is by default in modern PowerShell).
* Check your PowerShell profile ($PROFILE) to ensure Console2Ai.ps1 is being dot-sourced correctly and after PSReadLine might be imported.
* No other Alt+C binding is overriding it.

### AI Errors (❌ Console2Ai AI Error...)

* Verify aichat.exe is in your PATH and working (aichat --version).
* Check your aichat configuration (%APPDATA%\aichat\config.yaml). Is the model correct? Is your API key valid and correctly configured (e.g., OPENAI_API_KEY environment variable)?
* Check your internet connection.

### "No console history was captured"

* This can happen if the console buffer is empty or very short (e.g., right after Clear-Host or cls). The functions will still try to work with any typed user prompt.

## License

Do whatever you want just mention me
