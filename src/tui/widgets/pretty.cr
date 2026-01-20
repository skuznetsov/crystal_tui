# Pretty - Pretty-print data structures widget
module Tui
  class Pretty < Widget
    property data : String = ""
    property scroll_offset : Int32 = 0
    property indent_size : Int32 = 2

    # Styling
    property key_style : Style = Style.new(fg: Color.cyan)
    property string_style : Style = Style.new(fg: Color.green)
    property number_style : Style = Style.new(fg: Color.yellow)
    property bool_style : Style = Style.new(fg: Color.magenta)
    property null_style : Style = Style.new(fg: Color.palette(240))
    property bracket_style : Style = Style.new(fg: Color.white)
    property default_style : Style = Style.default

    @lines : Array(String) = [] of String
    @line_styles : Array(Array({Int32, Int32, Style})) = [] of Array({Int32, Int32, Style})

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    # Set data to display (auto-formats)
    def object=(obj) : Nil
      @data = format_object(obj)
      parse_for_highlighting
      mark_dirty!
    end

    # Set raw string data
    def data=(str : String) : Nil
      @data = str
      parse_for_highlighting
      mark_dirty!
    end

    # Format any object for display
    private def format_object(obj, depth : Int32 = 0) : String
      indent = " " * (depth * @indent_size)
      next_indent = " " * ((depth + 1) * @indent_size)

      case obj
      when Nil
        "null"
      when Bool
        obj.to_s
      when Number
        obj.to_s
      when String
        "\"#{escape_string(obj)}\""
      when Symbol
        ":#{obj}"
      when Array
        if obj.empty?
          "[]"
        else
          items = obj.map { |item| "#{next_indent}#{format_object(item, depth + 1)}" }
          "[\n#{items.join(",\n")}\n#{indent}]"
        end
      when Hash
        if obj.empty?
          "{}"
        else
          items = obj.map { |k, v| "#{next_indent}#{format_object(k, depth + 1)}: #{format_object(v, depth + 1)}" }
          "{\n#{items.join(",\n")}\n#{indent}}"
        end
      when NamedTuple
        if obj.empty?
          "{}"
        else
          items = obj.to_h.map { |k, v| "#{next_indent}#{k}: #{format_object(v, depth + 1)}" }
          "{\n#{items.join(",\n")}\n#{indent}}"
        end
      when Tuple
        if obj.empty?
          "()"
        else
          items = obj.to_a.map { |item| format_object(item, depth + 1) }
          "(#{items.join(", ")})"
        end
      else
        obj.inspect
      end
    end

    private def escape_string(str : String) : String
      str.gsub("\\", "\\\\")
         .gsub("\"", "\\\"")
         .gsub("\n", "\\n")
         .gsub("\t", "\\t")
         .gsub("\r", "\\r")
    end

    private def parse_for_highlighting : Nil
      @lines = @data.split('\n')
      @line_styles = @lines.map { |line| parse_line_styles(line) }
    end

    private def parse_line_styles(line : String) : Array({Int32, Int32, Style})
      styles = [] of {Int32, Int32, Style}
      pos = 0

      while pos < line.size
        char = line[pos]

        case char
        when '"'
          # String - find closing quote
          end_pos = pos + 1
          while end_pos < line.size
            if line[end_pos] == '"' && (end_pos == 0 || line[end_pos - 1] != '\\')
              break
            end
            end_pos += 1
          end
          styles << {pos, end_pos + 1, @string_style}
          pos = end_pos + 1
        when '0'..'9', '-'
          # Number
          end_pos = pos + 1
          while end_pos < line.size && (line[end_pos].ascii_number? || line[end_pos] == '.' || line[end_pos] == 'e' || line[end_pos] == 'E' || line[end_pos] == '+' || line[end_pos] == '-')
            end_pos += 1
          end
          styles << {pos, end_pos, @number_style}
          pos = end_pos
        when 't', 'f'
          # Possible boolean
          rest = line[pos..]
          if rest.starts_with?("true")
            styles << {pos, pos + 4, @bool_style}
            pos += 4
          elsif rest.starts_with?("false")
            styles << {pos, pos + 5, @bool_style}
            pos += 5
          else
            pos += 1
          end
        when 'n'
          # Possible null
          if line[pos..].starts_with?("null")
            styles << {pos, pos + 4, @null_style}
            pos += 4
          else
            pos += 1
          end
        when '[', ']', '{', '}', '(', ')', ','
          styles << {pos, pos + 1, @bracket_style}
          pos += 1
        when ':'
          # Key before this colon
          styles << {pos, pos + 1, @bracket_style}
          pos += 1
        else
          pos += 1
        end
      end

      styles
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      visible_lines = @rect.height
      max_offset = Math.max(0, @lines.size - visible_lines)
      @scroll_offset = @scroll_offset.clamp(0, max_offset)

      visible_lines.times do |i|
        line_idx = @scroll_offset + i
        break if line_idx >= @lines.size

        y = @rect.y + i
        next unless y >= clip.y && y < clip.y + clip.height

        line = @lines[line_idx]
        styles = @line_styles[line_idx]

        # Clear line
        @rect.width.times do |col|
          x = @rect.x + col
          buffer.set(x, y, ' ', @default_style) if clip.contains?(x, y)
        end

        # Render with styles
        render_styled_line(buffer, clip, @rect.x, y, line, styles)
      end

      # Scrollbar
      if @lines.size > visible_lines
        draw_scrollbar(buffer, clip, visible_lines)
      end
    end

    private def render_styled_line(buffer : Buffer, clip : Rect, x : Int32, y : Int32, line : String, styles : Array({Int32, Int32, Style})) : Nil
      # Default: render everything in default style
      styled_chars = Array(Style?).new(line.size, nil)

      # Apply styles
      styles.each do |start_pos, end_pos, style|
        (start_pos...end_pos).each do |i|
          styled_chars[i] = style if i < styled_chars.size
        end
      end

      # Render
      line.each_char_with_index do |char, i|
        px = x + i
        break if px >= @rect.x + @rect.width
        next unless clip.contains?(px, y)

        style = styled_chars[i]? || @default_style
        buffer.set(px, y, char, style)
      end
    end

    private def draw_scrollbar(buffer : Buffer, clip : Rect, visible : Int32) : Nil
      return if @rect.width < 2

      scrollbar_x = @rect.x + @rect.width - 1
      total = @lines.size
      return if total <= visible

      thumb_height = Math.max(1, (visible * @rect.height / total).to_i)
      thumb_pos = (@scroll_offset * (@rect.height - thumb_height) / (total - visible)).to_i

      track_style = Style.new(fg: Color.palette(240))
      thumb_style = Style.new(fg: Color.white)

      @rect.height.times do |i|
        y = @rect.y + i
        next unless clip.contains?(scrollbar_x, y)

        if i >= thumb_pos && i < thumb_pos + thumb_height
          buffer.set(scrollbar_x, y, '█', thumb_style)
        else
          buffer.set(scrollbar_x, y, '│', track_style)
        end
      end
    end

    def on_event(event : Event) : Bool
      return false unless focused?
      return false if event.stopped?

      case event
      when KeyEvent
        visible = @rect.height
        max_offset = Math.max(0, @lines.size - visible)

        case
        when event.matches?("up"), event.matches?("k")
          @scroll_offset = Math.max(0, @scroll_offset - 1)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("down"), event.matches?("j")
          @scroll_offset = Math.min(max_offset, @scroll_offset + 1)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("pageup"), event.matches?("ctrl+u")
          @scroll_offset = Math.max(0, @scroll_offset - visible)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("pagedown"), event.matches?("ctrl+d")
          @scroll_offset = Math.min(max_offset, @scroll_offset + visible)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("home"), event.matches?("g")
          @scroll_offset = 0
          mark_dirty!
          event.stop!
          return true
        when event.matches?("end"), event.matches?("G")
          @scroll_offset = max_offset
          mark_dirty!
          event.stop!
          return true
        end
      when MouseEvent
        if event.action.press? && event.in_rect?(@rect)
          if event.button.wheel_up?
            @scroll_offset = Math.max(0, @scroll_offset - 3)
            mark_dirty!
            event.stop!
            return true
          elsif event.button.wheel_down?
            max_offset = Math.max(0, @lines.size - @rect.height)
            @scroll_offset = Math.min(max_offset, @scroll_offset + 3)
            mark_dirty!
            event.stop!
            return true
          end
        end
      end

      super
    end

    def min_size : {Int32, Int32}
      {20, 5}
    end
  end
end
