---
title: Front matter should be hidden
author: test
---

# MD Vault

A **Markdown** reader and editor for macOS with *two views*: press ⌘E to flip
between them. This paragraph has `inline code`, a [link](https://apple.com),
~~struck text~~, and ***bold italic*** together.

## Formatting

Setext heading
--------------

> A block quote with **bold** inside.
>
> - and a nested list
> - second item

### Lists

- Bullet one
- Bullet two
  - Nested child
  - Another child
    with a lazy continuation line
- Bullet three

1. Ordered first
2. Ordered second
   1. Nested ordered
3. Ordered third

- [x] Completed task
- [ ] Pending task

### Loose list

- First item with a blank line after it

- Second item

### Code

Inline `let x = 1` then a fenced block:

```swift
struct MarkdownDocument: FileDocument {
    var text: String   // ** not bold ** and ## not a heading
}
```

    an indented code block
    second line

### Table

| Feature | Editor | Viewer |
|:--------|:------:|-------:|
| Syntax highlighting | yes | n/a |
| Formatted output | no | **yes** |
| `Code spans` | raw | styled |

### Edge cases

Escaped \*asterisks\* and \`backticks\` stay literal.
An autolink: <https://swift.org>, snake_case_word untouched, 2*3*4 untouched.

Hard break at the end of this line  
lands here.

---

##### Small heading
###### Smallest heading
