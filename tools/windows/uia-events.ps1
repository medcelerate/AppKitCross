# Listens to UI Automation events from an AppKitWin window and prints them (ADR-0013).
#
#   powershell -ExecutionPolicy Bypass -File tools\windows\uia-events.ps1 -Title "Hello, AppKit on Windows" -Seconds 30
#
# Subscribes to focus changes, Value.Value and Name property changes, Text changes and
# structure changes on the window's subtree, then pumps a WinForms message loop for
# `-Seconds` so handlers (which arrive on UIA's own threads) are collected and printed
# in order. Use it while pressing Tab through the window or typing into a field.
param(
    [string]$Title = "Hello, AppKit on Windows",
    [int]$Seconds = 30
)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

$events = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
function Describe($element) {
    try {
        $name = $element.Current.Name
        $type = $element.Current.ControlType.ProgrammaticName -replace '^ControlType\.', ''
        return "$type '$name'"
    } catch { return "<gone>" }
}

$root = [System.Windows.Automation.AutomationElement]::RootElement
$condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Title)
$window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
if (-not $window) { Write-Error "no top-level window named '$Title'"; exit 2 }
Write-Host "window: $(Describe $window) FrameworkId=$($window.Current.FrameworkId)"

$focusHandler = [System.Windows.Automation.AutomationFocusChangedEventHandler] {
    param($sender, $e)
    [void]$events.Add("$(Get-Date -Format HH:mm:ss.fff) focus -> $(Describe $sender)")
}
[System.Windows.Automation.Automation]::AddAutomationFocusChangedEventHandler($focusHandler)

$propertyHandler = [System.Windows.Automation.AutomationPropertyChangedEventHandler] {
    param($sender, $e)
    [void]$events.Add("$(Get-Date -Format HH:mm:ss.fff) property $($e.Property.ProgrammaticName) = '$($e.NewValue)' on $(Describe $sender)")
}
[System.Windows.Automation.Automation]::AddAutomationPropertyChangedEventHandler($window, [System.Windows.Automation.TreeScope]::Subtree, $propertyHandler,
    @([System.Windows.Automation.ValuePattern]::ValueProperty, [System.Windows.Automation.AutomationElement]::NameProperty,
      [System.Windows.Automation.TogglePattern]::ToggleStateProperty, [System.Windows.Automation.RangeValuePattern]::ValueProperty,
      [System.Windows.Automation.SelectionItemPattern]::IsSelectedProperty))

$eventHandler = [System.Windows.Automation.AutomationEventHandler] {
    param($sender, $e)
    [void]$events.Add("$(Get-Date -Format HH:mm:ss.fff) event $($e.EventId.ProgrammaticName) on $(Describe $sender)")
}
foreach ($id in @([System.Windows.Automation.TextPattern]::TextChangedEvent, [System.Windows.Automation.SelectionItemPattern]::ElementSelectedEvent,
                  [System.Windows.Automation.InvokePattern]::InvokedEvent)) {
    [System.Windows.Automation.Automation]::AddAutomationEventHandler($id, $window, [System.Windows.Automation.TreeScope]::Subtree, $eventHandler)
}
$structureHandler = [System.Windows.Automation.StructureChangedEventHandler] {
    param($sender, $e)
    [void]$events.Add("$(Get-Date -Format HH:mm:ss.fff) structure $($e.StructureChangeType) on $(Describe $sender)")
}
[System.Windows.Automation.Automation]::AddStructureChangedEventHandler($window, [System.Windows.Automation.TreeScope]::Subtree, $structureHandler)

Write-Host "listening for $Seconds s: press Tab through the window, toggle the check box, type into the edit..."
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $Seconds * 1000
$timer.Add_Tick({ [System.Windows.Forms.Application]::Exit() })
$timer.Start()
[System.Windows.Forms.Application]::Run()
[System.Windows.Automation.Automation]::RemoveAllEventHandlers()
Write-Host "$($events.Count) event(s):"
$events | ForEach-Object { Write-Host "  $_" }
