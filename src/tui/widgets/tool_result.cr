# ToolResult - Collapsible tool output with pluggable View
#
# Header: ● ▼ tool_name `key_arg` 1.2s [42]
# Content: Any View subclass (CodeView, DiffView, etc.)

require "json"

module Tui
  class ToolResult < Widget
    enum Status
      Running
      Success
      Error
    end

    property tool_name : String
    property key_arg : String?
    property arguments : Hash(String, JSON::Any)?  # All arguments for detailed display
    property status : Status = Status::Running
    property duration_ms : Int64 = 0
    property expanded : Bool = false
    property max_visible_lines : Int32 = 10

    # Content view - any View subclass
    @content_view : View?

    # Styling
    property running_color : Color = Color.white
    property success_color : Color = Color.green
    property error_color : Color = Color.red
    property header_fg : Color = Color.white
    property header_bg : Color? = nil
    property chevron_color : Color = Color.cyan

    def initialize(@tool_name : String, @key_arg : String? = nil, id : String? = nil)
      super(id)
      @focusable = true
    end

    # Format arguments for display based on tool type
    def format_args_display : String?
      args = @arguments
      return @key_arg unless args

      case @tool_name
      when "read_file", "Read"
        path = args["file_path"]?.try(&.as_s?) || @key_arg
        return nil unless path
        parts = [shorten_path(path)]
        if offset = args["offset"]?.try(&.as_i?)
          parts << "L#{offset}"
        end
        if limit = args["limit"]?.try(&.as_i?)
          parts << "+#{limit}"
        end
        parts.join(" ")
      when "grep", "Grep"
        pattern = args["pattern"]?.try(&.as_s?)
        path = args["path"]?.try(&.as_s?)
        parts = [] of String
        parts << "`#{shorten_pattern(pattern)}`" if pattern
        parts << "in #{shorten_path(path)}" if path && path != "."
        parts.empty? ? @key_arg : parts.join(" ")
      when "glob", "Glob"
        pattern = args["pattern"]?.try(&.as_s?)
        path = args["path"]?.try(&.as_s?)
        parts = [] of String
        parts << "`#{pattern}`" if pattern
        parts << "in #{shorten_path(path)}" if path && path != "."
        parts.empty? ? @key_arg : parts.join(" ")
      when "shell", "Bash"
        cmd = args["command"]?.try(&.as_s?) || @key_arg
        cmd ? "`#{shorten_command(cmd)}`" : @key_arg
      when "edit_file", "Edit"
        path = args["file_path"]?.try(&.as_s?) || @key_arg
        path ? shorten_path(path) : @key_arg
      when "write_file", "Write"
        path = args["file_path"]?.try(&.as_s?) || @key_arg
        path ? shorten_path(path) : @key_arg
      else
        @key_arg
      end
    end

    private def shorten_path(path : String?) : String
      return "" unless path
      # Show last 2 components if path is long
      if path.size > 40
        parts = path.split("/")
        if parts.size > 2
          ".../" + parts[-2..-1].join("/")
        else
          "...#{path[-37..]}"
        end
      else
        path
      end
    end

    private def shorten_pattern(pattern : String?) : String
      return "" unless pattern
      pattern.size > 25 ? "#{pattern[0, 22]}..." : pattern
    end

    private def shorten_command(cmd : String?) : String
      return "" unless cmd
      # Take first line, shorten if needed
      first_line = cmd.lines.first? || cmd
      first_line.size > 40 ? "#{first_line[0, 37]}..." : first_line
    end

    # ─────────────────────────────────────────────────────────────
    # Content View API
    # ─────────────────────────────────────────────────────────────

    # Set the content view (any View subclass)
    def content_view=(view : View) : Nil
      @content_view = view
      view.parent = self  # For mark_dirty! propagation
      view.auto_scroll = true
      view.content_bg = Color.palette(235)  # Dark background
      mark_dirty!
    end

    def content_view : View?
      @content_view
    end

    # Convenience: set content as string (creates CodeView if needed)
    def result=(text : String) : Nil
      ensure_code_view
      @content_view.try(&.set_content(text))
    end

    # Convenience: append line
    def append_line(line : String) : Nil
      ensure_code_view
      @content_view.try(&.append_content(line + "\n"))
    end

    # Ensure we have a CodeView for text content
    private def ensure_code_view : Nil
      return if @content_view
      view = CodeView.new("#{@id}-content")
      view.show_line_numbers = true
      view.show_border = true
      self.content_view = view
    end

    # ─────────────────────────────────────────────────────────────
    # Status API
    # ─────────────────────────────────────────────────────────────

    def complete(success : Bool, duration_ms : Int64, result : String? = nil) : Nil
      @status = success ? Status::Success : Status::Error
      @duration_ms = duration_ms
      if result && !result.empty?
        self.result = result
      end
      mark_dirty!
    end

    def toggle : Nil
      @expanded = !@expanded
      mark_dirty!
    end

    def expand : Nil
      @expanded = true
      mark_dirty!
    end

    def collapse : Nil
      @expanded = false
      mark_dirty!
    end

    # ─────────────────────────────────────────────────────────────
    # Size calculation
    # ─────────────────────────────────────────────────────────────

    def line_count : Int32
      @content_view.try(&.line_count) || 0
    end

    def visible_content_lines : Int32
      Math.min(@max_visible_lines, @rect.height - 1)
    end

    def preferred_height : Int32
      if @expanded && line_count > 0
        1 + Math.min(line_count, @max_visible_lines)
      else
        1
      end
    end

    def min_size : {Int32, Int32}
      {30, 1}
    end

    # ─────────────────────────────────────────────────────────────
    # Rendering
    # ─────────────────────────────────────────────────────────────

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Draw header
      draw_header(buffer, clip)

      # Draw content view if expanded
      if @expanded && (view = @content_view) && line_count > 0
        content_height = visible_content_lines
        content_rect = Rect.new(@rect.x, @rect.y + 1, @rect.width, content_height)
        view.rect = content_rect
        view.render(buffer, clip)
      end
    end

    private def draw_header(buffer : Buffer, clip : Rect) : Nil
      y = @rect.y
      x = @rect.x

      # Clear header line
      bg = @header_bg || Color.default
      clear_style = Style.new(fg: @header_fg, bg: bg)
      @rect.width.times do |i|
        buffer.set(@rect.x + i, y, ' ', clear_style) if clip.contains?(@rect.x + i, y)
      end

      # Status dot first
      dot_char, dot_color = case @status
                           when .running? then {'○', @running_color}
                           when .success? then {'●', @success_color}
                           when .error?   then {'●', @error_color}
                           else                {'○', @running_color}
                           end
      dot_style = Style.new(fg: dot_color, bg: bg)
      buffer.set(x, y, dot_char, dot_style) if clip.contains?(x, y)
      x += 2

      # Chevron (only if has content)
      if line_count > 0
        chevron = @expanded ? '▼' : '▶'
        chevron_style = Style.new(fg: @chevron_color, bg: bg)
        buffer.set(x, y, chevron, chevron_style) if clip.contains?(x, y)
        x += 2
      end

      # Tool name
      name_style = Style.new(fg: @header_fg, bg: bg, attrs: Attributes::Bold)
      @tool_name.each_char do |char|
        break if x >= @rect.right - 20
        buffer.set(x, y, char, name_style) if clip.contains?(x, y)
        x += 1
      end

      # Arguments display (formatted per tool type)
      if display = format_args_display
        x += 1 if x < @rect.right - 20
        # Don't add extra backticks if display already has them
        has_backticks = display.starts_with?('`')
        unless has_backticks
          buffer.set(x, y, '`', clear_style) if clip.contains?(x, y) && x < @rect.right - 15
          x += 1
        end
        display.each_char do |char|
          break if x >= @rect.right - 15
          buffer.set(x, y, char, clear_style) if clip.contains?(x, y)
          x += 1
        end
        unless has_backticks
          buffer.set(x, y, '`', clear_style) if clip.contains?(x, y) && x < @rect.right - 15
          x += 1
        end
      end

      # Duration (if completed)
      if @status != Status::Running
        x += 1 if x < @rect.right - 10
        duration_str = @duration_ms < 1000 ? "#{@duration_ms}ms" : "#{(@duration_ms / 1000.0).round(1)}s"
        dim_style = Style.new(fg: Color.palette(245), bg: bg)
        duration_str.each_char do |char|
          break if x >= @rect.right - 5
          buffer.set(x, y, char, dim_style) if clip.contains?(x, y)
          x += 1
        end
      end

      # Line count indicator (if has content and collapsed)
      if !@expanded && line_count > 0
        count_str = " [#{line_count}]"
        dim_style = Style.new(fg: Color.palette(240), bg: bg)
        count_str.each_char do |char|
          break if x >= @rect.right
          buffer.set(x, y, char, dim_style) if clip.contains?(x, y)
          x += 1
        end
      end
    end

    # ─────────────────────────────────────────────────────────────
    # Event handling
    # ─────────────────────────────────────────────────────────────

    def on_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when KeyEvent
        return false unless focused?

        case
        when event.matches?("enter"), event.matches?("space")
          toggle
          event.stop!
          return true
        when event.matches?("left")
          if @expanded
            collapse
            event.stop!
            return true
          end
        when event.matches?("right")
          if !@expanded
            expand
            event.stop!
            return true
          end
        end

        # Delegate scroll to content view when expanded
        if @expanded && (view = @content_view)
          if view.on_event(event)
            return true
          end
        end

      when MouseEvent
        # Click on header toggles
        if event.action.press? && event.button.left?
          if event.y == @rect.y && event.in_rect?(@rect)
            toggle
            event.stop!
            return true
          end
        end

        # Delegate mouse events (including wheel) to content view when expanded
        if @expanded && (view = @content_view) && line_count > 0
          content_rect = Rect.new(@rect.x, @rect.y + 1, @rect.width, visible_content_lines)
          if event.in_rect?(content_rect)
            # Set view's rect for event handling
            view.rect = content_rect
            if view.on_event(event)
              return true
            end
          end
        end
      end

      false
    end
  end
end
