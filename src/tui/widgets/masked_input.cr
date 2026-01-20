# MaskedInput - Input with format mask
# Mask characters:
#   9 - digit (0-9)
#   a - letter (a-z, A-Z)
#   * - alphanumeric
#   Any other character is literal
#
# Examples:
#   "(999) 999-9999" - US phone
#   "99/99/9999" - date
#   "aa-9999" - license plate
module Tui
  class MaskedInput < Widget
    property mask : String
    property placeholder_char : Char = '_'
    property style : Style = Style.default
    property cursor_style : Style = Style.new(bg: Color.white, fg: Color.black)
    property placeholder_style : Style = Style.new(fg: Color.palette(240))

    @value : Array(Char?)  # nil = not filled
    @cursor_pos : Int32 = 0
    @on_change : Proc(String, Nil)?
    @on_complete : Proc(String, Nil)?

    def initialize(@mask : String, id : String? = nil)
      super(id)
      @focusable = true
      @value = Array(Char?).new(@mask.size, nil)
      @cursor_pos = find_next_input_pos(0)
    end

    # Callback when value changes
    def on_change(&block : String -> Nil) : Nil
      @on_change = block
    end

    # Callback when all fields are filled
    def on_complete(&block : String -> Nil) : Nil
      @on_complete = block
    end

    # Get raw value (only user input, no mask chars)
    def raw_value : String
      String.build do |str|
        @mask.each_char_with_index do |mask_char, i|
          if is_input_position?(mask_char)
            if val = @value[i]
              str << val
            end
          end
        end
      end
    end

    # Get formatted value (with mask)
    def formatted_value : String
      String.build do |str|
        @mask.each_char_with_index do |mask_char, i|
          if is_input_position?(mask_char)
            if val = @value[i]
              str << val
            else
              str << @placeholder_char
            end
          else
            str << mask_char
          end
        end
      end
    end

    # Set raw value
    def raw_value=(input : String) : Nil
      clear
      input_chars = input.chars
      input_idx = 0

      @mask.each_char_with_index do |mask_char, i|
        break if input_idx >= input_chars.size
        if is_input_position?(mask_char)
          # Skip invalid characters in input, find next valid one
          while input_idx < input_chars.size
            char = input_chars[input_idx]
            input_idx += 1
            if valid_for_mask?(char, mask_char)
              @value[i] = char
              break
            end
          end
        end
      end

      @on_change.try &.call(raw_value)
      check_complete
      mark_dirty!
    end

    # Check if mask is complete
    def complete? : Bool
      @mask.each_char_with_index do |mask_char, i|
        if is_input_position?(mask_char) && @value[i].nil?
          return false
        end
      end
      true
    end

    def clear : Nil
      @value.fill(nil)
      @cursor_pos = find_next_input_pos(0)
      @on_change.try &.call(raw_value)
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?

      x = @rect.x
      y = @rect.y

      @mask.each_char_with_index do |mask_char, i|
        break if x >= @rect.x + @rect.width
        next unless clip.contains?(x, y)

        char_to_draw : Char
        char_style : Style

        if is_input_position?(mask_char)
          if val = @value[i]
            char_to_draw = val
            char_style = @style
          else
            char_to_draw = @placeholder_char
            char_style = @placeholder_style
          end
        else
          char_to_draw = mask_char
          char_style = @style
        end

        # Cursor
        if focused? && i == @cursor_pos
          char_style = @cursor_style
        end

        buffer.set(x, y, char_to_draw, char_style)
        x += 1
      end

      # Fill remaining space
      while x < @rect.x + @rect.width
        buffer.set(x, y, ' ', @style) if clip.contains?(x, y)
        x += 1
      end
    end

    def on_event(event : Event) : Bool
      return false unless focused?
      return false if event.stopped?

      case event
      when KeyEvent
        case
        when event.matches?("left")
          move_cursor_left
          event.stop!
          return true
        when event.matches?("right")
          move_cursor_right
          event.stop!
          return true
        when event.matches?("home")
          @cursor_pos = find_next_input_pos(0)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("end")
          @cursor_pos = find_prev_input_pos(@mask.size - 1)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("backspace")
          delete_backward
          event.stop!
          return true
        when event.matches?("delete")
          delete_at_cursor
          event.stop!
          return true
        else
          # Try to insert character
          if char = event.char
            if insert_char(char)
              event.stop!
              return true
            end
          end
        end

      when MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          # Click to position cursor
          relative_x = event.x - @rect.x
          new_pos = relative_x.clamp(0, @mask.size - 1)
          # Find nearest input position
          @cursor_pos = find_nearest_input_pos(new_pos)
          focus
          mark_dirty!
          event.stop!
          return true
        end
      end

      super
    end

    private def is_input_position?(mask_char : Char) : Bool
      mask_char == '9' || mask_char == 'a' || mask_char == '*'
    end

    private def valid_for_mask?(char : Char, mask_char : Char) : Bool
      case mask_char
      when '9' then char.ascii_number?
      when 'a' then char.ascii_letter?
      when '*' then char.ascii_alphanumeric?
      else          false
      end
    end

    private def find_next_input_pos(from : Int32) : Int32
      (from...@mask.size).each do |i|
        return i if is_input_position?(@mask[i])
      end
      # If no input position found, return last valid or from
      find_prev_input_pos(@mask.size - 1)
    end

    private def find_prev_input_pos(from : Int32) : Int32
      from.downto(0) do |i|
        return i if is_input_position?(@mask[i])
      end
      0
    end

    private def find_nearest_input_pos(pos : Int32) : Int32
      return pos if pos < @mask.size && is_input_position?(@mask[pos])

      # Search forward and backward
      fwd = find_next_input_pos(pos)
      bwd = find_prev_input_pos(pos)

      if (pos - bwd).abs <= (fwd - pos).abs
        bwd
      else
        fwd
      end
    end

    private def move_cursor_left : Nil
      new_pos = find_prev_input_pos(@cursor_pos - 1)
      if new_pos != @cursor_pos
        @cursor_pos = new_pos
        mark_dirty!
      end
    end

    private def move_cursor_right : Nil
      new_pos = find_next_input_pos(@cursor_pos + 1)
      if new_pos != @cursor_pos
        @cursor_pos = new_pos
        mark_dirty!
      end
    end

    private def insert_char(char : Char) : Bool
      return false unless @cursor_pos < @mask.size

      mask_char = @mask[@cursor_pos]
      return false unless is_input_position?(mask_char)
      return false unless valid_for_mask?(char, mask_char)

      @value[@cursor_pos] = char
      @on_change.try &.call(raw_value)

      # Move to next input position
      next_pos = find_next_input_pos(@cursor_pos + 1)
      @cursor_pos = next_pos if next_pos > @cursor_pos

      check_complete
      mark_dirty!
      true
    end

    private def delete_backward : Nil
      # Find previous input position
      prev_pos = find_prev_input_pos(@cursor_pos - 1)
      if prev_pos < @cursor_pos && @value[prev_pos]
        @value[prev_pos] = nil
        @cursor_pos = prev_pos
        @on_change.try &.call(raw_value)
        mark_dirty!
      elsif @value[@cursor_pos]
        # Delete at current position if nothing before
        @value[@cursor_pos] = nil
        @on_change.try &.call(raw_value)
        mark_dirty!
      end
    end

    private def delete_at_cursor : Nil
      if is_input_position?(@mask[@cursor_pos]) && @value[@cursor_pos]
        @value[@cursor_pos] = nil
        @on_change.try &.call(raw_value)
        mark_dirty!
      end
    end

    private def check_complete : Nil
      if complete?
        @on_complete.try &.call(raw_value)
      end
    end

    def min_size : {Int32, Int32}
      {@mask.size, 1}
    end
  end
end
