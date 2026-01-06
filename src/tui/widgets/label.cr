# Label widget - displays text
module Tui
  class Label < Widget
    include Reactive

    enum Align
      Left
      Center
      Right
    end

    reactive text : String = ""
    property style : Style = Style.default
    property align : Align = Align::Left

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
        display_line = Unicode.display_width(line) > @rect.width ? Unicode.truncate(line, @rect.width, "") : line
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
  end
end
