# TUML - TUI Markup Language

TUML allows you to define widget hierarchies in markup instead of code.

## Formats

TUML supports three formats:

| Format | Extension | Best For |
|--------|-----------|----------|
| Pug | `.tui` | Hand-written UIs, concise |
| YAML | `.tui.yaml` | Configuration, readable |
| JSON | `.tui.json` | Generation, tooling |

## Pug Format

The most concise format, inspired by Pug/Jade:

```pug
Panel#main(title="My App")
  Label#greeting Hello World
  Button#submit.primary Click Me
```

### Syntax

```
WidgetType#id.class1.class2(attr="value" attr2="value2") text content
```

- **WidgetType** - Widget class name (required)
- **#id** - Widget ID (optional)
- **.class** - CSS classes (optional, multiple allowed)
- **(attrs)** - Attributes in key="value" format (optional)
- **text** - Text content for Label, Button, etc. (optional)

### Nesting

Use indentation (2 spaces) for hierarchy:

```pug
Panel#outer
  Panel#inner
    Label Welcome
    Button OK
```

### Full Example

```pug
Panel#main(title="Settings" border="round")
  VBox
    Checkbox#dark(checked="true") Dark Mode
    Checkbox#sounds Enable Sounds

    Rule

    HBox
      Button#cancel Cancel
      Button#save.primary Save
```

## YAML Format

More verbose but familiar:

```yaml
Panel#main:
  title: Settings
  border: round
  children:
    - VBox:
        children:
          - Checkbox#dark:
              checked: true
              text: Dark Mode
          - Checkbox#sounds:
              text: Enable Sounds
          - Rule:
          - HBox:
              children:
                - Button#cancel:
                    text: Cancel
                - Button#save:
                    classes: [primary]
                    text: Save
```

### Structure

```yaml
WidgetType#id.class:
  attribute: value
  children:
    - ChildWidget:
        ...
```

## JSON Format

For machine generation:

```json
{
  "type": "Panel",
  "id": "main",
  "title": "Settings",
  "border": "round",
  "children": [
    {
      "type": "VBox",
      "children": [
        {
          "type": "Checkbox",
          "id": "dark",
          "checked": "true",
          "text": "Dark Mode"
        },
        {
          "type": "Button",
          "id": "save",
          "classes": ["primary"],
          "text": "Save"
        }
      ]
    }
  ]
}
```

## Using TUML

### Parse and Build

```crystal
require "tui"

# From string
widget = Tui::TUML::Builder.from_string(<<-TUI, :pug)
  Panel#main(title="Hello")
    Label Greetings!
    Button OK
TUI

# From file (auto-detects format)
widget = Tui::TUML::Builder.from_file("app.tui")
```

### In an App

```crystal
class MyApp < Tui::App
  def compose : Array(Tui::Widget)
    if widget = Tui::TUML::Builder.from_file("ui/main.tui")
      [widget]
    else
      [] of Tui::Widget
    end
  end

  def on_mount : Nil
    super

    # Wire up events after mounting
    if btn = query_one("#submit", Tui::Button)
      btn.on_click { submit_form }
    end
  end
end
```

## Supported Widgets

All built-in widgets are supported:

### Containers
- `Panel`, `VBox`, `HBox`, `Grid`

### Input
- `Button`, `Input`, `Checkbox`, `Switch`, `Slider`

### Display
- `Label`, `Header`, `Footer`, `Rule`, `ProgressBar`, `Placeholder`

### Data
- `Tree`, `ListView`, `DataTable`, `TextEditor`, `Log`

## Widget Attributes

Each widget supports different attributes:

### Panel
```pug
Panel#id(title="Title" border="round")
```

### Button
```pug
Button#id.class Label Text
# or
Button#id(label="Label Text")
```

### Input
```pug
Input#id(placeholder="Enter text" value="default")
```

### Checkbox
```pug
Checkbox#id(checked="true") Label Text
```

### Slider
```pug
Slider#id(min="0" max="100" value="50")
```

### ProgressBar
```pug
ProgressBar#id(value="0.75")
```

## Best Practices

1. **Use IDs** for widgets you need to reference in code
2. **Use classes** for styling groups of widgets
3. **Keep TUML simple** - complex logic belongs in code
4. **Separate concerns** - TUML for structure, TCSS for style, Crystal for behavior

## Comparison

| Aspect | TUML | Code |
|--------|------|------|
| Readability | Visual hierarchy | More verbose |
| Hot reload | Future feature | Not possible |
| Type safety | Runtime | Compile time |
| IDE support | Limited | Full |
| Best for | Layout, prototyping | Complex logic |

## Future Features

- Event binding syntax: `Button(@click="handler")`
- Data binding: `Label(text="{{ model.name }}")`
- Include/import: `@include "components/header.tui"`
- Visual editor
