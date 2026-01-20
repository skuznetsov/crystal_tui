# ColorPicker - Color selection widget
module Tui
  class ColorPicker < Widget
    # Basic 16 colors
    BASIC_COLORS = [
      Color.black, Color.red, Color.green, Color.yellow,
      Color.blue, Color.magenta, Color.cyan, Color.white,
      Color.palette(8), Color.palette(9), Color.palette(10), Color.palette(11),
      Color.palette(12), Color.palette(13), Color.palette(14), Color.palette(15),
    ]

    # Color names for display
    COLOR_NAMES = [
      "Black", "Red", "Green", "Yellow",
      "Blue", "Magenta", "Cyan", "White",
      "Gray", "Lt Red", "Lt Green", "Lt Yellow",
      "Lt Blue", "Lt Magenta", "Lt Cyan", "Bright White",
    ]

    property selected_index : Int32 = 0
    property show_palette : Bool = true  # Show 256-color palette
    property columns : Int32 = 8

    # Styling
    property cursor_style : Style = Style.new(attrs: Attributes::Bold | Attributes::Reverse)

    @on_select : Proc(Color, Nil)?
    @palette_mode : Bool = false  # false = basic, true = 256 palette
    @palette_offset : Int32 = 0   # For scrolling 256 palette

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    # Callback when color is selected
    def on_select(&block : Color -> Nil) : Nil
      @on_select = block
    end

    # Get selected color
    def selected_color : Color
      if @palette_mode
        Color.palette(@palette_offset + @selected_index)
      else
        BASIC_COLORS[@selected_index]? || Color.white
      end
    end

    # Set by color (finds closest match)
    def selected_color=(color : Color) : Nil
      # Try to find in basic colors first
      BASIC_COLORS.each_with_index do |c, i|
        if c == color
          @palette_mode = false
          @selected_index = i
          mark_dirty!
          return
        end
      end
      # Otherwise switch to palette mode
      @palette_mode = true
      # For palette colors, try to extract index
      @selected_index = 0
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      if @palette_mode
        render_palette(buffer, clip)
      else
        render_basic(buffer, clip)
      end
    end

    private def render_basic(buffer : Buffer, clip : Rect) : Nil
      rows = (BASIC_COLORS.size + @columns - 1) // @columns
      cell_width = Math.max(2, @rect.width // @columns)

      BASIC_COLORS.each_with_index do |color, i|
        row = i // @columns
        col = i % @columns

        x = @rect.x + col * cell_width
        y = @rect.y + row

        next if y >= @rect.y + @rect.height
        next unless y >= clip.y && y < clip.y + clip.height

        # Draw color block
        is_selected = i == @selected_index && focused?
        style = Style.new(bg: color)
        char = is_selected ? '█' : ' '

        cell_width.times do |dx|
          px = x + dx
          break if px >= @rect.x + @rect.width
          buffer.set(px, y, char, style) if clip.contains?(px, y)
        end

        # Draw selection indicator
        if is_selected
          buffer.set(x, y, '[', @cursor_style) if clip.contains?(x, y)
          buffer.set(x + cell_width - 1, y, ']', @cursor_style) if clip.contains?(x + cell_width - 1, y)
        end
      end

      # Draw selected color info
      info_y = @rect.y + rows + 1
      if info_y < @rect.y + @rect.height && info_y >= clip.y && info_y < clip.y + clip.height
        color = selected_color
        name = COLOR_NAMES[@selected_index]? || "Color"
        info = "#{name}"

        x = @rect.x
        info.each_char do |char|
          break if x >= @rect.x + @rect.width
          buffer.set(x, info_y, char, Style.new(fg: color)) if clip.contains?(x, info_y)
          x += 1
        end
      end
    end

    private def render_palette(buffer : Buffer, clip : Rect) : Nil
      # 256-color palette in a grid
      palette_cols = Math.min(16, @rect.width // 2)
      palette_rows = @rect.height - 1

      visible_colors = palette_cols * palette_rows
      max_offset = Math.max(0, 256 - visible_colors)
      @palette_offset = @palette_offset.clamp(0, max_offset)

      palette_rows.times do |row|
        y = @rect.y + row
        next unless y >= clip.y && y < clip.y + clip.height

        palette_cols.times do |col|
          color_idx = @palette_offset + row * palette_cols + col
          break if color_idx >= 256

          x = @rect.x + col * 2

          is_selected = (color_idx - @palette_offset) == @selected_index && focused?
          color = Color.palette(color_idx)
          style = Style.new(bg: color)

          if is_selected
            buffer.set(x, y, '[', @cursor_style) if clip.contains?(x, y)
            buffer.set(x + 1, y, ']', @cursor_style) if clip.contains?(x + 1, y)
          else
            buffer.set(x, y, ' ', style) if clip.contains?(x, y)
            buffer.set(x + 1, y, ' ', style) if clip.contains?(x + 1, y)
          end
        end
      end

      # Color index display
      info_y = @rect.y + palette_rows
      if info_y < @rect.y + @rect.height && info_y >= clip.y && info_y < clip.y + clip.height
        color = selected_color
        info = "Color ##{@palette_offset + @selected_index}"

        x = @rect.x
        info.each_char do |char|
          break if x >= @rect.x + @rect.width
          buffer.set(x, info_y, char, Style.new(fg: color)) if clip.contains?(x, info_y)
          x += 1
        end
      end
    end

    def on_event(event : Event) : Bool
      return false unless focused?
      return false if event.stopped?

      case event
      when KeyEvent
        max_index = @palette_mode ? 255 - @palette_offset : BASIC_COLORS.size - 1
        cols = @palette_mode ? Math.min(16, @rect.width // 2) : @columns

        case
        when event.matches?("left"), event.matches?("h")
          @selected_index = Math.max(0, @selected_index - 1)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("right"), event.matches?("l")
          @selected_index = Math.min(max_index, @selected_index + 1)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("up"), event.matches?("k")
          @selected_index = Math.max(0, @selected_index - cols)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("down"), event.matches?("j")
          @selected_index = Math.min(max_index, @selected_index + cols)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("tab")
          # Toggle between basic and palette modes
          @palette_mode = !@palette_mode
          @selected_index = 0
          @palette_offset = 0
          mark_dirty!
          event.stop!
          return true
        when event.matches?("enter"), event.matches?("space")
          @on_select.try &.call(selected_color)
          event.stop!
          return true
        when event.matches?("home")
          @selected_index = 0
          @palette_offset = 0
          mark_dirty!
          event.stop!
          return true
        when event.matches?("end")
          @selected_index = max_index
          mark_dirty!
          event.stop!
          return true
        end

      when MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          # Calculate clicked color
          if @palette_mode
            cols = Math.min(16, @rect.width // 2)
            col = (event.x - @rect.x) // 2
            row = event.y - @rect.y
            idx = row * cols + col
            if idx >= 0 && idx < 256 - @palette_offset
              @selected_index = idx
              @on_select.try &.call(selected_color)
              mark_dirty!
            end
          else
            cell_width = Math.max(2, @rect.width // @columns)
            col = (event.x - @rect.x) // cell_width
            row = event.y - @rect.y
            idx = row * @columns + col
            if idx >= 0 && idx < BASIC_COLORS.size
              @selected_index = idx
              @on_select.try &.call(selected_color)
              mark_dirty!
            end
          end
          focus
          event.stop!
          return true
        end
      end

      super
    end

    def min_size : {Int32, Int32}
      if @palette_mode
        {32, 5}  # 16 colors * 2 width, 4 rows + info
      else
        {@columns * 2, 3}  # columns * 2 width, 2 rows + info
      end
    end
  end
end
