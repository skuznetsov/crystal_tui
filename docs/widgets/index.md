# Widget Gallery

Crystal TUI includes 40+ widgets for building terminal interfaces.

## Containers

| Widget | Description |
|--------|-------------|
| `Panel` | Container with border and title |
| `VBox` | Vertical layout |
| `HBox` | Horizontal layout |
| `Grid` | CSS grid-style layout |
| `SplitContainer` | Resizable split panes |
| `TabbedPanel` | Tabbed content |
| `Collapsible` | Expandable section |
| `Dialog` | Modal dialog |

## Input Widgets

| Widget | Description |
|--------|-------------|
| `Button` | Clickable button |
| `Input` | Single-line text input |
| `MaskedInput` | Formatted input (phone, date) |
| `TextEditor` | Multi-line editor |
| `Checkbox` | Toggle checkbox |
| `RadioGroup` | Radio button group |
| `ComboBox` | Dropdown select |
| `Switch` | iOS-style toggle |
| `Slider` | Range slider |
| `Calendar` | Date picker |
| `TimePicker` | Time selection |
| `ColorPicker` | Color palette |

## Display Widgets

| Widget | Description |
|--------|-------------|
| `Label` | Text display |
| `Header` | App title bar with clock |
| `Footer` | Key bindings bar |
| `ProgressBar` | Progress indicator |
| `LoadingIndicator` | Animated spinner |
| `Toast` | Popup notifications |
| `Rule` | Visual divider |
| `Sparkline` | Mini trend chart |
| `Digits` | Large ASCII numbers |
| `Placeholder` | Development placeholder |
| `Pretty` | Pretty-print data |
| `RichText` | Styled text spans |
| `Link` | Clickable URL |

## Data Widgets

| Widget | Description |
|--------|-------------|
| `DataTable` | Data grid with sorting |
| `Tree` | Hierarchical tree view |
| `ListView` | Virtual scrolling list |
| `SelectionList` | Multi-select with checkboxes |
| `Log` | Scrolling log viewer |
| `FilePanel` | File browser |
| `TextViewer` | Scrollable text |
| `MarkdownView` | Markdown renderer |

## Layout Widgets

| Widget | Description |
|--------|-------------|
| `IconSidebar` | VSCode-style sidebar |
| `WindowManager` | Draggable windows |
| `MenuBar` | Application menu |

---

## Quick Examples

### Button

```crystal
button = Tui::Button.new("Click Me", id: "btn")
button.on_press { puts "Clicked!" }
```

```
┌──────────────┐
│ [ Click Me ] │
└──────────────┘
```

### Input

```crystal
input = Tui::Input.new(id: "name")
input.placeholder = "Enter your name"
input.on_change { |value| puts value }
```

```
┌────────────────────────────┐
│ Enter your name            │
└────────────────────────────┘
```

### Panel with Content

```crystal
panel = Tui::Panel.new("Settings", id: "settings")
panel.content = Tui::VBox.new do
  [
    Tui::Checkbox.new("Dark mode", id: "dark"),
    Tui::Checkbox.new("Notifications", id: "notif"),
  ] of Tui::Widget
end
```

```
┌─ Settings ──────────────────┐
│ [x] Dark mode               │
│ [ ] Notifications           │
└─────────────────────────────┘
```

### DataTable

```crystal
table = Tui::DataTable.new(id: "users")
table.add_column("name", "Name", width: 20)
table.add_column("email", "Email", width: 30)
table.add_row(name: "Alice", email: "alice@example.com")
table.add_row(name: "Bob", email: "bob@example.com")
```

```
┌─────────────────────┬────────────────────────────────┐
│ Name                │ Email                          │
├─────────────────────┼────────────────────────────────┤
│ Alice               │ alice@example.com              │
│ Bob                 │ bob@example.com                │
└─────────────────────┴────────────────────────────────┘
```
