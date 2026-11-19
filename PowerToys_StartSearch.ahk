#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

; ==============================================================================
; PowerToys Command Palette - Start Menu Search Interceptor
;
; Mode: Option 1 (Type-to-Search Handoff)
;
; Workflow:
; 1. Pressing Win opens the Windows Start Menu normally for pinned apps & power.
; 2. As soon as you type any character or paste, the Start Menu dismisses,
;    PowerToys Command Palette is summoned, and your typed text is entered
;    into the Command Palette search field.
; 3. Win + S and Win + Q directly invoke Command Palette.
;
; NOTE: Keep this file ASCII-only. Windows PowerShell 5.1 and some editors
; mangle non-ASCII characters when the file is read without a BOM.
; ==============================================================================

; --- Configuration -------------------------------------------------------------

; CmdPal hotkey in AutoHotkey Send syntax. Setup.ps1 detects your configured
; Command Palette hotkey and writes it to settings.ini next to this script.
; Default: Win + Alt + Space.
global CmdPalHotkey := IniRead(A_ScriptDir "\settings.ini", "CmdPal", "Hotkey", "!#{Space}")
global CmdPalWindow := "ahk_exe Microsoft.CmdPal.UI.exe"

; Set while a handoff is running so that keys typed during the transition are
; buffered by the InputHook instead of re-triggering the handoff hotkeys.
global HandoffActive := false

A_IconTip := "PowerToys Command Palette - Start Search"

; --- System Tray Configuration ------------------------------------------------
Tray := A_TrayMenu
Tray.Delete()
Tray.Add("PowerToys Start Search (Active)", (*) => 0)
Tray.Disable("PowerToys Start Search (Active)")
Tray.Add()
Tray.Add("Suspend / Resume", ToggleSuspend)
Tray.Add("Reload Script", (*) => Reload())
Tray.Add("Exit", (*) => ExitApp())

ToggleSuspend(*) {
    Suspend -1
    if A_IsSuspended {
        Tray.Check("Suspend / Resume")
        A_IconTip := "PowerToys Command Palette - Start Search (Suspended)"
    } else {
        Tray.Uncheck("Suspend / Resume")
        A_IconTip := "PowerToys Command Palette - Start Search"
    }
}

; Check whether the Start Menu or Search Host currently has focus
IsStartOrSearchActive(*) {
    if HandoffActive
        return false
    return WinActive("ahk_exe StartMenuExperienceHost.exe")
        || WinActive("ahk_exe SearchHost.exe")
}

; Summon PowerToys Command Palette
SummonCmdPal(*) {
    SendInput CmdPalHotkey
}

; Resolve a hotkey name (e.g. "a", "+a", "Space", "Numpad5") to the character
; it would normally type (US layout for shifted symbols).
ResolveKeyToChar(key) {
    if (key == "Space" || key == "+Space")
        return " "

    ; Numpad keys
    if (SubStr(key, 1, 6) == "Numpad") {
        suffix := SubStr(key, 7)
        if (suffix ~= "^\d$")
            return suffix
        static numpadMap := Map("Dot", ".", "Div", "/", "Mult", "*", "Add", "+", "Sub", "-")
        return numpadMap.Has(suffix) ? numpadMap[suffix] : ""
    }

    ; Shifted keys
    if (StrLen(key) == 2 && SubStr(key, 1, 1) == "+") {
        base := SubStr(key, 2)
        if (base ~= "^[a-zA-Z]$") {
            ; CapsLock inverts Shift for letters
            return GetKeyState("CapsLock", "T") ? StrLower(base) : StrUpper(base)
        }

        static shiftMap := Map(
            "1", "!", "2", "@", "3", "#", "4", "$", "5", "%",
            "6", "^", "7", "&", "8", "*", "9", "(", "0", ")",
            "-", "_", "=", "+", "[", "{", "]", "}", "\", "|",
            ";", ":", "'", '"', ",", "<", ".", ">", "/", "?",
            "``", "~"
        )
        return shiftMap.Has(base) ? shiftMap[base] : base
    }

    ; Unshifted letters
    if (key ~= "^[a-zA-Z]$")
        return GetKeyState("CapsLock", "T") ? StrUpper(key) : StrLower(key)

    return key
}

; Wait for the Command Palette window to become active. Returns true if it did.
WaitForCmdPalReady() {
    ; CmdPal can take a while on its first (cold) launch.
    if !WinWaitActive(CmdPalWindow, , 2)
        return false

    ; Give the WinUI3 XAML tree time to render and auto-focus the search box.
    Sleep 150
    return true
}

; Close Start, open Command Palette, and send the query.
;   text  - text to type into Command Palette
;   paste - if true, paste the clipboard instead of typing text
Handoff(text, paste := false) {
    global HandoffActive
    if HandoffActive
        return
    HandoffActive := true

    try {
        ; 1. Buffer keystrokes typed during the transition. MinSendLevel 1
        ;    ignores this script's own Escape / CmdPal hotkey sends while
        ;    still capturing everything the user physically types.
        ih := InputHook("T5")
        ih.MinSendLevel := 1
        ih.VisibleNonText := false
        ih.KeyOpt("{Enter}{NumpadEnter}{Escape}", "E")  ; replayed afterwards
        ih.Start()

        ; 2. Dismiss Start Menu / Windows Search
        SendInput "{Escape}"
        Sleep 50

        ; 3. Summon Command Palette
        SummonCmdPal()
        ready := WaitForCmdPalReady()

        ; 4. Collect anything typed in the meantime
        ih.Stop()
        if !paste
            text .= ih.Input
        endKey := (ih.EndReason == "EndKey") ? ih.EndKey : ""

        if !ready {
            ; Command Palette didn't open (PowerToys not running, CmdPal
            ; disabled, or hotkey mismatch). Fall back to Windows Search so
            ; the user's keystrokes are not lost.
            TrayTip "Command Palette did not open. Is PowerToys running with Command Palette enabled?", "PowerToys Start Search", "Iconx"
            SendInput "{LWin}"
            WinWaitActive("ahk_exe SearchHost.exe", , 1)
            Sleep 100
        }

        ; 5. Send the query
        if paste
            SendInput "^v"
        else if (text != "")
            SendText text

        if (endKey != "")
            SendInput "{" endKey "}"
    } finally {
        HandoffActive := false
    }
}

HandoffTyped(thisHotkey) {
    Handoff(ResolveKeyToChar(thisHotkey))
}

HandoffPaste(*) {
    Handoff("", true)
}

; ==============================================================================
; Hotkey Initialization (Auto-Execute Section)
; ==============================================================================

; Global shortcuts for Windows Search
Hotkey "#s", SummonCmdPal
Hotkey "#q", SummonCmdPal

; Conditional hotkeys for Start Menu / Search typing
HotIf IsStartOrSearchActive

; Ctrl+V pastes the clipboard into Command Palette
Hotkey "^v", HandoffPaste

; Keys that start a typing handoff
keys := [
    "a","b","c","d","e","f","g","h","i","j","k","l","m",
    "n","o","p","q","r","s","t","u","v","w","x","y","z",
    "0","1","2","3","4","5","6","7","8","9",
    "Space",
    "-","=","[","]","\","`;","'",",",".","/","``",
    "Numpad0","Numpad1","Numpad2","Numpad3","Numpad4",
    "Numpad5","Numpad6","Numpad7","Numpad8","Numpad9",
    "NumpadDot","NumpadDiv","NumpadMult","NumpadAdd","NumpadSub"
]

for k in keys {
    ; try: some symbol keys don't exist on non-US keyboard layouts, and an
    ; invalid key name would otherwise abort the whole script at startup.
    try Hotkey k, HandoffTyped
    if (StrLen(k) == 1)
        try Hotkey "+" k, HandoffTyped
}

HotIf
