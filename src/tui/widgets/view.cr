# View - Base class for scrollable content widgets
#
# Provides common functionality:
# - Scroll state management (offset, auto-scroll)
# - Scrollbar rendering
# - Keyboard/mouse scroll handling
# - Line-based rendering framework
#
# Subclasses implement:
# - line_count : total number of lines
# - render_line : how to render a single line
#
# Optional overrides:
# - set_content(String) : set content from string
# - append_content(String) : append to content

module Tui
  abstract class View < Widget
    # Scroll state
    @scroll_offset : Int32 = 0
    property auto_scroll : Bool = false
    @pending_scroll_to_bottom : Bool = false  # Deferred scroll when rect not yet set

    # Scrollbar styling
    property show_scrollbar : Bool = true
    property scrollbar_width : Int32 = 1
    property scrollbar_track_char : Char = '│'
    property scrollbar_thumb_char : Char = '█'
    property scrollbar_track_color : Color = Color.palette(240)
    property scrollbar_thumb_color : Color = Color.white
    property scrollbar_focused_color : Color = Color.cyan

    # Content area background
    property content_bg : Color = Color.default

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    # ─────────────────────────────────────────────────────────────
    # Abstract methods - must be implemented by subclasses
    # ─────────────────────────────────────────────────────────────

    # Total number of lines in content
    abstract def line_count : Int32

    # Render a single line at given position
    # @param buffer - render buffer
    # @param clip - clipping rect
    # @param y - screen Y position
    # @param line_index - 0-based line index in content
    # @param width - available width (excluding scrollbar)
    abstract def render_line(buffer : Buffer, clip : Rect, y : Int32, line_index : Int32, width : Int32) : Nil

    # ─────────────────────────────────────────────────────────────
    # Content API - override in subclasses as needed
    # ─────────────────────────────────────────────────────────────

    # Set content from string (override in subclasses)
    def set_content(text : String) : Nil
      # Default: no-op, subclasses implement
    end

    # Append content (override in subclasses)
    def append_content(text : String) : Nil
      # Default: no-op, subclasses implement
    end

    # Clear content (override in subclasses)
    def clear_content : Nil
      # Default: no-op, subclasses implement
    end

    # ─────────────────────────────────────────────────────────────
    # Scroll API
    # ─────────────────────────────────────────────────────────────

    def scroll_offset : Int32
      @scroll_offset
    end

    def scroll_offset=(value : Int32)
      max = max_scroll_offset
      @scroll_offset = value.clamp(0, max)
      @auto_scroll = @scroll_offset >= max
    end

    def visible_lines : Int32
      @rect.height
    end

    def max_scroll_offset : Int32
      Math.max(0, line_count - visible_lines)
    end

    def scroll_up(lines : Int32 = 1) : Nil
      self.scroll_offset = @scroll_offset - lines
      @auto_scroll = false
      mark_dirty!
    end

    def scroll_down(lines : Int32 = 1) : Nil
      self.scroll_offset = @scroll_offset + lines
      mark_dirty!
    end

    def scroll_to_top : Nil
      @scroll_offset = 0
      @auto_scroll = false
      mark_dirty!
    end

    def scroll_to_bottom : Nil
      # If rect is not valid yet, defer the scroll until render
      if @rect.height <= 0
        @pending_scroll_to_bottom = true
      else
        @scroll_offset = max_scroll_offset
      end
      @auto_scroll = true
      mark_dirty!
    end

    def page_up : Nil
      scroll_up(visible_lines - 1)
    end

    def page_down : Nil
      scroll_down(visible_lines - 1)
    end

    # Ensure a specific line is visible
    def ensure_visible(line_index : Int32) : Nil
      if line_index < @scroll_offset
        @scroll_offset = line_index
        @auto_scroll = false
      elsif line_index >= @scroll_offset + visible_lines
        @scroll_offset = line_index - visible_lines + 1
        @auto_scroll = @scroll_offset >= max_scroll_offset
      end
      mark_dirty!
    end

    # ─────────────────────────────────────────────────────────────
    # Rendering
    # ─────────────────────────────────────────────────────────────

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Process deferred scroll_to_bottom now that rect is valid
      if @pending_scroll_to_bottom
        @pending_scroll_to_bottom = false
        @scroll_offset = max_scroll_offset
      end

      content_width = @rect.width
      content_width -= @scrollbar_width if @show_scrollbar && needs_scrollbar?

      # Clear background
      bg_style = Style.new(bg: @content_bg)
      @rect.height.times do |row|
        @rect.width.times do |col|
          buffer.set(@rect.x + col, @rect.y + row, ' ', bg_style) if clip.contains?(@rect.x + col, @rect.y + row)
        end
      end

      # Render visible lines
      visible_lines.times do |i|
        line_idx = @scroll_offset + i
        break if line_idx >= line_count

        y = @rect.y + i
        next unless y < clip.bottom

        render_line(buffer, clip, y, line_idx, content_width)
      end

      # Render scrollbar
      if @show_scrollbar && needs_scrollbar?
        render_scrollbar(buffer, clip)
      end
    end

    def needs_scrollbar? : Bool
      line_count > visible_lines
    end

    private def render_scrollbar(buffer : Buffer, clip : Rect) : Nil
      return if @rect.width < 2

      scrollbar_x = @rect.right - @scrollbar_width
      total = line_count
      visible = visible_lines
      return if total <= visible

      # Calculate thumb position and size
      thumb_height = Math.max(1, (visible * @rect.height / total).to_i)
      max_offset = total - visible
      thumb_pos = max_offset > 0 ? (@scroll_offset * (@rect.height - thumb_height) / max_offset).to_i : 0

      track_style = Style.new(fg: @scrollbar_track_color)
      thumb_style = Style.new(fg: focused? ? @scrollbar_focused_color : @scrollbar_thumb_color)

      @rect.height.times do |i|
        y = @rect.y + i
        next unless clip.contains?(scrollbar_x, y)

        if i >= thumb_pos && i < thumb_pos + thumb_height
          buffer.set(scrollbar_x, y, @scrollbar_thumb_char, thumb_style)
        else
          buffer.set(scrollbar_x, y, @scrollbar_track_char, track_style)
        end
      end
    end

    # ─────────────────────────────────────────────────────────────
    # Event handling
    # ─────────────────────────────────────────────────────────────

    def on_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when MouseEvent
        # Wheel scrolling works without focus
        if event.in_rect?(@rect)
          if event.button.wheel_up?
            scroll_up(3)
            event.stop!
            return true
          elsif event.button.wheel_down?
            scroll_down(3)
            event.stop!
            return true
          end
        end

        # Click to focus
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          self.focused = true
          event.stop!
          return true
        end

      when KeyEvent
        return false unless focused?

        case
        when event.matches?("up"), event.matches?("k")
          scroll_up
          event.stop!
          return true
        when event.matches?("down"), event.matches?("j")
          scroll_down
          event.stop!
          return true
        when event.matches?("pageup"), event.matches?("ctrl+u")
          page_up
          event.stop!
          return true
        when event.matches?("pagedown"), event.matches?("ctrl+d")
          page_down
          event.stop!
          return true
        when event.matches?("home"), event.matches?("g")
          scroll_to_top
          event.stop!
          return true
        when event.matches?("end"), event.matches?("G")
          scroll_to_bottom
          event.stop!
          return true
        end
      end

      false
    end
  end
end
