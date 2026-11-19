#Requires AutoHotkey v2.0
; ==============================================================================
; Runtime tests for PowerToys_StartSearch.ahk (run by CI on Windows).
;
; Loads the real interceptor script, then exercises its functions. Any
; unhandled runtime error fails the run. Results go to stdout; exit code is
; 0 on success, 1 on assertion failures, 2 on an unhandled error.
;
;   AutoHotkey64.exe /ErrorStdOut tests\Test-Interceptor.ahk > results.txt
; ==============================================================================

global TestFailures := 0
global TestCount := 0

OnError(TestOnError)
TestOnError(e, mode) {
    Log("UNHANDLED ERROR: " e.Message " | what=" e.What " | line=" e.Line " | file=" e.File)
    ExitApp 2
}

Log(msg) {
    FileAppend msg "`n", "*"
}

AssertEq(actual, expected, name) {
    global TestFailures, TestCount
    TestCount += 1
    if (actual == expected) {
        Log("PASS  " name)
    } else {
        TestFailures += 1
        Log("FAIL  " name "  expected [" expected "] got [" actual "]")
    }
}

AssertNoThrow(fn, name) {
    global TestFailures, TestCount
    TestCount += 1
    try {
        fn()
        Log("PASS  " name)
    } catch as e {
        TestFailures += 1
        Log("FAIL  " name "  threw: " e.Message)
    }
}

; --- Load the interceptor (its auto-execute section runs here) -----------------
#Include %A_ScriptDir%\..\PowerToys_StartSearch.ahk

; --- Configuration ------------------------------------------------------------
AssertEq(CmdPalHotkey, "!#{Space}", "default CmdPal hotkey when settings.ini is absent")

iniFile := A_Temp "\cmdpal-test-settings.ini"
try FileDelete iniFile
FileAppend "[CmdPal]`r`nHotkey=^+{F5}`r`n", iniFile
AssertEq(IniRead(iniFile, "CmdPal", "Hotkey", "!#{Space}"), "^+{F5}", "hotkey read from a Setup.ps1-style settings.ini")
FileDelete iniFile

; --- ResolveKeyToChar ---------------------------------------------------------
SetCapsLockState "Off"
cases := [
    ["a", "a"], ["z", "z"], ["+a", "A"], ["+q", "Q"],
    ["0", "0"], ["+1", "!"], ["+2", "@"], ["+9", "("], ["+0", ")"],
    ["Space", " "],
    ["-", "-"], ["+-", "_"], ["=", "="], ["+=", "+"],
    ["[", "["], ["+[", "{"], ["]", "]"], ["+]", "}"],
    ["\", "\"], ["+\", "|"], [";", ";"], ["+;", ":"],
    ["'", "'"], ["+'", '"'], [",", ","], ["+,", "<"],
    [".", "."], ["+.", ">"], ["/", "/"], ["+/", "?"],
    ["``", "``"], ["+``", "~"],
    ["Numpad0", "0"], ["Numpad7", "7"], ["NumpadDot", "."], ["NumpadDiv", "/"],
    ["NumpadMult", "*"], ["NumpadAdd", "+"], ["NumpadSub", "-"]
]
for c in cases
    AssertEq(ResolveKeyToChar(c[1]), c[2], "ResolveKeyToChar(" c[1] ")")

SetCapsLockState "On"
AssertEq(ResolveKeyToChar("a"), "A", "CapsLock: a -> A")
AssertEq(ResolveKeyToChar("+a"), "a", "CapsLock: Shift+a -> a")
AssertEq(ResolveKeyToChar("1"), "1", "CapsLock: digits unaffected")
SetCapsLockState "Off"

; --- Hotkey registration -------------------------------------------------------
; Hotkey(name, , "On") throws if the hotkey was never created.
HotIf IsStartOrSearchActive
for k in ["a", "+a", "z", "0", "+1", "Space", ";", "+;", "``", "Numpad5", "NumpadAdd", "^v"]
    AssertNoThrow(Hotkey.Bind(k, , "On"), "Start-menu hotkey registered: " k)
HotIf
AssertNoThrow(Hotkey.Bind("#s", , "On"), "global hotkey registered: Win+S")
AssertNoThrow(Hotkey.Bind("#q", , "On"), "global hotkey registered: Win+Q")

; --- Context check --------------------------------------------------------------
AssertEq(!!IsStartOrSearchActive(), false, "hotkeys inactive when Start is not focused")
HandoffActive := true
AssertEq(!!IsStartOrSearchActive(), false, "hotkeys inactive while a handoff is running")
HandoffActive := false

; --- Tray Suspend / Resume (previously crashed: Menu has no .Tip) -------------
AssertNoThrow(ToggleSuspend, "Suspend via tray menu")
AssertEq(A_IsSuspended, 1, "script is suspended")
AssertEq(A_IconTip, "PowerToys Command Palette - Start Search (Suspended)", "tray tip shows suspended")
AssertNoThrow(ToggleSuspend, "Resume via tray menu")
AssertEq(A_IsSuspended, 0, "script is resumed")

; --- Full handoff with Command Palette absent -----------------------------------
; CmdPal isn't installed in CI, so this exercises the timeout + Windows Search
; fallback path end to end. It must finish without errors and reset its flag.
start := A_TickCount
AssertNoThrow(HandoffTyped.Bind("+c"), "typed handoff runs without errors when CmdPal is absent")
elapsed := A_TickCount - start
AssertEq(HandoffActive, false, "handoff flag reset after typed handoff")
AssertEq(elapsed >= 1900 && elapsed < 6000, true, "handoff waited ~2s for CmdPal (took " elapsed "ms)")
AssertNoThrow(HandoffPaste, "paste handoff runs without errors when CmdPal is absent")
AssertEq(HandoffActive, false, "handoff flag reset after paste handoff")
try Send "{Escape}"  ; close Windows Search if the fallback opened it

; --- Done -------------------------------------------------------------------------
Log("")
Log(TestCount - TestFailures " passed, " TestFailures " failed")
ExitApp TestFailures ? 1 : 0
