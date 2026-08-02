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
  crystal_tui:
    github: skuznetsov/crystal_tui
```

Install:

```bash
shards install
```

## Step 2: Hello World

Replace `src/my_tui_app.cr` with:

```crystal
require "crystal_tui"

class MyApp < Tui::App
  def compose : Array(Tui::Widget)
    [
      Tui::Panel.new("My First App", id: "main") do |panel|
        panel.content = Tui::VBox.new do
          [
            Tui::Label.new("Hello, TUI!", id: "greeting"),
            Tui::Button.new("Click Me", id: "btn"),
          ] of Tui::Widget
        end
      end
    ] of Tui::Widget
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
require "crystal_tui"

class MyApp < Tui::App
  @counter = 0
  @counter_label : Tui::Label?
  @counter_button : Tui::Button?

  def compose : Array(Tui::Widget)
    counter_label = Tui::Label.new("Count: 0", id: "counter")
    counter_button = Tui::Button.new("Increment", id: "btn")
    @counter_label = counter_label
    @counter_button = counter_button

    [
      Tui::Panel.new("Counter App", id: "main") do |panel|
        panel.content = Tui::VBox.new do
          [
            counter_label,
            counter_button,
          ] of Tui::Widget
        end
      end
    ] of Tui::Widget
  end

  def on_mount : Nil
    super

    # Add the handler to the button created by compose
    if btn = @counter_button
      btn.on_press do
        @counter += 1
        if label = @counter_label
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

Label {
  background: blue;
  color: white;
}
```

Visual `color` and `background` declarations are consumed by `Label`; buttons keep their constructor styles. `Panel` consumes border and title declarations.

Load it in your app:

```crystal
class MyApp < Tui::App
  self.css_path = "styles.tcss"

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
- Event handling examples are covered in the event handling section below.

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
# Override with an on_capture hook when custom behavior is needed:
def on_capture(event : Tui::Event) : Bool
  if event.is_a?(Tui::KeyEvent) && event.matches?("tab")
    focus_next
    return true
  end
  super
end
```
