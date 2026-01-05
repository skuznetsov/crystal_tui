# Simple text file viewer
module Tui
  class TextViewer < Widget
    @lines : Array(String) = [] of String
    @scroll : Int32 = 0
    @path : Path?

    property title : String = ""
    property border_style : Panel::BorderStyle = Panel::BorderStyle::Light
    property border_color : Color = Color.white
    property title_color : Color = Color.yellow
    property text_color : Color = Color.white
    property line_number_color : Color = Color.cyan
    property show_line_numbers : Bool = true

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
      style = Style.new(fg: @border_color)
      title_style = Style.new(fg: @title_color, attrs: Attributes::Bold)
      text_style = Style.new(fg: @text_color)
      line_num_style = Style.new(fg: @line_number_color)

      # Clear entire area first (important for overlay)
      clear_background(buffer, clip, text_style)

      # Draw border
      draw_border(buffer, clip, border, style)

      # Draw title
      draw_title(buffer, clip, border, style, title_style)

      # Draw content
      draw_content(buffer, clip, text_style, line_num_style)

      # Draw scroll indicator
      draw_scroll_indicator(buffer, clip, style)
    end

    private def clear_background(buffer : Buffer, clip : Rect, style : Style) : Nil
      @rect.height.times do |y|
        @rect.width.times do |x|
          draw_char(buffer, clip, @rect.x + x, @rect.y + y, ' ', style)
        end
      end
    end

    private def draw_border(buffer : Buffer, clip : Rect, border, style : Style) : Nil
      # Corners
      draw_char(buffer, clip, @rect.x, @rect.y, border[:tl], style)
      draw_char(buffer, clip, @rect.right - 1, @rect.y, border[:tr], style)
      draw_char(buffer, clip, @rect.x, @rect.bottom - 1, border[:bl], style)
      draw_char(buffer, clip, @rect.right - 1, @rect.bottom - 1, border[:br], style)

      # Horizontal lines
      (1...(@rect.width - 1)).each do |i|
        draw_char(buffer, clip, @rect.x + i, @rect.bottom - 1, border[:h], style)
      end

      # Vertical lines
      (1...(@rect.height - 1)).each do |i|
        draw_char(buffer, clip, @rect.x, @rect.y + i, border[:v], style)
        draw_char(buffer, clip, @rect.right - 1, @rect.y + i, border[:v], style)
      end
    end

    private def draw_title(buffer : Buffer, clip : Rect, border, style : Style, title_style : Style) : Nil
      return if @title.empty?

      max_len = @rect.width - 6
      display_title = @title.size > max_len ? "…" + @title[-(max_len - 1)..] : @title
      full_title = "#{border[:tl_title]} #{display_title} #{border[:tr_title]}"

      # Center title
      title_start = (@rect.width - full_title.size) // 2
      x = @rect.x + title_start

      full_title.each_char_with_index do |char, i|
        char_style = (i == 0 || i == full_title.size - 1) ? style : title_style
        draw_char(buffer, clip, x + i, @rect.y, char, char_style)
      end

      # Fill rest of top border
      (1...title_start).each do |i|
        draw_char(buffer, clip, @rect.x + i, @rect.y, border[:h], style)
      end
      ((title_start + full_title.size)...(@rect.width - 1)).each do |i|
        draw_char(buffer, clip, @rect.x + i, @rect.y, border[:h], style)
      end
    end

    private def draw_content(buffer : Buffer, clip : Rect, text_style : Style, line_num_style : Style) : Nil
      inner = inner_rect
      return if inner.height <= 0

      line_num_width = @show_line_numbers ? (@lines.size.to_s.size + 1) : 0
      text_width = inner.width - line_num_width

      visible_lines = inner.height
      visible_lines.times do |i|
        line_idx = @scroll + i
        break if line_idx >= @lines.size

        y = inner.y + i
        x = inner.x

        # Draw line number
        if @show_line_numbers
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

    private def draw_scroll_indicator(buffer : Buffer, clip : Rect, style : Style) : Nil
      return if @lines.size <= inner_rect.height

      # Simple percentage indicator
      percent = (@scroll * 100) // (@lines.size - inner_rect.height).clamp(1, Int32::MAX)
      indicator = " #{percent}% "

      x = @rect.right - indicator.size - 1
      indicator.each_char_with_index do |char, i|
        draw_char(buffer, clip, x + i, @rect.bottom - 1, char, style)
      end
    end

    private def inner_rect : Rect
      Rect.new(
        @rect.x + 1,
        @rect.y + 1,
        Math.max(0, @rect.width - 2),
        Math.max(0, @rect.height - 2)
      )
    end

    private def draw_char(buffer : Buffer, clip : Rect, x : Int32, y : Int32, char : Char, style : Style) : Nil
      buffer.set(x, y, char, style) if clip.contains?(x, y)
    end

    def handle_event(event : Event) : Bool
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
      case event.key
      when .up?
        scroll_by(-1)
        true
      when .down?
        scroll_by(1)
        true
      when .page_up?
        scroll_by(-(inner_rect.height))
        true
      when .page_down?
        scroll_by(inner_rect.height)
        true
      when .home?
        @scroll = 0
        mark_dirty!
        true
      when .end?
        @scroll = (@lines.size - inner_rect.height).clamp(0, Int32::MAX)
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
      max_scroll = (@lines.size - inner_rect.height).clamp(0, Int32::MAX)
      @scroll = (@scroll + delta).clamp(0, max_scroll)
      mark_dirty!
    end
  end
end
