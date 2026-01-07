require "../src/tui"

# Demo markdown content
DEMO_MARKDOWN = <<-MD
# Crystal TUI Markdown Demo

This is a **demonstration** of the *Markdown* rendering capabilities.

## Features

- **Bold text** for emphasis
- *Italic text* for subtle emphasis
- `inline code` for code snippets
- ~~Strikethrough~~ for deleted content
- [Links](https://example.com) to external resources

## Code Blocks

Here's some Crystal code:

```crystal
class Greeter
  def initialize(@name : String)
  end

  def greet
    puts "Hello, \#{@name}!"
  end
end

Greeter.new("World").greet
```

And some Python for comparison:

```python
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

print(fibonacci(10))
```

## Lists

### Unordered
- Item one
- Item two
  - Nested item
  - Another nested
- Item three

### Ordered
1. First step
2. Second step
3. Third step

## Blockquotes

> "The only way to do great work is to love what you do."
> — Steve Jobs

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| j/↓ | Scroll down |
| k/↑ | Scroll up |
| PgDn | Page down |
| PgUp | Page up |
| Home | Go to top |
| End | Go to bottom |
| q | Quit |

---

*Press 'q' to quit the demo*
MD

class MarkdownDemo < Tui::App
  @markdown_view : Tui::MarkdownView

  def initialize
    super
    @markdown_view = Tui::MarkdownView.new("markdown")
    @markdown_view.content = DEMO_MARKDOWN
  end

  def compose : Array(Tui::Widget)
    [@markdown_view] of Tui::Widget
  end

  def handle_event(event : Tui::Event) : Bool
    # Only quit on 'q', don't quit on other keys
    if event.is_a?(Tui::KeyEvent)
      return true if event.matches?("ctrl+c") || event.matches?("ctrl+q")

      if event.matches?("q")
        quit
        return true
      end
    end

    # Let markdown view handle scrolling
    if @markdown_view.handle_event(event)
      return true
    end

    false
  end
end

MarkdownDemo.new.run
