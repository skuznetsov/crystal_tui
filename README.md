# Crystal TUI

A modern, Textual-inspired TUI (Terminal User Interface) framework for Crystal.

## Features

- **Rich Widget Library**: 40+ widgets including Panel, Button, Input, DataTable, Tree, ListView, Log, and more
- **CSS Styling**: Textual-compatible CSS (TCSS) for styling with variables, selectors, and hot reload
- **Flexible Layout**: Flexbox-like layout engine with fr units, percentages, and constraints
- **DOM-like Event Model**: Capture/bubble phases familiar to web developers
- **Reactive Properties**: Automatic re-rendering on property changes
- **Overlay System**: Popups, dialogs, and menus that render above other widgets

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  tui:
    github: skuznetsov/crystal_tui
```

Then run:

```bash
shards install
```

## Quick Start

```crystal
require "tui"

class HelloWorld < Tui::App
  def compose : Array(Tui::Widget)
    [
      Tui::Panel.new("Hello, World!", id: "main") do |panel|
        panel.content = Tui::Label.new("welcome", text: "Welcome to Crystal TUI!")
      end
    ]
  end
end

HelloWorld.new.run
```

## Widgets

### Containers
- `Panel` - Container with border and title
- `HBox` / `VBox` - Horizontal/vertical layout
- `Grid` - CSS grid-style layout
- `SplitContainer` - Resizable split panes
- `TabbedPanel` - Tabbed content
- `Collapsible` - Expandable section
- `Dialog` - Modal dialog

### Input
- `Button` - Clickable button
- `Input` - Single-line text input
- `MaskedInput` - Input with format mask (phone, date)
- `TextEditor` - Multi-line editor
- `Checkbox` - Toggle checkbox
- `RadioGroup` - Radio button group
- `ComboBox` - Dropdown select
- `Switch` - iOS-style toggle
- `Slider` - Range slider
- `Calendar` - Date picker
- `ColorPicker` - Color selection (16/256 colors)
- `TimePicker` - Time selection (24h/12h)

### Display
- `Label` - Text display
- `Header` - App title bar with clock
- `Footer` - Key bindings bar
- `ProgressBar` - Progress indicator
- `LoadingIndicator` - Animated spinner
- `Toast` - Popup notifications
- `Rule` - Visual divider
- `Sparkline` - Mini trend chart
- `Digits` - Large ASCII art numbers
- `Placeholder` - Development placeholder
- `Pretty` - Pretty-print data structures

### Data
- `DataTable` - Data grid with sorting
- `Tree` - Hierarchical tree view
- `ListView` - Virtual scrolling list
- `SelectionList` - Multi-select list with checkboxes
- `Log` - Scrolling log viewer with levels
- `FilePanel` - File browser
- `TextViewer` - Scrollable text
- `MarkdownView` - Markdown renderer
- `Link` - Clickable URL/text

### Layout
- `IconSidebar` - VSCode-style sidebar
- `WindowManager` - Draggable windows

## CSS Styling

Crystal TUI uses TCSS (TUI CSS), a simplified CSS dialect:

```css
/* Variables */
$primary: cyan;
$bg: rgb(30, 30, 40);

/* Type selector */
Button {
  background: blue;
  color: white;
}

/* ID selector */
#main-panel {
  border: light white;
  padding: 1;
}

/* Class selector */
.active {
  background: $primary;
}

/* Pseudo-class */
Button:focus {
  background: white;
  color: black;
}

/* Descendant selector */
Panel Button {
  margin: 1;
}

/* Child selector */
Panel > Label {
  color: yellow;
}
```

### CSS Properties

**Layout:**
- `width`, `height` - Size (px, %, fr, auto)
- `min-width`, `max-width`, `min-height`, `max-height`
- `margin`, `margin-top/right/bottom/left`
- `padding`, `padding-top/right/bottom/left`

**Visual:**
- `background` - Background color
- `color` - Text color
- `border` - Border style and color

### Hot Reload

Enable CSS hot reload for development:

```crystal
class MyApp < Tui::App
  def initialize
    super
    load_css("styles/app.tcss")
    enable_css_hot_reload  # Watch for changes
  end
end
```

## Event Handling

Crystal TUI uses a **DOM-like event model** with capture and bubble phases, familiar to web developers:

```
CAPTURE (down):  App → Panel → Container → Button
TARGET:          Button handles the event
BUBBLE (up):     Button → Container → Panel → App
```

### Event Phases

1. **Capture Phase** - Event travels from root DOWN to target. Allows parent widgets to intercept events before they reach children.
2. **Target Phase** - Event is at the target widget (deepest widget for mouse, focused widget for keyboard).
3. **Bubble Phase** - Event travels from target UP to root. Allows parent widgets to react after children.

### Handling Events

Override `on_event` for target/bubble phase handling (most common):

```crystal
class MyWidget < Tui::Widget
  def on_event(event : Tui::Event) : Bool
    case event
    when Tui::KeyEvent
      if event.key.enter?
        do_something
        event.stop_propagation!  # Stop bubble
        return true
      end
    end
    false
  end
end
```

Override `on_capture` to intercept events BEFORE they reach children:

```crystal
class MyApp < Tui::App
  # Global hotkeys - intercept before any child can handle
  def on_capture(event : Tui::Event) : Nil
    if event.is_a?(Tui::KeyEvent)
      if event.modifiers.ctrl? && event.char == 's'
        save_document
        event.stop_propagation!  # Don't send to children
      elsif event.modifiers.ctrl? && event.char == 'q'
        quit
        event.stop_propagation!
      end
    end
  end
end
```

### Event Control Methods

```crystal
# Stop propagation to next widget (current widget's handlers still run)
event.stop_propagation!

# Stop immediately (no more handlers at all)
event.stop_immediate!

# Prevent default action (widget-specific behavior)
event.prevent_default!

# Check event phase
event.capturing?    # In capture phase?
event.at_target?    # At target widget?
event.bubbling?     # In bubble phase?

# Get target/current widget
event.target          # Original target widget
event.current_target  # Widget currently handling event
```

### Legacy Compatibility

Widgets that override `handle_event` directly continue to work with the legacy (depth-first) model. For new widgets, prefer using `on_event` and `on_capture`.

## Examples

See the `examples/` directory for complete examples:

- `hello.cr` - Basic hello world
- `buttons.cr` - Button interactions
- `table.cr` - DataTable usage
- `panels.cr` - Panel layouts
- `split_demo.cr` - SplitContainer
- `new_widgets_demo.cr` - Header, Tree, Switch, Toast
- `css_hot_reload_demo.cr` - CSS hot reload
- `vscode_demo.cr` - IDE-style layout

Run an example:

```bash
crystal run examples/hello.cr
```

## Development

```bash
# Run tests
crystal spec

# Build all examples
crystal build examples/*.cr -o bin/

# Generate API docs (outputs to docs/)
crystal docs
# Then open docs/index.html in browser
```

## License

MIT License - see [LICENSE](LICENSE)

## Credits

Inspired by [Textual](https://textual.textualize.io/) for Python.
