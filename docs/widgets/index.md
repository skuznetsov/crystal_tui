# Widget Gallery

Crystal TUI includes 40+ widgets for building terminal interfaces.

## Containers

| Widget | Description |
|--------|-------------|
| [Panel](panel.md) | Container with border and title |
| [VBox](vbox.md) | Vertical layout |
| [HBox](hbox.md) | Horizontal layout |
| [Grid](grid.md) | CSS grid-style layout |
| [SplitContainer](split-container.md) | Resizable split panes |
| [TabbedPanel](tabbed-panel.md) | Tabbed content |
| [Collapsible](collapsible.md) | Expandable section |
| [Dialog](dialog.md) | Modal dialog |

## Input Widgets

| Widget | Description |
|--------|-------------|
| [Button](button.md) | Clickable button |
| [Input](input.md) | Single-line text input |
| [MaskedInput](masked-input.md) | Formatted input (phone, date) |
| [TextEditor](text-editor.md) | Multi-line editor |
| [Checkbox](checkbox.md) | Toggle checkbox |
| [RadioGroup](radio-group.md) | Radio button group |
| [ComboBox](combo-box.md) | Dropdown select |
| [Switch](switch.md) | iOS-style toggle |
| [Slider](slider.md) | Range slider |
| [Calendar](calendar.md) | Date picker |
| [TimePicker](time-picker.md) | Time selection |
| [ColorPicker](color-picker.md) | Color palette |

## Display Widgets

| Widget | Description |
|--------|-------------|
| [Label](label.md) | Text display |
| [Header](header.md) | App title bar with clock |
| [Footer](footer.md) | Key bindings bar |
| [ProgressBar](progress-bar.md) | Progress indicator |
| [LoadingIndicator](loading-indicator.md) | Animated spinner |
| [Toast](toast.md) | Popup notifications |
| [Rule](rule.md) | Visual divider |
| [Sparkline](sparkline.md) | Mini trend chart |
| [Digits](digits.md) | Large ASCII numbers |
| [Placeholder](placeholder.md) | Development placeholder |
| [Pretty](pretty.md) | Pretty-print data |
| [RichText](rich-text.md) | Styled text spans |
| [Link](link.md) | Clickable URL |

## Data Widgets

| Widget | Description |
|--------|-------------|
| [DataTable](data-table.md) | Data grid with sorting |
| [Tree](tree.md) | Hierarchical tree view |
| [ListView](list-view.md) | Virtual scrolling list |
| [SelectionList](selection-list.md) | Multi-select with checkboxes |
| [Log](log.md) | Scrolling log viewer |
| [FilePanel](file-panel.md) | File browser |
| [TextViewer](text-viewer.md) | Scrollable text |
| [MarkdownView](markdown-view.md) | Markdown renderer |

## Layout Widgets

| Widget | Description |
|--------|-------------|
| [IconSidebar](icon-sidebar.md) | VSCode-style sidebar |
| [WindowManager](window-manager.md) | Draggable windows |
| [MenuBar](menu-bar.md) | Application menu |

---

## Quick Examples

### Button

```crystal
button = Tui::Button.new("Click Me", id: "btn")
button.on_click { puts "Clicked!" }
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
panel.content = Tui::VBox.new do |vbox|
  vbox.add_child Tui::Checkbox.new("Dark mode", id: "dark")
  vbox.add_child Tui::Checkbox.new("Notifications", id: "notif")
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
table.add_column("Name", width: 20)
table.add_column("Email", width: 30)
table.add_row(["Alice", "alice@example.com"])
table.add_row(["Bob", "bob@example.com"])
```

```
┌─────────────────────┬────────────────────────────────┐
│ Name                │ Email                          │
├─────────────────────┼────────────────────────────────┤
│ Alice               │ alice@example.com              │
│ Bob                 │ bob@example.com                │
└─────────────────────┴────────────────────────────────┘
```
