# Listens to UI Automation events from an AppKitCross window and prints them (ADR-0013).
#
#   powershell -ExecutionPolicy Bypass -File tools\windows\uia-events.ps1 -Title "Hello, AppKit on Windows" -Seconds 30
#   powershell -ExecutionPolicy Bypass -File tools\windows\uia-events.ps1 -SelfTest
#   powershell -ExecutionPolicy Bypass -File tools\windows\uia-events.ps1 -Title "Hello, AppKit on Windows" -Walk
#
# The handlers are C# (compiled here with Add-Type): UI Automation delivers events on
# its own threads, where a PowerShell script block has no runspace and fails silently,
# so the collection happens in C# and PowerShell only prints the list at the end.
# -Scope Desktop registers the property, event and structure handlers on the desktop
# root instead of the window's subtree. -SelfTest opens Notepad, focuses it and checks
# that a focus-changed event arrives, as a known-good baseline for the machine.
# -Walk (ADR-0013 follow-ups) prints the window's tree with each element's rectangle,
# AcceleratorKey and patterns, then walks the menu bar (the system's MenuBar of the HWND:
# expands View and lists its MenuItems, collapses it) and the first ComboBox (the colour
# pop-up: Expand shows a Menu of MenuItems, Invoke on the second picks it, the Value
# follows, the first is picked back), listening to MenuOpened/MenuClosed, focus and
# structure events meanwhile. Each step prints PASS/FAIL/INFO.
param(
    [string]$Title = "Hello, AppKit on Windows",
    [int]$Seconds = 30,
    [string]$Scope = "Window",
    [switch]$SelfTest,
    [switch]$Walk
)
$source = @"
using System;
using System.Collections.Generic;
using System.Windows.Automation;

public static class UiaEventLog {
    public static readonly List<string> Lines = new List<string>();
    static readonly object Gate = new object();
    static AutomationFocusChangedEventHandler focus;
    static AutomationPropertyChangedEventHandler property;
    static AutomationEventHandler plain;
    static StructureChangedEventHandler structure;

    static string Describe(object sender) {
        try {
            var e = sender as AutomationElement;
            if (e == null) return "<not an element>";
            var type = e.Current.ControlType.ProgrammaticName.Replace("ControlType.", "");
            return type + " '" + e.Current.Name + "' [" + e.Current.FrameworkId + "]";
        } catch (Exception ex) { return "<gone: " + ex.GetType().Name + ">"; }
    }
    static void Add(string line) {
        lock (Gate) { Lines.Add(DateTime.Now.ToString("HH:mm:ss.fff") + " " + line); }
    }
    public static AutomationElement FindWindow(string title) {
        var condition = new PropertyCondition(AutomationElement.NameProperty, title);
        return AutomationElement.RootElement.FindFirst(TreeScope.Children, condition);
    }
    public static void Start(AutomationElement scope) {
        focus = (sender, e) => Add("focus -> " + Describe(sender));
        Automation.AddAutomationFocusChangedEventHandler(focus);
        property = (sender, e) => Add("property " + e.Property.ProgrammaticName + " = '" + e.NewValue + "' on " + Describe(sender));
        Automation.AddAutomationPropertyChangedEventHandler(scope, TreeScope.Subtree, property,
            ValuePattern.ValueProperty, AutomationElement.NameProperty, TogglePattern.ToggleStateProperty,
            RangeValuePattern.ValueProperty, SelectionItemPattern.IsSelectedProperty);
        plain = (sender, e) => Add("event " + e.EventId.ProgrammaticName + " on " + Describe(sender));
        foreach (var id in new[] { TextPattern.TextChangedEvent, SelectionItemPattern.ElementSelectedEvent, InvokePattern.InvokedEvent }) {
            Automation.AddAutomationEventHandler(id, scope, TreeScope.Subtree, plain);
        }
        structure = (sender, e) => Add("structure " + e.StructureChangeType + " on " + Describe(sender) + " child runtime id [" + string.Join(",", e.GetRuntimeId() ?? new int[0]) + "]");
        Automation.AddStructureChangedEventHandler(scope, TreeScope.Subtree, structure);
        // Menus open in windows of their own: MenuOpened/MenuClosed are listened for on the desktop.
        foreach (var id in new[] { AutomationElement.MenuOpenedEvent, AutomationElement.MenuClosedEvent }) {
            Automation.AddAutomationEventHandler(id, AutomationElement.RootElement, TreeScope.Subtree, plain);
        }
    }

    // MARK: -Walk

    static string Patterns(AutomationElement e) {
        var names = new List<string>();
        foreach (var p in e.GetSupportedPatterns()) names.Add(p.ProgrammaticName.Replace("PatternIdentifiers.Pattern", ""));
        return string.Join(",", names);
    }
    static string Line(AutomationElement e) {
        var c = e.Current;
        var r = c.BoundingRectangle;
        var accel = string.IsNullOrEmpty(c.AcceleratorKey) ? "" : " accel=" + c.AcceleratorKey;
        string toggle = "";
        object tp;
        if (e.TryGetCurrentPattern(TogglePattern.Pattern, out tp)) toggle = " toggle=" + ((TogglePattern)tp).Current.ToggleState;
        string expand = "";
        object ep;
        if (e.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out ep)) expand = " " + ((ExpandCollapsePattern)ep).Current.ExpandCollapseState;
        return c.ControlType.ProgrammaticName.Replace("ControlType.", "") + " '" + c.Name + "' [" + c.FrameworkId + "] " +
               (r.IsEmpty ? "(no rect)" : string.Format("({0},{1} {2}x{3})", r.Left, r.Top, r.Width, r.Height)) + accel + toggle + expand + " {" + Patterns(e) + "}";
    }
    public static void Dump(AutomationElement e, int depth, int maxDepth) {
        Console.WriteLine(new string(' ', depth * 2) + Line(e));
        if (depth >= maxDepth) return;
        var walker = TreeWalker.ControlViewWalker;
        for (var c = walker.GetFirstChild(e); c != null; c = walker.GetNextSibling(c)) Dump(c, depth + 1, maxDepth);
    }
    static int failures = 0;
    static void Report(bool ok, string what) { if (!ok) failures++; Console.WriteLine((ok ? "PASS " : "FAIL ") + what); }
    static void Info(string what) { Console.WriteLine("INFO " + what); }
    static AutomationElement First(AutomationElement scope, ControlType type, string name = null) {
        Condition c = new PropertyCondition(AutomationElement.ControlTypeProperty, type);
        if (name != null) c = new AndCondition(c, new PropertyCondition(AutomationElement.NameProperty, name));
        return scope.FindFirst(TreeScope.Descendants, c);
    }
    /// The open menu: a top-level Menu (our menu windows are Menu elements at the root).
    static AutomationElement OpenMenu(int pid) {
        var c = new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Menu),
                                 new PropertyCondition(AutomationElement.ProcessIdProperty, pid));
        return AutomationElement.RootElement.FindFirst(TreeScope.Children, c) ?? AutomationElement.RootElement.FindFirst(TreeScope.Descendants, c);
    }
    public static int Walk(AutomationElement window) {
        failures = 0;
        int pid = window.Current.ProcessId;
        Console.WriteLine("== tree");
        Dump(window, 0, 6);
        Console.WriteLine("== menu bar (the system's MenuBar of the HWND)");
        var bar = First(window, ControlType.MenuBar);
        Report(bar != null, "the window has a MenuBar");
        if (bar != null) {
            var view = First(bar, ControlType.MenuItem, "View");
            Report(view != null, "MenuBar item 'View'");
            object ep;
            if (view != null && view.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out ep)) {
                try {
                    ((ExpandCollapsePattern)ep).Expand();
                    System.Threading.Thread.Sleep(600);
                    var menu = OpenMenu(pid) ?? First(AutomationElement.RootElement, ControlType.Menu, "View");
                    Report(menu != null, "View expanded into a Menu");
                    if (menu != null) {
                        Dump(menu, 1, 2);
                        var grid = First(menu, ControlType.MenuItem, "Show Grid");
                        Report(grid != null, "View > Show Grid");
                        if (grid != null) Info("Show Grid: " + Line(grid));
                    }
                    try { ((ExpandCollapsePattern)ep).Collapse(); } catch (Exception ex) { Info("Collapse: " + ex.GetType().Name); }
                } catch (Exception ex) {
                    Info("the system's menu-bar proxy refused Expand: " + ex.GetType().Name + " " + ex.Message + " (known; Alt and the mouse open it)");
                }
            } else if (view != null) {
                Info("View has no ExpandCollapse pattern: " + Line(view));
            }
        }
        Console.WriteLine("== pop-up (ComboBox)");
        var combo = First(window, ControlType.ComboBox);
        Report(combo != null, "a ComboBox (the colour pop-up)");
        if (combo != null) {
            Info(Line(combo));
            object ep, vp;
            Report(combo.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out ep), "the ComboBox has ExpandCollapse");
            string before = combo.TryGetCurrentPattern(ValuePattern.Pattern, out vp) ? ((ValuePattern)vp).Current.Value : "";
            Info("value before: '" + before + "'");
            if (ep != null) {
                ((ExpandCollapsePattern)ep).Expand();
                System.Threading.Thread.Sleep(600);
                Report(((ExpandCollapsePattern)ep).Current.ExpandCollapseState == ExpandCollapseState.Expanded, "expanded after Expand()");
                var walker = TreeWalker.ControlViewWalker;
                var child = walker.GetFirstChild(combo);
                Report(child != null && child.Current.ControlType == ControlType.Menu, "the open pop-up's child is a Menu");
                var items = new List<AutomationElement>();
                if (child != null) for (var c = walker.GetFirstChild(child); c != null; c = walker.GetNextSibling(c)) items.Add(c);
                foreach (var i in items) Info("  " + Line(i));
                Report(items.Count >= 2, items.Count + " MenuItem children");
                var standalone = OpenMenu(pid);
                Info("the menu window at the root: " + (standalone == null ? "none" : Line(standalone)));
                if (items.Count >= 2) {
                    object ip;
                    var target = items[1];
                    string name = target.Current.Name;
                    if (target.TryGetCurrentPattern(InvokePattern.Pattern, out ip)) {
                        ((InvokePattern)ip).Invoke();
                        System.Threading.Thread.Sleep(600);
                        string after = combo.TryGetCurrentPattern(ValuePattern.Pattern, out vp) ? ((ValuePattern)vp).Current.Value : "";
                        Report(after == name, "Invoke on '" + name + "' picked it (value '" + after + "')");
                        Report(((ExpandCollapsePattern)ep).Current.ExpandCollapseState == ExpandCollapseState.Collapsed, "collapsed after the pick");
                        // Put it back through the Value pattern.
                        try { ((ValuePattern)vp).SetValue(before); } catch (Exception ex) { Info("SetValue back: " + ex.Message); }
                    } else {
                        Report(false, "the item has Invoke");
                        ((ExpandCollapsePattern)ep).Collapse();
                    }
                } else {
                    ((ExpandCollapsePattern)ep).Collapse();
                }
            }
        }
        Console.WriteLine(failures == 0 ? "walk: all checks passed" : ("walk: " + failures + " check(s) failed"));
        return failures;
    }
    public static void Stop() { Automation.RemoveAllEventHandlers(); }
    public static string[] Snapshot() { lock (Gate) { return Lines.ToArray(); } }
}
"@
Add-Type -TypeDefinition $source -ReferencedAssemblies UIAutomationClient, UIAutomationTypes, WindowsBase

if ($SelfTest) {
    Write-Host "self-test: listening on the desktop, then focusing Notepad"
    [UiaEventLog]::Start([System.Windows.Automation.AutomationElement]::RootElement)
    $notepad = Start-Process notepad -PassThru
    Start-Sleep -Seconds 2
    # Windows 11's Notepad launcher exits and the window belongs to another process:
    # activate by title, not by the started PID.
    Add-Type -AssemblyName Microsoft.VisualBasic
    try { [Microsoft.VisualBasic.Interaction]::AppActivate("Notepad") } catch { Write-Host "self-test: AppActivate failed ($($_.Exception.Message)); relying on the launch focus" }
    Start-Sleep -Seconds 2
    [UiaEventLog]::Stop()
    $lines = [UiaEventLog]::Snapshot()
    Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
    Write-Host "$($lines.Count) event(s):"
    $lines | ForEach-Object { Write-Host "  $_" }
    if ($lines -match "focus") { Write-Host "self-test: PASS (focus events arrive on this machine)" } else { Write-Host "self-test: FAIL (no focus event even for Notepad)" }
    # (Windows 11 Notepad reports its editor as Document 'Text editor', not the window title.)
    exit 0
}

$window = [UiaEventLog]::FindWindow($Title)
if (-not $window) { Write-Error "no top-level window named '$Title'"; exit 2 }
Write-Host "window: $($window.Current.ControlType.ProgrammaticName) '$($window.Current.Name)' FrameworkId=$($window.Current.FrameworkId)"
if ($Walk) {
    [UiaEventLog]::Start($window)
    $failed = [UiaEventLog]::Walk($window)
    Start-Sleep -Milliseconds 500
    [UiaEventLog]::Stop()
    $lines = [UiaEventLog]::Snapshot()
    Write-Host "$($lines.Count) event(s) during the walk:"
    $lines | ForEach-Object { Write-Host "  $_" }
    exit $failed
}
$scopeElement = if ($Scope -eq "Desktop") { [System.Windows.Automation.AutomationElement]::RootElement } else { $window }
Write-Host "handlers scoped to: $Scope"
[UiaEventLog]::Start($scopeElement)
Write-Host "listening for $Seconds s: press Tab through the window, toggle the check box, type into the edit..."
Start-Sleep -Seconds $Seconds
[UiaEventLog]::Stop()
$lines = [UiaEventLog]::Snapshot()
Write-Host "$($lines.Count) event(s):"
$lines | ForEach-Object { Write-Host "  $_" }
