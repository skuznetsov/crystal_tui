# Property Inspector - Edit widget properties in TUI Editor
require "./canvas"

module TuiEditor
  # A property field definition
  struct PropertyField
    property name : String
    property label : String
    property type : Symbol  # :string, :number, :bool, :select
    property options : Array(String)?

    def initialize(@name, @label, @type = :string, @options = nil)
    end
  end

  class PropertyInspector < Tui::Panel
    # Alignment options
    VALIGN_OPTIONS = ["stretch", "top", "center", "bottom"]
    HALIGN_OPTIONS = ["stretch", "left", "center", "right"]

    # Property definitions per widget type
    PROPERTIES = {
      "Panel"       => [
        PropertyField.new("title", "Title"),
        PropertyField.new("id", "ID"),
        PropertyField.new("align", "Align", :select, VALIGN_OPTIONS),
      ],
      "VBox"        => [
        PropertyField.new("id", "ID"),
        PropertyField.new("align", "Align", :select, VALIGN_OPTIONS),
      ],
      "HBox"        => [
        PropertyField.new("id", "ID"),
        PropertyField.new("align", "Align", :select, HALIGN_OPTIONS),
      ],
      "VStack"      => [
        PropertyField.new("id", "ID"),
        PropertyField.new("align", "Align", :select, VALIGN_OPTIONS),
      ],
      "HStack"      => [
        PropertyField.new("id", "ID"),
        PropertyField.new("align", "Align", :select, HALIGN_OPTIONS),
      ],
      "Grid"        => [
        PropertyField.new("id", "ID"),
        PropertyField.new("columns", "Columns", :number),
        PropertyField.new("align", "Align", :select, VALIGN_OPTIONS),
      ],
      "Button"      => [
        PropertyField.new("id", "ID"),
        PropertyField.new("label", "Label"),
      ],
      "Input"       => [
        PropertyField.new("id", "ID"),
        PropertyField.new("placeholder", "Placeholder"),
      ],
      "Checkbox"    => [
        PropertyField.new("id", "ID"),
        PropertyField.new("label", "Label"),
      ],
      "Switch"      => [PropertyField.new("id", "ID")],
      "Slider"      => [
        PropertyField.new("id", "ID"),
        PropertyField.new("min", "Min", :number),
        PropertyField.new("max", "Max", :number),
      ],
      "Label"       => [
        PropertyField.new("id", "ID"),
        PropertyField.new("text", "Text"),
      ],
      "Header"      => [
        PropertyField.new("id", "ID"),
        PropertyField.new("title", "Title"),
      ],
      "Footer"      => [PropertyField.new("id", "ID")],
      "ProgressBar" => [
        PropertyField.new("id", "ID"),
        PropertyField.new("value", "Value", :number),
      ],
      "Rule"        => [PropertyField.new("id", "ID")],
      "Tree"        => [PropertyField.new("id", "ID")],
      "ListView"    => [PropertyField.new("id", "ID")],
      "DataTable"   => [PropertyField.new("id", "ID")],
      "Log"         => [PropertyField.new("id", "ID")],
    }

    @node : CanvasNode?
    @selected_field : Int32 = 0
    @editing : Bool = false
    @edit_buffer : String = ""
    @on_change : Proc(CanvasNode, String, String, Nil)?
    @scroll_offset : Int32 = 0

    def initialize
      super("Properties", id: "properties")
      @focusable = true
      @border_style = BorderStyle::None  # SplitContainer draws border
    end

    def node=(node : CanvasNode?) : Nil
      @node = node
      @selected_field = 0
      @editing = false
      @scroll_offset = 0
      mark_dirty!
    end

    def on_change(&block : CanvasNode, String, String -> Nil)
      @on_change = block
    end

    private def current_properties : Array(PropertyField)
      if node = @node
        PROPERTIES[node.widget_def.name]? || [] of PropertyField
      else
        [] of PropertyField
      end
    end

    private def get_field_value(node : CanvasNode, field : PropertyField) : String
      case field.name
      when "id"
        node.id
      else
        node.attrs[field.name]? || ""
      end
    end

    private def set_field_value(node : CanvasNode, field : PropertyField, value : String) : Nil
      case field.name
      when "id"
        node.id = value
      else
        node.attrs[field.name] = value
      end
      @on_change.try &.call(node, field.name, value)
    end

    def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
      super

      inner = inner_rect
      return if inner.empty?

      unless node = @node
        # No selection
        msg = "No widget selected"
        style = Tui::Style.new(fg: Tui::Color.rgb(100, 100, 100))
        draw_text(buffer, clip, inner.x, inner.y, msg, style, inner.width)
        return
      end

      props = current_properties
      y = inner.y

      # Widget type header
      header = "#{node.widget_def.icon} #{node.widget_def.name}"
      header_style = Tui::Style.new(fg: Tui::Color.yellow, attrs: Tui::Attributes::Bold)
      draw_text(buffer, clip, inner.x, y, header, header_style, inner.width)
      y += 2

      # Fields
      props.each_with_index do |field, i|
        next if y >= inner.y + inner.height
        is_selected = i == @selected_field

        # Label
        label_style = if is_selected && focused?
                        Tui::Style.new(fg: Tui::Color.cyan, attrs: Tui::Attributes::Bold)
                      else
                        Tui::Style.new(fg: Tui::Color.white)
                      end
        draw_text(buffer, clip, inner.x, y, "#{field.label}:", label_style, inner.width)
        y += 1

        # Value
        raw_value = get_field_value(node, field)
        value = if @editing && is_selected
                  if field.type == :select
                    "◀ #{@edit_buffer} ▶"  # Show arrows for select
                  else
                    @edit_buffer + "▏"
                  end
                else
                  if field.type == :select && field.options
                    "#{raw_value}"
                  else
                    raw_value
                  end
                end

        value_style = if is_selected && focused?
                        if @editing
                          Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.yellow)
                        else
                          Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.cyan)
                        end
                      else
                        Tui::Style.new(fg: Tui::Color.rgb(180, 180, 180))
                      end

        # Draw input box
        box_x = inner.x + 1
        box_width = inner.width - 2
        draw_text(buffer, clip, box_x, y, value.ljust(box_width), value_style, box_width)
        y += 2
      end

      # Hints
      if y < inner.y + inner.height - 1
        current_field = props[@selected_field]?
        is_select = current_field && current_field.type == :select
        hint = if @editing
                 is_select ? "←→=Change  Enter=Save  Esc=Cancel" : "Enter=Save  Esc=Cancel"
               else
                 "Enter=Edit  ↑↓=Navigate"
               end
        hint_style = Tui::Style.new(fg: Tui::Color.rgb(100, 100, 100))
        draw_text(buffer, clip, inner.x, inner.y + inner.height - 1, hint, hint_style, inner.width)
      end
    end

    private def draw_text(buffer : Tui::Buffer, clip : Tui::Rect, x : Int32, y : Int32,
                          text : String, style : Tui::Style, max_width : Int32) : Nil
      return unless clip.contains?(x, y)
      text.each_char_with_index do |char, i|
        break if i >= max_width
        buffer.set(x + i, y, char, style) if clip.contains?(x + i, y)
      end
    end

    def handle_event(event : Tui::Event) : Bool
      return false if event.stopped?

      case event
      when Tui::KeyEvent
        return false unless focused?

        if @editing
          return handle_edit_key(event)
        else
          return handle_nav_key(event)
        end
      when Tui::MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          focus unless focused?
          return true
        end
      end

      super
    end

    private def handle_edit_key(event : Tui::KeyEvent) : Bool
      props = current_properties
      field = props[@selected_field]?

      case
      when event.matches?("enter")
        # Save edit
        if node = @node
          if field
            set_field_value(node, field, @edit_buffer)
          end
        end
        @editing = false
        mark_dirty!
        return true
      when event.matches?("escape")
        # Cancel edit
        @editing = false
        mark_dirty!
        return true
      when event.matches?("left")
        # For select fields, cycle to previous option
        if field && field.type == :select && field.options
          cycle_select_option(field, -1)
          return true
        end
      when event.matches?("right")
        # For select fields, cycle to next option
        if field && field.type == :select && field.options
          cycle_select_option(field, 1)
          return true
        end
      when event.matches?("backspace")
        if field && field.type != :select
          @edit_buffer = @edit_buffer[0...-1] if @edit_buffer.size > 0
          mark_dirty!
        end
        return true
      else
        # Add character (not for select fields)
        if field && field.type != :select
          if event.char && event.char.not_nil!.printable?
            @edit_buffer += event.char.not_nil!.to_s
            mark_dirty!
            return true
          end
        end
      end
      false
    end

    private def cycle_select_option(field : PropertyField, direction : Int32) : Nil
      options = field.options
      return unless options && !options.empty?

      current_idx = options.index(@edit_buffer) || 0
      new_idx = (current_idx + direction) % options.size
      new_idx = options.size - 1 if new_idx < 0
      @edit_buffer = options[new_idx]
      mark_dirty!
    end

    private def handle_nav_key(event : Tui::KeyEvent) : Bool
      props = current_properties
      return false if props.empty?

      case
      when event.matches?("up"), event.matches?("k")
        @selected_field = (@selected_field - 1).clamp(0, props.size - 1)
        mark_dirty!
        return true
      when event.matches?("down"), event.matches?("j")
        @selected_field = (@selected_field + 1).clamp(0, props.size - 1)
        mark_dirty!
        return true
      when event.matches?("enter"), event.matches?("e")
        # Start editing
        if node = @node
          if field = props[@selected_field]?
            @edit_buffer = get_field_value(node, field)
            @editing = true
            mark_dirty!
          end
        end
        return true
      end
      false
    end
  end
end
