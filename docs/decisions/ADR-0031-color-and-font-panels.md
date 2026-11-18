# ADR-0031: Colour and font panels

Date: 2026-11-10. Status: accepted, awaiting verification on the Windows PC.

## Context

AppKit's shared `NSColorPanel` and `NSFontPanel` are utility windows the application
orders front (`orderFrontColorPanel:`, `orderFrontFontPanel:` from the standard toolbar
items of ADR-0018, the Format menu, a colour well's click). They do not talk to the view
that asked for them: the colour panel sends `changeColor:` and the font manager sends
`changeFont:` to a target or, with none, down the responder chain, and the receiver (an
`NSTextView`, a colour well, an application's own view) applies the panel's colour or
converts its fonts through `NSFontManager.convert(_:)`. `NSColorWell` is the control that
makes the colour panel edit its colour; `NSFontDescriptor` and `NSFontCollection` describe
and group the installed fonts the panel lists.

Windows has a system colour dialog (`ChooseColor`, a fixed modal dialog of 48 basic
colours and a custom-colour picker) and a system font dialog (`ChooseFont`, also modal,
with its own notion of styles and sizes). Linux has neither outside a toolkit (GTK's
`GtkColorChooserDialog` and `GtkFontChooserDialog` belong to GTK applications; the
xdg-desktop-portal has no colour or font chooser). Neither modal dialog can stand in for
AppKit's panels, which stay open beside the document, follow the selection and send
changes as the user drags.

## Decision

### The panels are drawn by the package on every backend

`NSColorPanel` and `NSFontPanel` are `NSPanel`s whose content the package draws with the
port's own views (NSColorPanelViews.swift, the `_NSFontPanelView`), so Win32, X11, Wayland
and the host backend show the same panels, in the current appearance (the semantic
colours of `NSColor` resolve per appearance; the swatches show a checkerboard behind
translucent colours). Both are utility windows (`.utilityWindow`: they never become the
main window), closable, created on first use by `shared`, placed beside the key window,
and hidden rather than destroyed when closed, as AppKit's.

The colour panel has a mode bar (Wheel, Sliders, Lists, Crayons; `NSColorPanel.Mode`
maps the four slider modes, the two list modes and the wheel and crayon modes onto it, and
`setPickerMask` hides the kinds an application excludes), the current colour as a
draggable swatch with its hex value, the picker for the mode (a hue/saturation wheel with
a brightness slider; gray, RGB, CMYK or HSB gradient sliders with numeric fields; the
colour lists in a pop-up over a table with swatches; Apple's 48 crayons), an opacity
slider when `showsAlpha`, the accessory view, and a row of ten favourite swatches kept
in the user defaults (click an empty slot to keep the current colour, a filled one to take
it back, drop a colour on one, right-click to clear). The window resizes itself to what it
shows (the opacity row, the accessory view).

The font panel has a preview (the selected font's name set in that font) over three
lists, Family, Typeface and Size, and a size field for sizes outside the list, with the
accessory view under them. The families come from `NSFontManager.availableFontFamilies`
and the typefaces from `availableMembers(ofFontFamily:)`. `validModesForFontPanel` on the
responder that would receive `changeFont:` hides the Typeface or Size list when the
responder does not want them; the collections column of Apple's panel is not shown.

### The responder chain does the work

A change in the colour panel posts `colorDidChangeNotification` and sends the action
(`changeColor:` unless `setAction` chose another) to the target, or with none through
`NSApplication.sendAction` (the key window's first responder, then the main window's,
then the application), every time the colour changes while `isContinuous` and once when
the mouse goes up otherwise. The panel's own window is the key window while the user
works in it, so the chain goes on to the main window's first responder: that is how the
document's text view receives it. `NSApplication.orderFrontColorPanel(_:)` shows the
panel; the application also answers `orderFrontColorPanel:` and `orderFrontFontPanel:`
as nil-target actions (the latter through `NSFontManager.shared`), so the standard
toolbar items of ADR-0018 enable and work.

A change in the font panel's lists tells `NSFontManager.shared` (`currentFontAction`
becomes `.viaPanelFontAction`), which sends `changeFont:` with itself as the sender; the
receiver passes each of its fonts to `convert(_:)`, which asks the panel: with one font
selected the panel's family, typeface and size replace it; when the panel stands for
several fonts (`setPanelFont(_:isMultiple:)`) only what the user changed applies to each.
The Font menu's Bold/Italic/Bigger/Smaller items go through the same `sendAction()`
with the trait or size action, as in AppKit. `NSTextView` handles `changeFont:` and
`changeColor:` for the selected characters of rich text (the typing attributes when the
selection is empty, the whole text otherwise), reports the selection's font to the font
manager as the first responder and as the selection moves (`usesFontPanel`), and so the
panel follows the caret. `setFont(_:range:)` and `setTextColor(_:range:)` apply to the
range in rich text.

### Colour wells

`NSColorWell` is an `NSControl` drawn by the package in the three styles (`.default`
bordered with the swatch inside the bezel, `.minimal`, `.expanded` with a pull-down
segment that sends `pulldownAction`). A click activates it: `activate(_:)` deactivates
the other wells when exclusive, makes the well the colour panel's target with the action
`takeColorFrom:`, gives the panel the well's colour and orders it front; a click on the
active well deactivates it. `takeColorFrom:` stores the panel's colour and sends the
well's own action, which is how SwiftUI's `ColorPicker` (an `NSColorWell` with a label)
updates its binding. Wells are drag sources (a drag past the click threshold calls
`NSColorPanel.dragColor(_:with:from:)`, which starts an ADR-0011 dragging session with
the colour on the pasteboard and a swatch image) and drag destinations for
`NSPasteboard.PasteboardType.color`, whose property list is the sRGB components
(`NSColor` adopts `NSPasteboardReading`/`NSPasteboardWriting`). A well is AXColorWell
with the colour's components as its value (settable from a hex or `rgb r g b a` string),
the role description "color well", a help string and the press action, which activates
it. UIA has no colour-well control type, so the Win32 bridge exposes a well as a Button
named by its role description with Invoke and a Value pattern; the panel's own sliders,
wheel and swatch opt in as accessibility elements (a plain `NSView` is ignored unless it
does), the sliders as AXSlider in percent with a settable range value, so Narrator reads
them as sliders.

### Font descriptors and collections over CoreText

`NSFontDescriptor` is a dictionary whose keys are the strings CoreText uses, so matching
is `CTFontDescriptorCreateMatchingFontDescriptors` on every platform: Apple's CoreText on
the macOS host (it answers a match with the PostScript name alone, so the descriptor
completes family, face, display name and traits from the font), and the port's CoreText
module on Windows and Linux, which gained `CTFontManagerCopyAvailableFontFamilyNames`
and face enumeration: Pango lists a family's faces (`pango_font_family_list_faces`);
the DirectWrite engine probes the regular, bold, italic and bold-italic faces of a family
through `makeFont` (a full `IDWriteFontFamily` enumeration is a follow-up). `NSFont` gains
`fontDescriptor` and `init?(descriptor:size:)` over the same attributes.

`NSFontCollection` holds query descriptors; `matchingDescriptors` is the installed faces
they match minus the exclusions. These platforms have no font collection files, so named
collections and their visibility live in the user defaults (`NSFontCollections`,
`NSHiddenFontCollections`, synchronised on each write because swift-corelibs-foundation
persists on `synchronize()` only); the standard names (All Fonts, Favorites, Recently
Used, User) always exist. `NSFontManager`'s collection methods are the same store.

### The native colour dialog on Windows, opt in

For parity with the file dialogs (ADR-0017), `APPKITWIN_COLOR_PANEL=native` makes
`NSColorPanel.orderFront(_:)` run the system colour dialog instead when the backend has
one (`PlatformBackend.runColorDialog(initial:parent:)`, `ChooseColorW` through the CD2D
shim on Windows, with the dialog's 16 custom colours kept for the process); the colour it
returns arrives as one final change (the notification and the action), and the panel's
window never shows. It is not the default: the dialog is modal, has no alpha, no lists,
no accessory view and no continuous updates, and does not follow the selection. There is
no native font dialog path: `ChooseFont` cannot express the panel's mode mask, multiple
selection or continuous conversion, and the package panel lists the same DirectWrite
families. Linux and the host backend have no native colour dialog; the variable is ignored
there.

## Consequences

- Applications written against AppKit's panels work unchanged: `NSColorPanel.shared`,
  `NSColorWell`, `changeColor:`/`changeFont:` in the responder chain, `NSFontManager`'s
  conversions and the Font menu, `NSFontDescriptor` matching and `NSFontCollection`.
- The hand-written types: `NSColorPanel`, `NSColorWell`, `NSColorList`, `NSFontPanel`,
  `NSFontDescriptor`, `NSFontCollection`, `NSMutableFontCollection` (their nested types
  stay in the generated `+Types.swift` files); `NSFontManager` and `NSFont` grew the
  descriptor and panel members; `NSTextView` the panel actions; `NSApplication` the
  nil-target panel actions; `NSColor` the pasteboard type; SwiftUI a `ColorPicker`.
- `NSColorList` has no shared folder to read: `availableColorLists` is the built-in lists
  (Apple, Crayons, Web Safe Colors) plus the lists this process has written
  (`write(to:)` writes a property list; nil goes to `~/Library/Colors/<name>.clr`).
- Not done: the image palette picker and custom `NSColorPickingCustom` pickers, the
  colour panel's magnifier (the "pick a colour from the screen" loupe), the font panel's
  collections column and effects (`NSFontPanel.ModeMask` effects are accepted and hide
  nothing), `NSFontManager.setFontPanelFactory`/`setFontManagerFactory` (stored, unused),
  and a full DirectWrite face enumeration.
