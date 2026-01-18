# ANSI escape code generation
module Tui::ANSI
  ESC = "\e"
  CSI = "\e["

  # Cursor movement
  def self.move(x : Int32, y : Int32) : String
    "#{CSI}#{y + 1};#{x + 1}H"
  end

  def self.move_up(n : Int32 = 1) : String
    "#{CSI}#{n}A"
  end

  def self.move_down(n : Int32 = 1) : String
    "#{CSI}#{n}B"
  end

  def self.move_right(n : Int32 = 1) : String
    "#{CSI}#{n}C"
  end

  def self.move_left(n : Int32 = 1) : String
    "#{CSI}#{n}D"
  end

  def self.home : String
    "#{CSI}H"
  end

  # Screen control
  def self.clear : String
    "#{CSI}2J"
  end

  def self.clear_line : String
    "#{CSI}2K"
  end

  def self.clear_to_end : String
    "#{CSI}0J"
  end

  # Cursor visibility
  def self.hide_cursor : String
    "#{CSI}?25l"
  end

  def self.show_cursor : String
    "#{CSI}?25h"
  end

  # Alternate screen buffer
  def self.enter_alt_screen : String
    "#{CSI}?1049h"
  end

  def self.leave_alt_screen : String
    "#{CSI}?1049l"
  end

  # Mouse support (SGR extended mode)
  def self.enable_mouse : String
    String.build do |s|
      s << "#{CSI}?1000h"  # Basic mouse
      s << "#{CSI}?1002h"  # Button event tracking
      s << "#{CSI}?1006h"  # SGR extended mode
    end
  end

  def self.disable_mouse : String
    String.build do |s|
      s << "#{CSI}?1006l"
      s << "#{CSI}?1002l"
      s << "#{CSI}?1000l"
    end
  end

  # Bracketed paste mode
  def self.enable_bracketed_paste : String
    "#{CSI}?2004h"
  end

  def self.disable_bracketed_paste : String
    "#{CSI}?2004l"
  end

  # Colors - 8 basic colors
  module Color
    BLACK   = 0
    RED     = 1
    GREEN   = 2
    YELLOW  = 3
    BLUE    = 4
    MAGENTA = 5
    CYAN    = 6
    WHITE   = 7
    DEFAULT = 9

    # Bright variants
    BRIGHT_BLACK   = 8
    BRIGHT_RED     = 9
    BRIGHT_GREEN   = 10
    BRIGHT_YELLOW  = 11
    BRIGHT_BLUE    = 12
    BRIGHT_MAGENTA = 13
    BRIGHT_CYAN    = 14
    BRIGHT_WHITE   = 15
  end

  def self.fg(color : Int32) : String
    if color < 8
      "#{CSI}3#{color}m"
    elsif color < 16
      "#{CSI}9#{color - 8}m"
    else
      "#{CSI}38;5;#{color}m"
    end
  end

  def self.bg(color : Int32) : String
    if color < 8
      "#{CSI}4#{color}m"
    elsif color < 16
      "#{CSI}10#{color - 8}m"
    else
      "#{CSI}48;5;#{color}m"
    end
  end

  # True color (24-bit)
  def self.fg_rgb(r : Int32, g : Int32, b : Int32) : String
    "#{CSI}38;2;#{r};#{g};#{b}m"
  end

  def self.bg_rgb(r : Int32, g : Int32, b : Int32) : String
    "#{CSI}48;2;#{r};#{g};#{b}m"
  end

  # Attributes
  def self.reset : String
    "#{CSI}0m"
  end

  def self.bold : String
    "#{CSI}1m"
  end

  def self.dim : String
    "#{CSI}2m"
  end

  def self.italic : String
    "#{CSI}3m"
  end

  def self.underline : String
    "#{CSI}4m"
  end

  def self.blink : String
    "#{CSI}5m"
  end

  def self.reverse : String
    "#{CSI}7m"
  end

  def self.strikethrough : String
    "#{CSI}9m"
  end

  # Combined style string
  def self.style(
    fg : Int32? = nil,
    bg : Int32? = nil,
    bold : Bool = false,
    dim : Bool = false,
    italic : Bool = false,
    underline : Bool = false,
    reverse : Bool = false
  ) : String
    String.build do |s|
      s << self.bold if bold
      s << self.dim if dim
      s << self.italic if italic
      s << self.underline if underline
      s << self.reverse if reverse
      s << self.fg(fg) if fg
      s << self.bg(bg) if bg
    end
  end
end
