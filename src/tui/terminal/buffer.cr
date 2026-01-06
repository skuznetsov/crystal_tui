# Double-buffered screen buffer (optimized flat array)
module Tui
  class Buffer
    getter width : Int32
    getter height : Int32

    @cells : Array(Cell)
    @prev_cells : Array(Cell)
    @dirty : Set(Tuple(Int32, Int32))

    def initialize(@width : Int32, @height : Int32)
      size = @width * @height
      @cells = Array.new(size) { Cell.empty }
      @prev_cells = Array.new(size) { Cell.new('\0') }  # Force initial draw
      @dirty = Set(Tuple(Int32, Int32)).new
    end

    # Set a cell at position
    def set(x : Int32, y : Int32, cell : Cell) : Nil
      return unless in_bounds?(x, y)

      idx = index(x, y)
      if @cells[idx] != cell
        @cells[idx] = cell
        @dirty.add({x, y})
      end
    end

    # Set a cell with char and style
    def set(x : Int32, y : Int32, char : Char, style : Style = Style.default) : Nil
      set(x, y, Cell.new(char, style))
    end

    # Get a cell at position
    def get(x : Int32, y : Int32) : Cell
      return Cell.empty unless in_bounds?(x, y)
      @cells[index(x, y)]
    end

    # Check if position is within bounds
    def in_bounds?(x : Int32, y : Int32) : Bool
      x >= 0 && x < @width && y >= 0 && y < @height
    end

    # Clear buffer with optional cell
    def clear(cell : Cell = Cell.empty) : Nil
      @height.times do |y|
        @width.times do |x|
          set(x, y, cell)
        end
      end
    end

    # Draw a string at position
    def draw_string(x : Int32, y : Int32, text : String, style : Style = Style.default) : Nil
      text.each_char_with_index do |char, i|
        set(x + i, y, char, style)
      end
    end

    # Draw a horizontal line
    def draw_hline(x : Int32, y : Int32, length : Int32, char : Char = '─', style : Style = Style.default) : Nil
      length.times do |i|
        set(x + i, y, char, style)
      end
    end

    # Draw a vertical line
    def draw_vline(x : Int32, y : Int32, length : Int32, char : Char = '│', style : Style = Style.default) : Nil
      length.times do |i|
        set(x, y + i, char, style)
      end
    end

    # Draw a box using BorderStyle enum
    def draw_box(x : Int32, y : Int32, w : Int32, h : Int32, style : Style = Style.default, border_style : BorderStyle = BorderStyle::Light) : Nil
      chars = Tui.border_chars(border_style)

      # Corners
      set(x, y, chars.tl, style)
      set(x + w - 1, y, chars.tr, style)
      set(x, y + h - 1, chars.bl, style)
      set(x + w - 1, y + h - 1, chars.br, style)

      # Horizontal lines
      draw_hline(x + 1, y, w - 2, chars.h, style)
      draw_hline(x + 1, y + h - 1, w - 2, chars.h, style)

      # Vertical lines
      draw_vline(x, y + 1, h - 2, chars.v, style)
      draw_vline(x + w - 1, y + 1, h - 2, chars.v, style)
    end

    # Legacy overload accepting Symbol for backwards compatibility
    def draw_box(x : Int32, y : Int32, w : Int32, h : Int32, style : Style, border_style : Symbol) : Nil
      bs = case border_style
           when :heavy  then BorderStyle::Heavy
           when :double then BorderStyle::Double
           when :round  then BorderStyle::Round
           when :ascii  then BorderStyle::Ascii
           else              BorderStyle::Light
           end
      draw_box(x, y, w, h, style, bs)
    end

    # Fill a rectangle
    def fill(x : Int32, y : Int32, w : Int32, h : Int32, cell : Cell = Cell.empty) : Nil
      h.times do |dy|
        w.times do |dx|
          set(x + dx, y + dy, cell)
        end
      end
    end

    # Resize buffer
    def resize(new_width : Int32, new_height : Int32) : Nil
      return if new_width == @width && new_height == @height

      new_size = new_width * new_height
      new_cells = Array.new(new_size) { Cell.empty }
      new_prev = Array.new(new_size) { Cell.new('\0') }

      # Copy existing content
      copy_height = Math.min(@height, new_height)
      copy_width = Math.min(@width, new_width)

      copy_height.times do |y|
        copy_width.times do |x|
          old_idx = y * @width + x
          new_idx = y * new_width + x
          new_cells[new_idx] = @cells[old_idx]
        end
      end

      @cells = new_cells
      @prev_cells = new_prev
      @width = new_width
      @height = new_height
      @dirty.clear

      # Mark all as dirty for full redraw
      @height.times do |y|
        @width.times do |x|
          @dirty.add({x, y})
        end
      end
    end

    # Flush changes to IO (typically STDOUT)
    def flush(io : IO) : Nil
      return if @dirty.empty?

      output = String.build do |s|
        last_style : Style? = nil
        last_x = -2
        last_y = -1

        # Sort dirty cells for sequential output
        sorted = @dirty.to_a.sort_by { |pos| {pos[1], pos[0]} }

        sorted.each do |pos|
          x, y = pos
          idx = y * @width + x
          cell = @cells[idx]

          # Skip if unchanged from previous frame
          next if @prev_cells[idx] == cell

          # Move cursor if not sequential
          if y != last_y || x != last_x + 1
            s << ANSI.move(x, y)
          end

          # Apply style if changed
          if last_style != cell.style
            s << cell.style.to_ansi
            last_style = cell.style
          end

          s << cell.char

          last_x = x
          last_y = y

          # Update previous buffer
          @prev_cells[idx] = cell
        end

        s << ANSI.reset
      end

      io.print(output)
      io.flush
      @dirty.clear
    end

    # Force full redraw on next flush
    def invalidate : Nil
      @height.times do |y|
        @width.times do |x|
          idx = index(x, y)
          @dirty.add({x, y})
          @prev_cells[idx] = Cell.new('\0')
        end
      end
    end

    # Get buffer content as string (for testing)
    def to_s(io : IO) : Nil
      @height.times do |y|
        @width.times do |x|
          io << @cells[index(x, y)].char
        end
        io << '\n' if y < @height - 1
      end
    end

    # Calculate flat array index from x,y coordinates
    @[AlwaysInline]
    private def index(x : Int32, y : Int32) : Int32
      y * @width + x
    end
  end
end
