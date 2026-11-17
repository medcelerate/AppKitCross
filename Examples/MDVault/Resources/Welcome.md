# Welcome to MD Vault

A Markdown app that shows you **both sides** of a document — the raw source and
the finished page — one keystroke apart. Press **⌘E** to see how this file is
written, then press it again to come back.

> Everything here is a plain `.md` file sitting on your Mac. No account, no sync,
> no cloud, no telemetry. Your writing stays yours.

## Try these

- [x] Open a Markdown file
- [ ] Press **⌘E** to reveal the raw source
- [ ] Press **⌘+** and **⌘-** to resize the text
- [ ] Make it your default: *File ▸ Set MD Vault as Default for Markdown*

## What it renders

| Element | You write | You get |
|:--------|:----------|--------:|
| Heading | `## Heading` | a styled heading |
| Emphasis | `**bold**`, `*italic*` | **bold**, *italic* |
| Code | `` `inline` `` | `inline` |
| Link | `[text](url)` | [text](https://example.com) |

### Code blocks keep their shape

```swift
func greet(_ name: String) -> String {
    // In the editor this stays plain text — ** and ## are inert in here.
    "Hello, \(name)"
}
```

### Lists nest as deep as you like

1. Draft the outline
2. Fill in the sections
   - Introduction
   - The argument
     - Supporting evidence
   - Conclusion
3. Read it back in the viewer

### And the small things work

Strikethrough for ~~things you changed your mind about~~, `inline code` in the
middle of a sentence, an autolink like <https://commonmark.org>, and a hard
break at the end of this line  
that lands exactly here.

---

## Where your files live

MD Vault never moves or copies anything. It opens the file you double-clicked,
edits it in place, and saves it with ⌘S — the same as any native Mac app.

Local images resolve relative to the document, so `![diagram](images/plan.png)`
finds `images/plan.png` next to this file.

*Written in Markdown. Rendered by MD Vault.*
