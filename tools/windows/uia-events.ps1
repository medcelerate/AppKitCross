# Listens to UI Automation events from an AppKitCross window and prints them (ADR-0013).
#
#   powershell -ExecutionPolicy Bypass -File tools\windows\uia-events.ps1 -Title "Hello, AppKit on Windows" -Seconds 30
#   powershell -ExecutionPolicy Bypass -File tools\windows\uia-events.ps1 -SelfTest
#
# The handlers are C# (compiled here with Add-Type): UI Automation delivers events on
# its own threads, where a PowerShell script block has no runspace and fails silently,
# so the collection happens in C# and PowerShell only prints the list at the end.
# -Scope Desktop registers the property, event and structure handlers on the desktop
# root instead of the window's subtree. -SelfTest opens Notepad, focuses it and checks
# that a focus-changed event arrives, as a known-good baseline for the machine.
param(
    [string]$Title = "Hello, AppKit on Windows",
    [int]$Seconds = 30,
    [string]$Scope = "Window",
    [switch]$SelfTest
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
        structure = (sender, e) => Add("structure " + e.StructureChangeType + " on " + Describe(sender));
        Automation.AddStructureChangedEventHandler(scope, TreeScope.Subtree, structure);
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
$scopeElement = if ($Scope -eq "Desktop") { [System.Windows.Automation.AutomationElement]::RootElement } else { $window }
Write-Host "handlers scoped to: $Scope"
[UiaEventLog]::Start($scopeElement)
Write-Host "listening for $Seconds s: press Tab through the window, toggle the check box, type into the edit..."
Start-Sleep -Seconds $Seconds
[UiaEventLog]::Stop()
$lines = [UiaEventLog]::Snapshot()
Write-Host "$($lines.Count) event(s):"
$lines | ForEach-Object { Write-Host "  $_" }
