# Console2Ai - PowerShell AI Assistant

[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Console2Ai is a PowerShell script that captures your console buffer content and sends it to an AI assistant. It uses [`aichat`](https://github.com/sigoden/aichat) as the backend for AI processing.

## Core Functionality

* **Console Buffer to AI Prompt:** The main feature is capturing text from your PowerShell console buffer (the last N lines) and sending it directly to the AI as part of the prompt. This provides context from your recent commands and their output.
* **Alt+C Hotkey:** Quick access to AI assistance with a simple keyboard shortcut.
* **Context Control:** Specify how many lines of console history (1-1999) to include in the AI prompt.
* **Session Logging:** Save your recent console lines to a text file for reference.

When you press Alt+C, the script analyzes your current input line, captures the specified number of console history lines, and sends everything to `aichat`. The AI response then replaces your current input line in the console.

## 📋 Prerequisites

Before you begin, ensure you have the following:

1.  **PowerShell:** Version 5.1 or higher. PowerShell 7+ is recommended for the best `PSReadLine` experience.
2.  **`aichat` by sigoden:** This is the AI chat client Console2Ai uses.
    *   **Installation:** Visit the [`aichat` GitHub releases page](https://github.com/sigoden/aichat/releases) and download the appropriate binary for your operating system (e.g., `aichat-*-windows-x86_64.exe`).
    *   **Link:** [https://github.com/sigoden/aichat?tab=readme-ov-file](https://github.com/sigoden/aichat?tab=readme-ov-file)

## 🛠️ Installation & Configuration

Follow these steps to get Console2Ai up and running:

### 1. Install and Configure `aichat`

   a.  **Download `aichat`:**
       Grab the latest release from [here](https://github.com/sigoden/aichat/releases). For Windows, you'll likely want the `...windows-x86_64.exe` file.

   b.  **Add `aichat` to your PATH:**
       For Console2Ai to find `aichat.exe`, it needs to be in your system's PATH.
       *   Create a dedicated folder for CLI tools, e.g., `C:\Tools\bin`.
       *   Rename the downloaded `aichat` executable to `aichat.exe` and move it to this folder.
       *   Add this folder to your PATH. You can do this via PowerShell:

         **For User PATH** (recommended, no admin rights needed):
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

         **For System PATH** (requires Admin, affects all users):
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
       *   **Verify:** Open a *new* PowerShell terminal and type `aichat --version`. You should see the version information.

   c.  **Configure `aichat` Model & API Key:**
       `aichat` needs to know which AI model to use and requires an API key for that service (e.g., OpenAI, OpenRouter, Ollama, Gemini, etc.).
       *   Follow the detailed configuration instructions on the [`aichat` configuration example](https://github.com/sigoden/aichat/blob/main/config.example.yaml).
       *   Create/edit a `config.yaml` file. For Windows, this file is located at: `C:\Users\Username\AppData\Roaming\aichat\config.yaml` (replace Username with your Windows username).
       *   You can quickly open this folder by typing `explorer %APPDATA%\aichat` in PowerShell.

       *   **Example configuration for OpenRouter with Claude:**

       ```yaml
       # see https://github.com/sigoden/aichat/blob/main/config.example.yaml
       model: openrouter:anthropic/claude-3.7-sonnet
       clients:
       - type: openai-compatible
         name: openrouter
         api_base: https://openrouter.ai/api/v1
         api_key: sk-or-v1-a96_YOUR_API_KEY
       ```
   
       *   Test `aichat` from your terminal after configuration: `aichat "What is PowerShell?"`
       *   This will make sure base application for this script is ok

### 2. Install `Console2Ai.ps1`

   a.  **Download the Script:**
       Download the `Console2Ai.ps1` script from this repository.

   b.  **Place it in a Scripts Folder:**
       Store `Console2Ai.ps1` in a convenient location, for example:
       *   `C:\Users\YourUser\Documents\PowerShell\Scripts\Console2Ai.ps1`
       *   Or a custom scripts folder like `C:\Scripts\Console2Ai.ps1`

   c.  **Add to your PowerShell Profile:**
       To make Console2Ai available every time you open PowerShell:
       *   Open your PowerShell profile script for editing:
         ```powershell
         notepad $PROFILE
         ```
        *   Add the following lines to your profile (adjust the path as needed):

          - If PSReadLine is not loaded by default, uncomment the first line.

         ```powershell
# Import-Module PSReadLine -ErrorAction SilentlyContinue  # Uncomment if needed
. C:\Users\YourUser\Documents\PowerShell\Scripts\Console2Ai.ps1  # Adjust path if needed
         ```
       *   Save the profile file and **restart PowerShell**.

## 🚀 How to Use Console2Ai

Once installed, you have a few ways to interact with Console2Ai:

### 1. The `Alt+C` Hotkey (Primary Method) 🔥

This is the quickest way to get AI assistance!

   a.  **Standard Query:**
       Type your question, command fragment, or error message into the PowerShell prompt.
       ```powershell
       PS C:\> Get-ChildItem -Path C:\NonExistentFolder -Recurse # You see an error after this
       PS C:\> How do I handle 'cannot find path' errors in Get-ChildItem? # Now press Alt+C
       ```
       Console2Ai will capture the last 15 lines of console history (by default) plus your typed query ("How do I handle..."). It will then show a `⌛ Console2Ai: Capturing 15 lines...` message, send it all to `aichat`, and replace your query with the AI's suggested command or explanation.

   b.  **Specify Line Count for History:** ✨
       If you want to provide more or less context from your console history:
       *   Start your typed line with a number (1-1999) followed by a space, then your query.
       ```powershell
       PS C:\> # ... lots of previous output ...
       PS C:\> 50 explain the last few commands and suggest an optimization # Press Alt+C
       ```
       Console2Ai will capture the last 50 lines of history along with your query.
       *   If you only type a number (e.g., `30`) and press `Alt+C`, it will use that many lines of history and a generic prompt for the AI.

### 2. Using the PowerShell Functions ⚙️

Console2Ai also provides standard PowerShell functions if you prefer:

   a.  **`Invoke-AIConsoleHelp`**
       Manually trigger AI assistance.
       ```powershell
       # Get help based on the last 15 lines of console history
       Invoke-AIConsoleHelp

       # Get help with more context and a specific prompt
       Invoke-AIConsoleHelp -LinesToCapture 25 -UserPrompt "What does this error mean and how to fix it?"
       ```

   b.  **`Save-ConsoleHistoryLog`** 💾
       Save recent console output to a file.
       ```powershell
       # Save the last 15 lines to .\log.txt
       Save-ConsoleHistoryLog

       # Save the last 30 lines to a custom file
       Save-ConsoleHistoryLog -LinesToCapture 30 -LogFilePath "C:\temp\session_details.txt"
       ```

### 3. Getting Help Within PowerShell ❓

You can use PowerShell's built-in help system:
```powershell
Get-Help Invoke-AIConsoleHelp -Full
Get-Help Save-ConsoleHistoryLog -Full
```

## 🔧 Customization (Optional)

You can modify Console2Ai.ps1 directly to change:

* **$Console2Ai_Hotkey_AIChatExecutable**: If aichat.exe is named differently or you want to use a full path.
* **$Console2Ai_Hotkey_AIPromptInstruction**: The default instruction template sent to the AI.

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

This project is licensed under the MIT License - see the LICENSE file for details (you should add one!).

Happy Hacking and may your console always be helpful! 🎉