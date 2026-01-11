require "../src/tui"

# Test character widths in the actual TUI environment
class WidthTestApp < Tui::App
  def initialize
    super
  end

  def compose : Array(Tui::Widget)
    # Create markdown view directly (without panel wrapper)
    content = Tui::MarkdownView.new("content")
    content.content = <<-MD
# Character Width Test

Test strings with markers (X marks boundaries):

**CJK Test:**
```
X但缺汉字X
0123456789
```

**Emoji Test:**
```
X⚠🔒🚀X
01234567
```

**Arrow Test:**
```
X→←↑↓X
012345
```

**Mixed Test (но缺 should be 4 chars wide):**
```
XХорошо для ReAct, но缺 langX
0         1         2
0123456789012345678901234567890
```

**Alignment Test:**
```
但缺 lang-specific/build.
0123456789012345678901234567
```

If widths are correct:
- X markers align vertically with numbers below
- "但缺" takes 4 columns (2+2)
- "но缺" takes 4 columns (1+1+2)

Press F10 or Ctrl+C to exit.
MD

    [content] of Tui::Widget
  end
end

WidthTestApp.new.run
