require "../src/tui"

# Demo showcasing new widgets: Header, Switch, LoadingIndicator, Toast, Tree, Rule

class NewWidgetsDemo < Tui::App
  @header : Tui::Header
  @toast : Tui::Toast
  @tree : Tui::Tree(String)
  @switch1 : Tui::Switch
  @switch2 : Tui::Switch
  @loader : Tui::LoadingIndicator
  @split : Tui::SplitContainer

  def initialize
    super

    # Header with clock
    @header = Tui::Header.new("header")
    @header.title = "Crystal TUI"
    @header.subtitle = "New Widgets Demo"
    @header.icon = "💎"
    @header.start_clock

    # Toast notification system
    @toast = Tui::Toast.new("toast")
    @toast.position = :top_right

    # Tree widget
    @tree = Tui::Tree(String).new("tree")
    setup_tree

    # Switches
    @switch1 = Tui::Switch.new("dark_mode", on: true)
    @switch1.on_label = "Dark"
    @switch1.off_label = "Light"
    @switch1.on_change { |on| @toast.info("Theme: #{on ? "Dark" : "Light"}") }

    @switch2 = Tui::Switch.new("notifications", on: false)
    @switch2.on_label = "ON"
    @switch2.off_label = "OFF"
    @switch2.on_change { |on| @toast.success("Notifications #{on ? "enabled" : "disabled"}") }

    # Loading indicator
    @loader = Tui::LoadingIndicator.new("loader")
    @loader.text = "Processing..."
    @loader.start

    # Layout
    @split = Tui::SplitContainer.new(
      direction: Tui::SplitContainer::Direction::Horizontal,
      ratio: 0.4
    )
    @split.first = create_left_panel
    @split.second = create_right_panel
  end

  private def setup_tree : Nil
    root = Tui::Tree::Node(String).new("root", "Project", '📁', '📂')
    @tree.root = root

    src = root.add("src", "src", '📁', '📂')
    src.add("main.cr", "main.cr", '💎')
    src.add("app.cr", "app.cr", '💎')

    widgets = src.add("widgets", "widgets", '📁', '📂')
    widgets.add("button.cr", "button.cr", '💎')
    widgets.add("input.cr", "input.cr", '💎')
    widgets.add("panel.cr", "panel.cr", '💎')

    spec = root.add("spec", "spec", '📁', '📂')
    spec.add("spec_helper.cr", "spec_helper.cr", '💎')
    spec.add("app_spec.cr", "app_spec.cr", '🧪')

    root.add("README.md", "README.md", '📄')
    root.add("shard.yml", "shard.yml", '⚙')

    root.expand
    src.expand

    @tree.on_select do |node|
      @toast.info("Selected: #{node.label}")
    end
  end

  private def create_left_panel : Tui::Panel
    panel = Tui::Panel.new("left")
    panel.title = "File Explorer"

    # Add tree as child
    panel.add_child(@tree)

    panel
  end

  private def create_right_panel : Tui::Panel
    panel = Tui::Panel.new("right")
    panel.title = "Settings"
    panel
  end

  def compose : Array(Tui::Widget)
    [@header, @split, @toast]
  end

  # Custom layout for header + content
  private def layout_children : Nil
    return if @children.empty?
    return if @rect.empty?

    # Header takes 1 row at top
    @header.rect = Tui::Rect.new(@rect.x, @rect.y, @rect.width, 1)

    # Split takes remaining space
    @split.rect = Tui::Rect.new(@rect.x, @rect.y + 1, @rect.width, @rect.height - 1)

    # Toast renders as overlay (doesn't need rect assignment)
  end

  def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
    layout_children

    # Render header
    @header.render(buffer, clip)

    # Render split container
    @split.render(buffer, clip)

    # Render controls in right panel
    render_settings(buffer, clip)

    # Toast renders via overlay system
    @toast.render(buffer, clip)
  end

  private def render_settings(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
    # Get right panel area
    right_panel = @split.second.as(Tui::Panel)
    x = right_panel.rect.x + 2
    y = right_panel.rect.y + 2

    # Dark mode switch
    label_style = Tui::Style.new(fg: Tui::Color.white)
    "Dark Mode:".each_char_with_index do |char, i|
      buffer.set(x + i, y, char, label_style) if clip.contains?(x + i, y)
    end
    @switch1.rect = Tui::Rect.new(x + 12, y, 20, 1)
    @switch1.render(buffer, clip)

    # Rule divider
    rule = Tui::Rule.new
    rule.rect = Tui::Rect.new(x, y + 2, right_panel.rect.width - 4, 1)
    rule.label = "Notifications"
    rule.render(buffer, clip)

    # Notifications switch
    y += 4
    "Enable:".each_char_with_index do |char, i|
      buffer.set(x + i, y, char, label_style) if clip.contains?(x + i, y)
    end
    @switch2.rect = Tui::Rect.new(x + 12, y, 20, 1)
    @switch2.render(buffer, clip)

    # Loading indicator
    y += 3
    @loader.rect = Tui::Rect.new(x, y, 30, 1)
    @loader.render(buffer, clip)

    # Instructions
    y += 3
    instructions = [
      "Press 1-4 for toast types",
      "Tab to switch focus",
      "Enter/Space to toggle",
      "Arrow keys in tree",
      "q to quit"
    ]
    inst_style = Tui::Style.new(fg: Tui::Color.palette(245))
    instructions.each_with_index do |line, i|
      line.each_char_with_index do |char, ci|
        buffer.set(x + ci, y + i, char, inst_style) if clip.contains?(x + ci, y + i)
      end
    end
  end

  def handle_event(event : Tui::Event) : Bool
    if event.is_a?(Tui::KeyEvent)
      case
      when event.matches?("1")
        @toast.info("This is an info message")
        return true
      when event.matches?("2")
        @toast.success("Operation completed!")
        return true
      when event.matches?("3")
        @toast.warning("Warning: Check your settings")
        return true
      when event.matches?("4")
        @toast.error("Error: Something went wrong")
        return true
      when event.matches?("l")
        if @loader.running?
          @loader.stop
          @loader.text = "Stopped"
        else
          @loader.text = "Processing..."
          @loader.start
        end
        mark_dirty!
        return true
      end
    end

    # Route to tree
    if @tree.handle_event(event)
      mark_dirty!
      return true
    end

    # Route to switches
    if @switch1.focused? && @switch1.handle_event(event)
      mark_dirty!
      return true
    end
    if @switch2.focused? && @switch2.handle_event(event)
      mark_dirty!
      return true
    end

    super
  end
end

NewWidgetsDemo.new.run
