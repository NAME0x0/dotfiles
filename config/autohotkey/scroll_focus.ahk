#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
;  Desktop keyboard script — komorebi focus scrolling + German accents.
;
;  1. Alt + ScrollWheel cycles focus through the Columns layout, approximating
;     PaperWM/Niri-style scrollable tiling on Windows.
;
;  2. Holding A / O / U / S for HOLD_MS replaces the letter with its German
;     form: a o u -> umlauts, s -> eszett. The letter is typed immediately on
;     key-down, so there is no input lag; if the key stays down long enough the
;     script backspaces over it and inserts the accented character. Auto-repeat
;     is suppressed on those four keys, so holding "a" no longer gives "aaaaa".
;     Case mirrors the keyboard: CapsLock XOR Shift. Eszett is always
;     lowercase (capital U+1E9E is deliberately not used).
;
;  Accents go dormant while a blocklisted window is focused (games), and wake
;  up the moment focus moves elsewhere. The script itself never stops.
;
;  Hotkeys:  Alt+Wheel          focus left/right
;            Alt+Shift+Wheel    move window left/right
;            Ctrl+Alt+U         accents on/off
;            Ctrl+Alt+I         show focused window's .exe and block status
;            Ctrl+Alt+Shift+Q   exit (also kills Alt+Wheel focus nav)
;
;  Launched at login by ScrollFocus.vbs in the Startup folder. komorebi does
;  not launch this script — komorebic has no --ahk flag.
; ============================================================================

SendMode "Input"
SetKeyDelay -1, -1
InstallKeybdHook
InstallMouseHook

; ----------------------------- CONFIG ---------------------------------------

HOLD_MS := 1000        ; how long the key must stay down to convert (ms)
TOAST_MS := 1200       ; how long the status tooltips stay up (ms)

; Windows whose process path contains any of these fragments are ignored.
; Covers Steam libraries, Epic installs and Ubisoft Connect games.
BLOCK_PATHS := [
    "\steamapps\common\",
    "\Epic Games\",
    "\Ubisoft Game Launcher\games\"
]

; Extra executables to ignore regardless of where they live.
; RobloxPlayerBeta.exe: Roblox installs per-user under AppData\Local\Roblox,
; which none of the path rules above catch.
BLOCK_EXES := [
    "Trackmania.exe",
    "TmForever.exe",
    "RobloxPlayerBeta.exe"
]

; Checked FIRST — these stay active even if a rule above would block them.
; Wallpaper Engine lives under steamapps\common but is a normal desktop app.
ALLOW_EXES := [
    "wallpaper32.exe",
    "wallpaper64.exe",
    "ui32.exe",
    "ui64.exe"
]

; ----------------------------- CHARACTER MAP --------------------------------
; Chr() codes instead of literal characters, so the file survives being saved
; in any encoding.

LOWER := Map(
    "a", Chr(0x00E4),   ; a-umlaut
    "o", Chr(0x00F6),   ; o-umlaut
    "u", Chr(0x00FC),   ; u-umlaut
    "s", Chr(0x00DF))   ; eszett

UPPER := Map(
    "a", Chr(0x00C4),   ; A-umlaut
    "o", Chr(0x00D6),   ; O-umlaut
    "u", Chr(0x00DC),   ; U-umlaut
    "s", Chr(0x00DF))   ; eszett stays lowercase

ACCENT_KEYS := ["a", "o", "u", "s"]

; Scancodes for the plain-letter echo. SendText delivers a Unicode packet
; (VK_PACKET), which games reading DirectInput/Raw Input ignore completely —
; that is what killed braking in Trackmania. A scancode looks like a real key.
SCAN := Map(
    "a", "{sc01E}",
    "o", "{sc018}",
    "u", "{sc016}",
    "s", "{sc01F}")

; ----------------------------- STATE ----------------------------------------

g_enabled   := true
g_heldKey   := ""       ; accent key currently physically down
g_armed     := false    ; a conversion is still pending for g_heldKey
g_startHwnd := 0        ; window that was active when the key went down

; Alt+Wheel focus scrolling, switched from the island panel's SCROLL FOCUS button.
; Only the four wheel hotkeys follow it; German accents are unaffected.
g_scroll := ReadScrollSetting()

; The panel sends this message: wParam 0 = off, 1 = on, 2 = just report. The
; reply is 100 + the resulting state, so the panel knows it landed and can show
; the real state instead of a remembered one. Must be registered here, in the
; auto-execute section - it ends at the first :: hotkey below.
OnMessage(0x8051, OnScrollToggle)

; ----------------------------- HOTKEY REGISTRATION --------------------------
; Registered with Hotkey() rather than as :: labels so all of it runs during
; the auto-execute section, which ends at the first :: definition below.

; Two variants per letter (plain and shifted) rather than a wildcard, so that
; Ctrl+A, Alt+S and friends are left completely alone.
;
; HotIf is what makes "dormant" mean dormant. Checking the blocklist inside the
; handler is too late — by then the hotkey has already swallowed the physical
; key, and nothing the script sends afterwards is a real keystroke. With HotIf,
; a blocked or disabled state means the hotkey is not active at all and the key
; reaches the application untouched.
HotIf AccentsActive
for key in ACCENT_KEYS {
    Hotkey "$" key,        AccentDown
    Hotkey "$" key " Up",  AccentUp
    Hotkey "$+" key,       AccentDown
    Hotkey "$+" key " Up", AccentUp
}
HotIf    ; back to global context for everything below

; Any other text-producing or caret-moving key cancels a pending conversion.
; Without this, holding "a" while typing "b" would backspace over the "b".
; Registered with ~* so they pass through untouched.
for key in CancelKeyList() {
    try Hotkey "~*" key, CancelPending
}

Hotkey "~*LButton", CancelPending
Hotkey "~*RButton", CancelPending
Hotkey "~*MButton", CancelPending

CancelKeyList() {
    keys := []
    for letter in StrSplit("bcdefghijklmnpqrtvwxyz")
        keys.Push(letter)
    for digit in StrSplit("0123456789")
        keys.Push(digit)
    for named in ["Space", "Enter", "Tab", "Backspace", "Delete", "Escape"
                , "Left", "Right", "Up", "Down", "Home", "End", "PgUp", "PgDn"
                , "NumpadEnter"]
        keys.Push(named)
    for punct in [",", ".", "/", ";", "'", "[", "]", "\", "-", "="]
        keys.Push(punct)
    return keys
}

; ----------------------------- ACCENT CORE ----------------------------------

; Gate for the accent hotkeys. Returning false leaves the key completely
; unhooked, so games and any other raw-input application see the hardware key.
AccentsActive(hotkeyName) {
    global g_enabled
    return g_enabled && !IsBlockedWindow()
}

AccentDown(hk) {
    global g_enabled, g_heldKey, g_armed, g_startHwnd, HOLD_MS, SCAN

    key := SubStr(hk, -1)

    ; Same key already down -> this is OS auto-repeat. Swallow it.
    if (g_heldKey = key)
        return

    ; A different accent key was down: its conversion is void.
    if (g_heldKey != "")
        CancelPending()

    g_heldKey   := key
    g_armed     := true
    g_startHwnd := WinExist("A")

    ; {Blind} keeps the real modifier state, so Shift and CapsLock produce the
    ; same character they would have without the script in the way.
    Send "{Blind}" SCAN[key]
    SetTimer ConvertPending, -HOLD_MS
}

AccentUp(hk) {
    global g_heldKey, g_armed

    key := SubStr(StrReplace(hk, " Up"), -1)

    ; Only the key that armed the timer may disarm it.
    if (g_heldKey != key)
        return

    SetTimer ConvertPending, 0
    g_heldKey := ""
    g_armed   := false
}

; Fires HOLD_MS after key-down. Everything below must still be true, because
; the conversion blind-fires a Backspace over whatever is left of the caret.
ConvertPending() {
    global g_enabled, g_heldKey, g_armed, g_startHwnd, LOWER, UPPER

    if (!g_armed || !g_enabled || g_heldKey = "")
        return

    key := g_heldKey

    ; Key must still be physically down.
    if (!GetKeyState(key, "P"))
        return

    ; Focus must not have moved to another window.
    if (WinExist("A") != g_startHwnd)
        return

    g_armed := false

    Send "{Backspace}"
    SendText(ShiftedCase() ? UPPER[key] : LOWER[key])
}

; Invoked by every non-accent key and by mouse clicks.
CancelPending(*) {
    global g_armed
    SetTimer ConvertPending, 0
    g_armed := false
}

; CapsLock XOR Shift — whatever the keyboard would have produced anyway. This
; is read for the plain letter too, not just the umlaut: the script re-sends
; the character itself, so ignoring CapsLock would type lowercase a/o/u/s
; while every untouched key on the keyboard produced capitals.
ShiftedCase() {
    caps  := GetKeyState("CapsLock", "T") ? 1 : 0
    shift := GetKeyState("Shift") ? 1 : 0
    return caps ^ shift
}

; ----------------------------- WINDOW BLOCKLIST -----------------------------

; Called on every accent keypress, so the result is cached per window handle.
IsBlockedWindow() {
    global BLOCK_PATHS, BLOCK_EXES, ALLOW_EXES
    static cachedHwnd := 0
    static cachedResult := false

    hwnd := WinExist("A")
    if (!hwnd)
        return false
    if (hwnd = cachedHwnd)
        return cachedResult

    cachedHwnd := hwnd
    cachedResult := false

    try {
        exe  := WinGetProcessName("ahk_id " hwnd)
        path := WinGetProcessPath("ahk_id " hwnd)
    } catch {
        return cachedResult    ; elevated or protected window: leave it enabled
    }

    for allowed in ALLOW_EXES {
        if (exe = allowed)
            return cachedResult
    }
    for blocked in BLOCK_EXES {
        if (exe = blocked)
            return cachedResult := true
    }
    for fragment in BLOCK_PATHS {
        if (InStr(path, fragment))
            return cachedResult := true
    }
    return cachedResult
}

; ----------------------------- TOAST ----------------------------------------

Toast(text) {
    global TOAST_MS
    ToolTip text
    SetTimer HideToast, -TOAST_MS
}

HideToast() {
    ToolTip
}

; ----------------------------- HOTKEYS --------------------------------------
; Everything below is a hotkey definition. The auto-execute section ends here,
; so no top-level setup code may follow.

; ─── Infinite Horizontal Scroll Focus ───
; Windows are tiled as equal-width columns; scrolling shifts focus through
; them like a horizontal carousel.

#HotIf ScrollActive()

; Alt + Scroll Down → Focus right (next window)
!WheelDown:: {
    Run 'komorebic.exe focus right', , 'Hide'
}

; Alt + Scroll Up → Focus left (previous window)
!WheelUp:: {
    Run 'komorebic.exe focus left', , 'Hide'
}

; Alt + Shift + Scroll Down → Move window right
!+WheelDown:: {
    Run 'komorebic.exe move right', , 'Hide'
}

; Alt + Shift + Scroll Up → Move window left
!+WheelUp:: {
    Run 'komorebic.exe move left', , 'Hide'
}

#HotIf

; ─── Accent control ───

^!u:: {
    global g_enabled
    g_enabled := !g_enabled
    CancelPending()
    Toast(g_enabled ? "German accents: ON" : "German accents: OFF")
}

; Shows the focused window's executable and whether it is currently blocked,
; so entries can be added to BLOCK_EXES without guesswork.
^!i:: {
    try {
        exe  := WinGetProcessName("A")
        path := WinGetProcessPath("A")
    } catch {
        Toast("Could not read the active window's process.")
        return
    }
    Toast(exe "`n" path "`n" (IsBlockedWindow() ? "-> blocked" : "-> active"))
}

^!+q::ExitApp

; ----------------------------- SCROLL TOGGLE ---------------------------------

ScrollActive(*) {
    global g_scroll
    return g_scroll
}

OnScrollToggle(wParam, lParam, msg, hwnd) {
    global g_scroll
    if (wParam = 0 || wParam = 1)
        g_scroll := (wParam = 1)
    return 100 + g_scroll
}

; The panel persists the setting so it survives a restart. Defaults to on.
ReadScrollSetting() {
    try {
        text := FileRead(A_Temp "\yasb_toggles.json", "UTF-8")
        if RegExMatch(text, '"scroll"\s*:\s*false')
            return false
    }
    return true
}
