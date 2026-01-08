# Widget Palette - List of available widgets for drag & drop
module TuiEditor
  # Widget definition for palette
  struct WidgetDef
    property name : String
    property icon : String
    property category : String
    property default_attrs : Hash(String, String)

    def initialize(@name, @icon, @category, @default_attrs = {} of String => String)
    end
  end

  class WidgetPalette < Tui::Panel
    # All available widgets
    WIDGETS = [
      # Containers
      WidgetDef.new("Panel", "□", "Containers", {"title" => "Panel"}),
      WidgetDef.new("VBox", "┃", "Containers", {"align" => "stretch"}),
      WidgetDef.new("HBox", "━", "Containers", {"align" => "stretch"}),
      WidgetDef.new("VStack", "↓", "Containers", {"align" => "top"}),
      WidgetDef.new("HStack", "→", "Containers", {"align" => "left"}),
      WidgetDef.new("Grid", "▦", "Containers", {"columns" => "2", "align" => "stretch"}),

      # Input
      WidgetDef.new("Button", "▣", "Input", {"label" => "Button"}),
      WidgetDef.new("Input", "▭", "Input", {"placeholder" => "Enter text"}),
      WidgetDef.new("Checkbox", "☐", "Input", {"label" => "Checkbox"}),
      WidgetDef.new("Switch", "◐", "Input"),
      WidgetDef.new("Slider", "─●─", "Input", {"min" => "0", "max" => "100"}),

      # Display
      WidgetDef.new("Label", "T", "Display", {"text" => "Label"}),
      WidgetDef.new("Header", "▔", "Display", {"title" => "Header"}),
      WidgetDef.new("Footer", "▁", "Display"),
      WidgetDef.new("ProgressBar", "▓", "Display", {"value" => "0.5"}),
      WidgetDef.new("Rule", "─", "Display"),

      # Data
      WidgetDef.new("Tree", "├", "Data"),
      WidgetDef.new("ListView", "≡", "Data"),
      WidgetDef.new("DataTable", "⊞", "Data"),
      WidgetDef.new("Log", "▤", "Data"),
    ]

    @selected_index : Int32 = 0
    @scroll_offset : Int32 = 0
    @on_select : Proc(WidgetDef, Nil)?
    @on_drag_start : Proc(WidgetDef, Int32, Int32, Nil)?
    @drag_widget : WidgetDef?
    @drag_start_y : Int32 = 0

    def initialize
      super("Widgets", id: "palette")
      @focusable = true
      @border_style = BorderStyle::None  # SplitContainer draws border
    end

    def on_select(&block : WidgetDef -> Nil)
      @on_select = block
    end

    def on_drag_start(&block : WidgetDef, Int32, Int32 -> Nil)
      @on_drag_start = block
    end

    def dragging? : Bool
      !@drag_widget.nil?
    end

    def selected_widget : WidgetDef?
      WIDGETS[@selected_index]?
    end

    def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
      super

      inner = inner_rect
      return if inner.empty?

      # Group widgets by category
      categories = WIDGETS.group_by(&.category)

      y = inner.y
      item_index = 0

      categories.each do |category, widgets|
        # Skip if scrolled past
        if y - @scroll_offset >= inner.y && y - @scroll_offset < inner.y + inner.height
          # Category header
          header_style = Tui::Style.new(fg: Tui::Color.yellow, attrs: Tui::Attributes::Bold)
          draw_text(buffer, clip, inner.x, y - @scroll_offset, "─ #{category} ─", header_style, inner.width)
        end
        y += 1

        widgets.each do |widget|
          if y - @scroll_offset >= inner.y && y - @scroll_offset < inner.y + inner.height
            is_selected = item_index == @selected_index

            style = if is_selected && focused?
                      Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.cyan)
                    elsif is_selected
                      Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.white)
                    else
                      Tui::Style.new(fg: Tui::Color.white)
                    end

            text = "  #{widget.icon} #{widget.name}"
            draw_text(buffer, clip, inner.x, y - @scroll_offset, text, style, inner.width)
          end
          y += 1
          item_index += 1
        end
      end
    end

    private def draw_text(buffer : Tui::Buffer, clip : Tui::Rect, x : Int32, y : Int32, text : String, style : Tui::Style, max_width : Int32)
      return unless clip.contains?(x, y)

      # Pad to full width for selection highlight
      padded = text.ljust(max_width)

      padded.each_char_with_index do |char, i|
        break if i >= max_width
        buffer.set(x + i, y, char, style) if clip.contains?(x + i, y)
      end
    end

    def handle_event(event : Tui::Event) : Bool
      return false if event.stopped?

      case event
      when Tui::KeyEvent
        return false unless focused?

        case
        when event.matches?("up"), event.matches?("k")
          select_prev
          return true
        when event.matches?("down"), event.matches?("j")
          select_next
          return true
        when event.matches?("enter"), event.matches?("space")
          if widget = selected_widget
            @on_select.try &.call(widget)
          end
          return true
        end
      when Tui::MouseEvent
        inner = inner_rect

        case event.action
        when .press?
          if event.button.left? && event.in_rect?(@rect)
            # Focus on click
            focus unless focused?

            # Calculate clicked index
            relative_y = event.y - inner.y + @scroll_offset

            # Find which item was clicked (accounting for category headers)
            widget = find_widget_at_y(relative_y)
            if widget
              @selected_index = WIDGETS.index(widget) || 0
              @drag_widget = widget
              @drag_start_y = event.y
              mark_dirty!
              return true
            end
          end

        when .drag?
          if @drag_widget && event.button.left?
            # Start drag if moved enough
            if (event.y - @drag_start_y).abs > 1 || !event.in_rect?(@rect)
              if widget = @drag_widget
                @on_drag_start.try &.call(widget, event.x, event.y)
                @drag_widget = nil
              end
            end
            return true
          end

        when .release?
          if @drag_widget
            # Click without drag - select/add widget
            if widget = @drag_widget
              @on_select.try &.call(widget)
            end
            @drag_widget = nil
            mark_dirty!
            return true
          end
        end
      end

      super
    end

    private def find_widget_at_y(relative_y : Int32) : WidgetDef?
      categories = WIDGETS.group_by(&.category)
      y_offset = 0

      categories.each do |_, widgets|
        y_offset += 1  # Category header
        widgets.each do |widget|
          if y_offset == relative_y
            return widget
          end
          y_offset += 1
        end
      end
      nil
    end

    private def select_prev
      @selected_index = (@selected_index - 1).clamp(0, WIDGETS.size - 1)
      ensure_visible
      mark_dirty!
    end

    private def select_next
      @selected_index = (@selected_index + 1).clamp(0, WIDGETS.size - 1)
      ensure_visible
      mark_dirty!
    end

    private def ensure_visible
      inner = inner_rect
      visible_height = inner.height

      # Calculate actual Y position accounting for category headers
      y_pos = 0
      categories = WIDGETS.group_by(&.category)
      items_before = 0

      categories.each do |_, widgets|
        y_pos += 1  # Category header
        if items_before + widgets.size > @selected_index
          y_pos += @selected_index - items_before
          break
        end
        y_pos += widgets.size
        items_before += widgets.size
      end

      if y_pos < @scroll_offset
        @scroll_offset = y_pos
      elsif y_pos >= @scroll_offset + visible_height
        @scroll_offset = y_pos - visible_height + 1
      end
    end
  end
end
