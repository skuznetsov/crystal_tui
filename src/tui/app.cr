# Main application class
module Tui
  abstract class App < Widget
    @buffer : Buffer
    @input : InputParser
    @running : Bool = false
    @last_size : {Int32, Int32}

    def initialize
      super(nil)
      width, height = Terminal.size
      @buffer = Buffer.new(width, height)
      @input = InputParser.new
      @last_size = {width, height}
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
      # Create a timer channel for periodic tasks (resize check)
      timer = Channel(Nil).new

      # Timer fiber - sends tick every 100ms for resize checks
      spawn(name: "tui-timer") do
        while @running
          sleep 100.milliseconds
          timer.send(nil) rescue break
        end
      end

      while @running
        # Wait for either input event or timer tick
        select
        when event = @input.events.receive?
          if event
            handle_event(event)
            # Render after event if dirty
            if dirty?
              layout_children
              render_all
            end
          else
            # Channel closed
            break
          end
        when timer.receive?
          # Timer tick - check for resize
          check_resize
          if dirty?
            layout_children
            render_all
          end
        end
      end

      timer.close
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

      # Render all visible children sorted by z_index (lower first, higher on top)
      clip = @rect
      @children.sort_by(&.z_index).each do |child|
        next unless child.visible?
        # Use render_rect for clipping (may be larger than layout rect for dropdowns, etc.)
        if child_clip = clip.intersect(child.render_rect)
          child.render(@buffer, child_clip)
        end
      end

      # Flush to terminal
      @buffer.flush(STDOUT)
      mark_clean!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      # App renders itself via render_all
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
