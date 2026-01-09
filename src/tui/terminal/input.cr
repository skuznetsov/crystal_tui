# Input parsing - keyboard and mouse events (event-driven)
module Tui
  class InputParser
    @buffer : Array(UInt8)
    @event_channel : Channel(Event)
    @running : Bool = false
    @input_fiber : Fiber?
    @input_provider : InputProvider

    # Byte constants for parsing
    BYTE_0 = '0'.ord.to_u8
    BYTE_9 = '9'.ord.to_u8
    BYTE_SEMICOLON = ';'.ord.to_u8
    BYTE_LESS_THAN = '<'.ord.to_u8
    BYTE_UPPER_A = 'A'.ord.to_u8
    BYTE_UPPER_B = 'B'.ord.to_u8
    BYTE_UPPER_C = 'C'.ord.to_u8
    BYTE_UPPER_D = 'D'.ord.to_u8
    BYTE_UPPER_F = 'F'.ord.to_u8
    BYTE_UPPER_H = 'H'.ord.to_u8
    BYTE_UPPER_M = 'M'.ord.to_u8
    BYTE_UPPER_O = 'O'.ord.to_u8
    BYTE_UPPER_P = 'P'.ord.to_u8
    BYTE_UPPER_Q = 'Q'.ord.to_u8
    BYTE_UPPER_R = 'R'.ord.to_u8
    BYTE_UPPER_S = 'S'.ord.to_u8
    BYTE_LOWER_M = 'm'.ord.to_u8
    BYTE_TILDE = '~'.ord.to_u8
    BYTE_BRACKET = '['.ord.to_u8
    BYTE_ESC = 27_u8

    def initialize(@input_provider : InputProvider = StdinInputProvider.new)
      @buffer = [] of UInt8
      @event_channel = Channel(Event).new(32)  # Buffered channel
    end

    # Get/set the input provider (for testing)
    property input_provider : InputProvider

    # Start the input reading fiber
    def start : Nil
      return if @running
      @running = true

      @input_fiber = spawn(name: "tui-input") do
        input_loop
      end
    end

    # Stop the input reading fiber
    def stop : Nil
      @running = false
      @event_channel.close
    end

    # Get event channel for select
    def events : Channel(Event)
      @event_channel
    end

    # Read next event (blocking) - waits for event
    def read_event : Event?
      return nil unless @running
      @event_channel.receive?
    end

    # Read event with timeout
    def read_event(timeout : Time::Span) : Event?
      return nil unless @running
      select
      when event = @event_channel.receive?
        event
      when timeout(timeout)
        nil
      end
    end

    private def input_loop : Nil
      while @running
        # Block until byte available (event-driven!)
        byte = @input_provider.read_byte
        break unless byte

        @buffer << byte

        # Try to parse complete events from buffer
        while event = parse_buffer
          break unless @running
          @event_channel.send(event) rescue break
        end
      end
    rescue IO::Error
      # Input closed
    end

    private def parse_buffer : Event?
      return nil if @buffer.empty?

      # Check for escape sequence
      if @buffer[0] == BYTE_ESC
        if @buffer.size == 1
          # Need more bytes - return nil, wait for input_loop to feed more
          return nil
        end

        # Check if this could be a standalone ESC (next byte took too long)
        # In event-driven mode, we process bytes as they arrive
        # If second byte is not part of escape sequence, treat ESC as standalone
        if @buffer[1] != BYTE_BRACKET && @buffer[1] != BYTE_UPPER_O
          @buffer.shift  # Remove ESC
          return KeyEvent.new(Key::Escape)
        end

        return parse_escape_sequence
      end

      # Regular character - need to decode UTF-8 properly
      char = decode_utf8_char
      return nil unless char  # Need more bytes for multi-byte char
      return KeyEvent.new(char)  # Positional to call char_to_key constructor
    end

    # Decode a complete UTF-8 character from buffer
    private def decode_utf8_char : Char?
      return nil if @buffer.empty?

      first = @buffer[0]

      # Determine how many bytes this UTF-8 character needs
      byte_count = if first < 0x80
                     1  # ASCII (0xxxxxxx)
                   elsif first & 0xE0 == 0xC0
                     2  # 2-byte sequence (110xxxxx)
                   elsif first & 0xF0 == 0xE0
                     3  # 3-byte sequence (1110xxxx)
                   elsif first & 0xF8 == 0xF0
                     4  # 4-byte sequence (11110xxx)
                   else
                     # Invalid UTF-8 start byte, consume and return replacement
                     @buffer.shift
                     return '\uFFFD'
                   end

      # Check if we have enough bytes
      return nil if @buffer.size < byte_count

      # Extract bytes and decode
      bytes = Slice(UInt8).new(byte_count)
      byte_count.times do |i|
        bytes[i] = @buffer.shift
      end

      # Convert bytes to string, then extract char
      str = String.new(bytes)
      str.empty? ? '\uFFFD' : str[0]
    end

    private def parse_escape_sequence : Event?
      return nil if @buffer.size < 2

      case @buffer[1]
      when BYTE_BRACKET
        parse_csi_sequence
      when BYTE_UPPER_O
        parse_ss3_sequence
      else
        # Alt + key
        @buffer.shift  # Remove ESC
        char = @buffer.shift.unsafe_chr
        return KeyEvent.new(char, Modifiers::Alt)  # Positional to call char_to_key constructor
      end
    end

    # Parse CSI (Control Sequence Introducer) sequences
    private def parse_csi_sequence : Event?
      return nil if @buffer.size < 3

      # First, find the terminating byte WITHOUT consuming the buffer
      # CSI sequences end with a letter (A-Z, a-z) or ~
      term_idx = -1
      (2...@buffer.size).each do |i|
        byte = @buffer[i]
        # Check if this is a terminating byte (letter or ~)
        if (byte >= 'A'.ord && byte <= 'Z'.ord) ||
           (byte >= 'a'.ord && byte <= 'z'.ord) ||
           byte == BYTE_TILDE
          term_idx = i
          break
        end
        # If it's not a digit, semicolon, or '<', it's invalid
        unless (byte >= BYTE_0 && byte <= BYTE_9) || byte == BYTE_SEMICOLON || byte == BYTE_LESS_THAN
          # Unknown byte in sequence - consume ESC [ and return nil
          @buffer.shift
          @buffer.shift
          return nil
        end
      end

      # If no terminator found yet, wait for more input
      return nil if term_idx == -1

      # Now we have a complete sequence, consume it
      @buffer.shift  # ESC
      @buffer.shift  # [

      # Check for mouse event (SGR format: <button;x;y;M or m)
      if @buffer[0]? == BYTE_LESS_THAN
        return parse_sgr_mouse
      end

      # Collect parameters and final byte
      params = [] of Int32
      current = 0

      while !@buffer.empty?
        byte = @buffer.shift

        if byte >= BYTE_0 && byte <= BYTE_9
          current = current * 10 + (byte - BYTE_0).to_i32
        elsif byte == BYTE_SEMICOLON
          params << current
          current = 0
        elsif byte == BYTE_UPPER_A  # Up
          params << current
          return KeyEvent.new(Key::Up, modifiers_from_params(params))
        elsif byte == BYTE_UPPER_B  # Down
          params << current
          return KeyEvent.new(Key::Down, modifiers_from_params(params))
        elsif byte == BYTE_UPPER_C  # Right
          params << current
          return KeyEvent.new(Key::Right, modifiers_from_params(params))
        elsif byte == BYTE_UPPER_D  # Left
          params << current
          return KeyEvent.new(Key::Left, modifiers_from_params(params))
        elsif byte == BYTE_UPPER_H  # Home
          params << current
          return KeyEvent.new(Key::Home, modifiers_from_params(params))
        elsif byte == BYTE_UPPER_F  # End
          params << current
          return KeyEvent.new(Key::End, modifiers_from_params(params))
        elsif byte == BYTE_UPPER_P  # F1 (with modifiers, CSI format)
          params << current
          return KeyEvent.new(Key::F1, modifiers_from_params(params))
        elsif byte == BYTE_UPPER_Q  # F2 (with modifiers, CSI format)
          params << current
          return KeyEvent.new(Key::F2, modifiers_from_params(params))
        elsif byte == BYTE_UPPER_R  # F3 (with modifiers, CSI format)
          params << current
          return KeyEvent.new(Key::F3, modifiers_from_params(params))
        elsif byte == BYTE_UPPER_S  # F4 (with modifiers, CSI format)
          params << current
          return KeyEvent.new(Key::F4, modifiers_from_params(params))
        elsif byte == BYTE_TILDE
          params << current
          return parse_tilde_sequence(params)
        elsif byte == BYTE_UPPER_M || byte == BYTE_LOWER_M
          # X10/normal mouse (not SGR)
          params << current
          return parse_x10_mouse(params, byte == BYTE_UPPER_M)
        else
          # Unknown sequence, discard
          return nil
        end
      end

      nil
    end

    # Parse SS3 sequences (F1-F4)
    private def parse_ss3_sequence : Event?
      return nil if @buffer.size < 3

      @buffer.shift  # ESC
      @buffer.shift  # O

      byte = @buffer.shift

      case byte
      when BYTE_UPPER_P
        KeyEvent.new(Key::F1)
      when BYTE_UPPER_Q
        KeyEvent.new(Key::F2)
      when BYTE_UPPER_R
        KeyEvent.new(Key::F3)
      when BYTE_UPPER_S
        KeyEvent.new(Key::F4)
      else
        nil
      end
    end

    private def parse_tilde_sequence(params : Array(Int32)) : Event?
      key = case params[0]?
            when 1  then Key::Home
            when 2  then Key::Insert
            when 3  then Key::Delete
            when 4  then Key::End
            when 5  then Key::PageUp
            when 6  then Key::PageDown
            when 15 then Key::F5
            when 17 then Key::F6
            when 18 then Key::F7
            when 19 then Key::F8
            when 20 then Key::F9
            when 21 then Key::F10
            when 23 then Key::F11
            when 24 then Key::F12
            else    return nil
            end

      KeyEvent.new(key, modifiers_from_param(params[1]?))
    end

    # Parse SGR extended mouse format: <button;x;y;M (press) or m (release)
    private def parse_sgr_mouse : Event?
      @buffer.shift  # Remove '<'

      params = [] of Int32
      current = 0

      while !@buffer.empty?
        byte = @buffer.shift

        if byte >= BYTE_0 && byte <= BYTE_9
          current = current * 10 + (byte - BYTE_0).to_i32
        elsif byte == BYTE_SEMICOLON
          params << current
          current = 0
        elsif byte == BYTE_UPPER_M  # Press
          params << current
          return create_mouse_event(params, pressed: true)
        elsif byte == BYTE_LOWER_M  # Release
          params << current
          return create_mouse_event(params, pressed: false)
        else
          return nil
        end
      end

      nil
    end

    private def parse_x10_mouse(params : Array(Int32), pressed : Bool) : Event?
      # X10 mouse format - less precise than SGR
      nil  # TODO: implement if needed
    end

    private def create_mouse_event(params : Array(Int32), pressed : Bool) : MouseEvent?
      return nil if params.size < 3

      button_code = params[0]
      x = params[1] - 1  # 1-indexed to 0-indexed
      y = params[2] - 1

      # Decode button
      button = case button_code & 0b11
               when 0 then MouseButton::Left
               when 1 then MouseButton::Middle
               when 2 then MouseButton::Right
               else        MouseButton::Left
               end

      # Check for wheel
      if button_code & 64 != 0
        button = (button_code & 1) == 0 ? MouseButton::WheelUp : MouseButton::WheelDown
      end

      # Decode modifiers
      modifiers = Modifiers::None
      modifiers |= Modifiers::Shift if button_code & 4 != 0
      modifiers |= Modifiers::Alt if button_code & 8 != 0
      modifiers |= Modifiers::Ctrl if button_code & 16 != 0

      # Determine action
      action = if button_code & 32 != 0
                 MouseAction::Drag
               elsif pressed
                 MouseAction::Press
               else
                 MouseAction::Release
               end

      MouseEvent.new(x, y, button, action, modifiers)
    end

    private def modifiers_from_param(param : Int32?) : Modifiers
      return Modifiers::None unless param

      modifiers = Modifiers::None
      # Param is 1 + modifier bits (shift=1, alt=2, ctrl=4)
      code = param - 1
      modifiers |= Modifiers::Shift if code & 1 != 0
      modifiers |= Modifiers::Alt if code & 2 != 0
      modifiers |= Modifiers::Ctrl if code & 4 != 0
      modifiers
    end

    # Extract modifiers from params array
    # Format: ESC [ param1 ; modifier_param X
    # modifier_param is typically params[1], or params.last if multiple params
    private def modifiers_from_params(params : Array(Int32)) : Modifiers
      # If we have 2+ params, modifier is in the last one (typically params[1])
      # Format: ESC [ 1 ; 2 A  means params = [1, 2], modifier = 2
      if params.size >= 2
        modifiers_from_param(params[1])
      else
        Modifiers::None
      end
    end
  end
end
