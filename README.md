# Crystal TUI

A modern, Textual-inspired TUI (Terminal User Interface) framework for Crystal.

## Features

- **Rich Widget Library**: 30+ widgets including Panel, Button, Input, DataTable, Tree, ListView, Log, and more
- **CSS Styling**: Textual-compatible CSS (TCSS) for styling with variables, selectors, and hot reload
- **Flexible Layout**: Flexbox-like layout engine with fr units, percentages, and constraints
- **Event System**: Comprehensive keyboard and mouse event handling
- **Reactive Properties**: Automatic re-rendering on property changes
- **Overlay System**: Popups, dialogs, and menus that render above other widgets

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  tui:
    github: sergeyklay/crystal_tui
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
- `TextEditor` - Multi-line editor
- `Checkbox` - Toggle checkbox
- `RadioGroup` - Radio button group
- `ComboBox` - Dropdown select
- `Switch` - iOS-style toggle

### Display
- `Label` - Text display
- `Header` - App title bar with clock
- `Footer` - Key bindings bar
- `ProgressBar` - Progress indicator
- `LoadingIndicator` - Animated spinner
- `Toast` - Popup notifications
- `Rule` - Visual divider
- `Sparkline` - Mini trend chart

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

```crystal
class MyApp < Tui::App
  def handle_event(event : Tui::Event) : Bool
    case event
    when Tui::KeyEvent
      if event.matches?("ctrl+s")
        save_file
        return true
      end
    when Tui::MouseEvent
      if event.action.click?
        handle_click(event.x, event.y)
        return true
      end
    end
    super
  end
end
```

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
