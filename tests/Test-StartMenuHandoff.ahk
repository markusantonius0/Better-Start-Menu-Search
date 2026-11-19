#Requires AutoHotkey v2.0
; ==============================================================================
; End-to-end test: with the interceptor and PowerToys Command Palette running,
; open the Start Menu, type a query quickly, and verify Command Palette opens
; with the full query in its search box.
;
; Input is sent at SendLevel 1 so the interceptor (a separate AHK process whose
; hotkeys have InputLevel 0) treats it like physical typing.
; Exit code: 0 = pass, 1 = fail. Results go to stdout.
; ==============================================================================

Log(msg) => FileAppend(msg "`n", "*")

Fail(msg) {
    Log("FAIL  " msg)
    try Log("      active window: " WinGetTitle("A") " (" WinGetProcessName("A") ")")
    ExitApp 1
}

query := "calc"
SendLevel 1
SetKeyDelay 25, 10

if !WinExist("ahk_exe Microsoft.CmdPal.UI.exe") && !ProcessExist("Microsoft.CmdPal.UI.exe")
    Log("NOTE  Command Palette process not detected before test")

; Make sure nothing else is in the way
Send "{Escape}"
Sleep 300

; 1. Open Start
Send "{LWin}"
if !WinWaitActive("ahk_exe StartMenuExperienceHost.exe", , 5)
    && !WinWaitActive("ahk_exe SearchHost.exe", , 1)
    Fail("Start Menu did not open")
Log("PASS  Start Menu opened (" WinGetProcessName("A") ")")
Sleep 700

; 2. Type the query quickly (exercises the keystroke buffering during handoff)
SendEvent query

; 3. Command Palette should take over
if !WinWaitActive("ahk_exe Microsoft.CmdPal.UI.exe", , 5)
    Fail("Command Palette did not become active after typing in Start")
Log("PASS  Command Palette became active")

; 4. Read back the search box text via the clipboard
Sleep 1000
A_Clipboard := ""
SendLevel 0
Send "^a^c"
ClipWait 2
got := A_Clipboard
if (got != query)
    Fail("search box contained [" got "], expected [" query "]")
Log("PASS  search box contains [" got "]")

Send "{Escape}"
Log("PASS  end-to-end handoff")
ExitApp 0
