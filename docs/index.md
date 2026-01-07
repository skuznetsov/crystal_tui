# Crystal TUI Documentation

A modern, Textual-inspired TUI framework for Crystal.

## Quick Links

- [Getting Started](guide/getting-started.md) - Build your first app in 5 minutes
- [Widget Gallery](widgets/index.md) - Browse 40+ widgets with examples
- [CSS Reference](css-reference/index.md) - Complete styling guide
- [TUML Guide](guide/tuml.md) - Define UIs in markup

## Features

- **40+ Widgets** - Buttons, inputs, tables, trees, dialogs, and more
- **CSS Styling** - Textual-compatible TCSS with hot reload
- **TUML Markup** - Define UIs in Pug, YAML, or JSON
- **Reactive** - Automatic re-rendering on property changes
- **Keyboard & Mouse** - Full input support with focus management

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

## Hello World

```crystal
require "tui"

class HelloApp < Tui::App
  def compose : Array(Tui::Widget)
    [
      Tui::Panel.new("Hello", id: "main") do |p|
        p.content = Tui::Label.new("Welcome to Crystal TUI!")
      end
    ]
  end
end

HelloApp.new.run
```

## Next Steps

1. Follow the [Getting Started](guide/getting-started.md) tutorial
2. Explore the [Widget Gallery](widgets/index.md)
3. Learn [CSS Styling](css-reference/index.md)
4. Try [TUML](guide/tuml.md) for declarative UIs
