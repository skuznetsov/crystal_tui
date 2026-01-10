# Input widget - single-line text input
module Tui
  class Input < Widget
    include Reactive

    reactive value : String = ""
    reactive placeholder : String = ""
    reactive password : Bool = false

    property style : Style = Style.new(fg: Color.white, bg: Color.default)
    property focus_style : Style = Style.new(fg: Color.white, bg: Color.blue)
    property placeholder_style : Style = Style.new(
      fg: Color.rgb(128, 128, 128),
      bg: Color.default
    )

    # Cursor position within value
    @cursor : Int32 = 0

    # Scroll offset for long text
    @scroll : Int32 = 0

    # Callbacks
    @on_change : Proc(String, Nil)?
    @on_submit : Proc(String, Nil)?

    def initialize(
      @value : String = "",
      @placeholder : String = "",
      id : String? = nil,
      @password : Bool = false
    )
      super(id)
      @focusable = true
      @cursor = @value.size
    end

    def on_change(&block : String -> Nil) : Nil
      @on_change = block
    end

    def on_submit(&block : String -> Nil) : Nil
      @on_submit = block
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?

      current_style = focused? ? @focus_style : @style

      # Draw background
      @rect.each_cell do |x, y|
        next unless clip.contains?(x, y)
        buffer.set(x, y, ' ', current_style)
      end

      # Determine display text
      display_text = if @value.empty?
                       @placeholder
                     elsif @password
                       "*" * @value.size
                     else
                       @value
                     end

      text_style = if @value.empty?
                     @placeholder_style
                   else
                     current_style
                   end

      # Calculate visible portion (with 1 char padding on each side)
      available_width = @rect.width - 2
      return if available_width <= 0

      # Adjust scroll to keep cursor visible
      if @cursor < @scroll
        @scroll = @cursor
      elsif @cursor > @scroll + available_width
        @scroll = @cursor - available_width
      end

      visible_start = @scroll
      visible_end = Math.min(display_text.size, @scroll + available_width)
      visible_text = display_text[visible_start...visible_end]? || ""

      # Draw text
      text_y = @rect.y + @rect.height // 2
      visible_text.each_char_with_index do |char, i|
        x = @rect.x + 1 + i
        next unless clip.contains?(x, text_y)
        buffer.set(x, text_y, char, text_style)
      end

      # Draw cursor if focused
      if focused?
        cursor_x = @rect.x + 1 + (@cursor - @scroll)
        if clip.contains?(cursor_x, text_y) && cursor_x < @rect.x + @rect.width - 1
          # Invert colors at cursor position
          cursor_char = if @cursor < @value.size
                          @password ? '*' : @value[@cursor]
                        else
                          ' '
                        end
          cursor_style = Style.new(
            fg: current_style.bg.default? ? Color.black : current_style.bg,
            bg: current_style.fg,
            attrs: current_style.attrs
          )
          buffer.set(cursor_x, text_y, cursor_char, cursor_style)
        end
      end
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?
      return false unless focused?

      case event
      when KeyEvent
        handled = handle_key(event)
        if handled
          event.stop!
          return true
        end
      when MouseEvent
        if event.action.press? && event.button.left?
          if @rect.contains?(event.x, event.y)
            # Click to position cursor
            click_x = event.x - @rect.x - 1 + @scroll
            @cursor = click_x.clamp(0, @value.size)
            mark_dirty!
            event.stop!
            return true
          end
        end
      end

      false
    end

    private def handle_key(event : KeyEvent) : Bool
      alt = event.modifiers.alt?
      ctrl = event.modifiers.ctrl?

      case event.key
      when .left?
        if alt || ctrl
          move_word_left
        else
          move_cursor(-1)
        end
        true
      when .right?
        if alt || ctrl
          move_word_right
        else
          move_cursor(1)
        end
        true
      when .home?
        @cursor = 0
        mark_dirty!
        true
      when .end?
        @cursor = @value.size
        mark_dirty!
        true
      when .backspace?
        delete_backward
        true
      when .delete?
        delete_forward
        true
      when .enter?
        @on_submit.try &.call(@value)
        true
      else
        # Check for printable character
        if char = event.char
          if char >= ' ' && char <= '~'
            insert_char(char)
            return true
          end
        end
        false
      end
    end

    private def move_cursor(delta : Int32) : Nil
      @cursor = (@cursor + delta).clamp(0, @value.size)
      mark_dirty!
    end

    private def move_word_left : Nil
      return if @cursor == 0
      # Skip whitespace first
      while @cursor > 0 && @value[@cursor - 1].whitespace?
        @cursor -= 1
      end
      # Then skip word characters
      while @cursor > 0 && !@value[@cursor - 1].whitespace?
        @cursor -= 1
      end
      mark_dirty!
    end

    private def move_word_right : Nil
      return if @cursor >= @value.size
      # Skip word characters first
      while @cursor < @value.size && !@value[@cursor].whitespace?
        @cursor += 1
      end
      # Then skip whitespace
      while @cursor < @value.size && @value[@cursor].whitespace?
        @cursor += 1
      end
      mark_dirty!
    end

    private def insert_char(char : Char) : Nil
      @value = @value[0, @cursor] + char + @value[@cursor..]
      @cursor += 1
      @on_change.try &.call(@value)
      mark_dirty!
    end

    private def delete_backward : Nil
      return if @cursor == 0
      @value = @value[0, @cursor - 1] + @value[@cursor..]
      @cursor -= 1
      @on_change.try &.call(@value)
      mark_dirty!
    end

    private def delete_forward : Nil
      return if @cursor >= @value.size
      @value = @value[0, @cursor] + @value[@cursor + 1..]
      @on_change.try &.call(@value)
      mark_dirty!
    end

    def watch_value(new_value : String)
      @cursor = @cursor.clamp(0, new_value.size)
      mark_dirty!
    end

    def watch_placeholder(value : String)
      mark_dirty!
    end

    def watch_password(value : Bool)
      mark_dirty!
    end
  end
end
