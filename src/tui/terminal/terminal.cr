# Low-level terminal control
module Tui::Terminal
  extend self

  @@initialized : Bool = false
  @@original_blocking : Bool = true
  @@sigint_pending : Bool = false
  @@resize_channel : Channel(Nil) = Channel(Nil).new(1)

  # Width corrections from runtime calibration
  # Maps codepoint -> actual_terminal_width
  @@width_corrections = {} of Int32 => Int32

  # Test characters for width calibration
  CALIBRATION_CHARS = [
    '缺', # CJK U+7F3A - common problematic character
    '漢', # CJK U+6F22
    '⚠', # Warning sign U+26A0
    '→', # Arrow U+2192
    '★', # Star U+2605
  ]

  # Initialize terminal for TUI mode
  def init : Nil
    return if @@initialized

    # Use alternate screen buffer
    STDOUT.print(ANSI.enter_alt_screen)

    # Hide cursor
    STDOUT.print(ANSI.hide_cursor)

    # Enable mouse
    STDOUT.print(ANSI.enable_mouse)

    # Enable bracketed paste
    STDOUT.print(ANSI.enable_bracketed_paste)

    # Distinguish Shift+Enter / Option+key from Enter / letter when the
    # terminal supports kitty CSI u or xterm modifyOtherKeys.
    STDOUT.print(ANSI.enable_modified_keys)

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

    # Disable bracketed paste
    STDOUT.print(ANSI.disable_bracketed_paste)

    STDOUT.print(ANSI.disable_modified_keys)

    # Show cursor
    STDOUT.print(ANSI.show_cursor)

    # Leave alternate screen
    STDOUT.print(ANSI.leave_alt_screen)

    # Reset colors
    STDOUT.print(ANSI.reset)
    STDOUT.flush

    @@initialized = false
  end

  def consume_sigint : Bool
    pending = @@sigint_pending
    @@sigint_pending = false if pending
    pending
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
    {% if flag?(:win32) %}
      # Try the Windows console API first
      info = uninitialized LibC::CONSOLE_SCREEN_BUFFER_INFO
      handle = LibC.GetStdHandle(LibC::STD_OUTPUT_HANDLE)
      if handle != LibC::INVALID_HANDLE_VALUE && LibC.GetConsoleScreenBufferInfo(handle, pointerof(info)) != 0
        cols = (info.srWindow.right - info.srWindow.left + 1).to_i32
        rows = (info.srWindow.bottom - info.srWindow.top + 1).to_i32
        return {cols, rows} if cols > 0 && rows > 0
      end
    {% else %}
      # Try ioctl first
      ws = uninitialized LibC::Winsize
      if LibC.ioctl(STDOUT.fd, LibC::TIOCGWINSZ, pointerof(ws)) == 0
        return {ws.ws_col.to_i32, ws.ws_row.to_i32}
      end
    {% end %}

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

  # Channel that receives resize notifications from SIGWINCH
  def resize_channel : Channel(Nil)
    @@resize_channel
  end

  private def setup_signals : Nil
    {% if flag?(:win32) %}
      # Windows has no SIGWINCH equivalent; poll the console size instead.
      start_resize_poller

      # Signal::INT/TERM traps raise NotImplementedError on win32.
      # Process.on_terminate is the portable replacement (backed by
      # SetConsoleCtrlHandler) and covers both cases below.
      Process.on_terminate do |reason|
        if reason.interrupted?
          @@sigint_pending = true
        else
          shutdown
          exit(143)
        end
      end
    {% else %}
      # Handle SIGWINCH for terminal resize - notify via channel
      Signal::WINCH.trap do
        select
        when @@resize_channel.send(nil)
        else
          # Channel full, resize already pending
        end
      end

      # Handle SIGINT and SIGTERM for clean shutdown
      Signal::INT.trap do
        @@sigint_pending = true
      end

      Signal::TERM.trap do
        shutdown
        exit(143)
      end
    {% end %}
  end

  {% if flag?(:win32) %}
    # Windows exposes no console-resize event; poll GetConsoleScreenBufferInfo
    # periodically and feed changes into the same resize_channel the Unix
    # WINCH trap uses.
    private def start_resize_poller : Nil
      spawn do
        last_size = size
        loop do
          sleep 250.milliseconds
          current = size
          next if current == last_size
          last_size = current
          select
          when @@resize_channel.send(nil)
          else
            # Channel full, resize already pending
          end
        end
      end
    end
  {% end %}
end

{% if flag?(:win32) %}
  # C library bindings for terminal size (Windows console API)
  lib LibC
    struct COORD
      x : Int16
      y : Int16
    end

    struct SMALL_RECT
      left : Int16
      top : Int16
      right : Int16
      bottom : Int16
    end

    struct CONSOLE_SCREEN_BUFFER_INFO
      dwSize : COORD
      dwCursorPosition : COORD
      wAttributes : UInt16
      srWindow : SMALL_RECT
      dwMaximumWindowSize : COORD
    end

    fun GetConsoleScreenBufferInfo(hConsoleOutput : HANDLE, lpConsoleScreenBufferInfo : CONSOLE_SCREEN_BUFFER_INFO*) : BOOL
  end
{% else %}
  # C library bindings for terminal size
  lib LibC
    struct Winsize
      ws_row : UInt16
      ws_col : UInt16
      ws_xpixel : UInt16
      ws_ypixel : UInt16
    end

  {% if flag?(:darwin) || flag?(:freebsd) %}
    TIOCGWINSZ = 0x40087468_u64
  {% else %}
    TIOCGWINSZ = 0x5413_u64
  {% end %}

    fun ioctl(fd : Int32, request : UInt64, ...) : Int32
  end
{% end %}
