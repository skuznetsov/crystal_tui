# Grid container - arranges children in a grid
module Tui
  class Grid < Widget
    property columns : Int32 = 2
    property rows : Int32 = 0  # 0 = auto (calculate from children count)
    property column_gap : Int32 = 0
    property row_gap : Int32 = 0

    # Store column and row spans per child (by index)
    @column_spans : Hash(Int32, Int32) = {} of Int32 => Int32
    @row_spans : Hash(Int32, Int32) = {} of Int32 => Int32

    def initialize(id : String? = nil, @columns : Int32 = 2, &block : -> Array(Widget))
      super(id)
      @compose_block = block
    end

    def initialize(id : String? = nil, @columns : Int32 = 2)
      super(id)
      @compose_block = nil
    end

    @compose_block : (-> Array(Widget))?

    def compose : Array(Widget)
      @compose_block.try(&.call) || [] of Widget
    end

    # Set column span for a child at index
    def set_column_span(child_index : Int32, span : Int32) : Nil
      @column_spans[child_index] = span.clamp(1, @columns)
    end

    # Set row span for a child at index
    def set_row_span(child_index : Int32, span : Int32) : Nil
      @row_spans[child_index] = span
    end

    # Get column span for a child
    def column_span(child_index : Int32) : Int32
      @column_spans[child_index]? || 1
    end

    # Get row span for a child
    def row_span(child_index : Int32) : Int32
      @row_spans[child_index]? || 1
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?

      layout_children

      @children.each do |child|
        next unless child.visible?
        if child_clip = clip.intersect(child.rect)
          child.render(buffer, child_clip)
        end
      end
    end

    private def layout_children : Nil
      return if @children.empty?
      return if @columns <= 0

      visible_children = @children.select(&.visible?)
      return if visible_children.empty?

      # Calculate actual row count
      actual_rows = if @rows > 0
                      @rows
                    else
                      # Auto-calculate rows based on children and columns
                      (visible_children.size + @columns - 1) // @columns
                    end

      # Calculate cell dimensions
      total_col_gap = @column_gap * (@columns - 1)
      total_row_gap = @row_gap * (actual_rows - 1)

      cell_width = (@rect.width - total_col_gap) // @columns
      cell_height = (@rect.height - total_row_gap) // actual_rows

      # Create a grid to track occupied cells
      occupied = Array(Array(Bool)).new(actual_rows) { Array(Bool).new(@columns, false) }

      # Place each child
      visible_children.each_with_index do |child, idx|
        col_span = column_span(idx)
        row_span_val = row_span(idx)

        # Find first available position
        pos = find_next_position(occupied, col_span, row_span_val)
        next unless pos

        col, row = pos

        # Mark cells as occupied
        row_span_val.times do |dr|
          col_span.times do |dc|
            r = row + dr
            c = col + dc
            if r < actual_rows && c < @columns
              occupied[r][c] = true
            end
          end
        end

        # Calculate position and size
        x = @rect.x + col * (cell_width + @column_gap)
        y = @rect.y + row * (cell_height + @row_gap)
        w = cell_width * col_span + @column_gap * (col_span - 1)
        h = cell_height * row_span_val + @row_gap * (row_span_val - 1)

        child.rect = Rect.new(x, y, w, h)
      end
    end

    private def find_next_position(occupied : Array(Array(Bool)), col_span : Int32, row_span_val : Int32) : {Int32, Int32}?
      rows = occupied.size
      cols = @columns

      rows.times do |row|
        cols.times do |col|
          next if col + col_span > cols
          next if row + row_span_val > rows

          # Check if all cells in span are free
          fits = true
          row_span_val.times do |dr|
            col_span.times do |dc|
              if occupied[row + dr][col + dc]
                fits = false
                break
              end
            end
            break unless fits
          end

          return {col, row} if fits
        end
      end

      nil
    end

    # Override to handle grid-specific CSS properties
    def apply_css_style(css_style : Hash(String, CSS::Value)) : Nil
      super(css_style)

      css_style.each do |property, value|
        case property
        when "grid-columns"
          @columns = value.to_s.to_i? || @columns
        when "grid-rows"
          @rows = value.to_s.to_i? || @rows
        when "grid-gutter", "gap"
          gap = value.to_s.to_i? || 0
          @column_gap = gap
          @row_gap = gap
        when "column-gap"
          @column_gap = value.to_s.to_i? || @column_gap
        when "row-gap"
          @row_gap = value.to_s.to_i? || @row_gap
        end
      end
    end
  end
end
