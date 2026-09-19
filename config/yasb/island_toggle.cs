// island_toggle - what YASB's island click runs.
//
// Signals the resident island_popup.ps1 to show or hide its panel, then exits.
// Replaces launching powershell.exe per click: this starts in tens of
// milliseconds instead of paying PowerShell and WPF startup every time.
//
// Built locally from this source (install.ps1 / build-island-toggle.ps1); no
// binary is committed to the repo.

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

static class IslandToggle
{
    [DllImport("user32.dll")]
    static extern bool AllowSetForegroundWindow(int processId);
    const int ASFW_ANY = -1;

    [STAThread]
    static void Main()
    {
        // This process was launched by the click, so Windows lets it take focus;
        // the resident popup was not. Hand the right on, or its window would open
        // without focus and then never hide when you click elsewhere.
        AllowSetForegroundWindow(ASFW_ANY);

        EventWaitHandle toggle;
        if (EventWaitHandle.TryOpenExisting(@"Local\YasbIslandToggle", out toggle))
        {
            using (toggle) toggle.Set();
            return;
        }

        // No resident yet (first click after login, or it was ended): start one,
        // already showing. Slower, once.
        string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "island_popup.ps1");
        var start = new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" -ShowOnStart");
        start.UseShellExecute = false;
        start.CreateNoWindow  = true;
        Process.Start(start);
    }
}
