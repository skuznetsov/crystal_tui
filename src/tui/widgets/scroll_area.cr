# ScrollArea - Container with vertical and horizontal scrollbars
#
# Wraps any content widget and provides scrolling when content
# exceeds the visible area. Shows scrollbars automatically.

module Tui
  class ScrollArea < Widget
    # Content dimensions (set by content widget or manually)
    property content_width : Int32 = 0
    property content_height : Int32 = 0

    # Scroll position
    property scroll_x : Int32 = 0
    property scroll_y : Int32 = 0

    # Scrollbar visibility
    enum ScrollBarPolicy
      Auto      # Show when needed
      Always    # Always show
      Never     # Never show
    end

    property v_policy : ScrollBarPolicy = ScrollBarPolicy::Auto
    property h_policy : ScrollBarPolicy = ScrollBarPolicy::Auto

    # Scrollbars
    @v_scrollbar : ScrollBar
    @h_scrollbar : ScrollBar

    # Colors (delegated to scrollbars)
    def track_color=(color : Color)
      @v_scrollbar.track_color = color
      @h_scrollbar.track_color = color
    end

    def thumb_color=(color : Color)
      @v_scrollbar.thumb_color = color
      @h_scrollbar.thumb_color = color
    end

    def thumb_active_color=(color : Color)
      @v_scrollbar.thumb_active_color = color
      @h_scrollbar.thumb_active_color = color
    end

    # Callbacks
    @on_scroll : Proc(Int32, Int32, Nil)?  # (scroll_x, scroll_y)

    def initialize(id : String? = nil)
      super(id)
      @focusable = true

      @v_scrollbar = ScrollBar.new("#{id}:v-scroll", ScrollBar::Orientation::Vertical)
      @h_scrollbar = ScrollBar.new("#{id}:h-scroll", ScrollBar::Orientation::Horizontal)

      @v_scrollbar.on_scroll { |offset| handle_v_scroll(offset) }
      @h_scrollbar.on_scroll { |offset| handle_h_scroll(offset) }
    end

    def on_scroll(&block : Int32, Int32 -> Nil) : Nil
      @on_scroll = block
    end

    # Update content size (call when content changes)
    def update_content_size(width : Int32, height : Int32) : Nil
      @content_width = width
      @content_height = height
      clamp_scroll
      update_scrollbars
      mark_dirty!
    end

    # Viewport dimensions (visible area minus scrollbars)
    def viewport_width : Int32
      w = @rect.width
      w -= 1 if show_v_scrollbar?
      w.clamp(0, Int32::MAX)
    end

    def viewport_height : Int32
      h = @rect.height
      h -= 1 if show_h_scrollbar?
      h.clamp(0, Int32::MAX)
    end

    # Check if scrollbars should be shown
    def show_v_scrollbar? : Bool
      case @v_policy
      when .always? then true
      when .never? then false
      else @content_height > @rect.height
      end
    end

    def show_h_scrollbar? : Bool
      case @h_policy
      when .always? then true
      when .never? then false
      else @content_width > viewport_width
      end
    end

    # Max scroll values
    def max_scroll_x : Int32
      (@content_width - viewport_width).clamp(0, Int32::MAX)
    end

    def max_scroll_y : Int32
      (@content_height - viewport_height).clamp(0, Int32::MAX)
    end

    # Scroll methods
    def scroll_to(x : Int32, y : Int32) : Nil
      old_x, old_y = @scroll_x, @scroll_y
      @scroll_x = x.clamp(0, max_scroll_x)
      @scroll_y = y.clamp(0, max_scroll_y)

      if old_x != @scroll_x || old_y != @scroll_y
        update_scrollbars
        @on_scroll.try &.call(@scroll_x, @scroll_y)
        mark_dirty!
      end
    end

    def scroll_by(dx : Int32, dy : Int32) : Nil
      scroll_to(@scroll_x + dx, @scroll_y + dy)
    end

    def scroll_to_top : Nil
      scroll_to(@scroll_x, 0)
    end

    def scroll_to_bottom : Nil
      scroll_to(@scroll_x, max_scroll_y)
    end

    def scroll_to_left : Nil
      scroll_to(0, @scroll_y)
    end

    def scroll_to_right : Nil
      scroll_to(max_scroll_x, @scroll_y)
    end

    def page_up : Nil
      scroll_by(0, -viewport_height)
    end

    def page_down : Nil
      scroll_by(0, viewport_height)
    end

    def page_left : Nil
      scroll_by(-viewport_width, 0)
    end

    def page_right : Nil
      scroll_by(viewport_width, 0)
    end

    # Ensure a position is visible
    def ensure_visible(x : Int32, y : Int32, width : Int32 = 1, height : Int32 = 1) : Nil
      new_x = @scroll_x
      new_y = @scroll_y

      # Horizontal
      if x < @scroll_x
        new_x = x
      elsif x + width > @scroll_x + viewport_width
        new_x = x + width - viewport_width
      end

      # Vertical
      if y < @scroll_y
        new_y = y
      elsif y + height > @scroll_y + viewport_height
        new_y = y + height - viewport_height
      end

      scroll_to(new_x, new_y)
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Update scrollbar positions
      layout_scrollbars

      # Render vertical scrollbar
      if show_v_scrollbar?
        @v_scrollbar.render(buffer, clip)
      end

      # Render horizontal scrollbar
      if show_h_scrollbar?
        @h_scrollbar.render(buffer, clip)
      end

      # Corner (when both scrollbars visible)
      if show_v_scrollbar? && show_h_scrollbar?
        corner_x = @rect.right - 1
        corner_y = @rect.bottom - 1
        if clip.contains?(corner_x, corner_y)
          buffer.set(corner_x, corner_y, '┘', Style.new(fg: @v_scrollbar.track_color))
        end
      end
    end

    private def layout_scrollbars : Nil
      has_v = show_v_scrollbar?
      has_h = show_h_scrollbar?

      if has_v
        v_height = has_h ? @rect.height - 1 : @rect.height
        @v_scrollbar.rect = Rect.new(@rect.right - 1, @rect.y, 1, v_height)
      end

      if has_h
        h_width = has_v ? @rect.width - 1 : @rect.width
        @h_scrollbar.rect = Rect.new(@rect.x, @rect.bottom - 1, h_width, 1)
      end
    end

    private def update_scrollbars : Nil
      @v_scrollbar.update(@content_height, viewport_height, @scroll_y)
      @h_scrollbar.update(@content_width, viewport_width, @scroll_x)
    end

    private def clamp_scroll : Nil
      @scroll_x = @scroll_x.clamp(0, max_scroll_x)
      @scroll_y = @scroll_y.clamp(0, max_scroll_y)
    end

    private def handle_v_scroll(offset : Int32) : Nil
      @scroll_y = offset
      @on_scroll.try &.call(@scroll_x, @scroll_y)
      mark_dirty!
    end

    private def handle_h_scroll(offset : Int32) : Nil
      @scroll_x = offset
      @on_scroll.try &.call(@scroll_x, @scroll_y)
      mark_dirty!
    end

    def on_event(event : Event) : Bool
      case event
      when MouseEvent
        handle_mouse(event)
      when KeyEvent
        handle_key(event)
      else
        false
      end
    end

    private def handle_mouse(event : MouseEvent) : Bool
      # Check scrollbars first
      if show_v_scrollbar? && (@v_scrollbar.hit_test?(event.x, event.y) || @v_scrollbar.dragging?)
        return @v_scrollbar.on_event(event)
      end

      if show_h_scrollbar? && (@h_scrollbar.hit_test?(event.x, event.y) || @h_scrollbar.dragging?)
        return @h_scrollbar.on_event(event)
      end

      # Handle scroll wheel in viewport
      if event.in_rect?(@rect)
        if event.button.wheel_up?
          scroll_by(0, -3)
          return true
        elsif event.button.wheel_down?
          scroll_by(0, 3)
          return true
        end
      end

      false
    end

    private def handle_key(event : KeyEvent) : Bool
      return false unless focused?

      case event.key
      when .up?
        scroll_by(0, -1)
        true
      when .down?
        scroll_by(0, 1)
        true
      when .left?
        scroll_by(-1, 0)
        true
      when .right?
        scroll_by(1, 0)
        true
      when .page_up?
        page_up
        true
      when .page_down?
        page_down
        true
      when .home?
        scroll_to_top
        true
      when .end?
        scroll_to_bottom
        true
      else
        false
      end
    end

    # Getters for scrollbars (for customization)
    def v_scrollbar : ScrollBar
      @v_scrollbar
    end

    def h_scrollbar : ScrollBar
      @h_scrollbar
    end
  end
end
