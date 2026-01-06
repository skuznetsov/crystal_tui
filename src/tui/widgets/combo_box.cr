# ComboBox with search widget
module Tui
  class ComboBox < Widget
    struct Item
      property id : String
      property label : String
      property data : String?

      def initialize(@id, @label, @data = nil)
      end
    end

    @items : Array(Item) = [] of Item
    @filtered_items : Array(Item) = [] of Item
    @selected : Int32 = -1
    @highlighted : Int32 = 0
    @open : Bool = false
    @search_text : String = ""
    @cursor_pos : Int32 = 0
    @saved_z_index : Int32 = 0  # For restore when dropdown closes

    # Style
    property fg_color : Color = Color.black
    property bg_color : Color = Color.white
    property focus_fg : Color = Color.black
    property focus_bg : Color = Color.cyan
    property dropdown_fg : Color = Color.black
    property dropdown_bg : Color = Color.white
    property highlight_fg : Color = Color.white
    property highlight_bg : Color = Color.blue
    property border_color : Color = Color.black
    property placeholder : String = "Select..."
    property max_visible_items : Int32 = 8
    property enable_search : Bool = true

    # Callbacks
    @on_change : Proc(Item, Nil)?

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    def add_item(id : String, label : String, data : String? = nil) : Nil
      @items << Item.new(id, label, data)
      update_filtered
      mark_dirty!
    end

    def items : Array(Item)
      @items
    end

    def clear_items : Nil
      @items.clear
      @filtered_items.clear
      @selected = -1
      @highlighted = 0
      mark_dirty!
    end

    def selected : Int32
      @selected
    end

    def selected_item : Item?
      @items[@selected]? if @selected >= 0
    end

    def selected_id : String?
      selected_item.try(&.id)
    end

    def select_by_id(id : String) : Bool
      @items.each_with_index do |item, i|
        if item.id == id
          @selected = i
          @on_change.try &.call(item)
          mark_dirty!
          return true
        end
      end
      false
    end

    def on_change(&block : Item -> Nil) : Nil
      @on_change = block
    end

    def open? : Bool
      @open
    end

    # Override to include dropdown area when open
    def render_rect : Rect
      if @open && !@filtered_items.empty?
        visible_count = Math.min(@filtered_items.size, @max_visible_items)
        # Include dropdown height + bottom border
        expanded_height = @rect.height + visible_count + 1
        Rect.new(@rect.x, @rect.y, @rect.width, expanded_height)
      else
        @rect
      end
    end

    def toggle : Nil
      @open = !@open
      if @open
        @search_text = ""
        @cursor_pos = 0
        update_filtered
        @highlighted = @filtered_items.index { |item| @selected >= 0 && item.id == @items[@selected].id } || 0
        # Boost z_index so dropdown appears above other widgets
        @saved_z_index = @z_index
        @z_index = 1000
      else
        # Restore original z_index
        @z_index = @saved_z_index
      end
      mark_dirty!
    end

    def close : Nil
      @open = false
      @z_index = @saved_z_index  # Restore original z_index
      mark_dirty!
    end

    private def update_filtered : Nil
      if @search_text.empty?
        @filtered_items = @items.dup
      else
        search = @search_text.downcase
        @filtered_items = @items.select { |item| item.label.downcase.includes?(search) }
      end
      @highlighted = @highlighted.clamp(0, (@filtered_items.size - 1).clamp(0, Int32::MAX))
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Draw main input field
      draw_input(buffer, clip)

      # Draw dropdown if open
      if @open
        draw_dropdown(buffer, clip)
      end
    end

    private def draw_input(buffer : Buffer, clip : Rect) : Nil
      is_focused = focused?
      style = Style.new(
        fg: is_focused ? @focus_fg : @fg_color,
        bg: is_focused ? @focus_bg : @bg_color
      )

      y = @rect.y
      x = @rect.x

      # Clear input line
      @rect.width.times do |i|
        buffer.set(@rect.x + i, y, ' ', style) if clip.contains?(@rect.x + i, y)
      end

      # Draw current value or search text
      text = if @open && @enable_search
               @search_text
             elsif @selected >= 0
               @items[@selected].label
             else
               @placeholder
             end

      text.each_char_with_index do |char, i|
        break if x + i >= @rect.right - 2
        buffer.set(x + i, y, char, style) if clip.contains?(x + i, y)
      end

      # Draw cursor when searching
      if @open && @enable_search && is_focused
        cursor_x = @rect.x + @cursor_pos
        if cursor_x < @rect.right - 2 && clip.contains?(cursor_x, y)
          cursor_style = Style.new(fg: style.bg, bg: style.fg)
          char = @cursor_pos < @search_text.size ? @search_text[@cursor_pos] : ' '
          buffer.set(cursor_x, y, char, cursor_style)
        end
      end

      # Draw dropdown arrow
      arrow = @open ? '▲' : '▼'
      buffer.set(@rect.right - 1, y, arrow, style) if clip.contains?(@rect.right - 1, y)
    end

    private def draw_dropdown(buffer : Buffer, clip : Rect) : Nil
      return if @filtered_items.empty?

      visible_count = Math.min(@filtered_items.size, @max_visible_items)
      dropdown_width = @rect.width
      dropdown_x = @rect.x
      dropdown_y = @rect.y + 1

      style = Style.new(fg: @dropdown_fg, bg: @dropdown_bg)
      highlight_style = Style.new(fg: @highlight_fg, bg: @highlight_bg)
      border_style = Style.new(fg: @border_color, bg: @dropdown_bg)

      # Calculate scroll offset
      scroll_offset = 0
      if @highlighted >= visible_count
        scroll_offset = @highlighted - visible_count + 1
      end

      # Draw items
      visible_count.times do |i|
        item_index = scroll_offset + i
        break if item_index >= @filtered_items.size

        item = @filtered_items[item_index]
        y = dropdown_y + i
        is_highlighted = item_index == @highlighted
        item_style = is_highlighted ? highlight_style : style

        # Clear line
        dropdown_width.times do |dx|
          buffer.set(dropdown_x + dx, y, ' ', item_style) if clip.contains?(dropdown_x + dx, y)
        end

        # Draw left border
        buffer.set(dropdown_x, y, '│', border_style) if clip.contains?(dropdown_x, y)

        # Draw item text
        label = item.label[0, dropdown_width - 3]
        label.each_char_with_index do |char, ci|
          buffer.set(dropdown_x + 1 + ci, y, char, item_style) if clip.contains?(dropdown_x + 1 + ci, y)
        end

        # Draw right border
        buffer.set(dropdown_x + dropdown_width - 1, y, '│', border_style) if clip.contains?(dropdown_x + dropdown_width - 1, y)
      end

      # Draw bottom border
      bottom_y = dropdown_y + visible_count
      buffer.set(dropdown_x, bottom_y, '└', border_style) if clip.contains?(dropdown_x, bottom_y)
      (1...dropdown_width - 1).each do |dx|
        buffer.set(dropdown_x + dx, bottom_y, '─', border_style) if clip.contains?(dropdown_x + dx, bottom_y)
      end
      buffer.set(dropdown_x + dropdown_width - 1, bottom_y, '┘', border_style) if clip.contains?(dropdown_x + dropdown_width - 1, bottom_y)

      # Draw scroll indicator
      if @filtered_items.size > visible_count
        indicator = "#{scroll_offset + 1}-#{scroll_offset + visible_count}/#{@filtered_items.size}"
        indicator_x = dropdown_x + dropdown_width - indicator.size - 2
        indicator.each_char_with_index do |char, i|
          buffer.set(indicator_x + i, bottom_y, char, border_style) if clip.contains?(indicator_x + i, bottom_y)
        end
      end
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when MouseEvent
        # Handle mouse events regardless of focus
        if event.action.press?
          if event.y == @rect.y && event.x >= @rect.x && event.x < @rect.right
            # Click on the combobox - focus and toggle
            self.focused = true  # Use setter to clear focus from other widgets
            toggle
            event.stop!
            return true
          elsif @open
            # Check if clicking on dropdown item
            dropdown_y = @rect.y + 1
            visible_count = Math.min(@filtered_items.size, @max_visible_items)
            if event.y >= dropdown_y && event.y < dropdown_y + visible_count
              index = event.y - dropdown_y
              if index >= 0 && index < @filtered_items.size
                @highlighted = index
                # Select and close
                selected_item = @filtered_items[@highlighted]
                @items.each_with_index do |item, i|
                  if item.id == selected_item.id
                    @selected = i
                    @on_change.try &.call(item)
                    break
                  end
                end
                close
                event.stop!
                return true
              end
            else
              close
            end
          end
        end
        return false

      when KeyEvent
        return false unless focused?
        if @open
          case event.key
          when .escape?
            close
            event.stop!
            return true
          when .enter?
            if @highlighted >= 0 && @highlighted < @filtered_items.size
              # Find original index
              selected_item = @filtered_items[@highlighted]
              @items.each_with_index do |item, i|
                if item.id == selected_item.id
                  @selected = i
                  @on_change.try &.call(item)
                  break
                end
              end
            end
            close
            event.stop!
            return true
          when .up?
            @highlighted = (@highlighted - 1).clamp(0, @filtered_items.size - 1)
            mark_dirty!
            event.stop!
            return true
          when .down?
            @highlighted = (@highlighted + 1).clamp(0, @filtered_items.size - 1)
            mark_dirty!
            event.stop!
            return true
          when .backspace?
            if @enable_search && @cursor_pos > 0
              @search_text = @search_text[0, @cursor_pos - 1] + @search_text[@cursor_pos..]
              @cursor_pos -= 1
              update_filtered
              mark_dirty!
              event.stop!
              return true
            end
          when .delete?
            if @enable_search && @cursor_pos < @search_text.size
              @search_text = @search_text[0, @cursor_pos] + @search_text[@cursor_pos + 1..]
              update_filtered
              mark_dirty!
              event.stop!
              return true
            end
          when .left?
            if @enable_search
              @cursor_pos = (@cursor_pos - 1).clamp(0, @search_text.size)
              mark_dirty!
              event.stop!
              return true
            end
          when .right?
            if @enable_search
              @cursor_pos = (@cursor_pos + 1).clamp(0, @search_text.size)
              mark_dirty!
              event.stop!
              return true
            end
          when .home?
            if @enable_search
              @cursor_pos = 0
              mark_dirty!
              event.stop!
              return true
            end
          when .end?
            if @enable_search
              @cursor_pos = @search_text.size
              mark_dirty!
              event.stop!
              return true
            end
          else
            # Character input for search
            if @enable_search
              if char = event.char
                if char.printable?
                  @search_text = @search_text[0, @cursor_pos] + char + @search_text[@cursor_pos..]
                  @cursor_pos += 1
                  update_filtered
                  mark_dirty!
                  event.stop!
                  return true
                end
              end
            end
          end
        else
          case event.key
          when .enter?, .space?, .down?
            toggle
            event.stop!
            return true
          end
        end
      end

      false
    end
  end
end
