# Double-buffered screen buffer
module Tui
  class Buffer
    getter width : Int32
    getter height : Int32

    @cells : Array(Array(Cell))
    @prev_cells : Array(Array(Cell))
    @dirty : Set(Tuple(Int32, Int32))

    def initialize(@width : Int32, @height : Int32)
      @cells = Array.new(@height) { Array.new(@width) { Cell.empty } }
      @prev_cells = Array.new(@height) { Array.new(@width) { Cell.new('\0') } }  # Force initial draw
      @dirty = Set(Tuple(Int32, Int32)).new
    end

    # Set a cell at position
    def set(x : Int32, y : Int32, cell : Cell) : Nil
      return unless in_bounds?(x, y)

      if @cells[y][x] != cell
        @cells[y][x] = cell
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
      @cells[y][x]
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

    # Draw a box
    def draw_box(x : Int32, y : Int32, w : Int32, h : Int32, style : Style = Style.default, border_style : Symbol = :light) : Nil
      chars = case border_style
              when :light
                {tl: '┌', tr: '┐', bl: '└', br: '┘', h: '─', v: '│'}
              when :heavy
                {tl: '┏', tr: '┓', bl: '┗', br: '┛', h: '━', v: '┃'}
              when :double
                {tl: '╔', tr: '╗', bl: '╚', br: '╝', h: '═', v: '║'}
              when :round
                {tl: '╭', tr: '╮', bl: '╰', br: '╯', h: '─', v: '│'}
              else
                {tl: '┌', tr: '┐', bl: '└', br: '┘', h: '─', v: '│'}
              end

      # Corners
      set(x, y, chars[:tl], style)
      set(x + w - 1, y, chars[:tr], style)
      set(x, y + h - 1, chars[:bl], style)
      set(x + w - 1, y + h - 1, chars[:br], style)

      # Horizontal lines
      draw_hline(x + 1, y, w - 2, chars[:h], style)
      draw_hline(x + 1, y + h - 1, w - 2, chars[:h], style)

      # Vertical lines
      draw_vline(x, y + 1, h - 2, chars[:v], style)
      draw_vline(x + w - 1, y + 1, h - 2, chars[:v], style)
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

      new_cells = Array.new(new_height) { Array.new(new_width) { Cell.empty } }
      new_prev = Array.new(new_height) { Array.new(new_width) { Cell.new('\0') } }

      # Copy existing content
      copy_height = Math.min(@height, new_height)
      copy_width = Math.min(@width, new_width)

      copy_height.times do |y|
        copy_width.times do |x|
          new_cells[y][x] = @cells[y][x]
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
          cell = @cells[y][x]

          # Skip if unchanged from previous frame
          next if @prev_cells[y][x] == cell

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
          @prev_cells[y][x] = cell
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
          @dirty.add({x, y})
          @prev_cells[y][x] = Cell.new('\0')
        end
      end
    end

    # Get buffer content as string (for testing)
    def to_s(io : IO) : Nil
      @height.times do |y|
        @width.times do |x|
          io << @cells[y][x].char
        end
        io << '\n' if y < @height - 1
      end
    end
  end
end
