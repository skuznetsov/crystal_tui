require "../src/tui"

# CSS Hot Reload Demo
# Run this and edit examples/demo.tcss to see live updates!

class CSSHotReloadDemo < Tui::App
  CSS_PATH = "examples/demo.tcss"

  @panel : Tui::Panel
  @button1 : Tui::Button
  @button2 : Tui::Button
  @label : Tui::Label
  @status : Tui::Label

  def initialize
    super

    @panel = Tui::Panel.new("CSS Hot Reload Demo", id: "main-panel")

    @button1 = Tui::Button.new("Primary Button", id: "button1")

    @button2 = Tui::Button.new("Secondary Button", id: "button2")

    @label = Tui::Label.new(id: "info-label")
    @label.text = "Edit examples/demo.tcss and save to see changes!"
    @label.add_class("info")

    @status = Tui::Label.new(id: "status")
    @status.text = "Watching: #{CSS_PATH}"
  end

  # Apply CSS after compose has mounted the widgets, then watch for edits.
  def on_mount : Nil
    super
    load_css(CSS_PATH) if File.exists?(CSS_PATH)
    setup_hot_reload
  end

  private def setup_hot_reload : Nil
    return unless File.exists?(CSS_PATH)

    hot_reload = Tui::CSS::HotReload.new(250.milliseconds)

    hot_reload.on_reload = ->(path : String) {
      @status.text = "✓ Reloaded: #{path} at #{Time.local.to_s("%H:%M:%S")}"
      mark_dirty!
    }

    hot_reload.on_error = ->(path : String, ex : Exception) {
      @status.text = "✗ Error: #{ex.message}"
      mark_dirty!
    }

    hot_reload.watch_for_app(CSS_PATH, self)
    hot_reload.start
  end

  def compose : Array(Tui::Widget)
    [@panel, @button1, @button2, @label, @status] of Tui::Widget
  end

  private def layout_children : Nil
    return if @rect.empty?

    # Panel fills most of screen
    @panel.rect = Tui::Rect.new(2, 1, @rect.width - 4, @rect.height - 3)

    # Button 1
    @button1.rect = Tui::Rect.new(4, 4, 20, 1)

    # Button 2
    @button2.rect = Tui::Rect.new(4, 6, 20, 1)

    # Info label
    @label.rect = Tui::Rect.new(4, 9, @rect.width - 10, 1)

    # Status at bottom
    @status.rect = Tui::Rect.new(2, @rect.height - 2, @rect.width - 4, 1)
  end
end

# Create the demo CSS file if it doesn't exist
unless File.exists?(CSSHotReloadDemo::CSS_PATH)
  File.write(CSSHotReloadDemo::CSS_PATH, <<-TCSS)
  /* Demo TCSS - Edit this file to see hot reload! */

  $primary: cyan;

  /* Main panel styling */
  #main-panel {
    border: light white;
    border-title-color: $primary;
    title-align: center;
  }

  /* Info label */
  .info {
    color: yellow;
    text-align: center;
  }

  /* Status label */
  #status {
    color: black;
    background: $primary;
    text-align: center;
  }
  TCSS
end

CSSHotReloadDemo.new.run
