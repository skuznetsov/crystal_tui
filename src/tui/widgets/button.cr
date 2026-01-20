# Button widget - clickable button with label
module Tui
  class Button < Widget
    include Reactive

    reactive label : String = ""
    reactive disabled : Bool = false

    property style : Style = Style.default
    property focus_style : Style = Style.new(
      fg: Color.black,
      bg: Color.cyan,
      attrs: Attributes::Bold
    )
    property disabled_style : Style = Style.new(
      fg: Color.rgb(128, 128, 128),  # Gray
      bg: Color.default,
      attrs: Attributes::None
    )

    # Signal when button is pressed
    @on_press : Proc(Nil)?

    def initialize(
      @label : String = "",
      id : String? = nil,
      @style : Style = Style.new(fg: Color.white, bg: Color.blue),
      @disabled : Bool = false
    )
      super(id)
      @focusable = true
    end

    # Set press handler
    def on_press(&block : -> Nil) : Nil
      @on_press = block
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?

      # Choose style based on state
      current_style = if @disabled
                        @disabled_style
                      elsif focused?
                        @focus_style
                      else
                        @style
                      end

      # Draw background
      @rect.each_cell do |x, y|
        next unless clip.contains?(x, y)
        buffer.set(x, y, ' ', current_style)
      end

      # Draw label centered
      display_label = "[ #{@label} ]"
      if @rect.width < display_label.size
        display_label = @label[0, @rect.width]? || @label
      end

      text_x = @rect.x + (@rect.width - display_label.size) // 2
      text_y = @rect.y + @rect.height // 2

      display_label.each_char_with_index do |char, i|
        x = text_x + i
        next unless clip.contains?(x, text_y)
        buffer.set(x, text_y, char, current_style)
      end
    end

    def on_event(event : Event) : Bool
      return false if @disabled
      return false if event.stopped?

      case event
      when KeyEvent
        if focused? && (event.matches?("enter") || event.matches?("space"))
          press
          event.stop!
          return true
        end
      when MouseEvent
        if event.action.press? && event.button.left?
          if @rect.contains?(event.x, event.y)
            focus!
            press
            event.stop!
            return true
          end
        end
      end

      false
    end

    # Trigger button press
    def press : Nil
      return if @disabled
      @on_press.try &.call
      # Emit ButtonPressed event for parent handling
      emit_pressed
    end

    private def emit_pressed : Nil
      # Parents can override handle_event to catch this
      # For now, the callback is the primary mechanism
    end

    def watch_label(value : String)
      mark_dirty!
    end

    def watch_disabled(value : Bool)
      mark_dirty!
    end
  end
end
