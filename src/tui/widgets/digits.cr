# Digits - Large number display using ASCII art
module Tui
  class Digits < Widget
    # 3x5 digit patterns (each digit is 3 chars wide, 5 lines tall)
    PATTERNS = {
      '0' => [
        "┌─┐",
        "│ │",
        "│ │",
        "│ │",
        "└─┘",
      ],
      '1' => [
        "  ┐",
        "  │",
        "  │",
        "  │",
        "  ╵",
      ],
      '2' => [
        "┌─┐",
        "  │",
        "┌─┘",
        "│  ",
        "└─┘",
      ],
      '3' => [
        "┌─┐",
        "  │",
        " ─┤",
        "  │",
        "└─┘",
      ],
      '4' => [
        "╷ ╷",
        "│ │",
        "└─┤",
        "  │",
        "  ╵",
      ],
      '5' => [
        "┌─┐",
        "│  ",
        "└─┐",
        "  │",
        "└─┘",
      ],
      '6' => [
        "┌─┐",
        "│  ",
        "├─┐",
        "│ │",
        "└─┘",
      ],
      '7' => [
        "┌─┐",
        "  │",
        "  │",
        "  │",
        "  ╵",
      ],
      '8' => [
        "┌─┐",
        "│ │",
        "├─┤",
        "│ │",
        "└─┘",
      ],
      '9' => [
        "┌─┐",
        "│ │",
        "└─┤",
        "  │",
        "└─┘",
      ],
      '-' => [
        "   ",
        "   ",
        "───",
        "   ",
        "   ",
      ],
      '+' => [
        "   ",
        " │ ",
        "─┼─",
        " │ ",
        "   ",
      ],
      '.' => [
        "   ",
        "   ",
        "   ",
        "   ",
        " ● ",
      ],
      ':' => [
        "   ",
        " ● ",
        "   ",
        " ● ",
        "   ",
      ],
      ' ' => [
        "   ",
        "   ",
        "   ",
        "   ",
        "   ",
      ],
    }

    DIGIT_WIDTH  = 3
    DIGIT_HEIGHT = 5
    SPACING      = 1

    property value : String = "0"
    property style : Style = Style.new(fg: Color.cyan)
    property dim_style : Style = Style.new(fg: Color.palette(240))

    def initialize(id : String? = nil, @value : String = "0")
      super(id)
    end

    # Set numeric value
    def number=(num : Int32 | Int64 | Float64) : Nil
      @value = num.to_s
      mark_dirty!
    end

    # Set time value (HH:MM:SS)
    def time=(t : Time) : Nil
      @value = t.to_s("%H:%M:%S")
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      x_offset = @rect.x
      y_offset = @rect.y

      @value.each_char do |char|
        pattern = PATTERNS[char]?
        next unless pattern

        # Render this digit
        pattern.each_with_index do |line, row|
          y = y_offset + row
          next if y >= @rect.y + @rect.height
          next unless y >= clip.y && y < clip.y + clip.height

          line.each_char_with_index do |c, col|
            x = x_offset + col
            next if x >= @rect.x + @rect.width
            next unless clip.contains?(x, y)

            # Use dim style for space/empty, normal for content
            char_style = c == ' ' ? @dim_style : @style
            buffer.set(x, y, c, char_style)
          end
        end

        x_offset += DIGIT_WIDTH + SPACING
      end
    end

    def min_size : {Int32, Int32}
      width = @value.size * (DIGIT_WIDTH + SPACING) - SPACING
      width = Math.max(DIGIT_WIDTH, width)
      {width, DIGIT_HEIGHT}
    end
  end
end
