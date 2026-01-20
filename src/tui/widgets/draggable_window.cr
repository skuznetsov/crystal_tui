# Draggable Window widget with title bar controls
module Tui
  class DraggableWindow < Widget
    enum State
      Normal
      Maximized
      Minimized
    end

    @title : String
    @content : Widget?
    @state : State = State::Normal
    @dragging : Bool = false
    @resizing : Bool = false
    @drag_offset_x : Int32 = 0
    @drag_offset_y : Int32 = 0
    @saved_rect : Rect?  # For restore after maximize
    @saved_z_index : Int32 = 0  # For restore after maximize
    @menu : MenuBar?
    @menu_open : Bool = false

    # Scrolling
    @scroll_y : Int32 = 0
    @content_height : Int32 = 0  # Track virtual content height

    # Title bar buttons
    property show_close : Bool = true
    property show_maximize : Bool = true
    property show_minimize : Bool = true
    property show_menu : Bool = false

    # Close behavior: true = minimize to taskbar, false = hide completely
    property close_minimizes : Bool = true

    # Style
    property title_fg : Color = Color.white
    property title_bg : Color = Color.blue
    property title_focused_fg : Color = Color.yellow
    property title_focused_bg : Color = Color.blue
    property border_color : Color = Color.cyan
    property border_focused_color : Color = Color.yellow
    property content_bg : Color = Color.blue
    property button_fg : Color = Color.white
    property button_close_fg : Color = Color.red
    property shadow : Bool = true
    property shadow_fg : Color = Color.palette(8)
    property shadow_bg : Color = Color.black
    property resizable : Bool = true
    property min_height : Int32 = 5
    property scrollable : Bool = true

    # Calculate minimum width based on title + buttons
    def min_width : Int32
      buttons_width = 0
      buttons_width += 2 if @show_close
      buttons_width += 2 if @show_maximize
      buttons_width += 2 if @show_minimize
      buttons_width += 2 if @show_menu
      shadow_offset = @shadow ? 2 : 0
      # border(2) + title(at least 3 chars) + buttons + shadow
      Math.max(10, 2 + Math.min(@title.size, 10) + buttons_width + shadow_offset)
    end
    property scroll_lines : Int32 = 3  # Lines per wheel event

    # Callbacks
    @on_close : Proc(Nil)?
    @on_maximize : Proc(Nil)?
    @on_minimize : Proc(Nil)?
    @on_restore : Proc(Nil)?
    @on_move : Proc(Int32, Int32, Nil)?
    @on_resize : Proc(Int32, Int32, Nil)?

    def initialize(@title : String, id : String? = nil)
      super(id)
      @focusable = true
    end

    def title : String
      @title
    end

    def title=(value : String) : Nil
      @title = value
      mark_dirty!
    end

    def content : Widget?
      @content
    end

    def content=(widget : Widget?) : Nil
      if old = @content
        remove_child(old)
      end
      @content = widget
      if widget
        add_child(widget)
      end
      mark_dirty!
    end

    def menu : MenuBar?
      @menu
    end

    def menu=(m : MenuBar?) : Nil
      @menu = m
      @show_menu = !m.nil?
      mark_dirty!
    end

    def state : State
      @state
    end

    def maximized? : Bool
      @state == State::Maximized
    end

    def minimized? : Bool
      @state == State::Minimized
    end

    # Callbacks
    def on_close(&block : -> Nil) : Nil
      @on_close = block
    end

    def on_maximize(&block : -> Nil) : Nil
      @on_maximize = block
    end

    def on_minimize(&block : -> Nil) : Nil
      @on_minimize = block
    end

    def on_restore(&block : -> Nil) : Nil
      @on_restore = block
    end

    def on_move(&block : Int32, Int32 -> Nil) : Nil
      @on_move = block
    end

    def on_resize(&block : Int32, Int32 -> Nil) : Nil
      @on_resize = block
    end

    # Actions
    def close : Nil
      if @close_minimizes
        minimize  # Minimize to taskbar instead of hiding
      else
        @visible = false  # Full close - hide the window
      end
      @on_close.try &.call
      mark_dirty!
    end

    # Force close (always hides, ignores close_minimizes)
    def force_close : Nil
      @visible = false
      @on_close.try &.call
      mark_dirty!
    end

    def show : Nil
      @visible = true
      @state = State::Normal
      mark_dirty!
    end

    def maximize : Nil
      return if @state == State::Maximized
      @saved_rect = @rect.dup
      @saved_z_index = @z_index
      @state = State::Maximized
      @z_index = 1000  # Bring to front
      # Resize to fill parent (or use reasonable default)
      if parent = @parent
        @rect = Rect.new(0, 0, parent.rect.width, parent.rect.height)
      end
      @on_maximize.try &.call
      mark_dirty!
    end

    def minimize : Nil
      return if @state == State::Minimized
      @saved_rect = @rect.dup unless @state == State::Maximized
      @state = State::Minimized
      # Move to taskbar area (above status bar, typically height - 2)
      if parent = @parent
        taskbar_y = parent.rect.height - 2
        # Calculate minimized width (title + restore button)
        min_bar_width = Math.min(@title.size + 6, 20)
        # Find position (simple: use saved x, or stack from left)
        @rect = Rect.new(@saved_rect.try(&.x) || 0, taskbar_y, min_bar_width, 1)
      end
      @on_minimize.try &.call
      mark_dirty!
    end

    def restore : Nil
      if saved = @saved_rect
        @rect = saved
      end
      @z_index = @saved_z_index  # Restore z-order
      @state = State::Normal
      @on_restore.try &.call
      mark_dirty!
    end

    def toggle_maximize : Nil
      if maximized?
        restore
      else
        maximize
      end
    end

    def move_to(x : Int32, y : Int32) : Nil
      @rect = Rect.new(x, y, @rect.width, @rect.height)
      @on_move.try &.call(x, y)
      mark_dirty!
    end

    def resize_to(width : Int32, height : Int32) : Nil
      @rect = Rect.new(@rect.x, @rect.y, width.clamp(min_width, Int32::MAX), height.clamp(@min_height, Int32::MAX))
      @on_resize.try &.call(@rect.width, @rect.height)
      mark_dirty!
    end

    # Scrolling
    def scroll_y : Int32
      @scroll_y
    end

    def scroll_y=(value : Int32) : Nil
      @scroll_y = value.clamp(0, max_scroll_y)
      mark_dirty!
    end

    def content_height : Int32
      @content_height
    end

    def content_height=(value : Int32) : Nil
      @content_height = value
      # Clamp scroll if content shrunk
      @scroll_y = @scroll_y.clamp(0, max_scroll_y)
      mark_dirty!
    end

    def max_scroll_y : Int32
      visible_height = content_rect.height
      Math.max(0, @content_height - visible_height)
    end

    def scroll_up(lines : Int32 = @scroll_lines) : Nil
      self.scroll_y = @scroll_y - lines
    end

    def scroll_down(lines : Int32 = @scroll_lines) : Nil
      self.scroll_y = @scroll_y + lines
    end

    def scroll_to_top : Nil
      self.scroll_y = 0
    end

    def scroll_to_bottom : Nil
      self.scroll_y = max_scroll_y
    end

    private def content_rect : Rect
      return Rect.new(0, 0, 0, 0) if minimized?
      title_height = 1
      menu_height = @menu && @menu_open ? 1 : 0
      shadow_offset = @shadow ? 2 : 0
      content_width = Math.max(0, @rect.width - 2 - shadow_offset)
      content_height = Math.max(0, @rect.height - title_height - menu_height - 1 - (@shadow ? 1 : 0))
      Rect.new(
        @rect.x + 1,
        @rect.y + title_height + menu_height,
        content_width,
        content_height
      )
    end

    private def title_bar_rect : Rect
      shadow_offset = @shadow ? 2 : 0
      Rect.new(@rect.x, @rect.y, @rect.width - shadow_offset, 1)
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      if minimized?
        render_minimized(buffer, clip)
        return
      end

      is_focused = focused?
      shadow_offset = @shadow ? 2 : 0
      window_rect = Rect.new(@rect.x, @rect.y, @rect.width - shadow_offset, @rect.height - (@shadow ? 1 : 0))

      # Draw shadow
      if @shadow
        draw_shadow(buffer, clip, window_rect)
      end

      # Draw border
      draw_border(buffer, clip, window_rect, is_focused)

      # Draw title bar
      draw_title_bar(buffer, clip, is_focused)

      # Draw menu bar if open
      if menu = @menu
        if @menu_open
          draw_menu_bar(buffer, clip, menu)
        end
      end

      # Draw content (clipped to content area, with scroll offset)
      if content = @content
        cr = content_rect
        # Apply scroll offset - move content up by scroll_y
        scrolled_rect = Rect.new(cr.x, cr.y - @scroll_y, cr.width, @content_height.clamp(cr.height, Int32::MAX))
        content.rect = scrolled_rect
        if content_clip = clip.intersect(cr)
          content.render(buffer, content_clip)
        end
      end

      # Draw resize handle
      if @resizable && !maximized?
        draw_resize_handle(buffer, clip, window_rect)
      end
    end

    private def render_minimized(buffer : Buffer, clip : Rect) : Nil
      # Render as taskbar button
      is_focused = focused?
      style = Style.new(
        fg: is_focused ? @title_focused_fg : @title_fg,
        bg: is_focused ? @title_focused_bg : @title_bg,
        attrs: is_focused ? Attributes::Bold : Attributes::None
      )

      y = @rect.y
      x = @rect.x
      available_width = @rect.width

      # Draw [▲ Title] style button
      buffer.set(x, y, '[', style) if clip.contains?(x, y)
      x += 1

      buffer.set(x, y, '▲', style) if clip.contains?(x, y)
      x += 1

      # Title (truncated to fit)
      title_space = Math.max(0, available_width - 4)  # 4 = [] + ▲ + space
      display_title = @title.size > title_space ? @title[0, Math.max(0, title_space - 1)] + "…" : @title
      display_title.each_char do |char|
        break if x >= @rect.x + available_width - 1
        buffer.set(x, y, char, style) if clip.contains?(x, y)
        x += 1
      end

      # Fill remaining space
      while x < @rect.x + available_width - 1
        buffer.set(x, y, ' ', style) if clip.contains?(x, y)
        x += 1
      end

      buffer.set(x, y, ']', style) if clip.contains?(x, y)
    end

    private def draw_shadow(buffer : Buffer, clip : Rect, window_rect : Rect) : Nil
      shadow_style = Style.new(fg: @shadow_fg, bg: @shadow_bg)

      # Right shadow
      (window_rect.y + 1).upto(window_rect.bottom) do |y|
        [window_rect.right, window_rect.right + 1].each do |x|
          next unless clip.contains?(x, y)
          existing = buffer.get(x, y)
          char = existing.char.printable? ? existing.char : ' '
          buffer.set(x, y, char, shadow_style)
        end
      end

      # Bottom shadow
      (window_rect.x + 2).upto(window_rect.right + 1) do |x|
        y = window_rect.bottom
        next unless clip.contains?(x, y)
        existing = buffer.get(x, y)
        char = existing.char.printable? ? existing.char : ' '
        buffer.set(x, y, char, shadow_style)
      end
    end

    private def draw_border(buffer : Buffer, clip : Rect, window_rect : Rect, is_focused : Bool) : Nil
      border_style = Style.new(fg: is_focused ? @border_focused_color : @border_color)

      # Corners
      buffer.set(window_rect.x, window_rect.y, '┌', border_style) if clip.contains?(window_rect.x, window_rect.y)
      buffer.set(window_rect.right - 1, window_rect.y, '┐', border_style) if clip.contains?(window_rect.right - 1, window_rect.y)
      buffer.set(window_rect.x, window_rect.bottom - 1, '└', border_style) if clip.contains?(window_rect.x, window_rect.bottom - 1)
      buffer.set(window_rect.right - 1, window_rect.bottom - 1, '┘', border_style) if clip.contains?(window_rect.right - 1, window_rect.bottom - 1)

      # Horizontal lines
      (1...window_rect.width - 1).each do |i|
        buffer.set(window_rect.x + i, window_rect.bottom - 1, '─', border_style) if clip.contains?(window_rect.x + i, window_rect.bottom - 1)
      end

      # Vertical lines
      (1...window_rect.height - 1).each do |i|
        buffer.set(window_rect.x, window_rect.y + i, '│', border_style) if clip.contains?(window_rect.x, window_rect.y + i)
        buffer.set(window_rect.right - 1, window_rect.y + i, '│', border_style) if clip.contains?(window_rect.right - 1, window_rect.y + i)
      end

      # Fill content background
      cr = content_rect
      content_style = Style.new(bg: @content_bg)
      cr.height.times do |row|
        cr.width.times do |col|
          buffer.set(cr.x + col, cr.y + row, ' ', content_style) if clip.contains?(cr.x + col, cr.y + row)
        end
      end
    end

    private def draw_title_bar(buffer : Buffer, clip : Rect, is_focused : Bool) : Nil
      tb = title_bar_rect
      style = Style.new(
        fg: is_focused ? @title_focused_fg : @title_fg,
        bg: is_focused ? @title_focused_bg : @title_bg,
        attrs: is_focused ? Attributes::Bold : Attributes::None
      )
      button_style = Style.new(fg: @button_fg, bg: style.bg)
      close_style = Style.new(fg: @button_close_fg, bg: style.bg)

      # Clear title bar
      (1...tb.width - 1).each do |i|
        buffer.set(tb.x + i, tb.y, ' ', style) if clip.contains?(tb.x + i, tb.y)
      end

      # Draw buttons on right side
      x = tb.right - 2

      # Close button [×]
      if @show_close
        buffer.set(x, tb.y, '×', close_style) if clip.contains?(x, tb.y)
        x -= 2
      end

      # Maximize button [□]
      if @show_maximize
        char = maximized? ? '◱' : '□'
        buffer.set(x, tb.y, char, button_style) if clip.contains?(x, tb.y)
        x -= 2
      end

      # Minimize button [_]
      if @show_minimize
        buffer.set(x, tb.y, '−', button_style) if clip.contains?(x, tb.y)
        x -= 2
      end

      # Menu button [≡]
      if @show_menu
        buffer.set(x, tb.y, '≡', button_style) if clip.contains?(x, tb.y)
        x -= 2
      end

      # Draw title (centered in remaining space)
      title_space = Math.max(0, x - tb.x - 1)
      return if title_space <= 0  # No space for title

      display_title = if @title.size > title_space
                        title_space > 1 ? @title[0, title_space - 1] + "…" : ""
                      else
                        @title
                      end
      title_x = tb.x + 2
      display_title.each_char do |char|
        buffer.set(title_x, tb.y, char, style) if clip.contains?(title_x, tb.y)
        title_x += 1
      end
    end

    private def draw_menu_bar(buffer : Buffer, clip : Rect, menu : MenuBar) : Nil
      menu_y = @rect.y + 1
      menu.rect = Rect.new(@rect.x + 1, menu_y, title_bar_rect.width - 2, 1)
      menu.render(buffer, clip)
    end

    private def draw_resize_handle(buffer : Buffer, clip : Rect, window_rect : Rect) : Nil
      handle_style = Style.new(fg: @border_focused_color)
      buffer.set(window_rect.right - 1, window_rect.bottom - 1, '◢', handle_style) if clip.contains?(window_rect.right - 1, window_rect.bottom - 1)
    end

    def on_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when KeyEvent
        return false unless focused?

        # Handle menu if open
        if @menu_open
          if menu = @menu
            if menu.handle_event(event)
              return true
            end
          end
          if event.key.escape?
            @menu_open = false
            mark_dirty!
            event.stop!
            return true
          end
        end

        # Window shortcuts
        case event.key
        when .escape?
          if @menu_open
            @menu_open = false
            mark_dirty!
            event.stop!
            return true
          end
        end

        if event.modifiers.alt?
          case event.char
          when 'x', 'X'
            close
            event.stop!
            return true
          when 'm', 'M'
            toggle_maximize
            event.stop!
            return true
          when 'n', 'N'
            minimize
            event.stop!
            return true
          when 'r', 'R'
            restore
            event.stop!
            return true
          end
        end

        # Forward to content
        if content = @content
          if content.handle_event(event)
            return true
          end
        end

      when MouseEvent
        tb = title_bar_rect

        case event.action
        when .press?
          # When minimized, click anywhere to restore
          if minimized?
            if event.in_rect?(@rect)
              restore
              event.stop!
              return true
            end
            return false
          end

          # Check title bar buttons
          if event.y == tb.y && event.x >= tb.x && event.x < tb.right
            button_x = tb.right - 2

            # Close button
            if @show_close && event.x == button_x
              close
              event.stop!
              return true
            end
            button_x -= 2

            # Maximize button
            if @show_maximize && event.x == button_x
              toggle_maximize
              event.stop!
              return true
            end
            button_x -= 2

            # Minimize button
            if @show_minimize && event.x == button_x
              minimize
              event.stop!
              return true
            end
            button_x -= 2

            # Menu button
            if @show_menu && event.x == button_x
              @menu_open = !@menu_open
              mark_dirty!
              event.stop!
              return true
            end

            # Start dragging
            if !maximized?
              @dragging = true
              @drag_offset_x = event.x - @rect.x
              @drag_offset_y = event.y - @rect.y
              capture_mouse  # Capture all mouse events during drag
              event.stop!
              return true
            end
          end

          # Check resize handle
          shadow_offset = @shadow ? 2 : 0
          window_rect = Rect.new(@rect.x, @rect.y, @rect.width - shadow_offset, @rect.height - (@shadow ? 1 : 0))
          if @resizable && !maximized? && event.x == window_rect.right - 1 && event.y == window_rect.bottom - 1
            @resizing = true
            capture_mouse  # Capture all mouse events during resize
            event.stop!
            return true
          end

          # Handle wheel scrolling in content area
          if @scrollable && event.in_rect?(content_rect)
            if event.button.wheel_up?
              scroll_up
              event.stop!
              return true
            elsif event.button.wheel_down?
              scroll_down
              event.stop!
              return true
            end
          end

          # Forward to content
          if content = @content
            if event.in_rect?(content_rect)
              return content.handle_event(event)
            end
          end

        when .drag?
          if @dragging
            new_x = event.x - @drag_offset_x
            new_y = event.y - @drag_offset_y
            move_to(new_x.clamp(0, Int32::MAX), new_y.clamp(0, Int32::MAX))
            event.stop!
            return true
          end

          if @resizing
            new_width = event.x - @rect.x + 1 + (@shadow ? 2 : 0)
            new_height = event.y - @rect.y + 1 + (@shadow ? 1 : 0)
            # Clamp to minimum size before resize_to (extra safety)
            new_width = new_width.clamp(min_width, Int32::MAX)
            new_height = new_height.clamp(@min_height, Int32::MAX)
            resize_to(new_width, new_height)
            event.stop!
            return true
          end

        when .release?
          if @dragging
            @dragging = false
            release_mouse  # Release mouse capture
            event.stop!
            return true
          end
          if @resizing
            @resizing = false
            release_mouse  # Release mouse capture
            event.stop!
            return true
          end
        end
      end

      false
    end
  end
end
