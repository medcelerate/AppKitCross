#!/usr/bin/env python3
"""Walks an AppKitCross application's AT-SPI2 tree over D-Bus (ADR-0013).

Finds the application on the accessibility bus by its toolkit name, prints the tree
(role, name, states) and checks the HelloWindow controls: a push button "Clear dots",
a check box "Show grid" that toggles through DoAction, a slider whose CurrentValue can
be set, and the editable text field. It then walks the menu bar (the application's
"menu bar" child: File, Edit, View, Help, View > Show Grid a checked check menu item with
its key binding) and the colour pop-up: expanding it shows a "menu" of "menu item"
children, picking "Red" selects it, and the pop-up is put back to "Blue".
Exits non-zero when a check fails.

Usage: atspi-probe.py [--expect-hello] [--dump]
Needs python3-dbus and AT_SPI_BUS_ADDRESS (or org.a11y.Bus on the session bus).
"""
import os
import sys
import time

import dbus

ACCESSIBLE = "org.a11y.atspi.Accessible"
COMPONENT = "org.a11y.atspi.Component"
ACTION = "org.a11y.atspi.Action"
VALUE = "org.a11y.atspi.Value"
TEXT = "org.a11y.atspi.Text"
PROPS = "org.freedesktop.DBus.Properties"
ROOT = "/org/a11y/atspi/accessible/root"


def a11y_bus():
    address = os.environ.get("AT_SPI_BUS_ADDRESS")
    if not address:
        session = dbus.SessionBus()
        address = str(session.get_object("org.a11y.Bus", "/org/a11y/bus").GetAddress(dbus_interface="org.a11y.Bus"))
    return dbus.bus.BusConnection(address)


class Node:
    def __init__(self, bus, name, path):
        self.bus, self.name, self.path = bus, str(name), str(path)
        self.obj = bus.get_object(self.name, self.path)

    def prop(self, iface, name):
        return self.obj.Get(iface, name, dbus_interface=PROPS)

    def call(self, iface, method, *args):
        return getattr(dbus.Interface(self.obj, iface), method)(*args)

    @property
    def role(self):
        return str(self.call(ACCESSIBLE, "GetRoleName"))

    @property
    def label(self):
        return str(self.prop(ACCESSIBLE, "Name"))

    def states(self):
        words = [int(w) for w in self.call(ACCESSIBLE, "GetState")]
        bits = words[0] | (words[1] << 32)
        return {n for n, b in STATE_BITS.items() if bits & (1 << b)}

    def children(self):
        return [Node(self.bus, n, p) for (n, p) in self.call(ACCESSIBLE, "GetChildren")]

    def interfaces(self):
        return [str(i) for i in self.call(ACCESSIBLE, "GetInterfaces")]


STATE_BITS = {"active": 1, "checked": 4, "collapsed": 5, "editable": 7, "enabled": 8, "expandable": 9, "expanded": 10,
              "focusable": 11, "focused": 12, "multi line": 17, "multiselectable": 18, "resizable": 21,
              "selectable": 22, "selected": 23, "sensitive": 24, "showing": 25, "single line": 26, "visible": 30,
              "indeterminate": 32, "checkable": 41, "has popup": 42, "read only": 43}


def action_index(node, name):
    """The index of a named action (DoAction takes indices), or -1."""
    names = [str(a[0]) for a in node.call(ACTION, "GetActions")]
    return names.index(name) if name in names else -1


def dump(node, depth=0, out=None):
    out = out if out is not None else []
    try:
        extents = tuple(int(v) for v in node.call(COMPONENT, "GetExtents", dbus.UInt32(0))) if COMPONENT in node.interfaces() else ()
    except dbus.DBusException:
        extents = ()
    line = "  " * depth + "%s %r %s %s" % (node.role, node.label, sorted(node.states()), extents)
    print(line)
    out.append(node)
    for c in node.children():
        dump(c, depth + 1, out)
    return out


def find_app(bus, toolkit="AppKitCross", timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        desktop = Node(bus, "org.a11y.atspi.Registry", ROOT)
        for app in desktop.children():
            try:
                if str(app.prop("org.a11y.atspi.Application", "ToolkitName")) == toolkit:
                    return app
            except dbus.DBusException:
                continue
        time.sleep(0.5)
    return None


def main():
    bus = a11y_bus()
    app = find_app(bus)
    if app is None:
        print("probe: no AppKitCross application on the accessibility bus", file=sys.stderr)
        return 2
    print("application %r (%s)" % (app.label, app.name))
    nodes = dump(app)
    failures = []

    def expect(cond, what):
        print(("ok   " if cond else "FAIL ") + what)
        if not cond:
            failures.append(what)

    if "--expect-hello" in sys.argv:
        by = lambda role, label: next((n for n in nodes if n.role == role and n.label == label), None)
        windows = [n for n in nodes if n.role == "frame"]
        expect(any(w.label.startswith("Hello") for w in windows), "a frame titled Hello...")
        button = by("push button", "Clear dots")
        expect(button is not None, "push button 'Clear dots'")
        if button:
            expect("focusable" in button.states() and "enabled" in button.states(), "button is focusable and enabled")
            expect([str(a[0]) for a in button.call(ACTION, "GetActions")] == ["press"], "button has the press action")
            x, y, w, h = (int(v) for v in button.call(COMPONENT, "GetExtents", dbus.UInt32(0)))
            expect(w > 0 and h > 0, "button has extents (%d,%d %dx%d)" % (x, y, w, h))
            hit = button.call(COMPONENT, "GetAccessibleAtPoint", dbus.Int32(x + w // 2), dbus.Int32(y + h // 2), dbus.UInt32(0))
            expect(str(hit[1]) == button.path, "GetAccessibleAtPoint at the button's centre is the button")
        check = by("check box", "Show grid")
        expect(check is not None, "check box 'Show grid'")
        if check:
            before = "checked" in check.states()
            expect(bool(check.call(ACTION, "DoAction", dbus.Int32(0))), "DoAction(press) on the check box")
            time.sleep(0.2)
            expect(("checked" in check.states()) != before, "the check box toggled (%s -> %s)" % (before, not before))
            check.call(ACTION, "DoAction", dbus.Int32(0))      # put it back
        slider = next((n for n in nodes if n.role == "slider"), None)
        expect(slider is not None, "a slider")
        if slider:
            lo, hi = float(slider.prop(VALUE, "MinimumValue")), float(slider.prop(VALUE, "MaximumValue"))
            expect(lo < hi, "slider range %g..%g" % (lo, hi))
            slider.obj.Set(VALUE, "CurrentValue", dbus.Double(hi), dbus_interface=PROPS)
            time.sleep(0.2)
            expect(float(slider.prop(VALUE, "CurrentValue")) == hi, "slider CurrentValue set to the maximum")
        field = next((n for n in nodes if n.role == "text" and "editable" in n.states()), None)
        expect(field is not None, "an editable text field")
        if field:
            expect(bool(field.call("org.a11y.atspi.EditableText", "SetTextContents", "Ada")), "SetTextContents on the field")
            time.sleep(0.2)
            expect(str(field.call(TEXT, "GetText", dbus.Int32(0), dbus.Int32(-1))) == "Ada", "GetText returns the new text")
            expect(int(field.prop(TEXT, "CharacterCount")) == 3, "CharacterCount is 3")
        label = by("label", "Your name:")
        expect(label is not None, "label 'Your name:'")
        if label:
            expect(str(label.call(TEXT, "GetText", dbus.Int32(0), dbus.Int32(-1))) == "Your name:", "the label's text")
        combo = next((n for n in nodes if n.role == "combo box"), None)
        expect(combo is not None, "a combo box (the colour pop-up)")
        # The menu bar: no window draws one on Linux, so it is the application's child.
        bar = next((c for c in app.children() if c.role == "menu bar"), None)
        expect(bar is not None, "the application has a 'menu bar' child")
        if bar:
            titles = [c.label for c in bar.children()]
            expect(titles[:4] == ["File", "Edit", "View", "Help"], "menu bar items %s" % titles)
            view = next((c for c in bar.children() if c.label == "View"), None)
            menu = view.children()[0] if view and view.children() else None
            expect(menu is not None and menu.role == "menu", "View holds a 'menu'")
            grid = next((i for i in menu.children() if i.label == "Show Grid"), None) if menu else None
            expect(grid is not None and grid.role == "check menu item" and "checked" in grid.states(), "View > Show Grid is a checked check menu item")
            if grid:
                binding = str(grid.call(ACTION, "GetKeyBinding", dbus.Int32(0)))
                expect(binding.endswith("<Control>g"), "Show Grid's key binding %r" % binding)
        if combo:
            expect({"expandable", "collapsed", "has popup"} <= combo.states(), "the pop-up is expandable, collapsed and has a popup")
            expect(combo.children() == [], "a closed pop-up has no children")
            expand = action_index(combo, "expand")
            expect(expand >= 0 and bool(combo.call(ACTION, "DoAction", dbus.Int32(expand))), "DoAction(expand) on the pop-up")
            time.sleep(0.3)
            expect("expanded" in combo.states(), "the pop-up is expanded")
            kids = combo.children()
            expect(len(kids) == 1 and kids[0].role == "menu", "the open pop-up's child is a 'menu'")
            items = kids[0].children() if kids else []
            labels = [i.label for i in items]
            # The selected item carries the check mark, so it is a check menu item.
            roles = [i.role for i in items]
            expect(labels == ["Blue", "Red", "Green"] and all(r in ("menu item", "check menu item") for r in roles), "its items %s (%s)" % (labels, roles))
            red = next((i for i in items if i.label == "Red"), None)
            if red:
                x, y, w, h = (int(v) for v in red.call(COMPONENT, "GetExtents", dbus.UInt32(0)))
                expect(w > 0 and h > 0, "the open item 'Red' has extents (%d,%d %dx%d)" % (x, y, w, h))
                expect(bool(red.call(ACTION, "DoAction", dbus.Int32(0))), "DoAction(press) on 'Red' picks it")
                time.sleep(0.3)
                expect(combo.label == "Red", "the pop-up now shows 'Red' (%r)" % combo.label)
                expect(combo.children() == [] and "collapsed" in combo.states(), "the pop-up is collapsed again")
                # Put it back.
                combo.call(ACTION, "DoAction", dbus.Int32(expand))
                time.sleep(0.3)
                again = combo.children()
                blue = next((i for i in again[0].children() if i.label == "Blue"), None) if again else None
                if blue:
                    blue.call(ACTION, "DoAction", dbus.Int32(0))
                    time.sleep(0.2)
    if failures:
        print("probe: %d check(s) failed" % len(failures), file=sys.stderr)
        return 1
    print("probe: %d nodes, all checks passed" % len(nodes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
