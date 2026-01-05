# Low-level terminal control
module Tui::Terminal
  extend self

  @@initialized : Bool = false
  @@original_blocking : Bool = true

  # Initialize terminal for TUI mode
  def init : Nil
    return if @@initialized

    # Use alternate screen buffer
    STDOUT.print(ANSI.enter_alt_screen)

    # Hide cursor
    STDOUT.print(ANSI.hide_cursor)

    # Enable mouse
    STDOUT.print(ANSI.enable_mouse)

    # Clear screen
    STDOUT.print(ANSI.clear)
    STDOUT.print(ANSI.home)
    STDOUT.flush

    @@initialized = true

    # Setup signal handlers
    setup_signals
  end

  # Restore terminal to original state
  def shutdown : Nil
    return unless @@initialized

    # Disable mouse
    STDOUT.print(ANSI.disable_mouse)

    # Show cursor
    STDOUT.print(ANSI.show_cursor)

    # Leave alternate screen
    STDOUT.print(ANSI.leave_alt_screen)

    # Reset colors
    STDOUT.print(ANSI.reset)
    STDOUT.flush

    @@initialized = false
  end

  # Check if terminal is initialized
  def initialized? : Bool
    @@initialized
  end

  # Run block in raw mode
  def raw(&block)
    STDIN.raw do
      yield
    end
  end

  # Get terminal size
  def size : {Int32, Int32}
    # Try ioctl first
    ws = uninitialized LibC::Winsize
    if LibC.ioctl(STDOUT.fd, LibC::TIOCGWINSZ, pointerof(ws)) == 0
      return {ws.ws_col.to_i32, ws.ws_row.to_i32}
    end

    # Fallback to environment variables
    cols = ENV["COLUMNS"]?.try(&.to_i32?) || 80
    rows = ENV["LINES"]?.try(&.to_i32?) || 24
    {cols, rows}
  end

  # Get terminal width
  def width : Int32
    size[0]
  end

  # Get terminal height
  def height : Int32
    size[1]
  end

  # Move cursor to position
  def cursor(x : Int32, y : Int32) : Nil
    STDOUT.print(ANSI.move(x, y))
    STDOUT.flush
  end

  # Clear screen
  def clear : Nil
    STDOUT.print(ANSI.clear)
    STDOUT.print(ANSI.home)
    STDOUT.flush
  end

  # Ring the bell
  def bell : Nil
    STDOUT.print('\a')
    STDOUT.flush
  end

  # Set window title (if supported)
  def set_title(title : String) : Nil
    STDOUT.print("\e]0;#{title}\a")
    STDOUT.flush
  end

  private def setup_signals : Nil
    # Handle SIGWINCH for terminal resize
    Signal::WINCH.trap do
      # Will be handled by event loop
    end

    # Handle SIGINT and SIGTERM for clean shutdown
    Signal::INT.trap do
      shutdown
      exit(130)
    end

    Signal::TERM.trap do
      shutdown
      exit(143)
    end
  end
end

# C library bindings for terminal size
lib LibC
  struct Winsize
    ws_row : UInt16
    ws_col : UInt16
    ws_xpixel : UInt16
    ws_ypixel : UInt16
  end

  {% if flag?(:darwin) %}
    TIOCGWINSZ = 0x40087468_u64
  {% else %}
    TIOCGWINSZ = 0x5413_u64
  {% end %}

  fun ioctl(fd : Int32, request : UInt64, ...) : Int32
end
