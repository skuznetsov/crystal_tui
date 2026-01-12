# ScrollBar - Reusable scrollbar widget
#
# Can be used standalone or composed into other widgets.
# Supports vertical and horizontal orientations.
# Handles mouse click, drag, and wheel events.
# Can render as overlay (on top of content) or inline.

module Tui
  class ScrollBar < Widget
    enum Orientation
      Vertical
      Horizontal
    end

    property orientation : Orientation = Orientation::Vertical
    property total : Int32 = 0        # Total items/lines
    property viewport : Int32 = 0     # Visible items/lines (viewport size)
    property offset : Int32 = 0       # Current scroll offset

    # Colors
    property track_color : Color = Color.palette(240)
    property thumb_color : Color = Color.white
    property thumb_active_color : Color = Color.cyan
    property arrow_color : Color = Color.cyan

    # Characters
    property track_char_v : Char = '│'
    property track_char_h : Char = '─'
    property thumb_char : Char = '█'

    # Settings
    property? show_arrows : Bool = true        # Show navigation arrows
    property? use_overlay : Bool = false       # Render via overlay system (on top of content)
    property click_tolerance : Int32 = 1       # Tolerance for scrollbar click detection

    # Drag state
    @dragging : Bool = false
    @drag_start_pos : Int32 = 0
    @drag_start_offset : Int32 = 0

    # Callbacks
    @on_scroll : Proc(Int32, Nil)?

    def initialize(id : String? = nil, @orientation : Orientation = Orientation::Vertical)
      super(id)
      @focusable = false  # Usually not focusable, parent handles focus
    end

    # Register scroll callback - called when user interacts with scrollbar
    def on_scroll(&block : Int32 -> Nil) : Nil
      @on_scroll = block
    end

    # Update scrollbar state (called by parent widget)
    def update(total : Int32, visible : Int32, offset : Int32) : Nil
      changed = @total != total || @viewport != visible || @offset != offset
      @total = total
      @viewport = visible
      @offset = offset
      mark_dirty! if changed
    end

    # Check if scrollbar is needed
    def needed? : Bool
      @total > @viewport && @viewport > 0
    end

    # Maximum scroll offset
    def max_offset : Int32
      (@total - @viewport).clamp(0, Int32::MAX)
    end

    # Check if coordinates are on the scrollbar (with tolerance)
    def hit_test?(x : Int32, y : Int32) : Bool
      return false unless needed?

      case @orientation
      when .vertical?
        x >= @rect.x - @click_tolerance && x <= @rect.right + @click_tolerance &&
        y >= @rect.y && y < @rect.bottom
      when .horizontal?
        x >= @rect.x && x < @rect.right &&
        y >= @rect.y - @click_tolerance && y <= @rect.bottom + @click_tolerance
      else
        false
      end
    end

    # Dragging state (for parent to know)
    def dragging? : Bool
      @dragging
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return unless needed?

      if @use_overlay
        register_overlay
      else
        render_direct(buffer, clip)
      end
    end

    private def register_overlay : Nil
      rect = @rect
      orientation = @orientation
      total = @total
      visible = @viewport
      offset = @offset
      dragging = @dragging
      show_arrows = @show_arrows
      track_color = @track_color
      thumb_color = @thumb_color
      thumb_active_color = @thumb_active_color
      arrow_color = @arrow_color
      track_char_v = @track_char_v
      track_char_h = @track_char_h
      thumb_char = @thumb_char

      Tui.register_scrollbar do |buf, clip|
        draw_scrollbar(
          buf, clip, rect, orientation,
          total, visible, offset, dragging, show_arrows,
          track_color, thumb_color, thumb_active_color, arrow_color,
          track_char_v, track_char_h, thumb_char
        )
      end
    end

    private def render_direct(buffer : Buffer, clip : Rect) : Nil
      draw_scrollbar(
        buffer, clip, @rect, @orientation,
        @total, @viewport, @offset, @dragging, @show_arrows,
        @track_color, @thumb_color, @thumb_active_color, @arrow_color,
        @track_char_v, @track_char_h, @thumb_char
      )
    end

    private def draw_scrollbar(
      buffer : Buffer, clip : Rect, rect : Rect, orientation : Orientation,
      total : Int32, visible : Int32, offset : Int32, dragging : Bool, show_arrows : Bool,
      track_color : Color, thumb_color : Color, thumb_active_color : Color, arrow_color : Color,
      track_char_v : Char, track_char_h : Char, thumb_char : Char
    ) : Nil
      case orientation
      when .vertical?
        draw_vertical(buffer, clip, rect, total, visible, offset, dragging,
                      track_color, thumb_color, thumb_active_color, track_char_v, thumb_char)
      when .horizontal?
        draw_horizontal(buffer, clip, rect, total, visible, offset, dragging, show_arrows,
                        track_color, thumb_color, thumb_active_color, arrow_color, track_char_h, thumb_char)
      end
    end

    private def draw_vertical(
      buffer : Buffer, clip : Rect, rect : Rect,
      total : Int32, visible : Int32, offset : Int32, dragging : Bool,
      track_color : Color, thumb_color : Color, thumb_active_color : Color,
      track_char : Char, thumb_char : Char
    ) : Nil
      return if rect.height < 1

      track_style = Style.new(fg: track_color)
      thumb_style = Style.new(fg: dragging ? thumb_active_color : thumb_color)

      # Calculate thumb position and size
      thumb_height = Math.max(1, (visible * rect.height / total).to_i)
      max_scroll = (total - visible).clamp(0, Int32::MAX)
      thumb_pos = max_scroll > 0 ? (offset * (rect.height - thumb_height) / max_scroll).to_i : 0

      # Force buffer update for scrollbar column
      buffer.invalidate_region(rect.x, rect.y, 1, rect.height)

      rect.height.times do |i|
        y = rect.y + i
        next unless clip.contains?(rect.x, y)

        if i >= thumb_pos && i < thumb_pos + thumb_height
          buffer.set(rect.x, y, thumb_char, thumb_style)
        else
          buffer.set(rect.x, y, track_char, track_style)
        end
      end
    end

    private def draw_horizontal(
      buffer : Buffer, clip : Rect, rect : Rect,
      total : Int32, visible : Int32, offset : Int32, dragging : Bool, show_arrows : Bool,
      track_color : Color, thumb_color : Color, thumb_active_color : Color, arrow_color : Color,
      track_char : Char, thumb_char : Char
    ) : Nil
      return if rect.width < 1

      track_style = Style.new(fg: track_color)
      thumb_style = Style.new(fg: dragging ? thumb_active_color : thumb_color)
      arrow_style = Style.new(fg: arrow_color)

      # Calculate thumb position and size
      thumb_width = Math.max(2, (visible * rect.width / total).to_i)
      max_scroll = (total - visible).clamp(0, Int32::MAX)
      thumb_pos = max_scroll > 0 ? (offset * (rect.width - thumb_width) / max_scroll).to_i : 0

      rect.width.times do |i|
        x = rect.x + i
        next unless clip.contains?(x, rect.y)

        if i >= thumb_pos && i < thumb_pos + thumb_width
          buffer.set(x, rect.y, thumb_char, thumb_style)
        else
          buffer.set(x, rect.y, track_char, track_style)
        end
      end

      # Draw navigation arrows
      if show_arrows
        if offset > 0
          buffer.set(rect.x, rect.y, '◀', arrow_style) if clip.contains?(rect.x, rect.y)
        end
        if offset < max_scroll
          end_x = rect.right - 1
          buffer.set(end_x, rect.y, '▶', arrow_style) if clip.contains?(end_x, rect.y)
        end
      end
    end

    # Get thumb info for external use
    def thumb_info : {pos: Int32, size: Int32}
      case @orientation
      when .vertical?
        thumb_size = Math.max(1, (@viewport * @rect.height / @total).to_i)
        max_scroll = max_offset
        thumb_pos = max_scroll > 0 ? (@offset * (@rect.height - thumb_size) / max_scroll).to_i : 0
        {pos: thumb_pos, size: thumb_size}
      when .horizontal?
        thumb_size = Math.max(2, (@viewport * @rect.width / @total).to_i)
        max_scroll = max_offset
        thumb_pos = max_scroll > 0 ? (@offset * (@rect.width - thumb_size) / max_scroll).to_i : 0
        {pos: thumb_pos, size: thumb_size}
      else
        {pos: 0, size: 0}
      end
    end

    def on_event(event : Event) : Bool
      return false unless needed?

      case event
      when MouseEvent
        handle_mouse(event)
      else
        false
      end
    end

    private def handle_mouse(event : MouseEvent) : Bool
      case event.action
      when .press?
        return false unless event.button.left?
        return false unless hit_test?(event.x, event.y)

        case @orientation
        when .vertical?
          handle_vertical_click(event.y)
        when .horizontal?
          handle_horizontal_click(event.x)
        end
        true

      when .drag?
        return false unless @dragging

        case @orientation
        when .vertical?
          handle_vertical_drag(event.y)
        when .horizontal?
          handle_horizontal_drag(event.x)
        end
        true

      when .release?
        if @dragging
          @dragging = false
          mark_dirty!
          return true
        end
        false

      else
        # Handle wheel events
        if event.button.wheel_up? && hit_test?(event.x, event.y)
          scroll_by(-3)
          return true
        elsif event.button.wheel_down? && hit_test?(event.x, event.y)
          scroll_by(3)
          return true
        end
        false
      end
    end

    private def handle_vertical_click(screen_y : Int32) : Nil
      local_y = screen_y - @rect.y
      thumb = thumb_info

      if local_y >= thumb[:pos] && local_y < thumb[:pos] + thumb[:size]
        # Clicked on thumb - start drag
        @dragging = true
        @drag_start_pos = screen_y
        @drag_start_offset = @offset
        mark_dirty!
      elsif local_y < thumb[:pos]
        # Click above thumb - page up
        scroll_by(-@viewport)
      else
        # Click below thumb - page down
        scroll_by(@viewport)
      end
    end

    private def handle_horizontal_click(screen_x : Int32) : Nil
      local_x = screen_x - @rect.x
      thumb = thumb_info

      if local_x >= thumb[:pos] && local_x < thumb[:pos] + thumb[:size]
        # Clicked on thumb - start drag
        @dragging = true
        @drag_start_pos = screen_x
        @drag_start_offset = @offset
        mark_dirty!
      elsif local_x < thumb[:pos]
        # Click left of thumb - page left
        scroll_by(-@viewport)
      else
        # Click right of thumb - page right
        scroll_by(@viewport)
      end
    end

    private def handle_vertical_drag(screen_y : Int32) : Nil
      thumb = thumb_info
      track_height = @rect.height - thumb[:size]
      return if track_height <= 0

      delta_y = screen_y - @drag_start_pos
      scroll_per_pixel = max_offset.to_f / track_height
      new_offset = (@drag_start_offset + delta_y * scroll_per_pixel).to_i
      scroll_to(new_offset)
    end

    private def handle_horizontal_drag(screen_x : Int32) : Nil
      thumb = thumb_info
      track_width = @rect.width - thumb[:size]
      return if track_width <= 0

      delta_x = screen_x - @drag_start_pos
      scroll_per_pixel = max_offset.to_f / track_width
      new_offset = (@drag_start_offset + delta_x * scroll_per_pixel).to_i
      scroll_to(new_offset)
    end

    # Public scroll methods
    def scroll_by(delta : Int32) : Nil
      scroll_to(@offset + delta)
    end

    def scroll_to(new_offset : Int32) : Nil
      clamped = new_offset.clamp(0, max_offset)
      return if clamped == @offset

      @offset = clamped
      @on_scroll.try &.call(@offset)
      mark_dirty!
    end

    def scroll_to_start : Nil
      scroll_to(0)
    end

    def scroll_to_end : Nil
      scroll_to(max_offset)
    end
  end
end
