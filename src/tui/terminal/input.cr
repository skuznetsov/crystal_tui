# Input parsing - keyboard and mouse events (event-driven)
module Tui
  class InputParser
    @buffer : Array(UInt8)
    @event_channel : Channel(Event)
    @running : Bool = false
    @input_fiber : Fiber?
    @input_provider : InputProvider
    @paste_mode : Bool = false
    @paste_buffer : Array(UInt8)
    @pending_events : Array(Event)
    @pending_burst : String
    @pending_burst_at : Time::Instant?
    @pending_burst_chars : Int32 = 0
    @burst_active : Bool = false
    @burst_buffer : String
    @burst_last_at : Time::Instant?
    @burst_window_until : Time::Instant?
    @wakeup_scheduled : Bool = false

    # Byte constants for parsing
    BYTE_0         = '0'.ord.to_u8
    BYTE_9         = '9'.ord.to_u8
    BYTE_SEMICOLON = ';'.ord.to_u8
    BYTE_COLON     = ':'.ord.to_u8
    BYTE_LESS_THAN = '<'.ord.to_u8
    BYTE_UPPER_A   = 'A'.ord.to_u8
    BYTE_UPPER_B   = 'B'.ord.to_u8
    BYTE_UPPER_C   = 'C'.ord.to_u8
    BYTE_UPPER_D   = 'D'.ord.to_u8
    BYTE_UPPER_F   = 'F'.ord.to_u8
    BYTE_UPPER_H   = 'H'.ord.to_u8
    BYTE_UPPER_M   = 'M'.ord.to_u8
    BYTE_UPPER_O   = 'O'.ord.to_u8
    BYTE_UPPER_P   = 'P'.ord.to_u8
    BYTE_UPPER_Q   = 'Q'.ord.to_u8
    BYTE_UPPER_R   = 'R'.ord.to_u8
    BYTE_UPPER_S   = 'S'.ord.to_u8
    BYTE_UPPER_Z   = 'Z'.ord.to_u8
    BYTE_LOWER_M   = 'm'.ord.to_u8
    BYTE_LOWER_U   = 'u'.ord.to_u8
    BYTE_TILDE     = '~'.ord.to_u8
    BYTE_BRACKET   = '['.ord.to_u8
    BYTE_ESC       = 27_u8

    PASTE_END            = [BYTE_ESC, BYTE_BRACKET, '2'.ord.to_u8, '0'.ord.to_u8, '1'.ord.to_u8, BYTE_TILDE]
    BURST_MIN_CHARS      = 3
    BURST_CHAR_INTERVAL  = 8.milliseconds
    BURST_ENTER_SUPPRESS = 120.milliseconds

    def initialize(@input_provider : InputProvider = StdinInputProvider.new)
      @buffer = [] of UInt8
      @event_channel = Channel(Event).new(32) # Buffered channel
      @paste_buffer = [] of UInt8
      @pending_events = [] of Event
      @pending_burst = ""
      @burst_buffer = ""
    end

    property input_provider : InputProvider

    # Feed raw terminal bytes and drain complete events (tests and tooling).
    def feed(data : String) : Array(Event)
      events = [] of Event
      data.each_byte do |byte|
        @buffer << byte
        while event = parse_buffer
          events << event
        end
      end
      events
    end

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

    # Check if there's pending burst data that might need flushing
    def has_pending_burst? : Bool
      @burst_active || !@pending_burst.empty? || !@pending_events.empty?
    end

    # Flush pending paste burst data if due (non-bracketed paste heuristic)
    def flush_paste_burst : Event?
      if event = pop_pending_event
        return event
      end

      now = Time.instant

      if @burst_active && burst_timed_out?(now)
        event = PasteEvent.new(@burst_buffer)
        reset_burst
        return event
      end

      if !@pending_burst.empty? && pending_timed_out?(now)
        enqueue_chars_as_key_events(@pending_burst)
        @pending_burst = ""
        @pending_burst_at = nil
        @pending_burst_chars = 0
        return pop_pending_event
      end

      nil
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

      if event = pop_pending_event
        return event
      end

      if @paste_mode
        return parse_paste_buffer
      end

      # Check for escape sequence
      if @buffer[0] == BYTE_ESC
        if @buffer.size == 1
          # Need more bytes - return nil, wait for input_loop to feed more
          return nil
        end

        second = @buffer[1]
        if second == BYTE_BRACKET || second == BYTE_UPPER_O
          event = parse_escape_sequence
          return handle_non_char_event(event) if event
          return parse_paste_buffer if @paste_mode
          return nil
        end

        # ESC ESC: keep double-escape working (one Escape now, leftover ESC waits).
        if second == BYTE_ESC
          @buffer.shift
          return handle_non_char_event(KeyEvent.new(Key::Escape))
        end

        # ESC + byte is Option/Alt+key in terminals that use Meta as ESC prefix.
        event = parse_escape_sequence
        return handle_non_char_event(event) if event
        return nil
      end

      # Regular character - need to decode UTF-8 properly
      char = decode_utf8_char
      return nil unless char # Need more bytes for multi-byte char
      handle_char(char)
    end

    private def handle_char(char : Char) : Event?
      # Ignore NUL (Ctrl+Space) - used for system keyboard layout switching
      if char.ord == 0
        return nil
      end

      if char == '\r' || char == '\n'
        return handle_enter_char(char)
      end

      if char.ord == 3
        return handle_non_char_event(KeyEvent.new('c', Modifiers::Ctrl))
      end

      if char.printable?
        return handle_plain_char(char)
      end

      handle_non_char_event(KeyEvent.new(char))
    end

    private def handle_plain_char(char : Char) : Event?
      now = Time.instant

      if @burst_active
        append_to_burst(char, now)
        return nil
      end

      if letter = KeyEvent.mac_option_key(char)
        return handle_non_char_event(KeyEvent.new(letter, Modifiers::Alt))
      end

      if @pending_burst.empty?
        @pending_burst = char.to_s
        @pending_burst_at = now
        @pending_burst_chars = 1
        @burst_window_until = now + BURST_ENTER_SUPPRESS
        schedule_wakeup
        return nil
      end

      if @pending_burst_at && now - @pending_burst_at.not_nil! <= BURST_CHAR_INTERVAL
        @pending_burst += char
        @pending_burst_at = now
        @pending_burst_chars += 1
        @burst_window_until = now + BURST_ENTER_SUPPRESS
        start_burst(now) if @pending_burst_chars >= BURST_MIN_CHARS
        return nil
      end

      enqueue_chars_as_key_events(@pending_burst)
      @pending_burst = char.to_s
      @pending_burst_at = now
      @pending_burst_chars = 1
      @burst_window_until = now + BURST_ENTER_SUPPRESS
      schedule_wakeup
      pop_pending_event
    end

    private def handle_enter_char(char : Char) : Event?
      now = Time.instant
      if should_capture_enter?(now)
        append_to_pending_or_burst('\n', now)
        return nil
      end

      flush_all_buffers
      enqueue_event(KeyEvent.new(char))
      pop_pending_event
    end

    private def should_capture_enter?(now : Time::Instant) : Bool
      return true if @burst_active
      if @burst_window_until
        return now <= @burst_window_until.not_nil!
      end
      false
    end

    private def start_burst(now : Time::Instant) : Nil
      return if @pending_burst.empty?
      @burst_active = true
      @burst_buffer = @pending_burst
      @pending_burst = ""
      @pending_burst_at = nil
      @pending_burst_chars = 0
      @burst_last_at = now
      @burst_window_until = now + BURST_ENTER_SUPPRESS
      schedule_wakeup
    end

    private def append_to_burst(char : Char, now : Time::Instant) : Nil
      @burst_buffer += char
      @burst_last_at = now
      @burst_window_until = now + BURST_ENTER_SUPPRESS
      schedule_wakeup
    end

    private def append_to_pending_or_burst(char : Char, now : Time::Instant) : Nil
      if @burst_active
        append_to_burst(char, now)
        return
      end

      @pending_burst += char
      @pending_burst_at = now
      @pending_burst_chars += 1
      @burst_window_until = now + BURST_ENTER_SUPPRESS
      start_burst(now) if @pending_burst_chars >= BURST_MIN_CHARS
    end

    private def handle_non_char_event(event : Event?) : Event?
      return nil unless event

      flush_all_buffers
      enqueue_event(event)
      pop_pending_event
    end

    private def flush_all_buffers : Nil
      if @burst_active
        enqueue_event(PasteEvent.new(@burst_buffer))
        reset_burst
      end

      if !@pending_burst.empty?
        enqueue_chars_as_key_events(@pending_burst)
        @pending_burst = ""
        @pending_burst_at = nil
        @pending_burst_chars = 0
      end

      @burst_window_until = nil
    end

    private def reset_burst : Nil
      @burst_active = false
      @burst_buffer = ""
      @burst_last_at = nil
    end

    # Decode a complete UTF-8 character from buffer
    private def decode_utf8_char : Char?
      return nil if @buffer.empty?

      first = @buffer[0]

      # Determine how many bytes this UTF-8 character needs
      byte_count = if first < 0x80
                     1 # ASCII (0xxxxxxx)
                   elsif first & 0xE0 == 0xC0
                     2 # 2-byte sequence (110xxxxx)
                   elsif first & 0xF0 == 0xE0
                     3 # 3-byte sequence (1110xxxx)
                   elsif first & 0xF8 == 0xF0
                     4 # 4-byte sequence (11110xxx)
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
        @buffer.shift # Remove ESC
        char = @buffer.shift.unsafe_chr
        return KeyEvent.new(char, Modifiers::Alt) # Positional to call char_to_key constructor
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
        # Digits, separators, SGR '<', and kitty colon subfields are valid.
        unless (byte >= BYTE_0 && byte <= BYTE_9) || byte == BYTE_SEMICOLON || byte == BYTE_LESS_THAN || byte == BYTE_COLON
          # Unknown byte in sequence - consume ESC [ and return nil
          @buffer.shift
          @buffer.shift
          return nil
        end
      end

      # If no terminator found yet, wait for more input
      return nil if term_idx == -1

      # Now we have a complete sequence, consume it
      @buffer.shift # ESC
      @buffer.shift # [

      # Check for mouse event (SGR format: <button;x;y;M or m)
      if @buffer[0]? == BYTE_LESS_THAN
        return parse_sgr_mouse
      end

      # Collect parameters and final byte. Kitty CSI u uses colon subfields:
      #   CSI key:shifted:base ; modifiers:event-type ; text u
      params = [] of Int32
      current = 0
      event_type = 1
      skip_subfield = false
      read_event_type = false

      while !@buffer.empty?
        byte = @buffer.shift

        if byte >= BYTE_0 && byte <= BYTE_9
          digit = (byte - BYTE_0).to_i32
          if read_event_type
            event_type = event_type * 10 + digit
          elsif skip_subfield
            # Ignore shifted/base/text subfields; the first number is the key.
          else
            current = current * 10 + digit
          end
        elsif byte == BYTE_COLON
          if params.size == 1 && !skip_subfield && !read_event_type
            read_event_type = true
            event_type = 0
          else
            skip_subfield = true
            read_event_type = false
          end
        elsif byte == BYTE_SEMICOLON
          params << current
          current = 0
          skip_subfield = false
          read_event_type = false
        elsif byte == BYTE_UPPER_A # Up
          params << current
          return csi_event_unless_release(event_type, KeyEvent.new(Key::Up, modifiers_from_params(params)))
        elsif byte == BYTE_UPPER_B # Down
          params << current
          return csi_event_unless_release(event_type, KeyEvent.new(Key::Down, modifiers_from_params(params)))
        elsif byte == BYTE_UPPER_C # Right
          params << current
          return csi_event_unless_release(event_type, KeyEvent.new(Key::Right, modifiers_from_params(params)))
        elsif byte == BYTE_UPPER_D # Left
          params << current
          return csi_event_unless_release(event_type, KeyEvent.new(Key::Left, modifiers_from_params(params)))
        elsif byte == BYTE_UPPER_H # Home
          params << current
          return csi_event_unless_release(event_type, KeyEvent.new(Key::Home, modifiers_from_params(params)))
        elsif byte == BYTE_UPPER_F # End
          params << current
          return csi_event_unless_release(event_type, KeyEvent.new(Key::End, modifiers_from_params(params)))
        elsif byte == BYTE_UPPER_P # F1 (with modifiers, CSI format)
          params << current
          return csi_event_unless_release(event_type, KeyEvent.new(Key::F1, modifiers_from_params(params)))
        elsif byte == BYTE_UPPER_Q # F2 (with modifiers, CSI format)
          params << current
          return csi_event_unless_release(event_type, KeyEvent.new(Key::F2, modifiers_from_params(params)))
        elsif byte == BYTE_UPPER_R # F3 (with modifiers, CSI format)
          params << current
          return csi_event_unless_release(event_type, KeyEvent.new(Key::F3, modifiers_from_params(params)))
        elsif byte == BYTE_UPPER_S # F4 (with modifiers, CSI format)
          params << current
          return csi_event_unless_release(event_type, KeyEvent.new(Key::F4, modifiers_from_params(params)))
        elsif byte == BYTE_TILDE
          params << current
          return csi_event_unless_release(event_type, parse_tilde_sequence(params))
        elsif byte == BYTE_LOWER_U
          params << current
          return csi_event_unless_release(event_type, parse_csi_u_sequence(params))
        elsif byte == BYTE_UPPER_Z
          params << current
          mods = modifiers_from_params(params)
          mods |= Modifiers::Shift
          return csi_event_unless_release(event_type, KeyEvent.new(Key::Tab, mods, '\t'))
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

      @buffer.shift # ESC
      @buffer.shift # O

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
      first = params[0]?
      mods = modifiers_from_param(params[1]?)

      case first
      when 200
        start_paste_mode
        return nil
      when 201
        return nil
      when 1
        KeyEvent.new(Key::Home, mods)
      when 2
        KeyEvent.new(Key::Insert, mods)
      when 3
        KeyEvent.new(Key::Delete, mods)
      when 4
        KeyEvent.new(Key::End, mods)
      when 5
        KeyEvent.new(Key::PageUp, mods)
      when 6
        KeyEvent.new(Key::PageDown, mods)
      when 13
        # Some terminals encode Shift+Enter as CSI 13 ; modifier ~
        KeyEvent.new(Key::Enter, mods, '\r')
      when 15
        KeyEvent.new(Key::F5, mods)
      when 17
        KeyEvent.new(Key::F6, mods)
      when 18
        KeyEvent.new(Key::F7, mods)
      when 19
        KeyEvent.new(Key::F8, mods)
      when 20
        KeyEvent.new(Key::F9, mods)
      when 21
        KeyEvent.new(Key::F10, mods)
      when 23
        KeyEvent.new(Key::F11, mods)
      when 24
        KeyEvent.new(Key::F12, mods)
      when 27
        # xterm modifyOtherKeys: CSI 27 ; modifier ; key ~
        keycode = params[2]?
        return nil unless keycode
        key_event_from_codepoint(keycode, mods)
      else
        nil
      end
    end

    private def parse_csi_u_sequence(params : Array(Int32)) : Event?
      codepoint = params[0]?
      return nil unless codepoint

      mods = params.size >= 2 ? modifiers_from_param(params[1]) : Modifiers::None
      key_event_from_codepoint(codepoint, mods)
    end

    private def key_event_from_codepoint(code : Int32, modifiers : Modifiers) : Event?
      case code
      when 9
        KeyEvent.new(Key::Tab, modifiers, '\t')
      when 10
        KeyEvent.new(Key::Enter, modifiers, '\n')
      when 13
        KeyEvent.new(Key::Enter, modifiers, '\r')
      when 27
        KeyEvent.new(Key::Escape, modifiers, '\e')
      when 8, 127
        KeyEvent.new(Key::Backspace, modifiers)
      when 32
        KeyEvent.new(Key::Space, modifiers, ' ')
      else
        return nil if code < 0 || code > 0x10FFFF
        return nil if code >= 0xD800 && code <= 0xDFFF

        char = code.chr
        if !modifiers.ctrl? && (letter = KeyEvent.mac_option_key(char))
          return KeyEvent.new(letter, modifiers | Modifiers::Alt)
        end
        KeyEvent.new(char, modifiers)
      end
    end

    private def csi_event_unless_release(event_type : Int32, event : Event?) : Event?
      return nil if event_type == 3
      event
    end

    # Parse SGR extended mouse format: <button;x;y;M (press) or m (release)
    private def parse_sgr_mouse : Event?
      @buffer.shift # Remove '<'

      params = [] of Int32
      current = 0

      while !@buffer.empty?
        byte = @buffer.shift

        if byte >= BYTE_0 && byte <= BYTE_9
          current = current * 10 + (byte - BYTE_0).to_i32
        elsif byte == BYTE_SEMICOLON
          params << current
          current = 0
        elsif byte == BYTE_UPPER_M # Press
          params << current
          return create_mouse_event(params, pressed: true)
        elsif byte == BYTE_LOWER_M # Release
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
      nil # TODO: implement if needed
    end

    private def create_mouse_event(params : Array(Int32), pressed : Bool) : MouseEvent?
      return nil if params.size < 3

      button_code = params[0]
      x = params[1] - 1 # 1-indexed to 0-indexed
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

    private def start_paste_mode : Nil
      flush_all_buffers
      @paste_mode = true
      @paste_buffer.clear
    end

    private def parse_paste_buffer : Event?
      return nil if @buffer.empty? && @paste_buffer.empty?

      if end_idx = find_sequence(@buffer, PASTE_END)
        end_idx.times { @paste_buffer << @buffer.shift }
        PASTE_END.size.times { @buffer.shift }

        bytes = Slice(UInt8).new(@paste_buffer.size) { |i| @paste_buffer[i] }
        text = String.new(bytes)

        @paste_buffer.clear
        @paste_mode = false
        return handle_non_char_event(PasteEvent.new(text))
      end

      keep = PASTE_END.size - 1
      if @buffer.size > keep
        move_count = @buffer.size - keep
        move_count.times { @paste_buffer << @buffer.shift }
      end

      nil
    end

    private def find_sequence(buffer : Array(UInt8), sequence : Array(UInt8)) : Int32?
      max_start = buffer.size - sequence.size
      return nil if max_start < 0

      (0..max_start).each do |i|
        matched = true
        sequence.size.times do |j|
          if buffer[i + j] != sequence[j]
            matched = false
            break
          end
        end
        return i if matched
      end

      nil
    end

    private def burst_timed_out?(now : Time::Instant) : Bool
      return false unless @burst_last_at
      now - @burst_last_at.not_nil! > BURST_CHAR_INTERVAL
    end

    private def pending_timed_out?(now : Time::Instant) : Bool
      return false unless @pending_burst_at
      now - @pending_burst_at.not_nil! > BURST_CHAR_INTERVAL
    end

    private def enqueue_event(event : Event) : Nil
      @pending_events << event
    end

    private def enqueue_chars_as_key_events(text : String) : Nil
      text.each_char do |char|
        @pending_events << KeyEvent.new(char)
      end
    end

    private def pop_pending_event : Event?
      return nil if @pending_events.empty?
      @pending_events.shift
    end

    # Schedule a wakeup event to flush pending chars after timeout
    private def schedule_wakeup : Nil
      return if @wakeup_scheduled
      @wakeup_scheduled = true

      spawn do
        sleep BURST_CHAR_INTERVAL + 1.milliseconds
        @wakeup_scheduled = false
        # If there's still pending data, send wakeup to trigger flush
        if !@pending_burst.empty? || @burst_active
          @event_channel.send(WakeupEvent.new) rescue nil
        end
      end
    end
  end
end
