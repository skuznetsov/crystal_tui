# Getting Started

Build your first Crystal TUI app in 5 minutes.

## Prerequisites

- Crystal 1.10+ installed
- A terminal with Unicode support

## Step 1: Create Project

```bash
mkdir my_tui_app && cd my_tui_app
crystal init app my_tui_app
```

Add dependency to `shard.yml`:

```yaml
dependencies:
  tui:
    github: skuznetsov/crystal_tui
```

Install:

```bash
shards install
```

## Step 2: Hello World

Replace `src/my_tui_app.cr` with:

```crystal
require "tui"

class MyApp < Tui::App
  def compose : Array(Tui::Widget)
    [
      Tui::Panel.new("My First App", id: "main") do |panel|
        panel.content = Tui::VBox.new do |vbox|
          vbox.add_child Tui::Label.new("Hello, TUI!", id: "greeting")
          vbox.add_child Tui::Button.new("Click Me", id: "btn")
        end
      end
    ]
  end
end

MyApp.new.run
```

Run:

```bash
crystal run src/my_tui_app.cr
```

Press `Ctrl+C` to exit.

## Step 3: Handle Events

Make the button interactive:

```crystal
require "tui"

class MyApp < Tui::App
  @counter = 0

  def compose : Array(Tui::Widget)
    [
      Tui::Panel.new("Counter App", id: "main") do |panel|
        panel.content = Tui::VBox.new do |vbox|
          vbox.add_child Tui::Label.new("Count: 0", id: "counter")
          vbox.add_child Tui::Button.new("Increment", id: "btn")
        end
      end
    ]
  end

  def on_mount : Nil
    super

    # Find the button and add click handler
    if btn = query_one("#btn", Tui::Button)
      btn.on_click do
        @counter += 1
        if label = query_one("#counter", Tui::Label)
          label.text = "Count: #{@counter}"
        end
      end
    end
  end
end

MyApp.new.run
```

## Step 4: Add Styling

Create `styles.tcss`:

```css
/* styles.tcss */
Panel {
  border: round cyan;
}

#counter {
  color: yellow;
  text-style: bold;
}

Button {
  background: blue;
  color: white;
}

Button:focus {
  background: cyan;
  color: black;
}
```

Load it in your app:

```crystal
class MyApp < Tui::App
  @@css_path = "styles.tcss"

  # ... rest of code
end
```

## Step 5: Dev Mode

Enable hot reload for CSS:

```bash
TUI_DEV=1 crystal run src/my_tui_app.cr
```

Now edit `styles.tcss` and see changes instantly!

## Next Steps

- [Widget Gallery](../widgets/index.md) - Explore all widgets
- [CSS Reference](../css-reference/index.md) - Learn styling
- [TUML Guide](tuml.md) - Declarative UI definitions
- [Events Guide](events.md) - Keyboard and mouse handling

## Common Patterns

### Query Widgets

```crystal
# By ID
panel = query_one("#main", Tui::Panel)

# By class
buttons = query_all(".primary")

# By type
labels = query_all("Label")
```

### Update Widgets

```crystal
# Reactive properties auto-update
label.text = "New text"  # Triggers re-render

# Manual refresh
widget.mark_dirty!
```

### Focus Management

```crystal
# Set focus
button.focus

# Tab navigation is automatic
# Override with:
def on_key(event : Tui::KeyEvent) : Bool
  if event.matches?("tab")
    focus_next
    return true
  end
  false
end
```
