# ListView - Virtual scrolling list for large datasets
module Tui
  class ListView(T) < Widget
    property items : Array(T) = [] of T
    property selected_index : Int32 = 0
    property scroll_offset : Int32 = 0

    # Styling
    property item_height : Int32 = 1
    property selected_style : Style = Style.new(fg: Color.black, bg: Color.cyan)
    property normal_style : Style = Style.default
    property hover_style : Style = Style.new(fg: Color.white, bg: Color.palette(238))

    # Callbacks
    @item_renderer : Proc(T, Int32, Bool, String)?
    @on_select : Proc(T, Int32, Nil)?
    @on_activate : Proc(T, Int32, Nil)?

    def initialize(id : String? = nil, @items : Array(T) = [] of T)
      super(id)
      @focusable = true
    end

    # Set custom item renderer
    def item_renderer(&block : T, Int32, Bool -> String) : Nil
      @item_renderer = block
    end

    # Callback when selection changes
    def on_select(&block : T, Int32 -> Nil) : Nil
      @on_select = block
    end

    # Callback when item is activated (Enter)
    def on_activate(&block : T, Int32 -> Nil) : Nil
      @on_activate = block
    end

    # Number of visible items
    def visible_count : Int32
      return 0 if @rect.height <= 0
      @rect.height // @item_height
    end

    # Ensure selected item is visible
    private def ensure_visible : Nil
      return if @items.empty?

      visible = visible_count
      return if visible == 0

      if @selected_index < @scroll_offset
        @scroll_offset = @selected_index
      elsif @selected_index >= @scroll_offset + visible
        @scroll_offset = @selected_index - visible + 1
      end

      # Clamp scroll offset
      max_offset = Math.max(0, @items.size - visible)
      @scroll_offset = @scroll_offset.clamp(0, max_offset)
    end

    # Selection methods
    def select_index(index : Int32) : Nil
      return if @items.empty?
      old_index = @selected_index
      @selected_index = index.clamp(0, @items.size - 1)
      if @selected_index != old_index
        ensure_visible
        @on_select.try &.call(@items[@selected_index], @selected_index)
        mark_dirty!
      end
    end

    def select_next : Nil
      select_index(@selected_index + 1)
    end

    def select_prev : Nil
      select_index(@selected_index - 1)
    end

    def select_first : Nil
      select_index(0)
    end

    def select_last : Nil
      select_index(@items.size - 1)
    end

    def page_down : Nil
      select_index(@selected_index + visible_count)
    end

    def page_up : Nil
      select_index(@selected_index - visible_count)
    end

    # Get selected item
    def selected_item : T?
      return nil if @items.empty? || @selected_index < 0 || @selected_index >= @items.size
      @items[@selected_index]
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
        is_selected = item_index == @selected_index
        y = @rect.y + i * @item_height

        # Skip if outside clip
        next unless y >= clip.y && y < clip.y + clip.height

        # Get display text
        text = render_item(item, item_index, is_selected)

        # Choose style
        style = if is_selected && focused?
                  @selected_style
                elsif is_selected
                  @hover_style
                else
                  @normal_style
                end

        # Clear line
        @rect.width.times do |x|
          buffer.set(@rect.x + x, y, ' ', style) if clip.contains?(@rect.x + x, y)
        end

        # Draw text
        display_text = Unicode.truncate(text, @rect.width, "...")
        current_x = @rect.x
        display_text.each_char do |char|
          break if current_x >= @rect.x + @rect.width
          if clip.contains?(current_x, y)
            buffer.set(current_x, y, char, style)
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
          select_prev
          event.stop!
          return true
        when event.matches?("down"), event.matches?("j")
          select_next
          event.stop!
          return true
        when event.matches?("home"), event.matches?("g")
          select_first
          event.stop!
          return true
        when event.matches?("end"), event.matches?("G")
          select_last
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
        when event.matches?("enter"), event.matches?("space")
          if item = selected_item
            @on_activate.try &.call(item, @selected_index)
            event.stop!
            return true
          end
        end
      when MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          # Calculate clicked item index
          relative_y = event.y - @rect.y
          clicked_index = @scroll_offset + relative_y // @item_height
          if clicked_index >= 0 && clicked_index < @items.size
            if clicked_index == @selected_index
              # Double-click behavior: activate
              @on_activate.try &.call(@items[clicked_index], clicked_index)
            else
              select_index(clicked_index)
            end
            focus
            event.stop!
            return true
          end
        elsif event.action.press? && event.in_rect?(@rect)
          if event.button.wheel_up?
            select_prev
            event.stop!
            return true
          elsif event.button.wheel_down?
            select_next
            event.stop!
            return true
          end
        end
      end

      super
    end

    def min_size : {Int32, Int32}
      {10, 3}
    end
  end
end
