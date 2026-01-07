# Rule - Horizontal or vertical divider line
module Tui
  class Rule < Widget
    enum Direction
      Horizontal
      Vertical
    end

    property direction : Direction = Direction::Horizontal
    property color : Color = Color.palette(240)
    property style : Symbol = :line  # :line, :double, :thick, :dashed, :dotted
    property label : String = ""
    property label_color : Color = Color.white

    CHARS = {
      horizontal: {
        line:   '─',
        double: '═',
        thick:  '━',
        dashed: '╌',
        dotted: '┄',
      },
      vertical: {
        line:   '│',
        double: '║',
        thick:  '┃',
        dashed: '╎',
        dotted: '┆',
      },
    }

    def initialize(id : String? = nil, @direction : Direction = Direction::Horizontal)
      super(id)
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      line_style = Style.new(fg: @color)
      chars = @direction.horizontal? ? CHARS[:horizontal] : CHARS[:vertical]
      char = chars[@style]? || chars[:line]

      case @direction
      when .horizontal?
        render_horizontal(buffer, clip, char, line_style)
      when .vertical?
        render_vertical(buffer, clip, char, line_style)
      end
    end

    private def render_horizontal(buffer : Buffer, clip : Rect, char : Char, style : Style) : Nil
      y = @rect.y
      x_start = @rect.x
      x_end = @rect.x + @rect.width

      if @label.empty?
        # Simple line
        (x_start...x_end).each do |x|
          buffer.set(x, y, char, style) if clip.contains?(x, y)
        end
      else
        # Line with label in center
        label_text = " #{@label} "
        label_start = x_start + (@rect.width - label_text.size) // 2
        label_end = label_start + label_text.size
        label_style = Style.new(fg: @label_color)

        (x_start...x_end).each do |x|
          if x >= label_start && x < label_end
            char_idx = x - label_start
            buffer.set(x, y, label_text[char_idx], label_style) if clip.contains?(x, y)
          else
            buffer.set(x, y, char, style) if clip.contains?(x, y)
          end
        end
      end
    end

    private def render_vertical(buffer : Buffer, clip : Rect, char : Char, style : Style) : Nil
      x = @rect.x
      y_start = @rect.y
      y_end = @rect.y + @rect.height

      (y_start...y_end).each do |y|
        buffer.set(x, y, char, style) if clip.contains?(x, y)
      end
    end

    def min_size : {Int32, Int32}
      case @direction
      when .horizontal?
        {@label.size + 4, 1}
      when .vertical?
        {1, 3}
      else
        {1, 1}
      end
    end
  end
end
