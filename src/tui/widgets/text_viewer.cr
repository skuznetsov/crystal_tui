# Simple text file viewer
module Tui
  class TextViewer < Widget
    enum LineNumberPosition
      Inside   # Line numbers inside the border (default)
      Outside  # Line numbers to the left of the border
    end

    @lines : Array(String) = [] of String
    @scroll : Int32 = 0
    @path : Path?

    property title : String = ""
    property border_style : Panel::BorderStyle = Panel::BorderStyle::Light
    property border_color : Color = Color.cyan
    property title_color : Color = Color.cyan
    property bg_color : Color = Color.blue
    property text_color : Color = Color.cyan
    property line_number_color : Color = Color.yellow
    property show_line_numbers : Bool = true
    property line_number_position : LineNumberPosition = LineNumberPosition::Outside

    # Callback when viewer should close
    @on_close : Proc(Nil)?

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    def on_close(&block : -> Nil) : Nil
      @on_close = block
    end

    def load_file(path : Path) : Bool
      @path = path
      @title = path.basename
      @scroll = 0

      begin
        content = File.read(path.to_s)
        @lines = content.lines
        mark_dirty!
        true
      rescue ex
        @lines = ["Error loading file:", ex.message || "Unknown error"]
        mark_dirty!
        false
      end
    end

    def load_text(text : String, title : String = "Text") : Nil
      @title = title
      @path = nil
      @scroll = 0
      @lines = text.lines
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      border = Panel::BORDERS[@border_style]
      style = Style.new(fg: @border_color, bg: @bg_color)
      title_style = Style.new(fg: @title_color, bg: @bg_color, attrs: Attributes::Bold)
      text_style = Style.new(fg: @text_color, bg: @bg_color)
      line_num_style = Style.new(fg: @line_number_color, bg: @bg_color)

      # Calculate line number width for outside positioning
      outside_ln_width = if @show_line_numbers && @line_number_position.outside?
                           @lines.size.to_s.size + 1  # +1 for space after
                         else
                           0
                         end

      # Border rect (shifted right if line numbers outside)
      border_rect = Rect.new(
        @rect.x + outside_ln_width,
        @rect.y,
        @rect.width - outside_ln_width,
        @rect.height
      )

      # Clear entire area first (important for overlay)
      clear_background(buffer, clip, Style.new(bg: @bg_color))

      # Draw line numbers outside border
      if @show_line_numbers && @line_number_position.outside?
        draw_line_numbers_outside(buffer, clip, line_num_style, border_rect)
      end

      # Draw border
      draw_border(buffer, clip, border, style, border_rect)

      # Draw title
      draw_title(buffer, clip, border, style, title_style, border_rect)

      # Draw content
      draw_content(buffer, clip, text_style, line_num_style, border_rect)

      # Draw scroll indicator
      draw_scroll_indicator(buffer, clip, style, border_rect)
    end

    private def clear_background(buffer : Buffer, clip : Rect, style : Style) : Nil
      @rect.height.times do |y|
        @rect.width.times do |x|
          draw_char(buffer, clip, @rect.x + x, @rect.y + y, ' ', style)
        end
      end
    end

    private def draw_line_numbers_outside(buffer : Buffer, clip : Rect, style : Style, border_rect : Rect) : Nil
      inner = inner_rect(border_rect)
      return if inner.height <= 0

      line_num_width = @lines.size.to_s.size

      visible_lines = inner.height
      visible_lines.times do |i|
        line_idx = @scroll + i
        break if line_idx >= @lines.size

        y = inner.y + i
        x = @rect.x  # Start from actual rect, not border_rect

        num_str = (line_idx + 1).to_s.rjust(line_num_width)
        num_str.each_char do |char|
          draw_char(buffer, clip, x, y, char, style)
          x += 1
        end
        # Space between numbers and border
        draw_char(buffer, clip, x, y, ' ', style)
      end
    end

    private def draw_border(buffer : Buffer, clip : Rect, border, style : Style, border_rect : Rect) : Nil
      # Corners
      draw_char(buffer, clip, border_rect.x, border_rect.y, border[:tl], style)
      draw_char(buffer, clip, border_rect.right - 1, border_rect.y, border[:tr], style)
      draw_char(buffer, clip, border_rect.x, border_rect.bottom - 1, border[:bl], style)
      draw_char(buffer, clip, border_rect.right - 1, border_rect.bottom - 1, border[:br], style)

      # Horizontal lines
      (1...(border_rect.width - 1)).each do |i|
        draw_char(buffer, clip, border_rect.x + i, border_rect.bottom - 1, border[:h], style)
      end

      # Vertical lines
      (1...(border_rect.height - 1)).each do |i|
        draw_char(buffer, clip, border_rect.x, border_rect.y + i, border[:v], style)
        draw_char(buffer, clip, border_rect.right - 1, border_rect.y + i, border[:v], style)
      end
    end

    private def draw_title(buffer : Buffer, clip : Rect, border, style : Style, title_style : Style, border_rect : Rect) : Nil
      return if @title.empty?

      max_len = border_rect.width - 6
      display_title = @title.size > max_len ? "…" + @title[-(max_len - 1)..] : @title
      full_title = "#{border[:tl_title]} #{display_title} #{border[:tr_title]}"

      # Center title
      title_start = (border_rect.width - full_title.size) // 2
      x = border_rect.x + title_start

      full_title.each_char_with_index do |char, i|
        char_style = (i == 0 || i == full_title.size - 1) ? style : title_style
        draw_char(buffer, clip, x + i, border_rect.y, char, char_style)
      end

      # Fill rest of top border
      (1...title_start).each do |i|
        draw_char(buffer, clip, border_rect.x + i, border_rect.y, border[:h], style)
      end
      ((title_start + full_title.size)...(border_rect.width - 1)).each do |i|
        draw_char(buffer, clip, border_rect.x + i, border_rect.y, border[:h], style)
      end
    end

    private def draw_content(buffer : Buffer, clip : Rect, text_style : Style, line_num_style : Style, border_rect : Rect) : Nil
      inner = inner_rect(border_rect)
      return if inner.height <= 0

      # Only use inside line numbers if position is Inside
      inside_ln = @show_line_numbers && @line_number_position.inside?
      line_num_width = inside_ln ? (@lines.size.to_s.size + 1) : 0
      text_width = inner.width - line_num_width

      visible_lines = inner.height
      visible_lines.times do |i|
        line_idx = @scroll + i
        break if line_idx >= @lines.size

        y = inner.y + i
        x = inner.x

        # Draw line number (inside only)
        if inside_ln
          num_str = (line_idx + 1).to_s.rjust(line_num_width - 1)
          num_str.each_char do |char|
            draw_char(buffer, clip, x, y, char, line_num_style)
            x += 1
          end
          draw_char(buffer, clip, x, y, ' ', text_style)
          x += 1
        end

        # Draw line content
        line = @lines[line_idx]
        chars_drawn = 0
        line.each_char do |char|
          break if chars_drawn >= text_width
          if char == '\t'
            # Expand tabs
            spaces = 4 - (chars_drawn % 4)
            spaces.times do
              break if chars_drawn >= text_width
              draw_char(buffer, clip, x, y, ' ', text_style)
              x += 1
              chars_drawn += 1
            end
          elsif char.printable?
            draw_char(buffer, clip, x, y, char, text_style)
            x += 1
            chars_drawn += 1
          end
        end

        # Clear rest of line
        while x < inner.right
          draw_char(buffer, clip, x, y, ' ', text_style)
          x += 1
        end
      end

      # Clear empty lines
      ((visible_lines.clamp(0, @lines.size - @scroll))...visible_lines).each do |i|
        y = inner.y + i
        inner.width.times do |j|
          draw_char(buffer, clip, inner.x + j, y, ' ', text_style)
        end
      end
    end

    private def draw_scroll_indicator(buffer : Buffer, clip : Rect, style : Style, border_rect : Rect) : Nil
      inner = inner_rect(border_rect)
      return if @lines.size <= inner.height

      # Simple percentage indicator
      percent = (@scroll * 100) // (@lines.size - inner.height).clamp(1, Int32::MAX)
      indicator = " #{percent}% "

      x = border_rect.right - indicator.size - 1
      indicator.each_char_with_index do |char, i|
        draw_char(buffer, clip, x + i, border_rect.bottom - 1, char, style)
      end
    end

    private def inner_rect(border_rect : Rect) : Rect
      Rect.new(
        border_rect.x + 1,
        border_rect.y + 1,
        Math.max(0, border_rect.width - 2),
        Math.max(0, border_rect.height - 2)
      )
    end

    # Convenience: get inner rect using effective border rect
    private def effective_inner_rect : Rect
      inner_rect(effective_border_rect)
    end

    # Border rect accounting for outside line numbers
    private def effective_border_rect : Rect
      outside_ln_width = if @show_line_numbers && @line_number_position.outside?
                           @lines.size.to_s.size + 1
                         else
                           0
                         end
      Rect.new(
        @rect.x + outside_ln_width,
        @rect.y,
        @rect.width - outside_ln_width,
        @rect.height
      )
    end

    private def draw_char(buffer : Buffer, clip : Rect, x : Int32, y : Int32, char : Char, style : Style) : Nil
      buffer.set(x, y, char, style) if clip.contains?(x, y)
    end

    def on_event(event : Event) : Bool
      return false if event.stopped?
      return false unless focused?

      case event
      when KeyEvent
        if handle_key(event)
          event.stop!
          return true
        end
      end

      false
    end

    private def handle_key(event : KeyEvent) : Bool
      inner = effective_inner_rect
      case event.key
      when .up?
        scroll_by(-1)
        true
      when .down?
        scroll_by(1)
        true
      when .page_up?
        scroll_by(-inner.height)
        true
      when .page_down?
        scroll_by(inner.height)
        true
      when .home?
        @scroll = 0
        mark_dirty!
        true
      when .end?
        @scroll = (@lines.size - inner.height).clamp(0, Int32::MAX)
        mark_dirty!
        true
      when .escape?, .f10?
        @on_close.try &.call
        true
      else
        if event.char == 'q'
          @on_close.try &.call
          true
        else
          false
        end
      end
    end

    private def scroll_by(delta : Int32) : Nil
      max_scroll = (@lines.size - effective_inner_rect.height).clamp(0, Int32::MAX)
      @scroll = (@scroll + delta).clamp(0, max_scroll)
      mark_dirty!
    end
  end
end
