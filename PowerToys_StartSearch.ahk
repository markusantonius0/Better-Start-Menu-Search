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
;    PowerToys Command Palette (Win + Alt + Space) is summoned, and your typed
;    text is seamlessly entered into the Command Palette search field.
; 3. Win + S and Win + Q directly invoke Command Palette.
; ==============================================================================

A_IconTip := "PowerToys Command Palette - Start Search"

; --- System Tray Configuration ---
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
        Tray.Tip := "PowerToys Command Palette - Start Search (Suspended)"
    } else {
        Tray.Uncheck("Suspend / Resume")
        Tray.Tip := "PowerToys Command Palette - Start Search"
    }
}

; Check whether the Start Menu or Search Host currently has focus
IsStartOrSearchActive(*) {
    return WinActive("ahk_exe StartMenuExperienceHost.exe") 
        || WinActive("ahk_exe SearchHost.exe")
}

; Summon PowerToys Command Palette
SummonCmdPal(*) {
    SendInput "!#{Space}" ; CmdPal hotkey â€” patched by Setup.ps1
}

; Resolve key name / shift state to the appropriate character
ResolveKeyToChar(key) {
    if (key == "Space")
        return " "
    
    ; Numpad keys
    if (SubStr(key, 1, 6) == "Numpad") {
        suffix := SubStr(key, 7)
        if (suffix ~= "^\d$")
            return suffix
        if (suffix == "Dot")
            return "."
        if (suffix == "Div")
            return "/"
        if (suffix == "Mult")
            return "*"
        if (suffix == "Add")
            return "+"
        if (suffix == "Sub")
            return "-"
        return ""
    }

    ; Shifted keys
    if (SubStr(key, 1, 1) == "+") {
        base := SubStr(key, 2)
        if (base ~= "^[a-zA-Z]$") {
            ; Check CapsLock state for inversion
            return GetKeyState("CapsLock", "T") ? StrLower(base) : StrUpper(base)
        }
        
        static shiftMap := Map(
            "1", "!", "2", "@", "3", "#", "4", "$", "5", "%",
            "6", "^", "7", "&", "8", "*", "9", "(", "0", ")",
            "-", "_", "=", "+", "[", "{", "]", "}", "\", "|",
            ";", ":", "'", '"', ",", "<", ".", ">", "/", "?",
            "``", "~"
        )
        if shiftMap.Has(base)
            return shiftMap[base]
        return base
    }

    ; Unshifted letters
    if (key ~= "^[a-zA-Z]$") {
        return GetKeyState("CapsLock", "T") ? StrUpper(key) : StrLower(key)
    }

    return key
}

; Wait for Command Palette window to appear and its search box to gain focus.
; WinUI3 apps need extra time for the XAML tree to initialize after the window
; becomes "active" â€” the search TextBox isn't focusable immediately.
WaitForCmdPalReady() {
    ; Phase 1: Wait for the window itself (up to 500ms)
    loop 25 {
        if WinActive("ahk_exe Microsoft.CmdPal.UI.exe")
            break
        Sleep 20
    }

    ; Phase 2: Give the WinUI3 XAML tree time to fully render and auto-focus
    ; the search box. CmdPal has "HighlightSearchOnActivate: true" which means
    ; it will focus the search box, but it needs the render cycle to complete.
    Sleep 150

    ; Phase 3: As a safety net, send Tab then Shift+Tab to force-cycle focus
    ; back to the search box in case XAML auto-focus didn't fire.
    SendInput "{Tab}{Shift down}{Tab}{Shift up}"
    Sleep 30
}

; Handoff sequence: closes Start Menu, opens Command Palette, sends typed query
HandoffToCmdPal(firstKey) {
    ; 1. Start an input hook to capture any fast keystrokes typed during transition
    ih := InputHook("T0.6") ; Max 600ms buffer timeout (matches longer wait)
    ih.VisibleNonText := false
    ih.KeyOpt("{All}", "N")  ; Intercept and buffer all keys
    ih.Start()

    ; 2. Dismiss Start Menu / Windows Search
    SendInput "{Escape}"
    Sleep 30

    ; 3. Summon Command Palette (Win + Alt + Space)
    SummonCmdPal()

    ; 4. Wait for Command Palette to be ready with search box focused
    WaitForCmdPalReady()

    ; 5. Stop the buffer and collect any characters typed during the switch
    ih.Stop()
    bufferedInput := ih.Input

    ; 6. Send the initial character followed by buffered input
    initialChar := ResolveKeyToChar(firstKey)
    fullText := initialChar . bufferedInput

    if (fullText != "") {
        SendText fullText
    }
}

; Direct paste handoff (Ctrl + V while Start is open)
HandoffPaste(*) {
    SendInput "{Escape}"
    Sleep 30
    SummonCmdPal()
    WaitForCmdPalReady()
    SendInput "^v"
}

; ==============================================================================
; Hotkey Initialization (Auto-Execute Section)
; ==============================================================================

; Global shortcuts for Windows Search
Hotkey "#s", SummonCmdPal
Hotkey "#q", SummonCmdPal

; Conditional hotkeys for Start Menu / Search typing
HotIf IsStartOrSearchActive

; Register Ctrl+V for paste handoff
Hotkey "^v", HandoffPaste

; Register keys for typing handoff
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
    Hotkey k, HandoffToCmdPal
    if (StrLen(k) == 1 && SubStr(k, 1, 6) != "Numpad") {
        Hotkey "+" . k, HandoffToCmdPal
    }
}

HotIf
