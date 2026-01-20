# DataTable widget - tabular data display with selection
module Tui
  class DataTable < Widget
    struct Column
      property key : String
      property label : String
      property width : Int32?      # nil = auto
      property align : Label::Align

      def initialize(
        @key : String,
        @label : String = "",
        @width : Int32? = nil,
        @align : Label::Align = Label::Align::Left
      )
        @label = @key if @label.empty?
      end
    end

    alias Row = Hash(String, String)

    property columns : Array(Column) = [] of Column
    property rows : Array(Row) = [] of Row

    # State
    @cursor_row : Int32 = 0
    @show_header : Bool = true
    @zebra_stripes : Bool = false
    @scroll_y : Int32 = 0

    # Property accessors
    def cursor_row : Int32
      @cursor_row
    end

    def cursor_row=(value : Int32) : Int32
      @cursor_row = value
      mark_dirty!
      value
    end

    def show_header? : Bool
      @show_header
    end

    def show_header=(value : Bool) : Bool
      @show_header = value
      mark_dirty!
      value
    end

    def zebra_stripes? : Bool
      @zebra_stripes
    end

    def zebra_stripes=(value : Bool) : Bool
      @zebra_stripes = value
      mark_dirty!
      value
    end

    # Styles
    property header_style : Style = Style.new(
      fg: Color.black,
      bg: Color.white,
      attrs: Attributes::Bold
    )
    property row_style : Style = Style.new(fg: Color.white, bg: Color.default)
    property alt_row_style : Style = Style.new(fg: Color.white, bg: Color.rgb(30, 30, 40))
    property cursor_style : Style = Style.new(fg: Color.black, bg: Color.cyan)
    property selected_style : Style = Style.new(fg: Color.yellow, bg: Color.blue)

    # Multi-selection
    @selected : Set(Int32) = Set(Int32).new

    # Callbacks
    @on_select : Proc(Int32, Row, Nil)?
    @on_activate : Proc(Int32, Row, Nil)?

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    def on_select(&block : Int32, Row -> Nil) : Nil
      @on_select = block
    end

    def on_activate(&block : Int32, Row -> Nil) : Nil
      @on_activate = block
    end

    # Add a column
    def add_column(key : String, label : String = "", width : Int32? = nil, align : Label::Align = Label::Align::Left) : Nil
      @columns << Column.new(key, label, width, align)
      mark_dirty!
    end

    # Add a row
    def add_row(data : Row) : Nil
      @rows << data
      mark_dirty!
    end

    def add_row(**data) : Nil
      row = Row.new
      data.each { |k, v| row[k.to_s] = v.to_s }
      add_row(row)
    end

    # Clear all rows
    def clear_rows : Nil
      @rows.clear
      @cursor_row = 0
      @scroll_y = 0
      @selected.clear
      mark_dirty!
    end

    # Get selected rows
    def selected_rows : Array(Row)
      @selected.map { |i| @rows[i]? }.compact
    end

    # Toggle selection on current row
    def toggle_selection : Nil
      if @selected.includes?(@cursor_row)
        @selected.delete(@cursor_row)
      else
        @selected.add(@cursor_row)
      end
      mark_dirty!
    end

    # Select all
    def select_all : Nil
      @rows.size.times { |i| @selected.add(i) }
      mark_dirty!
    end

    # Clear selection
    def clear_selection : Nil
      @selected.clear
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Calculate column widths
      col_widths = calculate_column_widths

      # Draw header
      y = @rect.y
      if @show_header
        draw_header(buffer, clip, col_widths, y)
        y += 1
      end

      # Calculate visible rows
      visible_height = @rect.height - (@show_header ? 1 : 0)
      ensure_cursor_visible(visible_height)

      # Draw rows
      visible_height.times do |i|
        row_idx = @scroll_y + i
        break if row_idx >= @rows.size

        row_y = y + i
        next unless row_y < @rect.y + @rect.height

        draw_row(buffer, clip, col_widths, row_y, row_idx)
      end

      # Fill empty space
      empty_start = y + Math.min(visible_height, @rows.size - @scroll_y)
      (empty_start...(@rect.y + @rect.height)).each do |empty_y|
        @rect.width.times do |x|
          buffer.set(@rect.x + x, empty_y, ' ', @row_style) if clip.contains?(@rect.x + x, empty_y)
        end
      end
    end

    private def calculate_column_widths : Array(Int32)
      return [] of Int32 if @columns.empty?

      available = @rect.width - (@columns.size - 1)  # Account for separators
      fixed_width = 0
      auto_count = 0

      @columns.each do |col|
        if w = col.width
          fixed_width += w
        else
          auto_count += 1
        end
      end

      auto_width = auto_count > 0 ? (available - fixed_width) // auto_count : 0
      auto_width = Math.max(1, auto_width)

      @columns.map { |col| col.width || auto_width }
    end

    private def draw_header(buffer : Buffer, clip : Rect, widths : Array(Int32), y : Int32) : Nil
      x = @rect.x

      @columns.each_with_index do |col, i|
        width = widths[i]
        draw_cell(buffer, clip, x, y, width, col.label, @header_style, col.align)
        x += width + 1  # +1 for separator
      end

      # Fill remaining width
      while x < @rect.x + @rect.width
        buffer.set(x, y, ' ', @header_style) if clip.contains?(x, y)
        x += 1
      end
    end

    private def draw_row(buffer : Buffer, clip : Rect, widths : Array(Int32), y : Int32, row_idx : Int32) : Nil
      row = @rows[row_idx]
      x = @rect.x

      # Determine style
      style = if row_idx == @cursor_row && focused?
                @cursor_style
              elsif @selected.includes?(row_idx)
                @selected_style
              elsif @zebra_stripes && row_idx.odd?
                @alt_row_style
              else
                @row_style
              end

      @columns.each_with_index do |col, i|
        width = widths[i]
        value = row[col.key]? || ""
        draw_cell(buffer, clip, x, y, width, value, style, col.align)
        x += width + 1
      end

      # Fill remaining width
      while x < @rect.x + @rect.width
        buffer.set(x, y, ' ', style) if clip.contains?(x, y)
        x += 1
      end
    end

    private def draw_cell(buffer : Buffer, clip : Rect, x : Int32, y : Int32, width : Int32, text : String, style : Style, align : Label::Align) : Nil
      # Truncate or pad text
      display = if text.size > width
                  text[0, width - 1] + "…"
                else
                  text
                end

      # Calculate position based on alignment
      text_x = case align
               when .left?   then x
               when .center? then x + (width - display.size) // 2
               when .right?  then x + width - display.size
               else               x
               end

      # Draw padding before
      (x...text_x).each do |px|
        buffer.set(px, y, ' ', style) if clip.contains?(px, y)
      end

      # Draw text
      display.each_char_with_index do |char, i|
        px = text_x + i
        buffer.set(px, y, char, style) if clip.contains?(px, y)
      end

      # Draw padding after
      ((text_x + display.size)...(x + width)).each do |px|
        buffer.set(px, y, ' ', style) if clip.contains?(px, y)
      end
    end

    private def ensure_cursor_visible(visible_height : Int32) : Nil
      return if visible_height <= 0

      if @cursor_row < @scroll_y
        @scroll_y = @cursor_row
      elsif @cursor_row >= @scroll_y + visible_height
        @scroll_y = @cursor_row - visible_height + 1
      end
    end

    def on_event(event : Event) : Bool
      return false if event.stopped?
      return false unless focused?

      case event
      when KeyEvent
        handled = handle_key(event)
        if handled
          event.stop!
          return true
        end
      when MouseEvent
        if event.button.left? && event.action.press?
          if @rect.contains?(event.x, event.y)
            handle_click(event.y)
            event.stop!
            return true
          end
        elsif event.button.wheel_up?
          move_cursor(-3)
          event.stop!
          return true
        elsif event.button.wheel_down?
          move_cursor(3)
          event.stop!
          return true
        end
      end

      false
    end

    private def handle_key(event : KeyEvent) : Bool
      case event.key
      when .up?
        move_cursor(-1)
        true
      when .down?
        move_cursor(1)
      when .page_up?
        move_cursor(-(@rect.height - (@show_header ? 1 : 0)))
        true
      when .page_down?
        move_cursor(@rect.height - (@show_header ? 1 : 0))
        true
      when .home?
        @cursor_row = 0
        @on_select.try &.call(@cursor_row, @rows[@cursor_row]) if @rows.any?
        mark_dirty!
        true
      when .end?
        @cursor_row = @rows.size - 1 if @rows.any?
        @on_select.try &.call(@cursor_row, @rows[@cursor_row]) if @rows.any?
        mark_dirty!
        true
      when .enter?
        if @rows.any? && @cursor_row < @rows.size
          @on_activate.try &.call(@cursor_row, @rows[@cursor_row])
        end
        true
      when .space?
        toggle_selection
        true
      else
        false
      end
    end

    private def handle_click(click_y : Int32) : Nil
      header_offset = @show_header ? 1 : 0
      row_y = click_y - @rect.y - header_offset
      return if row_y < 0

      new_cursor = @scroll_y + row_y
      if new_cursor < @rows.size
        @cursor_row = new_cursor
        @on_select.try &.call(@cursor_row, @rows[@cursor_row])
        mark_dirty!
      end
    end

    private def move_cursor(delta : Int32) : Bool
      return false if @rows.empty?

      old_cursor = @cursor_row
      @cursor_row = (@cursor_row + delta).clamp(0, @rows.size - 1)

      if @cursor_row != old_cursor
        @on_select.try &.call(@cursor_row, @rows[@cursor_row])
        mark_dirty!
      end
      true
    end
  end
end
