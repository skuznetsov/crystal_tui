# A single cell in the terminal buffer
module Tui
  # Color representation
  struct Color
    property value : Int32
    property? transparent : Bool

    def initialize(@value : Int32 = -1, @transparent : Bool = false)
    end

    def self.default : Color
      new(-1)
    end

    def self.transparent : Color
      new(-1, transparent: true)
    end

    def self.black : Color
      new(ANSI::Color::BLACK)
    end

    def self.red : Color
      new(ANSI::Color::RED)
    end

    def self.green : Color
      new(ANSI::Color::GREEN)
    end

    def self.yellow : Color
      new(ANSI::Color::YELLOW)
    end

    def self.blue : Color
      new(ANSI::Color::BLUE)
    end

    def self.magenta : Color
      new(ANSI::Color::MAGENTA)
    end

    def self.cyan : Color
      new(ANSI::Color::CYAN)
    end

    def self.white : Color
      new(ANSI::Color::WHITE)
    end

    # 256 color palette
    def self.palette(index : Int32) : Color
      new(index)
    end

    # True color (24-bit RGB)
    def self.rgb(r : Int32, g : Int32, b : Int32) : Color
      # Encode as negative to distinguish from 256 palette
      # Format: -((r << 16) | (g << 8) | b) - 1
      new(-((r << 16) | (g << 8) | b) - 2)
    end

    def rgb? : Bool
      @value < -1
    end

    def to_rgb : {Int32, Int32, Int32}
      if rgb?
        encoded = -(@value + 2)
        r = (encoded >> 16) & 0xFF
        g = (encoded >> 8) & 0xFF
        b = encoded & 0xFF
        {r, g, b}
      else
        {0, 0, 0}
      end
    end

    def default? : Bool
      @value == -1 && !@transparent
    end

    def ==(other : Color) : Bool
      @value == other.value && @transparent == other.transparent?
    end

    # Dim this color (for shadow effects)
    def dimmed : Color
      if rgb?
        r, g, b = to_rgb
        Color.rgb(r // 2, g // 2, b // 2)
      elsif @value >= 0 && @value < 8
        # Basic colors -> dim versions
        self
      else
        self
      end
    end
  end

  # Text attributes
  @[Flags]
  enum Attributes
    Bold
    Dim
    Italic
    Underline
    Blink
    Reverse
    Strikethrough
  end

  # Style combining colors and attributes
  struct Style
    property fg : Color
    property bg : Color
    property attrs : Attributes

    def initialize(
      @fg : Color = Color.default,
      @bg : Color = Color.default,
      @attrs : Attributes = Attributes::None
    )
    end

    def self.default : Style
      new
    end

    def bold? : Bool
      @attrs.bold?
    end

    def dim? : Bool
      @attrs.dim?
    end

    def italic? : Bool
      @attrs.italic?
    end

    def underline? : Bool
      @attrs.underline?
    end

    def reverse? : Bool
      @attrs.reverse?
    end

    def ==(other : Style) : Bool
      @fg == other.fg && @bg == other.bg && @attrs == other.attrs
    end

    # Generate ANSI escape sequence for this style
    def to_ansi : String
      String.build do |s|
        s << ANSI.reset

        s << ANSI.bold if bold?
        s << ANSI.dim if dim?
        s << ANSI.italic if italic?
        s << ANSI.underline if underline?
        s << ANSI.reverse if reverse?

        unless @fg.default? || @fg.transparent?
          if @fg.rgb?
            r, g, b = @fg.to_rgb
            s << ANSI.fg_rgb(r, g, b)
          else
            s << ANSI.fg(@fg.value)
          end
        end

        unless @bg.default? || @bg.transparent?
          if @bg.rgb?
            r, g, b = @bg.to_rgb
            s << ANSI.bg_rgb(r, g, b)
          else
            s << ANSI.bg(@bg.value)
          end
        end
      end
    end
  end

  # A single cell on screen
  struct Cell
    property char : Char
    property style : Style
    property? wide : Bool          # True if this is a wide (2-column) character
    property? continuation : Bool  # True if this is the right half of a wide char

    def initialize(@char : Char = ' ', @style : Style = Style.default, @wide : Bool = false, @continuation : Bool = false)
    end

    def self.empty : Cell
      new(' ')
    end

    def self.transparent : Cell
      new(' ', Style.new(bg: Color.transparent))
    end

    # Continuation cell (right half of wide char)
    def self.continuation(style : Style = Style.default) : Cell
      new(' ', style, wide: false, continuation: true)
    end

    def ==(other : Cell) : Bool
      @char == other.char && @style == other.style && @wide == other.wide? && @continuation == other.continuation?
    end

    def transparent_bg? : Bool
      @style.bg.transparent?
    end

    # Create copy with dimmed colors (for shadow)
    def with_dimmed_colors : Cell
      Cell.new(
        @char,
        Style.new(
          fg: @style.fg.dimmed,
          bg: @style.bg.dimmed,
          attrs: @style.attrs | Attributes::Dim
        )
      )
    end
  end
end
