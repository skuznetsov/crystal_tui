# Placeholder - Development placeholder widget
# Shows a labeled box with optional dimensions, useful during layout development
module Tui
  class Placeholder < Widget
    property label : String
    property show_dimensions : Bool = true
    property fill_char : Char = '·'

    # Styling
    property border_style : Style = Style.new(fg: Color.palette(240))
    property label_style : Style = Style.new(fg: Color.cyan)
    property dim_style : Style = Style.new(fg: Color.palette(100))
    property fill_style : Style = Style.new(fg: Color.palette(236))

    def initialize(@label : String = "Placeholder", id : String? = nil)
      super(id)
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Draw border
      draw_border(buffer, clip)

      # Draw fill pattern
      draw_fill(buffer, clip)

      # Draw label (centered)
      draw_label(buffer, clip)

      # Draw dimensions
      draw_dimensions(buffer, clip) if @show_dimensions
    end

    private def draw_border(buffer : Buffer, clip : Rect) : Nil
      # Top border
      if @rect.y >= clip.y && @rect.y < clip.y + clip.height
        buffer.set(@rect.x, @rect.y, '┌', @border_style) if clip.contains?(@rect.x, @rect.y)
        (1...@rect.width - 1).each do |i|
          x = @rect.x + i
          buffer.set(x, @rect.y, '─', @border_style) if clip.contains?(x, @rect.y)
        end
        buffer.set(@rect.x + @rect.width - 1, @rect.y, '┐', @border_style) if clip.contains?(@rect.x + @rect.width - 1, @rect.y)
      end

      # Bottom border
      bottom_y = @rect.y + @rect.height - 1
      if bottom_y >= clip.y && bottom_y < clip.y + clip.height
        buffer.set(@rect.x, bottom_y, '└', @border_style) if clip.contains?(@rect.x, bottom_y)
        (1...@rect.width - 1).each do |i|
          x = @rect.x + i
          buffer.set(x, bottom_y, '─', @border_style) if clip.contains?(x, bottom_y)
        end
        buffer.set(@rect.x + @rect.width - 1, bottom_y, '┘', @border_style) if clip.contains?(@rect.x + @rect.width - 1, bottom_y)
      end

      # Side borders
      (1...@rect.height - 1).each do |i|
        y = @rect.y + i
        next unless y >= clip.y && y < clip.y + clip.height
        buffer.set(@rect.x, y, '│', @border_style) if clip.contains?(@rect.x, y)
        buffer.set(@rect.x + @rect.width - 1, y, '│', @border_style) if clip.contains?(@rect.x + @rect.width - 1, y)
      end
    end

    private def draw_fill(buffer : Buffer, clip : Rect) : Nil
      (1...@rect.height - 1).each do |row|
        y = @rect.y + row
        next unless y >= clip.y && y < clip.y + clip.height

        (1...@rect.width - 1).each do |col|
          x = @rect.x + col
          next unless clip.contains?(x, y)
          buffer.set(x, y, @fill_char, @fill_style)
        end
      end
    end

    private def draw_label(buffer : Buffer, clip : Rect) : Nil
      return if @rect.height < 3 || @rect.width < 5

      # Center vertically
      y = @rect.y + @rect.height // 2
      return unless y >= clip.y && y < clip.y + clip.height

      # Truncate label if needed
      max_width = @rect.width - 4
      display_label = if @label.size > max_width
                        @label[0, max_width - 1] + "…"
                      else
                        @label
                      end

      # Center horizontally
      x = @rect.x + (@rect.width - display_label.size) // 2

      display_label.each_char_with_index do |char, i|
        px = x + i
        buffer.set(px, y, char, @label_style) if clip.contains?(px, y)
      end
    end

    private def draw_dimensions(buffer : Buffer, clip : Rect) : Nil
      return if @rect.height < 5 || @rect.width < 10

      dim_str = "#{@rect.width}×#{@rect.height}"

      # Position below label
      y = @rect.y + @rect.height // 2 + 1
      return unless y >= clip.y && y < clip.y + clip.height
      return if y >= @rect.y + @rect.height - 1

      x = @rect.x + (@rect.width - dim_str.size) // 2

      dim_str.each_char_with_index do |char, i|
        px = x + i
        buffer.set(px, y, char, @dim_style) if clip.contains?(px, y)
      end
    end

    def min_size : {Int32, Int32}
      {Math.max(10, @label.size + 4), 5}
    end
  end
end
