# Checkbox widget
module Tui
  class Checkbox < Widget
    @checked : Bool = false
    @label : String

    # Style
    property fg_color : Color = Color.white
    property bg_color : Color = Color.default
    property check_color : Color = Color.green
    property focus_fg : Color = Color.yellow
    property focus_bg : Color = Color.default
    property checked_char : Char = '✓'
    property unchecked_char : Char = ' '
    property box_style : Symbol = :brackets  # :brackets, :unicode

    # Callbacks
    @on_change : Proc(Bool, Nil)?

    def initialize(@label : String, @checked : Bool = false, id : String? = nil)
      super(id)
      @focusable = true
    end

    def checked? : Bool
      @checked
    end

    def checked=(value : Bool) : Nil
      old = @checked
      @checked = value
      if old != value
        @on_change.try &.call(value)
        mark_dirty!
      end
    end

    def toggle : Nil
      self.checked = !@checked
    end

    def label : String
      @label
    end

    def label=(value : String) : Nil
      @label = value
      mark_dirty!
    end

    def on_change(&block : Bool -> Nil) : Nil
      @on_change = block
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      is_focused = focused?
      style = Style.new(
        fg: is_focused ? @focus_fg : @fg_color,
        bg: is_focused ? @focus_bg : @bg_color,
        attrs: is_focused ? Attributes::Bold : Attributes::None
      )
      check_style = Style.new(fg: @check_color, bg: style.bg)

      y = @rect.y
      x = @rect.x

      # Draw checkbox
      left, right = case @box_style
                    when :unicode
                      {'☐', '☑'}
                    else
                      {'[', ']'}
                    end

      if @box_style == :unicode
        char = @checked ? '☑' : '☐'
        buffer.set(x, y, char, @checked ? check_style : style) if clip.contains?(x, y)
        x += 1
      else
        buffer.set(x, y, '[', style) if clip.contains?(x, y)
        x += 1
        char = @checked ? @checked_char : @unchecked_char
        buffer.set(x, y, char, @checked ? check_style : style) if clip.contains?(x, y)
        x += 1
        buffer.set(x, y, ']', style) if clip.contains?(x, y)
        x += 1
      end

      # Space
      buffer.set(x, y, ' ', style) if clip.contains?(x, y)
      x += 1

      # Label
      @label.each_char do |char|
        break if x >= @rect.right
        buffer.set(x, y, char, style) if clip.contains?(x, y)
        x += 1
      end
    end

    def on_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when MouseEvent
        # Handle mouse regardless of focus
        if event.action.press? && event.in_rect?(@rect)
          self.focused = true  # Use setter to clear focus from other widgets
          toggle
          event.stop!
          return true
        end
        return false

      when KeyEvent
        return false unless focused?
        case event.key
        when .space?, .enter?
          toggle
          event.stop!
          return true
        end
      end

      false
    end
  end
end
