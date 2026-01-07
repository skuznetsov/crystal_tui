require "../src/tui"

# VSCode-like layout demo
# ┌────┬──────────────────────────────────┐
# │ 💬 │ [Chat 1] [Chat 2] [main.cr]      │
# │Chats├──────────────────────────────────┤
# │    │                                   │
# │ 📁 │  Content area                     │
# │Files│  (markdown, files, settings)     │
# │    │                                   │
# │ ⚙️ │                                   │
# │Set │                                   │
# └────┴──────────────────────────────────┘

SAMPLE_CHAT = <<-MD
# Assistant Response

I'll help you implement that feature. Here's the approach:

## Analysis

The current code has a few issues:

1. **Missing validation** - Input isn't validated
2. **No error handling** - Exceptions aren't caught
3. *Performance* - Could be optimized

## Solution

Here's the fix:

```crystal
def process(input : String) : Result
  raise ArgumentError.new("Empty input") if input.empty?

  begin
    data = parse(input)
    transform(data)
  rescue ex : ParseError
    Result.error(ex.message)
  end
end
```

> Note: This handles edge cases properly.

---

Let me know if you need any clarification!
MD

SAMPLE_FILE = <<-MD
# main.cr

```crystal
require "./lib/app"

module MyApp
  VERSION = "1.0.0"

  def self.run
    app = App.new
    app.configure do |config|
      config.debug = true
      config.log_level = :info
    end
    app.start
  end
end

MyApp.run
```
MD

SAMPLE_SETTINGS = <<-MD
# Settings

## General

- **Theme**: Dark
- **Font Size**: 14px
- **Tab Size**: 2 spaces

## Editor

- **Auto Save**: Enabled
- **Format on Save**: Enabled
- **Line Numbers**: On

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Save | Ctrl+S |
| Find | Ctrl+F |
| Replace | Ctrl+H |
MD

class VSCodeDemo < Tui::App
  @sidebar : Tui::IconSidebar
  @tabs : Tui::TabbedPanel
  @split : Tui::SplitContainer
  @chat_view : Tui::MarkdownView
  @file_view : Tui::MarkdownView
  @settings_view : Tui::MarkdownView
  @current_mode : String = "chats"

  def initialize
    super

    # Create sidebar with emoji icons (Unicode support handles 2-wide chars)
    @sidebar = Tui::IconSidebar.new("sidebar")
    @sidebar.width = 5  # Width for emoji + padding
    @sidebar.show_border = false  # SplitContainer draws the splitter
    @sidebar.add_item("chats", '💬', "Chats", "Chat sessions")
    @sidebar.add_item("files", '📁', "Files", "File explorer")
    @sidebar.add_item("settings", '⚙', "Settings", "Configuration")
    @sidebar.set_badge("chats", 2)

    @sidebar.on_select do |id|
      switch_mode(id)
    end

    # Create content views
    @chat_view = Tui::MarkdownView.new("chat")
    @chat_view.content = SAMPLE_CHAT

    @file_view = Tui::MarkdownView.new("file")
    @file_view.content = SAMPLE_FILE

    @settings_view = Tui::MarkdownView.new("settings")
    @settings_view.content = SAMPLE_SETTINGS

    # Create tabbed panel for content
    @tabs = Tui::TabbedPanel.new("tabs")
    @tabs.positions = Set{Tui::TabbedPanel::TabPosition::Top}
    @tabs.add_tab("chat1", "Session 1") { @chat_view }
    @tabs.add_tab("chat2", "Session 2") { create_chat2_view }
    @tabs.content_bg = Tui::Color.palette(234)

    # Create split container: sidebar | tabs
    @split = Tui::SplitContainer.new(
      direction: Tui::SplitContainer::Direction::Horizontal,
      ratio: 0.0,  # Start at minimum
      id: "main_split"
    )
    @split.show_border = false  # No outer border
    @split.min_first = @sidebar.width  # Match sidebar width exactly
    @split.first = @sidebar
    @split.second = @tabs
  end

  private def create_chat2_view : Tui::MarkdownView
    view = Tui::MarkdownView.new("chat2")
    view.content = <<-MD
    # Session 2

    Previous conversation about **Crystal TUI**...

    ## Topic: Widget System

    - Discussed widget hierarchy
    - Planned event bubbling
    - Reviewed render pipeline

    ```crystal
    class Widget
      property rect : Rect
      property visible : Bool

      def render(buffer, clip)
        # ...
      end
    end
    ```
    MD
    view
  end

  private def switch_mode(id : String) : Nil
    @current_mode = id

    # Clear and rebuild tabs based on mode
    # For simplicity, we just update the tab labels to indicate mode
    case id
    when "chats"
      @tabs.switch_to("chat1")
    when "files"
      # Show file tabs
      @tabs.switch_to("chat1")  # Would show file tabs
    when "settings"
      @tabs.switch_to("chat1")  # Would show settings
    end

    mark_dirty!
  end

  def compose : Array(Tui::Widget)
    [@split] of Tui::Widget
  end

  def handle_event(event : Tui::Event) : Bool
    if event.is_a?(Tui::KeyEvent)
      # App-level shortcuts
      if event.matches?("ctrl+c") || event.matches?("ctrl+q")
        quit
        return true
      end

      if event.matches?("q")
        quit
        return true
      end

      # Switch sidebar with numbers
      if event.matches?("1")
        @sidebar.active_index = 0
        return true
      elsif event.matches?("2")
        @sidebar.active_index = 1
        return true
      elsif event.matches?("3")
        @sidebar.active_index = 2
        return true
      end

      # Tab switching
      if event.matches?("ctrl+tab")
        @tabs.active_tab = (@tabs.active_tab + 1) % @tabs.tabs.size
        mark_dirty!
        return true
      end
    end

    # Delegate to split container
    super
  end
end

VSCodeDemo.new.run
