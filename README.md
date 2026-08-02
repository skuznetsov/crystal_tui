# Crystal TUI

A modern, Textual-inspired TUI (Terminal User Interface) framework for Crystal.

## Features

- **Rich Widget Library**: 40+ widgets including Panel, Button, Input, DataTable, Tree, ListView, Log, and more
- **CSS Styling**: A TCSS subset with variables, selectors, and CSS hot reload
- **Flexible Layout**: Flexbox-like layout engine with fr units, percentages, and constraints
- **DOM-like Event Routing**: Capture and bubble hooks around child dispatch
- **Reactive Properties**: Automatic re-rendering on property changes
- **Overlay System**: Popups, dialogs, and menus that render above other widgets

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  crystal_tui:
    github: skuznetsov/crystal_tui
```

Then run:

```bash
shards install
```

## Quick Start

```crystal
require "crystal_tui"

class HelloWorld < Tui::App
  def compose : Array(Tui::Widget)
    [
      Tui::Panel.new("Hello, World!", id: "main") do |panel|
        panel.content = Tui::Label.new("Welcome to Crystal TUI!", id: "welcome")
      end
    ] of Tui::Widget
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

/* Type selector (Label consumes visual color properties) */
Label {
  background: blue;
  color: white;
}

/* ID selector */
#main-panel {
  border: light white;
  padding: 1;
}

/* Class selector (apply this class to a Label) */
.active {
  background: $primary;
}

/* Pseudo-class (Panel consumes border properties) */
Panel:focus {
  border: round yellow;
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
- `background`, `color`, `text-*` - Applied by `Label`; other widgets retain constructor styles
- `border` - Applied by `Panel`

The base widget stores `opacity`, but rendering does not currently apply it.
State selectors are matched when the stylesheet is applied; hover assignment and automatic style recomputation after state changes are not enabled yet.

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

Crystal TUI routes events in a **DOM-like capture/child/bubble order**, familiar to web developers:

```
CAPTURE HOOK:    App → Panel → Container (`on_capture`)
CHILD/TARGET:    Button handles the event
BUBBLE HOOK:     Button → Container → Panel → App (`on_event`)
```

### Event Phases

1. **Capture hook** - `on_capture` runs before children and can intercept an event.
2. **Child/target routing** - Mouse events visit children; key and paste events go to the focused widget.
3. **Bubble hook** - `on_event` runs after children have had a chance to handle the event.

The `Event::Phase`, `target`, and `current_target` accessors are reserved metadata: the current dispatcher does not populate them, so the phase predicates remain at their default state.

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
    super
  end
end
```

Override `on_capture` to intercept events BEFORE they reach children:

```crystal
class MyApp < Tui::App
  # Global hotkeys - intercept before any child can handle
  def on_capture(event : Tui::Event) : Bool
    if event.is_a?(Tui::KeyEvent)
      if event.modifiers.ctrl? && event.char == 's'
        save_document
        event.stop_propagation!  # Don't send to children
        return true
      elsif event.modifiers.ctrl? && event.char == 'q'
        quit
        event.stop_propagation!
        return true
      end
    end
    super
  end
end
```

### Event Control Methods

```crystal
# Stop propagation to next widget (current widget's handlers still run)
event.stop_propagation!

# Stop propagation and set the immediate-stop flag
event.stop_immediate!

# Set the default-prevented flag (built-in widgets do not consume it yet)
event.prevent_default!

# Phase/target metadata is reserved for a future dispatcher update.
# `phase` remains `None`, and `target`/`current_target` remain nil today.
```

`prevent_default!` and `stop_immediate!` currently set event flags; no widget consumes the default-prevented flag, and immediate-handler semantics are reserved for a future dispatcher update.

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
- `vscode_layout.cr` - IDE-style layout

Run an example:

```bash
crystal run examples/hello.cr
```

## Development

```bash
# Run tests
crystal spec

# Build all examples
mkdir -p bin
for example in examples/*.cr; do
  crystal build "$example" -o "bin/$(basename "$example" .cr)"
done

# Generate API docs (outputs to docs/)
crystal docs
# Then open docs/index.html in browser
```

## License

MIT License - see [LICENSE](LICENSE)

## Credits

Inspired by [Textual](https://textual.textualize.io/) for Python.
