# Tabbed panel widget with flexible tab positions
module Tui
  class TabbedPanel < Widget
    enum TabPosition
      Top
      Bottom
      Left
      Right
    end

    struct Tab
      property id : String
      property label : String
      property tooltip : String?
      property content : Widget?
      property closable : Bool

      def initialize(@id, @label, @tooltip = nil, @content = nil, @closable = true)
      end
    end

    @tabs : Array(Tab) = [] of Tab
    @active_tab : Int32 = 0
    @positions : Set(TabPosition) = Set{TabPosition::Top}
    @hovered_tab : Int32 = -1
    @show_tooltip : Bool = false
    @overflow_open : Bool = false
    @overflow_selected : Int32 = 0
    @overflow_overlay : OverlayRenderer? = nil

    # Style
    property tab_bg : Color = Color.cyan
    property tab_fg : Color = Color.black
    property active_tab_bg : Color = Color.white
    property active_tab_fg : Color = Color.black
    property focused_tab_bg : Color = Color.yellow  # Background when panel is focused
    property focused_tab_fg : Color = Color.black   # Foreground when panel is focused
    property content_bg : Color = Color.blue
    property content_fg : Color = Color.white
    property border_color : Color = Color.cyan
    property border_style : Panel::BorderStyle = Panel::BorderStyle::Light
    property overflow_bg : Color = Color.cyan
    property overflow_fg : Color = Color.black
    property overflow_active_bg : Color = Color.blue
    property overflow_active_fg : Color = Color.white

    # Tab size for vertical tabs
    property vertical_tab_height : Int32 = 6  # Max chars shown vertically

    # Overflow settings
    property enable_overflow : Bool = true
    property chevron_char : Char = '▼'
    property show_close_button : Bool = true

    # Callbacks
    @on_tab_close : Proc(String, Nil)?
    @on_tab_switch : Proc(String, Nil)?

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    def positions : Set(TabPosition)
      @positions
    end

    def positions=(positions : Set(TabPosition))
      @positions = positions
      mark_dirty!
    end

    def add_position(pos : TabPosition) : Nil
      @positions << pos
      mark_dirty!
    end

    def remove_position(pos : TabPosition) : Nil
      @positions.delete(pos)
      mark_dirty!
    end

    def add_tab(id : String, label : String, tooltip : String? = nil, &block : -> Widget?) : Nil
      content = block.call
      @tabs << Tab.new(id, label, tooltip, content)
      if content
        add_child(content)
      end
      mark_dirty!
    end

    def add_tab(tab : Tab) : Nil
      @tabs << tab
      if content = tab.content
        add_child(content)
      end
      mark_dirty!
    end

    def tabs : Array(Tab)
      @tabs
    end

    def active_tab : Int32
      @active_tab
    end

    def active_tab=(index : Int32) : Nil
      old_tab = @active_tab
      @active_tab = index.clamp(0, @tabs.size - 1)
      if old_tab != @active_tab
        @on_tab_switch.try &.call(@tabs[@active_tab]?.try(&.id) || "")
      end
      mark_dirty!
    end

    def active_tab_id : String?
      @tabs[@active_tab]?.try(&.id)
    end

    def on_tab_close(&block : String -> Nil) : Nil
      @on_tab_close = block
    end

    def on_tab_switch(&block : String -> Nil) : Nil
      @on_tab_switch = block
    end

    def close_tab(id : String) : Bool
      index = @tabs.index { |t| t.id == id }
      return false unless index

      tab = @tabs[index]
      if content = tab.content
        remove_child(content)
      end
      @tabs.delete_at(index)

      # Adjust active tab
      old_active = @active_tab
      if @active_tab >= @tabs.size
        @active_tab = (@tabs.size - 1).clamp(0, Int32::MAX)
      end

      @on_tab_close.try &.call(id)

      # Notify if active tab changed
      if old_active != @active_tab || index <= old_active
        @on_tab_switch.try &.call(@tabs[@active_tab]?.try(&.id) || "")
      end

      mark_dirty!
      true
    end

    def close_active_tab : Bool
      return false if @tabs.empty?
      id = @tabs[@active_tab].id
      close_tab(id)
    end

    def switch_to(id : String) : Bool
      @tabs.each_with_index do |tab, i|
        if tab.id == id
          old_tab = @active_tab
          @active_tab = i
          if old_tab != @active_tab
            @on_tab_switch.try &.call(id)
          end
          mark_dirty!
          return true
        end
      end
      false
    end

    # Override find_widget_at to only consider active tab's content
    # This prevents inactive tabs' stale rects from interfering with hit testing
    def find_widget_at(x : Int32, y : Int32) : Widget?
      return nil unless visible?
      return nil unless rect.contains?(x, y)

      # Only check active tab's content, not all children
      if @active_tab >= 0 && @active_tab < @tabs.size
        if content = @tabs[@active_tab].content
          if found = content.find_widget_at(x, y)
            return found
          end
        end
      end

      # No active content contains point, we are the target
      self
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Calculate content area (excluding tab bars)
      content_rect = calculate_content_rect

      # CRITICAL: Invalidate tab bar regions to prevent corruption
      invalidate_tab_bars(buffer)

      # Draw tab bars on each position (without overflow menu yet)
      @positions.each do |pos|
        case pos
        when .top?
          draw_horizontal_tabs(buffer, clip, top: true, draw_overflow: false)
        when .bottom?
          draw_horizontal_tabs(buffer, clip, top: false, draw_overflow: false)
        when .left?
          draw_vertical_tabs(buffer, clip, left: true)
        when .right?
          draw_vertical_tabs(buffer, clip, left: false)
        end
      end

      # Draw content area background
      content_style = Style.new(fg: @content_fg, bg: @content_bg)
      content_rect.height.times do |y|
        content_rect.width.times do |x|
          buffer.set(content_rect.x + x, content_rect.y + y, ' ', content_style) if clip.contains?(content_rect.x + x, content_rect.y + y)
        end
      end

      # Render active tab content
      if @active_tab >= 0 && @active_tab < @tabs.size
        if content = @tabs[@active_tab].content
          content.rect = content_rect
          content.render(buffer, clip)
        end
      end

      # NOTE: Overflow menu is now rendered via App overlay system (not clipped)

      # Draw tooltip if hovering
      if @show_tooltip && @hovered_tab >= 0 && @hovered_tab < @tabs.size
        if tooltip = @tabs[@hovered_tab].tooltip
          draw_tooltip(buffer, clip, tooltip)
        end
      end
    end

    private def calculate_content_rect : Rect
      x = @rect.x
      y = @rect.y
      w = @rect.width
      h = @rect.height

      # Adjust for each tab position
      if @positions.includes?(TabPosition::Top)
        y += 1
        h -= 1
      end
      if @positions.includes?(TabPosition::Bottom)
        h -= 1
      end
      if @positions.includes?(TabPosition::Left)
        x += tab_bar_width + 1
        w -= tab_bar_width + 1
      end
      if @positions.includes?(TabPosition::Right)
        w -= tab_bar_width + 1
      end

      Rect.new(x, y, Math.max(0, w), Math.max(0, h))
    end

    private def tab_bar_width : Int32
      # Width for vertical tabs: max label length (truncated) + padding
      @vertical_tab_height.clamp(3, 10)
    end

    # Force redraw of tab bar regions to prevent corruption
    private def invalidate_tab_bars(buffer : Buffer) : Nil
      return if @rect.empty?

      @positions.each do |pos|
        case pos
        when .top?
          buffer.invalidate_region(@rect.x, @rect.y, @rect.width, 1)
        when .bottom?
          buffer.invalidate_region(@rect.x, @rect.bottom - 1, @rect.width, 1)
        when .left?
          buffer.invalidate_region(@rect.x, @rect.y, tab_bar_width + 1, @rect.height)
        when .right?
          buffer.invalidate_region(@rect.right - tab_bar_width - 1, @rect.y, tab_bar_width + 1, @rect.height)
        end
      end
    end

    private def draw_horizontal_tabs(buffer : Buffer, clip : Rect, top : Bool, draw_overflow : Bool = true) : Nil
      y = top ? @rect.y : @rect.bottom - 1
      # Use focused style when panel is focused
      bg = focused? ? @focused_tab_bg : @tab_bg
      fg = focused? ? @focused_tab_fg : @tab_fg
      style = Style.new(fg: fg, bg: bg)
      active_style = Style.new(fg: @active_tab_fg, bg: @active_tab_bg)
      chevron_style = Style.new(fg: fg, bg: bg, attrs: Attributes::Bold)

      # Clear tab bar
      @rect.width.times do |i|
        buffer.set(@rect.x + i, y, ' ', style) if clip.contains?(@rect.x + i, y)
      end

      # Calculate which tabs fit
      available_width = @rect.width - 4  # Reserve space for chevron [▼]
      visible_tabs = calculate_visible_tabs(available_width)
      has_overflow = @enable_overflow && visible_tabs < @tabs.size

      # Draw visible tabs
      x = @rect.x + 1
      visible_tabs.times do |i|
        tab = @tabs[i]
        is_active = i == @active_tab
        tab_style = is_active ? active_style : style

        # Draw tab label
        label = " #{tab.label} "
        label.each_char do |char|
          break if x >= @rect.right - (has_overflow ? 4 : 1)
          buffer.set(x, y, char, tab_style) if clip.contains?(x, y)
          x += 1
        end

        # Separator
        if i < visible_tabs - 1
          buffer.set(x, y, '│', style) if clip.contains?(x, y)
          x += 1
        end
      end

      # Draw chevron if overflow
      if has_overflow
        hidden_count = @tabs.size - visible_tabs
        chevron = " #{@chevron_char}#{hidden_count} "
        chevron_x = @rect.right - chevron.size
        chevron.each_char_with_index do |char, i|
          buffer.set(chevron_x + i, y, char, chevron_style) if clip.contains?(chevron_x + i, y)
        end

        # Draw overflow dropdown if open (only if draw_overflow is true)
        if draw_overflow && @overflow_open
          draw_overflow_menu(buffer, clip, chevron_x, y, top)
        end
      end
    end

    private def calculate_visible_tabs(available_width : Int32) : Int32
      width = 0
      @tabs.each_with_index do |tab, i|
        tab_width = tab.label.size + 3  # " label " + separator
        if width + tab_width > available_width
          return i
        end
        width += tab_width
      end
      @tabs.size
    end

    # Draw overflow menu only (called after content to appear on top)
    private def draw_overflow_menu_only(buffer : Buffer, clip : Rect, top : Bool) : Nil
      available_width = @rect.width - 4
      visible_tabs = calculate_visible_tabs(available_width)
      return if visible_tabs >= @tabs.size  # No overflow

      hidden_count = @tabs.size - visible_tabs
      chevron = " #{@chevron_char}#{hidden_count} "
      chevron_x = @rect.right - chevron.size
      bar_y = top ? @rect.y : @rect.bottom - 1

      draw_overflow_menu(buffer, clip, chevron_x, bar_y, top)
    end

    # Draw overflow menu as overlay (called from App overlay system with full clip)
    private def draw_overflow_menu_overlay(buffer : Buffer, clip : Rect) : Nil
      return unless @overflow_open
      return if @rect.empty?

      available_width = @rect.width - 4
      visible_tabs = calculate_visible_tabs(available_width)
      return if visible_tabs >= @tabs.size  # No overflow

      hidden_count = @tabs.size - visible_tabs
      chevron = " #{@chevron_char}#{hidden_count} "
      chevron_x = @rect.right - chevron.size

      # Determine if tabs are at top or bottom
      top = @positions.includes?(TabPosition::Top)
      bar_y = top ? @rect.y : @rect.bottom - 1

      draw_overflow_menu(buffer, clip, chevron_x, bar_y, top)
    end

    private def draw_overflow_menu(buffer : Buffer, clip : Rect, chevron_x : Int32, bar_y : Int32, top : Bool) : Nil
      # Width: borders (2) + prefix "● " (2 display width) + label + padding (1)
      max_label_width = @tabs.max_of { |t| Unicode.display_width(t.label) }
      menu_width = max_label_width + 5  # 2 borders + 2 prefix + 1 padding
      menu_height = @tabs.size
      # Position menu left of chevron, but ensure it fits within clip (full screen) bounds
      menu_x = chevron_x - menu_width + 4
      menu_x = menu_x.clamp(clip.x, clip.right - menu_width)
      menu_y = top ? bar_y + 1 : bar_y - menu_height

      style = Style.new(fg: @overflow_fg, bg: @overflow_bg)
      active_style = Style.new(fg: @overflow_active_fg, bg: @overflow_active_bg)
      # Dark gray border for visibility on cyan background
      border_style_val = Style.new(fg: Color.palette(240), bg: @overflow_bg)
      border = Panel::BORDERS[@border_style]

      # Clear menu background first (prevents stray pixels)
      total_height = menu_height + 2  # items + top/bottom borders
      total_height.times do |row|
        menu_width.times do |col|
          buffer.set(menu_x + col, menu_y + row, ' ', style) if clip.contains?(menu_x + col, menu_y + row)
        end
      end

      # Draw top border
      buffer.set(menu_x, menu_y, border[:tl], border_style_val) if clip.contains?(menu_x, menu_y)
      (1...menu_width - 1).each do |i|
        buffer.set(menu_x + i, menu_y, border[:h], border_style_val) if clip.contains?(menu_x + i, menu_y)
      end
      buffer.set(menu_x + menu_width - 1, menu_y, border[:tr], border_style_val) if clip.contains?(menu_x + menu_width - 1, menu_y)

      # Draw menu items (shifted down by 1 for top border)
      @tabs.each_with_index do |tab, i|
        item_y = menu_y + 1 + i
        is_active = i == @overflow_selected
        is_current = i == @active_tab
        item_style = is_active ? active_style : style

        # Left border
        buffer.set(menu_x, item_y, border[:v], border_style_val) if clip.contains?(menu_x, item_y)

        # Content - use display width aware rendering
        label = is_current ? "● #{tab.label}" : "  #{tab.label}"
        content_width = menu_width - 2  # space between borders
        x_offset = 0
        label.each_char do |char|
          break if x_offset >= content_width
          char_width = Unicode.display_width(char.to_s)
          buffer.set(menu_x + 1 + x_offset, item_y, char, item_style) if clip.contains?(menu_x + 1 + x_offset, item_y)
          x_offset += char_width
        end
        # Fill remaining space with background
        while x_offset < content_width
          buffer.set(menu_x + 1 + x_offset, item_y, ' ', item_style) if clip.contains?(menu_x + 1 + x_offset, item_y)
          x_offset += 1
        end

        # Right border
        buffer.set(menu_x + menu_width - 1, item_y, border[:v], border_style_val) if clip.contains?(menu_x + menu_width - 1, item_y)
      end

      # Draw bottom border (shifted down by 1 for top border)
      bottom_y = menu_y + 1 + menu_height
      buffer.set(menu_x, bottom_y, border[:bl], border_style_val) if clip.contains?(menu_x, bottom_y)
      (1...menu_width - 1).each do |i|
        buffer.set(menu_x + i, bottom_y, border[:h], border_style_val) if clip.contains?(menu_x + i, bottom_y)
      end
      buffer.set(menu_x + menu_width - 1, bottom_y, border[:br], border_style_val) if clip.contains?(menu_x + menu_width - 1, bottom_y)
    end

    def toggle_overflow : Nil
      @overflow_open = !@overflow_open
      @overflow_selected = @active_tab if @overflow_open

      if @overflow_open
        # Register overlay for menu rendering
        @overflow_overlay = ->(buffer : Buffer, clip : Rect) {
          draw_overflow_menu_overlay(buffer, clip)
        }
        App.add_overlay(@overflow_overlay.not_nil!)
      else
        # Remove overlay
        if overlay = @overflow_overlay
          App.remove_overlay(overlay)
          @overflow_overlay = nil
        end
      end
      mark_dirty!
    end

    def close_overflow : Nil
      return unless @overflow_open
      @overflow_open = false
      if overlay = @overflow_overlay
        App.remove_overlay(overlay)
        @overflow_overlay = nil
      end
      mark_dirty!
    end

    private def draw_vertical_tabs(buffer : Buffer, clip : Rect, left : Bool) : Nil
      x = left ? @rect.x : @rect.right - tab_bar_width - 1
      style = Style.new(fg: @tab_fg, bg: @tab_bg)
      active_style = Style.new(fg: @active_tab_fg, bg: @active_tab_bg)
      border_style_obj = Style.new(fg: @border_color, bg: @tab_bg)
      border = Panel::BORDERS[@border_style]

      # Calculate vertical tab positions
      start_y = @rect.y
      if @positions.includes?(TabPosition::Top)
        start_y += 1
      end

      # Draw vertical tabs
      current_y = start_y
      @tabs.each_with_index do |tab, i|
        is_active = i == @active_tab
        tab_style = is_active ? active_style : style

        # Draw vertical label (top to bottom)
        label = tab.label[0, @vertical_tab_height]  # Truncate
        label.each_char_with_index do |char, ci|
          ty = current_y + ci
          break if ty >= @rect.bottom

          if left
            # Left tabs: draw chars, then border
            (tab_bar_width).times do |dx|
              buffer.set(x + dx, ty, ' ', tab_style) if clip.contains?(x + dx, ty)
            end
            # Center the character
            char_x = x + (tab_bar_width - 1) // 2
            buffer.set(char_x, ty, char, tab_style) if clip.contains?(char_x, ty)
            # Border on right
            buffer.set(x + tab_bar_width, ty, border[:v], border_style_obj) if clip.contains?(x + tab_bar_width, ty)
          else
            # Right tabs: border, then chars
            buffer.set(x, ty, border[:v], border_style_obj) if clip.contains?(x, ty)
            (tab_bar_width).times do |dx|
              buffer.set(x + 1 + dx, ty, ' ', tab_style) if clip.contains?(x + 1 + dx, ty)
            end
            # Center the character
            char_x = x + 1 + (tab_bar_width - 1) // 2
            buffer.set(char_x, ty, char, tab_style) if clip.contains?(char_x, ty)
          end
        end

        current_y += label.size + 1  # +1 for separator

        # Draw horizontal separator between tabs
        if i < @tabs.size - 1 && current_y < @rect.bottom
          if left
            (tab_bar_width).times do |dx|
              buffer.set(x + dx, current_y - 1, '─', border_style_obj) if clip.contains?(x + dx, current_y - 1)
            end
            buffer.set(x + tab_bar_width, current_y - 1, '┤', border_style_obj) if clip.contains?(x + tab_bar_width, current_y - 1)
          else
            buffer.set(x, current_y - 1, '├', border_style_obj) if clip.contains?(x, current_y - 1)
            (tab_bar_width).times do |dx|
              buffer.set(x + 1 + dx, current_y - 1, '─', border_style_obj) if clip.contains?(x + 1 + dx, current_y - 1)
            end
          end
        end
      end
    end

    private def draw_tooltip(buffer : Buffer, clip : Rect, text : String) : Nil
      # Simple tooltip near mouse/hover position
      tooltip_style = Style.new(fg: Color.black, bg: Color.yellow)

      # Position tooltip (simple: near bottom of content area)
      content_rect = calculate_content_rect
      x = content_rect.x + 2
      y = content_rect.bottom - 2

      # Draw tooltip
      padded = " #{text} "
      padded.each_char_with_index do |char, i|
        buffer.set(x + i, y, char, tooltip_style) if clip.contains?(x + i, y)
      end
    end

    # Handle events using DOM-like capture/bubble model
    # KeyEvents: handled when TabbedPanel is target (tab bar focused)
    # MouseEvents: handled when click is on tab bar area
    # Tab from content bubbles up - parent decides where focus goes
    def on_event(event : Event) : Bool
      case event
      when KeyEvent
        handle_key_event(event)
      when MouseEvent
        handle_mouse_event(event)
      else
        false
      end
    end

    private def handle_key_event(event : KeyEvent) : Bool
      # Only handle keys when WE are the target (tab bar is focused)
      # Let Tab bubble up from content - parent handles focus cycling
      return false unless event.at_target? && focused?

      # Handle overflow menu if open
      if @overflow_open
        case event.key
        when .escape?
          close_overflow
          event.stop_propagation!
          return true
        when .up?
          @overflow_selected = (@overflow_selected - 1).clamp(0, @tabs.size - 1)
          mark_dirty!
          event.stop_propagation!
          return true
        when .down?
          @overflow_selected = (@overflow_selected + 1).clamp(0, @tabs.size - 1)
          mark_dirty!
          event.stop_propagation!
          return true
        when .enter?
          self.active_tab = @overflow_selected
          close_overflow
          event.stop_propagation!
          return true
        end
      end

      case event.key
      when .left?
        prev_tab
        event.stop_propagation!
        return true
      when .right?
        next_tab
        event.stop_propagation!
        return true
      when .up?
        if @positions.includes?(TabPosition::Left) || @positions.includes?(TabPosition::Right)
          prev_tab
          event.stop_propagation!
          return true
        end
      when .down?
        if @positions.includes?(TabPosition::Left) || @positions.includes?(TabPosition::Right)
          next_tab
          event.stop_propagation!
          return true
        end
      when .enter?
        # Enter on tab bar = focus content
        focus_content
        event.stop_propagation!
        return true
      when .tab?
        # Tab when tab bar focused = switch tabs (Shift+Tab = prev)
        if event.modifiers.shift?
          prev_tab
        else
          next_tab
        end
        event.stop_propagation!
        return true
      else
        # Number keys 1-9 to switch tabs
        if char = event.char
          if char >= '1' && char <= '9'
            index = char.to_i - 1
            if index < @tabs.size
              self.active_tab = index
              close_overflow
              event.stop_propagation!
              return true
            end
          end
          # 'o' to open overflow menu
          if char == 'o' && @enable_overflow && @tabs.size > calculate_visible_tabs(@rect.width - 4)
            toggle_overflow
            event.stop_propagation!
            return true
          end
        end
      end

      false
    end

    private def handle_mouse_event(event : MouseEvent) : Bool
      if event.action.press?
        # Check if click is on overflow chevron
        if click_on_chevron?(event.x, event.y)
          toggle_overflow
          event.stop_propagation!
          return true
        end

        # Check if click is in overflow menu
        if @overflow_open
          if menu_index = overflow_menu_item_at(event.x, event.y)
            self.active_tab = menu_index
            close_overflow
            event.stop_propagation!
            return true
          else
            close_overflow
          end
        end

        # Check if click is on a tab
        if tab_index = tab_at(event.x, event.y)
          self.active_tab = tab_index
          self.focused = true  # Focus tab bar on click
          event.stop_propagation!
          return true
        end
      elsif event.action.move?
        # Hover in overflow menu
        if @overflow_open
          if menu_index = overflow_menu_item_at(event.x, event.y)
            if @overflow_selected != menu_index
              @overflow_selected = menu_index
              mark_dirty!
            end
          end
        end

        # Hover detection for tooltips
        if tab_index = tab_at(event.x, event.y)
          if @hovered_tab != tab_index
            @hovered_tab = tab_index
            @show_tooltip = true
            mark_dirty!
          end
        else
          if @show_tooltip
            @show_tooltip = false
            @hovered_tab = -1
            mark_dirty!
          end
        end
      end

      false
    end

    # Focus the content of the active tab
    def focus_content : Nil
      return unless @active_tab >= 0 && @active_tab < @tabs.size
      if content = @tabs[@active_tab].content
        content.focused = true
      end
    end

    private def click_on_chevron?(mx : Int32, my : Int32) : Bool
      return false unless @enable_overflow

      # Check if we have overflow
      visible = calculate_visible_tabs(@rect.width - 4)
      return false if visible >= @tabs.size

      # Check if clicking on chevron area (right side of tab bar)
      bar_y = @positions.includes?(TabPosition::Top) ? @rect.y : @rect.bottom - 1

      hidden_count = @tabs.size - visible
      chevron = " #{@chevron_char}#{hidden_count} "
      chevron_start = @rect.right - chevron.size

      return false unless my == bar_y

      mx >= chevron_start
    end

    private def overflow_menu_item_at(mx : Int32, my : Int32) : Int32?
      return nil unless @overflow_open

      # Calculate menu position (same as in draw)
      visible = calculate_visible_tabs(@rect.width - 4)
      hidden_count = @tabs.size - visible
      chevron = " #{@chevron_char}#{hidden_count} "
      chevron_x = @rect.right - chevron.size
      menu_width = @tabs.max_of(&.label.size) + 4
      menu_x = (chevron_x - menu_width + chevron.size).clamp(@rect.x, @rect.right - menu_width)

      top = @positions.includes?(TabPosition::Top)
      bar_y = top ? @rect.y : @rect.bottom - 1
      menu_y = top ? bar_y + 1 : bar_y - @tabs.size

      return nil unless mx >= menu_x && mx < menu_x + menu_width
      return nil unless my >= menu_y && my < menu_y + @tabs.size

      my - menu_y
    end

    private def tab_at(x : Int32, y : Int32) : Int32?
      # Check horizontal tabs (top)
      if @positions.includes?(TabPosition::Top) && y == @rect.y
        return horizontal_tab_at(x)
      end

      # Check horizontal tabs (bottom)
      if @positions.includes?(TabPosition::Bottom) && y == @rect.bottom - 1
        return horizontal_tab_at(x)
      end

      # Check vertical tabs (left)
      if @positions.includes?(TabPosition::Left) && x >= @rect.x && x < @rect.x + tab_bar_width + 1
        return vertical_tab_at(y)
      end

      # Check vertical tabs (right)
      if @positions.includes?(TabPosition::Right) && x >= @rect.right - tab_bar_width - 1
        return vertical_tab_at(y)
      end

      nil
    end

    private def horizontal_tab_at(x : Int32) : Int32?
      current_x = @rect.x + 1
      @tabs.each_with_index do |tab, i|
        tab_width = tab.label.size + 2  # spaces around label
        if x >= current_x && x < current_x + tab_width
          return i
        end
        current_x += tab_width + 1  # +1 for separator
      end
      nil
    end

    private def vertical_tab_at(y : Int32) : Int32?
      start_y = @rect.y
      if @positions.includes?(TabPosition::Top)
        start_y += 1
      end

      current_y = start_y
      @tabs.each_with_index do |tab, i|
        label_height = tab.label[0, @vertical_tab_height].size
        if y >= current_y && y < current_y + label_height
          return i
        end
        current_y += label_height + 1  # +1 for separator
      end
      nil
    end

    private def next_tab : Nil
      self.active_tab = (@active_tab + 1) % @tabs.size
    end

    private def prev_tab : Nil
      new_index = (@active_tab - 1) % @tabs.size
      new_index = @tabs.size - 1 if new_index < 0
      self.active_tab = new_index
    end
  end
end
