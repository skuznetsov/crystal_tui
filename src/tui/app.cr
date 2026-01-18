# Main application class
module Tui
  # Theme mode for styling
  enum Theme
    Light
    Dark
  end

  # Overlay callback for rendering popups/menus on top of everything
  alias OverlayRenderer = Proc(Buffer, Rect, Nil)

  # Module-level overlay storage (shared across all App subclasses)
  class_getter overlays : Array(OverlayRenderer) = [] of OverlayRenderer
  class_property current_app : App? = nil

  # Scrollbar overlay registry - drawn after all widgets, before regular overlays
  # This ensures scrollbars are never overwritten by content
  # Cleared each frame before render, widgets register during their render
  class_getter scrollbar_overlays : Array(OverlayRenderer) = [] of OverlayRenderer

  # Clear scrollbar overlays (called at start of each frame)
  def self.clear_scrollbar_overlays : Nil
    @@scrollbar_overlays.clear
  end

  # Register a scrollbar to be drawn at end of frame
  def self.register_scrollbar(&block : Buffer, Rect -> Nil) : Nil
    @@scrollbar_overlays << block
  end
  class_property theme : Theme = Theme::Dark

  # Dev mode - enables hot reload and debug features
  # Set via TUI_DEV=1 environment variable or programmatically
  class_property? dev_mode : Bool = ENV.has_key?("TUI_DEV") && ENV["TUI_DEV"] == "1"

  # Last CSS error (for error overlay)
  class_property css_error : {path: String, error: String}? = nil

  abstract class App < Widget
    @buffer : Buffer
    @input : InputParser
    @running : Bool = false
    @last_size : {Int32, Int32}
    @stylesheet : CSS::Stylesheet?
    @css_hot_reload : CSS::HotReload?

    # CSS file path (set by subclass or via css_file class method)
    class_property css_path : String?

    def initialize
      super(nil)
      width, height = Terminal.size
      @buffer = Buffer.new(width, height)
      @input = InputParser.new
      @last_size = {width, height}
      Tui.current_app = self

      # Load CSS if path is set
      if css_path = self.class.css_path
        load_css(css_path)

        # Auto-enable hot reload in dev mode
        if Tui.dev_mode?
          enable_css_hot_reload(css_path)
        end
      end
    end

    # Load CSS from file
    def load_css(path : String) : Nil
      return unless File.exists?(path)
      @stylesheet = CSS.parse_file(path)
      apply_styles_to_all
    end

    # Load CSS from string
    def load_css_string(css : String) : Nil
      @stylesheet = CSS.parse(css)
      apply_styles_to_all
    end

    # Apply a stylesheet
    def apply_stylesheet(stylesheet : CSS::Stylesheet) : Nil
      @stylesheet = stylesheet
      apply_styles_to_all
    end

    # Enable hot reload for CSS file
    def enable_css_hot_reload(path : String? = nil, interval : Time::Span = 500.milliseconds) : Nil
      css_path = path || self.class.css_path
      return unless css_path

      @css_hot_reload = CSS::HotReload.new(interval)
      hr = @css_hot_reload.not_nil!

      # Set up error handler to capture CSS errors
      hr.on_error = ->(path : String, ex : Exception) {
        Tui.css_error = {path: path, error: ex.message || "Unknown error"}
        mark_dirty!
        nil
      }

      # Clear error on successful reload
      hr.on_reload = ->(path : String) {
        Tui.css_error = nil
        nil
      }

      hr.watch_for_app(css_path, self)
      hr.start
    end

    # Get current stylesheet
    def stylesheet : CSS::Stylesheet?
      @stylesheet
    end

    # Apply CSS styles to all widgets
    private def apply_styles_to_all : Nil
      return unless stylesheet = @stylesheet
      apply_styles_recursive(self, stylesheet)
    end

    private def apply_styles_recursive(widget : Widget, stylesheet : CSS::Stylesheet) : Nil
      # Get computed style for this widget
      style = stylesheet.style_for(widget)
      widget.apply_css_style(style) unless style.empty?

      # Recurse to children
      widget.children.each do |child|
        apply_styles_recursive(child, stylesheet)
      end
    end

    # Register an overlay to be rendered on top of everything
    def self.add_overlay(renderer : OverlayRenderer) : Nil
      Tui.overlays << renderer
      Tui.current_app.try(&.mark_dirty!)
    end

    # Remove an overlay
    def self.remove_overlay(renderer : OverlayRenderer) : Nil
      Tui.overlays.delete(renderer)
      Tui.current_app.try(&.mark_dirty!)
    end

    # Clear all overlays
    def self.clear_overlays : Nil
      Tui.overlays.clear
      Tui.current_app.try(&.mark_dirty!)
    end

    # Override to create root widget tree
    abstract def compose : Array(Widget)

    # Start the application
    def run : Nil
      Terminal.init
      @running = true

      begin
        run_with_input
      ensure
        Terminal.shutdown
      end
    end

    # Mount and layout without starting terminal (for testing)
    def mount_headless(width : Int32, height : Int32) : Nil
      @buffer = Buffer.new(width, height)
      @rect = Rect.new(0, 0, width, height)
      on_mount
      layout_children
    end

    # Refresh layout (public access to layout_children)
    def refresh : Nil
      layout_children
    end

    private def run_with_input : Nil
      # Mount widgets
      on_mount

      # Set initial layout
      @rect = Rect.new(0, 0, @buffer.width, @buffer.height)
      layout_children

      # Initial render
      render_all

      # Main event loop - use raw mode only if TTY
      if STDIN.tty?
        STDIN.raw do
          @input.start
          begin
            event_loop
          ensure
            @input.stop
          end
        end
      else
        # Non-TTY mode (pipe/testing) - limited functionality
        @input.start
        begin
          event_loop
        ensure
          @input.stop
        end
      end
    end

    # Stop the application
    def quit : Nil
      @running = false
      @input.stop
    end

    private def event_loop : Nil
      while @running
        begin
          # Render immediately if dirty (don't wait for events)
          if dirty?
            layout_children
            render_all
          end

          # Wait for input or resize signal (no timeout = no CPU overhead when idle)
          select
          when event = @input.events.receive
            handle_event(event)
          when Terminal.resize_channel.receive
            check_resize
          end

          if Terminal.consume_sigint
            handle_event(KeyEvent.new('c', Modifiers::Ctrl))
          end

          if event = @input.flush_paste_burst
            handle_event(event)
          end
        rescue Channel::ClosedError
          break
        end
      end
    end

    private def check_resize : Nil
      current_size = Terminal.size
      return if current_size == @last_size

      @last_size = current_size
      @buffer.resize(current_size[0], current_size[1])
      @rect = Rect.new(0, 0, current_size[0], current_size[1])

      # Dispatch resize event
      event = ResizeEvent.new(current_size[0], current_size[1])
      handle_event(event)

      mark_dirty!
    end

    private def layout_children : Nil
      # Simple layout: give all space to children stacked vertically
      return if @children.empty?

      available_height = @rect.height
      child_count = @children.count(&.visible?)
      return if child_count == 0

      height_per_child = available_height // child_count
      current_y = @rect.y

      @children.each do |child|
        next unless child.visible?

        child.rect = Rect.new(
          @rect.x,
          current_y,
          @rect.width,
          height_per_child
        )
        current_y += height_per_child
      end
    end

    private def render_all : Nil
      @buffer.clear

      # Clear scrollbar registry - widgets will register during this frame's render
      Tui.clear_scrollbar_overlays

      # Render all visible children sorted by z_index (lower first, higher on top)
      clip = @rect
      @children.sort_by(&.z_index).each do |child|
        next unless child.visible?
        # Use render_rect for clipping (may be larger than layout rect for dropdowns, etc.)
        if child_clip = clip.intersect(child.render_rect)
          child.render(@buffer, child_clip)
        end
      end

      # Render scrollbar overlays AFTER all widgets (guarantees scrollbars on top of content)
      full_clip = @rect
      Tui.scrollbar_overlays.each do |scrollbar|
        scrollbar.call(@buffer, full_clip)
      end

      # Render overlays LAST (on top of everything, with full screen clip)
      Tui.overlays.each do |overlay|
        overlay.call(@buffer, full_clip)
      end

      # Render CSS error overlay in dev mode
      if Tui.dev_mode? && (css_error = Tui.css_error)
        render_css_error_overlay(@buffer, full_clip, css_error)
      end

      # Flush to terminal
      @buffer.flush(STDOUT)
      mark_clean!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      # Render children (for headless testing via harness)
      # When running normally, render_all is used instead
      Tui.clear_scrollbar_overlays

      @children.sort_by(&.z_index).each do |child|
        next unless child.visible?
        if child_clip = clip.intersect(child.render_rect)
          child.render(buffer, child_clip)
        end
      end

      # Render scrollbar overlays after all widgets
      Tui.scrollbar_overlays.each do |scrollbar|
        scrollbar.call(buffer, clip)
      end

      # Render overlays
      Tui.overlays.each do |overlay|
        overlay.call(buffer, clip)
      end
    end

    # Render CSS error overlay (dev mode only)
    private def render_css_error_overlay(buffer : Buffer, clip : Rect, error : {path: String, error: String}) : Nil
      # Error box dimensions
      error_style = Style.new(fg: Color.white, bg: Color.red, attrs: Attributes::Bold)
      path_style = Style.new(fg: Color.yellow, bg: Color.red)
      msg_style = Style.new(fg: Color.white, bg: Color.red)

      lines = [] of String
      lines << " CSS Error "
      lines << ""
      lines << " File: #{error[:path]} "
      lines << ""

      # Wrap error message
      error[:error].split('\n').each do |line|
        lines << " #{line} "
      end
      lines << ""
      lines << " Fix the error to reload "

      # Calculate box size
      max_width = lines.map { |l| Unicode.display_width(l) }.max
      box_width = Math.min(max_width + 4, clip.width - 4)
      box_height = Math.min(lines.size + 2, clip.height - 2)

      # Center the box
      box_x = clip.x + (clip.width - box_width) // 2
      box_y = clip.y + 1  # Near top

      # Draw background
      box_height.times do |dy|
        box_width.times do |dx|
          buffer.set(box_x + dx, box_y + dy, ' ', error_style)
        end
      end

      # Draw border
      buffer.set(box_x, box_y, '┌', error_style)
      buffer.set(box_x + box_width - 1, box_y, '┐', error_style)
      buffer.set(box_x, box_y + box_height - 1, '└', error_style)
      buffer.set(box_x + box_width - 1, box_y + box_height - 1, '┘', error_style)

      (1...box_width - 1).each do |dx|
        buffer.set(box_x + dx, box_y, '─', error_style)
        buffer.set(box_x + dx, box_y + box_height - 1, '─', error_style)
      end

      (1...box_height - 1).each do |dy|
        buffer.set(box_x, box_y + dy, '│', error_style)
        buffer.set(box_x + box_width - 1, box_y + dy, '│', error_style)
      end

      # Draw title
      title = " CSS Error "
      title_x = box_x + (box_width - Unicode.display_width(title)) // 2
      title.each_char_with_index do |char, i|
        buffer.set(title_x + i, box_y, char, error_style)
      end

      # Draw content
      content_y = box_y + 2
      lines[2..].each_with_index do |line, idx|
        break if content_y + idx >= box_y + box_height - 1

        style = idx == 0 ? path_style : msg_style  # File path in yellow
        x = box_x + 2
        line.each_char_with_index do |char, i|
          break if x + i >= box_x + box_width - 2
          buffer.set(x + i, content_y + idx, char, style)
        end
      end
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?

      # Handle app-level keys
      if event.is_a?(KeyEvent)
        if event.matches?("ctrl+c") || event.matches?("ctrl+q")
          quit
          return true
        end

        # Tab focus navigation
        if event.matches?("tab")
          focus_next
          return true
        end

        if event.matches?("shift+tab")
          focus_prev
          return true
        end

        # Route key events to focused widget first
        if focused = Widget.focused_widget
          if focused.handle_event(event)
            return true
          end
        end

        # 'q' for quit only if not handled by focused widget
        if event.matches?("q")
          quit
          return true
        end
      end

      # Delegate to children (for mouse events, etc.)
      super
    end

    # Override to be notified of app-level events
    def on_resize(width : Int32, height : Int32) : Nil
    end

    # Get app reference (self)
    def app : App?
      self
    end
  end
end
