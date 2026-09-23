// island_toggle - the YASB island's two entry points.
//
//   island_toggle.exe           the click: show or hide the resident panel
//   island_toggle.exe --label   the bar poll: print the island's label
//   island_toggle.exe --shortcuts   the keyboard button: show or hide the cheatsheet
//   island_toggle.exe --print <name>   the AI usage labels' JSON
//
// Both talk to the resident island_popup.ps1 instead of starting PowerShell,
// which cost ~750 ms of CPU per label poll (a C# compile and a WMI query every
// time). This uses ~60 ms.
//
// Built locally from this source (install.ps1 / build-island-toggle.ps1); no
// binary is committed to the repo.

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

static class IslandToggle
{
    [DllImport("user32.dll")]
    static extern bool AllowSetForegroundWindow(int processId);
    const int ASFW_ANY = -1;

    const string ResidentMutex = @"Local\YasbIslandResident";
    const string ToggleEvent   = @"Local\YasbIslandToggle";
    const string SheetEvent    = @"Local\YasbShortcutsToggle";

    [STAThread]
    static void Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--label") { PrintLabel(); return; }
        if (args.Length > 1 && args[0] == "--print") { PrintAiUsage(args[1]); return; }

        // This process was launched by the click, so Windows lets it take focus;
        // the resident popup was not. Hand the right on, or its window would open
        // without focus and then never hide when you click elsewhere.
        AllowSetForegroundWindow(ASFW_ANY);

        bool sheet = args.Length > 0 && args[0] == "--shortcuts";

        EventWaitHandle toggle;
        if (EventWaitHandle.TryOpenExisting(sheet ? SheetEvent : ToggleEvent, out toggle))
        {
            using (toggle) toggle.Set();
            return;
        }

        // No resident yet (first click after login, or it was ended): start one,
        // already showing. Slower, once.
        StartResident(sheet ? " -ShowShortcuts" : " -ShowOnStart");
    }

    // Prints the label the resident keeps in %TEMP%. If the resident is gone it
    // prints a plain clock instead and restarts it, so the bar never freezes on a
    // stale value - the next poll picks the real label back up.
    static void PrintLabel()
    {
        string path = Path.Combine(Path.GetTempPath(), "yasb_island_label.txt");
        string label = null;

        Mutex resident;
        bool alive = Mutex.TryOpenExisting(ResidentMutex, out resident);
        if (alive) resident.Dispose();

        // The label carries HH:mm, so a live resident rewrites it at least every
        // minute. Older than 90 s means its label thread is stuck even though the
        // process is up.
        if (alive && File.Exists(path) &&
            (DateTime.UtcNow - File.GetLastWriteTimeUtc(path)).TotalSeconds < 90)
        {
            for (int attempt = 0; attempt < 2 && label == null; attempt++)
            {
                try { label = File.ReadAllText(path, Encoding.UTF8); }
                catch (IOException) { Thread.Sleep(20); }   // caught mid-replace; try once more
            }
        }

        if (label == null)
        {
            // Default glyph as a number: kept ASCII so no editor or encoding can mangle it.
            label = ((char)0xF2DB).ToString() + " \"TIME\" " + DateTime.Now.ToString("HH:mm");
            if (!alive) StartResident("");
        }

        // Raw UTF-8 bytes, no BOM: YASB decodes stdout as UTF-8 and would render a BOM.
        byte[] bytes = new UTF8Encoding(false).GetBytes(label);
        using (Stream stdout = Console.OpenStandardOutput()) stdout.Write(bytes, 0, bytes.Length);
    }

    // --print claude | codex: the JSON the resident writes for the bar's AI usage
    // labels (label, label_alt, tooltip). Only %TEMP%\yasb_ai_<name>.json, and only
    // plain names, so this can never be pointed at another file.
    static void PrintAiUsage(string name)
    {
        foreach (char ch in name) if (!char.IsLetterOrDigit(ch)) return;

        string path = Path.Combine(Path.GetTempPath(), "yasb_ai_" + name + ".json");
        string json = null;

        // Rewritten every 30 s; ten minutes old means the resident has stopped.
        if (File.Exists(path) && (DateTime.UtcNow - File.GetLastWriteTimeUtc(path)).TotalMinutes < 10)
        {
            for (int attempt = 0; attempt < 2 && json == null; attempt++)
            {
                try { json = File.ReadAllText(path, Encoding.UTF8); }
                catch (IOException) { Thread.Sleep(20); }
            }
        }

        if (json == null)
        {
            string upper = name.ToUpperInvariant();
            json = "{\"label\":\"\\\"" + upper + "\\\" --\",\"label_alt\":\"\\\"" + upper + "\\\" --\"," +
                   "\"tooltip\":\"Waiting for usage data from YASB.\"}";
        }

        byte[] bytes = new UTF8Encoding(false).GetBytes(json);
        using (Stream stdout = Console.OpenStandardOutput()) stdout.Write(bytes, 0, bytes.Length);
    }

    static void StartResident(string showSwitch)
    {
        string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "island_popup.ps1");
        var start = new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"" + showSwitch);
        // ShellExecute, not CreateProcess with handle inheritance: in --label mode our
        // stdout is YASB's pipe, and a resident that inherited it would hold it open
        // for its whole life - YASB reads to end-of-output, so its label thread
        // would hang forever the first time a dead resident had to be restarted.
        start.UseShellExecute = true;
        start.WindowStyle     = ProcessWindowStyle.Hidden;
        Process.Start(start);
    }
}
