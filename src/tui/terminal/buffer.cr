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

    # Set a wide character (handles 2-cell characters like emoji/CJK)
    def set_wide(x : Int32, y : Int32, char : Char, style : Style = Style.default) : Int32
      width = Unicode.char_width(char)
      if width == 2
        # Wide character: set main cell and continuation
        set(x, y, Cell.new(char, style, wide: true, continuation: false))
        set(x + 1, y, Cell.continuation(style))
        2
      else
        # Normal character
        set(x, y, Cell.new(char, style))
        width
      end
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

    # Draw a string at position (with Unicode width support)
    def draw_string(x : Int32, y : Int32, text : String, style : Style = Style.default) : Int32
      current_x = x
      text.each_char do |char|
        width = set_wide(current_x, y, char, style)
        current_x += width
      end
      current_x - x  # Return total width drawn
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

          # Handle continuation cells
          # Skip if both current and previous are continuation (nothing to output)
          # But if previous was NOT continuation and current IS, or vice versa, output needed
          prev_cell = @prev_cells[idx]
          if cell.continuation?
            # If previous was also continuation, skip (terminal fills these)
            if prev_cell.continuation?
              @prev_cells[idx] = cell
              next
            end
            # Previous was NOT continuation, but now it IS - need to output space to clear
            # (This happens when a wide char replaces a narrow one at position x+1)
            # Move cursor and output a space to clear the ghost character
            if y != last_y || x != (last_x + 1)
              s << ANSI.move(x, y)
            end
            if last_style != cell.style
              s << cell.style.to_ansi
              last_style = cell.style
            end
            s << ' '  # Output space to clear the old character
            last_x = x
            last_y = y
            @prev_cells[idx] = cell
            next
          elsif prev_cell.continuation? && !cell.continuation?
            # Previous was continuation, now it's not - need to output the new cell
            # This clears the "ghost" from the old wide character
            # Fall through to output the cell
          end

          # Move cursor if not sequential
          # For wide chars, cursor moves 2 positions
          expected_x = last_x + (last_y == y && last_x >= 0 && @cells[last_y * @width + last_x]?.try(&.wide?) ? 2 : 1)
          if y != last_y || x != expected_x
            s << ANSI.move(x, y)
          end

          # Apply style if changed from last output OR if different from what was previously in this cell
          # The second condition fixes a bug where consecutive cells with same new style but different
          # old styles would cause the terminal to keep the old style
          prev_cell_style = @prev_cells[idx].style
          if last_style != cell.style || prev_cell_style != cell.style
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

    # Force redraw of a specific region
    def invalidate_region(x : Int32, y : Int32, width : Int32, height : Int32) : Nil
      height.times do |dy|
        py = y + dy
        next unless py >= 0 && py < @height
        width.times do |dx|
          px = x + dx
          next unless px >= 0 && px < @width
          idx = index(px, py)
          @dirty.add({px, py})
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

    # Get buffer content with ANSI color codes (for visual debugging)
    def to_ansi : String
      String.build do |s|
        last_style : Style? = nil
        @height.times do |y|
          @width.times do |x|
            cell = @cells[index(x, y)]
            # Skip continuation cells
            next if cell.continuation?

            if last_style != cell.style
              s << cell.style.to_ansi
              last_style = cell.style
            end
            s << cell.char
          end
          s << ANSI.reset << '\n'
          last_style = nil
        end
      end
    end

    # Save buffer as ANSI-colored text file
    def save_ansi(path : String) : Nil
      File.write(path, to_ansi)
    end

    # Get buffer as simple grid for analysis (returns array of rows)
    def to_grid : Array(String)
      (0...@height).map do |y|
        String.build do |s|
          @width.times do |x|
            cell = @cells[index(x, y)]
            s << (cell.continuation? ? ' ' : cell.char)
          end
        end.rstrip
      end
    end

    # Debug dump: show non-space characters with positions
    def debug_dump : String
      String.build do |s|
        s << "Buffer #{@width}x#{@height}\n"
        s << "=" * 40 << "\n"
        @height.times do |y|
          row = String.build do |rs|
            @width.times do |x|
              cell = @cells[index(x, y)]
              rs << (cell.continuation? ? ' ' : cell.char)
            end
          end
          stripped = row.rstrip
          s << "Row #{y.to_s.rjust(2)}: |#{stripped}|\n" unless stripped.empty?
        end
      end
    end

    # Calculate flat array index from x,y coordinates
    @[AlwaysInline]
    private def index(x : Int32, y : Int32) : Int32
      y * @width + x
    end
  end
end
