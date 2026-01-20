# CodeView - Scrollable code/text viewer with line numbers
#
# Inherits from View for scroll handling.
# Features:
# - Line numbers (optional)
# - Syntax-aware coloring (via line_style callback)
# - Left border indicator
# - Auto-scroll on append

module Tui
  class CodeView < View
    @lines : Array(String) = [] of String

    # Display options
    property show_line_numbers : Bool = true
    property line_number_width : Int32 = 4
    property show_border : Bool = true

    # Styling
    property line_number_color : Color = Color.palette(240)
    property border_color : Color = Color.palette(240)
    property text_color : Color = Color.palette(252)

    # Optional callback for custom line styling
    @line_style_callback : Proc(Int32, String, Style)?

    def initialize(id : String? = nil)
      super(id)
      @auto_scroll = true
    end

    # ─────────────────────────────────────────────────────────────
    # Content API (implements View contract)
    # ─────────────────────────────────────────────────────────────

    def content : String
      @lines.join("\n")
    end

    # View contract: set_content
    def set_content(text : String) : Nil
      @lines = text.lines
      if @auto_scroll
        scroll_to_bottom
      end
      mark_dirty!
    end

    # Alias for compatibility
    def content=(text : String) : Nil
      set_content(text)
    end

    def lines : Array(String)
      @lines
    end

    # View contract: clear_content
    def clear_content : Nil
      @lines.clear
      @scroll_offset = 0
      mark_dirty!
    end

    # Alias for compatibility
    def clear : Nil
      clear_content
    end

    # View contract: append_content
    def append_content(text : String) : Nil
      text.each_line do |line|
        @lines << line
      end
      if @auto_scroll
        scroll_to_bottom
      end
      mark_dirty!
    end

    # Alias for compatibility
    def append(text : String) : Nil
      append_content(text)
    end

    def append_line(line : String) : Nil
      @lines << line
      if @auto_scroll
        scroll_to_bottom
      end
      mark_dirty!
    end

    # Set callback for custom line styling
    def on_line_style(&block : Int32, String -> Style) : Nil
      @line_style_callback = block
    end

    # ─────────────────────────────────────────────────────────────
    # View implementation
    # ─────────────────────────────────────────────────────────────

    def line_count : Int32
      @lines.size
    end

    def render_line(buffer : Buffer, clip : Rect, y : Int32, line_index : Int32, width : Int32) : Nil
      x = @rect.x
      line = @lines[line_index]? || ""

      # Left border
      if @show_border
        border_style = Style.new(fg: @border_color, bg: @content_bg)
        buffer.set(x, y, '│', border_style) if clip.contains?(x, y)
        x += 1
      end

      # Line number
      if @show_line_numbers
        num_style = Style.new(fg: @line_number_color, bg: @content_bg)
        num_str = (line_index + 1).to_s.rjust(@line_number_width)
        num_str.each_char do |char|
          buffer.set(x, y, char, num_style) if clip.contains?(x, y)
          x += 1
        end
        # Separator
        buffer.set(x, y, '│', num_style) if clip.contains?(x, y)
        x += 1
      end

      # Content
      text_style = if callback = @line_style_callback
                     callback.call(line_index, line)
                   else
                     Style.new(fg: @text_color, bg: @content_bg)
                   end

      line.each_char do |char|
        break if x >= @rect.x + width
        buffer.set(x, y, char, text_style) if clip.contains?(x, y)
        x += Unicode.char_width(char)
      end
    end

    # ─────────────────────────────────────────────────────────────
    # Size calculation
    # ─────────────────────────────────────────────────────────────

    def prefix_width : Int32
      w = 0
      w += 1 if @show_border
      w += @line_number_width + 1 if @show_line_numbers
      w
    end
  end
end
