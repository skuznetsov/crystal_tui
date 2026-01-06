# Radio button group widget
module Tui
  class RadioGroup < Widget
    struct Option
      property id : String
      property label : String

      def initialize(@id, @label)
      end
    end

    @options : Array(Option) = [] of Option
    @selected : Int32 = 0
    @focused_index : Int32 = 0

    # Style
    property fg_color : Color = Color.white
    property bg_color : Color = Color.default
    property selected_color : Color = Color.green
    property focus_fg : Color = Color.yellow
    property focus_bg : Color = Color.default
    property horizontal : Bool = false  # Layout direction
    property spacing : Int32 = 2  # Space between options

    # Callbacks
    @on_change : Proc(String, Nil)?

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    def add_option(id : String, label : String) : Nil
      @options << Option.new(id, label)
      mark_dirty!
    end

    def options : Array(Option)
      @options
    end

    def selected : Int32
      @selected
    end

    def selected=(index : Int32) : Nil
      old = @selected
      @selected = index.clamp(0, @options.size - 1)
      if old != @selected && @options.size > 0
        @on_change.try &.call(@options[@selected].id)
        mark_dirty!
      end
    end

    def selected_id : String?
      @options[@selected]?.try(&.id)
    end

    def select_by_id(id : String) : Bool
      @options.each_with_index do |opt, i|
        if opt.id == id
          self.selected = i
          return true
        end
      end
      false
    end

    def on_change(&block : String -> Nil) : Nil
      @on_change = block
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      is_focused = focused?

      if @horizontal
        render_horizontal(buffer, clip, is_focused)
      else
        render_vertical(buffer, clip, is_focused)
      end
    end

    private def render_horizontal(buffer : Buffer, clip : Rect, is_focused : Bool) : Nil
      y = @rect.y
      x = @rect.x

      @options.each_with_index do |option, i|
        x = render_option(buffer, clip, x, y, option, i, is_focused)
        x += @spacing
      end
    end

    private def render_vertical(buffer : Buffer, clip : Rect, is_focused : Bool) : Nil
      @options.each_with_index do |option, i|
        y = @rect.y + i
        break if y >= @rect.bottom
        render_option(buffer, clip, @rect.x, y, option, i, is_focused)
      end
    end

    private def render_option(buffer : Buffer, clip : Rect, x : Int32, y : Int32, option : Option, index : Int32, is_focused : Bool) : Int32
      is_selected = index == @selected
      is_option_focused = is_focused && index == @focused_index

      style = Style.new(
        fg: is_option_focused ? @focus_fg : @fg_color,
        bg: is_option_focused ? @focus_bg : @bg_color,
        attrs: is_option_focused ? Attributes::Bold : Attributes::None
      )
      selected_style = Style.new(fg: @selected_color, bg: style.bg)

      # Draw radio button
      buffer.set(x, y, '(', style) if clip.contains?(x, y)
      x += 1
      char = is_selected ? '●' : ' '
      buffer.set(x, y, char, is_selected ? selected_style : style) if clip.contains?(x, y)
      x += 1
      buffer.set(x, y, ')', style) if clip.contains?(x, y)
      x += 1

      # Space
      buffer.set(x, y, ' ', style) if clip.contains?(x, y)
      x += 1

      # Label
      option.label.each_char do |char|
        buffer.set(x, y, char, style) if clip.contains?(x, y)
        x += 1
      end

      x
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when MouseEvent
        # Handle mouse regardless of focus
        if event.action.press?
          if index = option_at(event.x, event.y)
            self.focused = true  # Use setter to clear focus from other widgets
            @focused_index = index
            self.selected = index
            event.stop!
            return true
          end
        end
        return false

      when KeyEvent
        return false unless focused?
        case event.key
        when .up?
          if !@horizontal
            move_focus(-1)
            event.stop!
            return true
          end
        when .down?
          if !@horizontal
            move_focus(1)
            event.stop!
            return true
          end
        when .left?
          if @horizontal
            move_focus(-1)
            event.stop!
            return true
          end
        when .right?
          if @horizontal
            move_focus(1)
            event.stop!
            return true
          end
        when .space?, .enter?
          self.selected = @focused_index
          event.stop!
          return true
        end
      end

      false
    end

    private def move_focus(delta : Int32) : Nil
      @focused_index = (@focused_index + delta).clamp(0, @options.size - 1)
      mark_dirty!
    end

    private def option_at(mx : Int32, my : Int32) : Int32?
      if @horizontal
        # Calculate horizontal positions
        x = @rect.x
        @options.each_with_index do |option, i|
          width = 4 + option.label.size  # (●) + label
          if my == @rect.y && mx >= x && mx < x + width
            return i
          end
          x += width + @spacing
        end
      else
        # Vertical layout
        if mx >= @rect.x && mx < @rect.right
          index = my - @rect.y
          if index >= 0 && index < @options.size
            return index
          end
        end
      end
      nil
    end
  end
end
