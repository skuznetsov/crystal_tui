# Label widget - displays text
module Tui
  class Label < Widget
    include Reactive

    enum Align
      Left
      Center
      Right
    end

    enum TextOverflow
      Clip      # Just cut off
      Ellipsis  # Add ... at end
    end

    reactive text : String = ""
    property style : Style = Style.default
    property align : Align = Align::Left
    property text_overflow : TextOverflow = TextOverflow::Ellipsis

    def initialize(
      @text : String = "",
      id : String? = nil,
      @style : Style = Style.default,
      @align : Align = Align::Left
    )
      super(id)
    end

    # Convenience constructor with named style
    def self.new(
      text : String,
      id : String? = nil,
      fg : Color? = nil,
      bg : Color? = nil,
      bold : Bool = false,
      align : Align = Align::Left
    ) : Label
      attrs = Attributes::None
      attrs |= Attributes::Bold if bold

      style = Style.new(
        fg: fg || Color.default,
        bg: bg || Color.default,
        attrs: attrs
      )

      new(text, id, style, align)
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?

      # Clear background
      @rect.each_cell do |x, y|
        next unless clip.contains?(x, y)
        buffer.set(x, y, ' ', @style)
      end

      # Split text into lines
      lines = @text.split('\n')

      # Draw each line
      lines.each_with_index do |line, line_idx|
        break if line_idx >= @rect.height

        # Truncate line to fit width (using display width)
        ellipsis = @text_overflow.ellipsis? ? "…" : ""
        display_line = if Unicode.display_width(line) > @rect.width
                         Unicode.truncate(line, @rect.width, ellipsis)
                       else
                         line
                       end
        line_width = Unicode.display_width(display_line)

        # Calculate x position based on alignment
        text_x = case @align
                 when .left?
                   @rect.x
                 when .center?
                   @rect.x + (@rect.width - line_width) // 2
                 when .right?
                   @rect.x + @rect.width - line_width
                 else
                   @rect.x
                 end

        text_y = @rect.y + line_idx

        # Draw line (tracking display position for wide chars)
        display_pos = 0
        display_line.each_char do |char|
          char_width = Unicode.char_width(char)
          next if char_width == 0  # Skip combining characters

          x = text_x + display_pos
          break if x >= @rect.x + @rect.width  # Stop if we'd overflow

          if clip.contains?(x, text_y)
            buffer.set(x, text_y, char, @style)
            # Wide characters: fill second cell with space to prevent artifacts
            if char_width == 2 && clip.contains?(x + 1, text_y)
              buffer.set(x + 1, text_y, ' ', @style)
            end
          end

          display_pos += char_width
        end
      end
    end

    def watch_text(value : String)
      mark_dirty!
    end

    # Override to handle text-specific CSS properties
    def apply_css_style(css_style : Hash(String, CSS::Value)) : Nil
      super(css_style)

      css_style.each do |property, value|
        case property
        when "text-align"
          @align = case value.to_s.downcase
                   when "left"   then Align::Left
                   when "center" then Align::Center
                   when "right"  then Align::Right
                   else               Align::Left
                   end
        when "color"
          if color = parse_color(value)
            @style = Style.new(fg: color, bg: @style.bg, attrs: @style.attrs)
          end
        when "background"
          if color = parse_color(value)
            @style = Style.new(fg: @style.fg, bg: color, attrs: @style.attrs)
          end
        when "text-style"
          attrs = parse_text_style(value.to_s)
          @style = Style.new(fg: @style.fg, bg: @style.bg, attrs: attrs)
        when "text-overflow"
          @text_overflow = case value.to_s.downcase
                           when "clip"     then TextOverflow::Clip
                           when "ellipsis" then TextOverflow::Ellipsis
                           else                 TextOverflow::Ellipsis
                           end
        end
      end
    end

    private def parse_color(value : CSS::Value) : Color?
      case value
      when Color
        value.as(Color)
      when String
        str = value.as(String).downcase
        case str
        when "white"   then Color.white
        when "black"   then Color.black
        when "red"     then Color.red
        when "green"   then Color.green
        when "blue"    then Color.blue
        when "yellow"  then Color.yellow
        when "cyan"    then Color.cyan
        when "magenta" then Color.magenta
        else                nil
        end
      else
        nil
      end
    end

    private def parse_text_style(value : String) : Attributes
      attrs = Attributes::None
      value.split(/\s+/).each do |part|
        case part.downcase
        when "bold"      then attrs |= Attributes::Bold
        when "dim"       then attrs |= Attributes::Dim
        when "italic"    then attrs |= Attributes::Italic
        when "underline" then attrs |= Attributes::Underline
        when "blink"     then attrs |= Attributes::Blink
        when "reverse"   then attrs |= Attributes::Reverse
        when "strike", "strikethrough" then attrs |= Attributes::Strikethrough
        end
      end
      attrs
    end
  end
end
