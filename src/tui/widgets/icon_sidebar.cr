# IconSidebar - VSCode-style vertical icon bar
module Tui
  class IconSidebar < Widget
    struct SidebarItem
      property id : String
      property icon : Char
      property label : String
      property tooltip : String?
      property badge : Int32?

      def initialize(@id, @icon, @label, @tooltip = nil, @badge = nil)
      end
    end

    @items : Array(SidebarItem) = [] of SidebarItem
    @active_index : Int32 = 0
    @hovered_index : Int32 = -1

    # Visual settings
    property width : Int32 = 4
    property icon_style : Style = Style.new(fg: Color.palette(250))
    property active_style : Style = Style.new(fg: Color.white, bg: Color.palette(237))
    property hover_style : Style = Style.new(fg: Color.cyan)
    property badge_style : Style = Style.new(fg: Color.black, bg: Color.yellow)
    property bg_style : Style = Style.new(bg: Color.palette(235))
    property border_style : Style = Style.new(fg: Color.palette(240))
    property? show_border : Bool = true
    property? show_active_indicator : Bool = true
    property active_indicator_style : Style = Style.new(fg: Color.cyan)

    # Callbacks
    @on_select : Proc(String, Nil)?

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    # Add item
    def add_item(id : String, icon : Char, label : String, tooltip : String? = nil) : SidebarItem
      item = SidebarItem.new(id, icon, label, tooltip)
      @items << item
      mark_dirty!
      item
    end

    # Get items
    def items : Array(SidebarItem)
      @items
    end

    # Active item
    def active_id : String?
      @items[@active_index]?.try(&.id)
    end

    def active_index : Int32
      @active_index
    end

    def active_index=(index : Int32) : Nil
      old = @active_index
      @active_index = index.clamp(0, (@items.size - 1).clamp(0, Int32::MAX))
      if old != @active_index
        @on_select.try &.call(@items[@active_index].id)
        mark_dirty!
      end
    end

    def select(id : String) : Bool
      @items.each_with_index do |item, i|
        if item.id == id
          self.active_index = i
          return true
        end
      end
      false
    end

    # Set badge on item
    def set_badge(id : String, count : Int32?) : Bool
      @items.each_with_index do |item, i|
        if item.id == id
          @items[i] = SidebarItem.new(item.id, item.icon, item.label, item.tooltip, count)
          mark_dirty!
          return true
        end
      end
      false
    end

    # Callback
    def on_select(&block : String -> Nil) : Nil
      @on_select = block
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Clear background
      @rect.height.times do |row|
        @width.times do |col|
          x = @rect.x + col
          y = @rect.y + row
          buffer.set(x, y, ' ', @bg_style) if clip.contains?(x, y)
        end
      end

      # Draw items
      @items.each_with_index do |item, i|
        draw_item(buffer, clip, item, i)
      end

      # Draw right border
      if @show_border
        border_x = @rect.x + @width - 1
        @rect.height.times do |row|
          y = @rect.y + row
          buffer.set(border_x, y, '│', @border_style) if clip.contains?(border_x, y)
        end
      end
    end

    private def draw_item(buffer : Buffer, clip : Rect, item : SidebarItem, index : Int32) : Nil
      y = @rect.y + index * 3  # 3 rows per item: padding, icon, padding
      return if y >= @rect.bottom - 2

      is_active = index == @active_index
      is_hovered = index == @hovered_index

      style = if is_active
                @active_style
              elsif is_hovered
                @hover_style
              else
                @icon_style
              end

      # Draw active indicator (left edge)
      if is_active && @show_active_indicator
        buffer.set(@rect.x, y + 1, '▌', @active_indicator_style) if clip.contains?(@rect.x, y + 1)
      end

      # Calculate icon width and center position
      icon_width = Unicode.char_width(item.icon)
      # Reserve space for: indicator (1) + content + border (0/1)
      indicator_space = @show_active_indicator ? 1 : 0
      border_space = @show_border ? 1 : 0
      bg_width = @width - border_space  # Full width for background (minus border only)
      icon_area_width = @width - indicator_space - border_space  # Area for icon (minus indicator too)
      # Center icon within icon area (after indicator)
      icon_x = @rect.x + indicator_space + (icon_area_width - icon_width) // 2
      icon_y = y + 1

      # Background for active item (covers full width except border)
      if is_active
        bg_width.times do |col|
          x = @rect.x + col
          [y, y + 1, y + 2].each do |row|
            buffer.set(x, row, ' ', @active_style) if clip.contains?(x, row) && row < @rect.bottom
          end
        end
      end

      # Draw icon using set_wide for proper wide char handling
      buffer.set_wide(icon_x, icon_y, item.icon, style) if clip.contains?(icon_x, icon_y)

      # Draw badge if present
      if badge = item.badge
        badge_text = badge > 99 ? "99" : badge.to_s
        badge_x = icon_x + 1
        badge_y = y
        badge_text.each_char_with_index do |c, ci|
          buffer.set(badge_x + ci, badge_y, c, @badge_style) if clip.contains?(badge_x + ci, badge_y)
        end
      end
    end

    def on_event(event : Event) : Bool
      case event
      when KeyEvent
        return false unless focused?

        case event.key
        when .up?
          prev_item
          event.stop!
          return true
        when .down?
          next_item
          event.stop!
          return true
        when .enter?
          @on_select.try &.call(@items[@active_index].id) if @active_index < @items.size
          event.stop!
          return true
        end

        # Number keys 1-9
        if char = event.char
          if char >= '1' && char <= '9'
            index = char.to_i - 1
            if index < @items.size
              self.active_index = index
              event.stop!
              return true
            end
          end
        end

      when MouseEvent
        # Check if click is in sidebar area
        return false unless event.in_rect?(@rect)

        item_index = (event.y - @rect.y) // 3
        return false if item_index < 0 || item_index >= @items.size

        case event.action
        when .press?
          self.active_index = item_index
          event.stop!
          return true
        when .move?
          if @hovered_index != item_index
            @hovered_index = item_index
            mark_dirty!
          end
        end
      end

      false
    end

    private def next_item : Nil
      self.active_index = (@active_index + 1) % @items.size
    end

    private def prev_item : Nil
      new_idx = @active_index - 1
      new_idx = @items.size - 1 if new_idx < 0
      self.active_index = new_idx
    end

    # Get required width for layout
    def preferred_width : Int32
      @width
    end
  end
end
