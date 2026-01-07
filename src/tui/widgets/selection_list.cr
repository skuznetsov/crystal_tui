# SelectionList - Multi-select list with checkboxes
module Tui
  class SelectionList(T) < Widget
    property items : Array(T) = [] of T
    property selected_indices : Set(Int32) = Set(Int32).new
    property cursor_index : Int32 = 0
    property scroll_offset : Int32 = 0

    # Styling
    property item_height : Int32 = 1
    property cursor_style : Style = Style.new(fg: Color.black, bg: Color.cyan)
    property selected_style : Style = Style.new(fg: Color.green)
    property normal_style : Style = Style.default
    property checkbox_style : Style = Style.new(fg: Color.yellow)

    # Callbacks
    @item_renderer : Proc(T, Int32, Bool, String)?
    @on_selection_change : Proc(Set(Int32), Nil)?
    @on_activate : Proc(Array(T), Nil)?

    def initialize(id : String? = nil, @items : Array(T) = [] of T)
      super(id)
      @focusable = true
    end

    # Set custom item renderer
    def item_renderer(&block : T, Int32, Bool -> String) : Nil
      @item_renderer = block
    end

    # Callback when selection changes
    def on_selection_change(&block : Set(Int32) -> Nil) : Nil
      @on_selection_change = block
    end

    # Callback when Enter is pressed (returns all selected items)
    def on_activate(&block : Array(T) -> Nil) : Nil
      @on_activate = block
    end

    # Number of visible items
    def visible_count : Int32
      return 0 if @rect.height <= 0
      @rect.height // @item_height
    end

    # Ensure cursor is visible
    private def ensure_visible : Nil
      return if @items.empty?

      visible = visible_count
      return if visible == 0

      if @cursor_index < @scroll_offset
        @scroll_offset = @cursor_index
      elsif @cursor_index >= @scroll_offset + visible
        @scroll_offset = @cursor_index - visible + 1
      end

      # Clamp scroll offset
      max_offset = Math.max(0, @items.size - visible)
      @scroll_offset = @scroll_offset.clamp(0, max_offset)
    end

    # Cursor movement
    def move_cursor(index : Int32) : Nil
      return if @items.empty?
      @cursor_index = index.clamp(0, @items.size - 1)
      ensure_visible
      mark_dirty!
    end

    def cursor_next : Nil
      move_cursor(@cursor_index + 1)
    end

    def cursor_prev : Nil
      move_cursor(@cursor_index - 1)
    end

    def cursor_first : Nil
      move_cursor(0)
    end

    def cursor_last : Nil
      move_cursor(@items.size - 1)
    end

    def page_down : Nil
      move_cursor(@cursor_index + visible_count)
    end

    def page_up : Nil
      move_cursor(@cursor_index - visible_count)
    end

    # Selection methods
    def toggle_selection(index : Int32) : Nil
      return if index < 0 || index >= @items.size

      if @selected_indices.includes?(index)
        @selected_indices.delete(index)
      else
        @selected_indices.add(index)
      end

      @on_selection_change.try &.call(@selected_indices)
      mark_dirty!
    end

    def toggle_current : Nil
      toggle_selection(@cursor_index)
    end

    def select_all : Nil
      @items.size.times { |i| @selected_indices.add(i) }
      @on_selection_change.try &.call(@selected_indices)
      mark_dirty!
    end

    def deselect_all : Nil
      @selected_indices.clear
      @on_selection_change.try &.call(@selected_indices)
      mark_dirty!
    end

    def select_range(from : Int32, to : Int32) : Nil
      (Math.min(from, to)..Math.max(from, to)).each do |i|
        @selected_indices.add(i) if i >= 0 && i < @items.size
      end
      @on_selection_change.try &.call(@selected_indices)
      mark_dirty!
    end

    # Get selected items
    def selected_items : Array(T)
      @selected_indices.to_a.sort.compact_map do |i|
        @items[i]?
      end
    end

    # Check if item is selected
    def selected?(index : Int32) : Bool
      @selected_indices.includes?(index)
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      ensure_visible
      visible = visible_count

      # Only render visible items (virtual scrolling)
      visible.times do |i|
        item_index = @scroll_offset + i
        break if item_index >= @items.size

        item = @items[item_index]
        is_cursor = item_index == @cursor_index
        is_selected = selected?(item_index)
        y = @rect.y + i * @item_height

        # Skip if outside clip
        next unless y >= clip.y && y < clip.y + clip.height

        # Get display text
        text = render_item(item, item_index, is_selected)

        # Choose style for line background
        line_style = if is_cursor && focused?
                       @cursor_style
                     else
                       @normal_style
                     end

        # Clear line
        @rect.width.times do |x|
          buffer.set(@rect.x + x, y, ' ', line_style) if clip.contains?(@rect.x + x, y)
        end

        current_x = @rect.x

        # Draw checkbox
        checkbox = is_selected ? "[×] " : "[ ] "
        cb_style = if is_cursor && focused?
                     @cursor_style
                   else
                     @checkbox_style
                   end
        checkbox.each_char do |char|
          break if current_x >= @rect.x + @rect.width
          if clip.contains?(current_x, y)
            buffer.set(current_x, y, char, cb_style)
          end
          current_x += 1
        end

        # Draw text
        text_style = if is_cursor && focused?
                       @cursor_style
                     elsif is_selected
                       @selected_style
                     else
                       @normal_style
                     end

        remaining_width = @rect.x + @rect.width - current_x
        display_text = Unicode.truncate(text, remaining_width, "...")
        display_text.each_char do |char|
          break if current_x >= @rect.x + @rect.width
          if clip.contains?(current_x, y)
            buffer.set(current_x, y, char, text_style)
          end
          current_x += Unicode.char_width(char)
        end
      end

      # Draw scrollbar if needed
      if @items.size > visible && visible > 0
        draw_scrollbar(buffer, clip, visible)
      end
    end

    private def render_item(item : T, index : Int32, selected : Bool) : String
      if renderer = @item_renderer
        renderer.call(item, index, selected)
      else
        item.to_s
      end
    end

    private def draw_scrollbar(buffer : Buffer, clip : Rect, visible : Int32) : Nil
      return if @rect.width < 2

      scrollbar_x = @rect.x + @rect.width - 1
      total = @items.size
      return if total <= visible

      # Calculate thumb position and size
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

    def handle_event(event : Event) : Bool
      return false unless focused?
      return false if event.stopped?

      case event
      when KeyEvent
        case
        when event.matches?("up"), event.matches?("k")
          cursor_prev
          event.stop!
          return true
        when event.matches?("down"), event.matches?("j")
          cursor_next
          event.stop!
          return true
        when event.matches?("home"), event.matches?("g")
          cursor_first
          event.stop!
          return true
        when event.matches?("end"), event.matches?("G")
          cursor_last
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
        when event.matches?("space")
          toggle_current
          event.stop!
          return true
        when event.matches?("enter")
          items = selected_items
          @on_activate.try &.call(items) unless items.empty?
          event.stop!
          return true
        when event.matches?("ctrl+a")
          select_all
          event.stop!
          return true
        when event.matches?("ctrl+shift+a"), event.matches?("escape")
          deselect_all
          event.stop!
          return true
        end
      when MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          # Calculate clicked item index
          relative_y = event.y - @rect.y
          clicked_index = @scroll_offset + relative_y // @item_height
          if clicked_index >= 0 && clicked_index < @items.size
            move_cursor(clicked_index)
            toggle_selection(clicked_index)
            focus
            event.stop!
            return true
          end
        elsif event.action.press? && event.in_rect?(@rect)
          if event.button.wheel_up?
            cursor_prev
            event.stop!
            return true
          elsif event.button.wheel_down?
            cursor_next
            event.stop!
            return true
          end
        end
      end

      super
    end

    def min_size : {Int32, Int32}
      {14, 3}  # 4 for checkbox + 10 for text
    end
  end
end
