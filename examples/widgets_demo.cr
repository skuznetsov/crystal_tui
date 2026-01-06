# Widgets Demo - showcases ProgressBar, Checkbox, RadioGroup, ComboBox, DraggableWindow
require "../src/tui"

# Global debug log
class DebugLog
  @@messages = [] of String
  @@max_lines = 30  # Keep more messages to test scrolling
  @@callback : Proc(Nil)?

  def self.log(msg : String)
    @@messages << msg
    @@messages.shift if @@messages.size > @@max_lines
    @@callback.try &.call
  end

  def self.messages : Array(String)
    @@messages
  end

  def self.on_update(&block : -> Nil)
    @@callback = block
  end

  def self.clear
    @@messages.clear
  end
end

class WidgetsDemo < Tui::App
  @progress_bar : Tui::ProgressBar
  @progress_bar_text : Tui::ProgressBar
  @checkbox : Tui::Checkbox
  @radio_group : Tui::RadioGroup
  @combo_box : Tui::ComboBox
  @window : Tui::DraggableWindow
  @log_panel : Tui::Panel
  @log_content : Tui::Label
  @status_label : Tui::Label
  @title_label : Tui::Label

  def initialize
    super

    # Title
    @title_label = Tui::Label.new(
      "=== Crystal TUI Widgets Demo ===  (Tab to navigate, +/- progress, F10 quit)",
      fg: Tui::Color.green,
      bold: true
    )

    # Normal progress bar
    @progress_bar = Tui::ProgressBar.new("progress1")
    @progress_bar.label = "Download"
    @progress_bar.value = 35.0

    # Progress bar with centered text
    @progress_bar_text = Tui::ProgressBar.new("progress2")
    @progress_bar_text.show_center_text = true
    @progress_bar_text.center_text = "Installing..."
    @progress_bar_text.value = 65.0
    @progress_bar_text.filled_bg = Tui::Color.blue
    @progress_bar_text.empty_bg = Tui::Color.palette(8)
    @progress_bar_text.text_fg = Tui::Color.white

    # Checkbox
    @checkbox = Tui::Checkbox.new("checkbox1")
    @checkbox.label = "Enable feature"
    @checkbox.on_change do |checked|
      update_status("Checkbox: #{checked ? "checked" : "unchecked"}")
    end

    # Radio Group
    @radio_group = Tui::RadioGroup.new("radio1")
    @radio_group.add_option("opt1", "Option 1")
    @radio_group.add_option("opt2", "Option 2")
    @radio_group.add_option("opt3", "Option 3")
    @radio_group.on_change do |id|
      update_status("Radio: selected #{id}")
    end

    # ComboBox
    @combo_box = Tui::ComboBox.new("combo1")
    @combo_box.placeholder = "Select language..."
    @combo_box.add_item("crystal", "Crystal")
    @combo_box.add_item("ruby", "Ruby")
    @combo_box.add_item("python", "Python")
    @combo_box.add_item("rust", "Rust")
    @combo_box.add_item("go", "Go")
    @combo_box.add_item("typescript", "TypeScript")
    @combo_box.add_item("javascript", "JavaScript")
    @combo_box.on_change do |item|
      update_status("ComboBox: selected #{item.label}")
    end

    # Draggable Window
    @window = Tui::DraggableWindow.new("Demo Window", "window1")
    @window.rect = Tui::Rect.new(45, 2, 30, 10)  # Set initial position
    @window.on_close do
      update_status("Window close clicked")
    end
    @window.on_maximize do
      update_status("Window maximized")
    end
    @window.on_minimize do
      update_status("Window minimized")
    end
    @window.on_move do |x, y|
      DebugLog.log("Window moved to #{x},#{y}")
    end

    # Add content to window
    content_label = Tui::Label.new("Drag title bar\nAlt+X close\nAlt+M maximize", fg: Tui::Color.cyan)
    @window.content = content_label

    # Log panel
    @log_panel = Tui::Panel.new("log_panel")
    @log_panel.title = "Debug Log"
    @log_panel.border_color = Tui::Color.yellow

    @log_content = Tui::Label.new("Click anywhere to see events...", fg: Tui::Color.white)
    @log_panel.content = @log_content

    # Update log display when new messages arrive
    DebugLog.on_update do
      @log_content.text = DebugLog.messages.join("\n")
      # Update content height for scrolling
      @log_panel.content_height = DebugLog.messages.size
      @log_content.mark_dirty!
      @log_panel.mark_dirty!
      mark_dirty!
    end

    # Status label
    @status_label = Tui::Label.new("Press Tab to navigate, Space to select, F10 to quit", fg: Tui::Color.yellow)

    # Set initial focus
    @checkbox.focused = true

    DebugLog.log("Demo started")
  end

  def compose : Array(Tui::Widget)
    [@title_label, @progress_bar, @progress_bar_text, @checkbox, @radio_group, @combo_box, @window, @log_panel, @status_label]
  end

  # Custom layout - not the default vertical stack
  private def layout_children : Nil
    width = @rect.width
    height = @rect.height

    @title_label.rect = Tui::Rect.new(2, 0, width - 4, 1)
    @progress_bar.rect = Tui::Rect.new(2, 2, 40, 1)
    @progress_bar_text.rect = Tui::Rect.new(2, 4, 40, 1)
    @checkbox.rect = Tui::Rect.new(2, 6, 30, 1)
    @radio_group.rect = Tui::Rect.new(2, 8, 40, 3)
    @combo_box.rect = Tui::Rect.new(2, 12, 25, 1)
    # Don't overwrite DraggableWindow rect - it manages its own position
    # Initial position is set in initialize
    @log_panel.rect = Tui::Rect.new(2, 14, 40, 8)
    @status_label.rect = Tui::Rect.new(0, height - 1, width, 1)
  end

  private def update_status(msg : String)
    @status_label.text = msg
    @status_label.mark_dirty!
    DebugLog.log(msg)
  end

  def handle_event(event : Tui::Event) : Bool
    # Log mouse events for debugging
    if event.is_a?(Tui::MouseEvent)
      if event.action.press?
        if event.button.wheel_up?
          DebugLog.log("Wheel UP at #{event.x},#{event.y}")
        elsif event.button.wheel_down?
          DebugLog.log("Wheel DOWN at #{event.x},#{event.y}")
        else
          DebugLog.log("Click at #{event.x},#{event.y} btn=#{event.button}")
        end
      elsif event.action.drag?
        DebugLog.log("Drag at #{event.x},#{event.y}")
      end
    end

    case event
    when Tui::KeyEvent
      case event.key
      when .f10?
        quit
        event.stop!
        return true
      when .tab?
        # Tab navigation between focusable widgets
        cycle_focus(event.modifiers.shift?)
        event.stop!
        return true
      end

      # Simulate progress with +/-
      if event.char == '+'
        @progress_bar.advance(5.0)
        @progress_bar_text.advance(5.0)
        @progress_bar_text.center_text = "#{@progress_bar_text.percentage.to_i}% complete"
        event.stop!
        return true
      end

      if event.char == '-'
        @progress_bar.value = @progress_bar.value - 5.0
        @progress_bar_text.value = @progress_bar_text.value - 5.0
        @progress_bar_text.center_text = "#{@progress_bar_text.percentage.to_i}% complete"
        event.stop!
        return true
      end
    end

    super
  end

  private def cycle_focus(reverse : Bool)
    focusable = @children.select(&.focusable?)
    return if focusable.empty?

    current_index = focusable.index { |w| w.focused? } || -1

    # Unfocus current
    if current_index >= 0
      focusable[current_index].focused = false
    end

    # Focus next/prev
    if reverse
      new_index = current_index <= 0 ? focusable.size - 1 : current_index - 1
    else
      new_index = (current_index + 1) % focusable.size
    end

    focusable[new_index].focused = true
    focusable[new_index].mark_dirty!
    mark_dirty!
  end
end

demo = WidgetsDemo.new
demo.run
