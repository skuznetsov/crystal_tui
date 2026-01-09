# Input provider abstraction for testability
module Tui
  # Abstract input provider - can be real keyboard or mock
  abstract class InputProvider
    abstract def read_byte : UInt8?
    abstract def start : Nil
    abstract def stop : Nil
  end

  # Real input from STDIN
  class StdinInputProvider < InputProvider
    def read_byte : UInt8?
      STDIN.read_byte
    end

    def start : Nil
      # Nothing to do for real STDIN
    end

    def stop : Nil
      # Nothing to do for real STDIN
    end
  end

  # Mock input for testing - reads from a queue
  class MockInputProvider < InputProvider
    @queue : Array(UInt8)
    @event_queue : Array(Event)
    @blocking : Bool

    def initialize(@blocking : Bool = false)
      @queue = [] of UInt8
      @event_queue = [] of Event
    end

    # Add raw bytes to the queue
    def push_bytes(bytes : Array(UInt8)) : Nil
      @queue.concat(bytes)
    end

    def push_bytes(*bytes : UInt8) : Nil
      bytes.each { |b| @queue << b }
    end

    # Add a string (converted to bytes)
    def push_string(str : String) : Nil
      str.bytes.each { |b| @queue << b }
    end

    # Add escape sequence for a key
    def push_key(key : Key, modifiers : Modifiers = Modifiers::None) : Nil
      case key
      when .escape?
        @queue << 27_u8
      when .enter?
        @queue << 13_u8
      when .tab?
        @queue << 9_u8
      when .backspace?
        @queue << 127_u8
      when .up?
        push_csi_arrow('A', modifiers)
      when .down?
        push_csi_arrow('B', modifiers)
      when .right?
        push_csi_arrow('C', modifiers)
      when .left?
        push_csi_arrow('D', modifiers)
      when .home?
        @queue << 27_u8 << '['.ord.to_u8 << 'H'.ord.to_u8
      when .end?
        @queue << 27_u8 << '['.ord.to_u8 << 'F'.ord.to_u8
      when .page_up?
        @queue << 27_u8 << '['.ord.to_u8 << '5'.ord.to_u8 << '~'.ord.to_u8
      when .page_down?
        @queue << 27_u8 << '['.ord.to_u8 << '6'.ord.to_u8 << '~'.ord.to_u8
      when .delete?
        @queue << 27_u8 << '['.ord.to_u8 << '3'.ord.to_u8 << '~'.ord.to_u8
      when .insert?
        @queue << 27_u8 << '['.ord.to_u8 << '2'.ord.to_u8 << '~'.ord.to_u8
      when .f1?
        @queue << 27_u8 << 'O'.ord.to_u8 << 'P'.ord.to_u8
      when .f2?
        @queue << 27_u8 << 'O'.ord.to_u8 << 'Q'.ord.to_u8
      when .f3?
        @queue << 27_u8 << 'O'.ord.to_u8 << 'R'.ord.to_u8
      when .f4?
        @queue << 27_u8 << 'O'.ord.to_u8 << 'S'.ord.to_u8
      when .f5?
        @queue << 27_u8 << '['.ord.to_u8 << '1'.ord.to_u8 << '5'.ord.to_u8 << '~'.ord.to_u8
      when .f6?
        @queue << 27_u8 << '['.ord.to_u8 << '1'.ord.to_u8 << '7'.ord.to_u8 << '~'.ord.to_u8
      when .f7?
        @queue << 27_u8 << '['.ord.to_u8 << '1'.ord.to_u8 << '8'.ord.to_u8 << '~'.ord.to_u8
      when .f8?
        @queue << 27_u8 << '['.ord.to_u8 << '1'.ord.to_u8 << '9'.ord.to_u8 << '~'.ord.to_u8
      when .f9?
        @queue << 27_u8 << '['.ord.to_u8 << '2'.ord.to_u8 << '0'.ord.to_u8 << '~'.ord.to_u8
      when .f10?
        @queue << 27_u8 << '['.ord.to_u8 << '2'.ord.to_u8 << '1'.ord.to_u8 << '~'.ord.to_u8
      when .f11?
        @queue << 27_u8 << '['.ord.to_u8 << '2'.ord.to_u8 << '3'.ord.to_u8 << '~'.ord.to_u8
      when .f12?
        @queue << 27_u8 << '['.ord.to_u8 << '2'.ord.to_u8 << '4'.ord.to_u8 << '~'.ord.to_u8
      end
    end

    # Add a character (with optional ctrl modifier)
    def push_char(char : Char, modifiers : Modifiers = Modifiers::None) : Nil
      if modifiers.ctrl?
        # Ctrl+A = 1, Ctrl+B = 2, etc.
        if char >= 'a' && char <= 'z'
          @queue << (char.ord - 'a'.ord + 1).to_u8
        elsif char >= 'A' && char <= 'Z'
          @queue << (char.ord - 'A'.ord + 1).to_u8
        end
      elsif modifiers.alt?
        @queue << 27_u8
        char.to_s.bytes.each { |b| @queue << b }
      else
        char.to_s.bytes.each { |b| @queue << b }
      end
    end

    # Add mouse event
    def push_mouse(x : Int32, y : Int32, button : MouseButton, action : MouseAction) : Nil
      # SGR format: ESC [ < button ; x+1 ; y+1 ; M/m
      @queue << 27_u8 << '['.ord.to_u8 << '<'.ord.to_u8

      button_code = case button
                    when .left?      then 0
                    when .middle?    then 1
                    when .right?     then 2
                    when .wheel_up?   then 64
                    when .wheel_down? then 65
                    else                  0
                    end

      button_code |= 32 if action.drag?

      "#{button_code};#{x + 1};#{y + 1}".bytes.each { |b| @queue << b }
      @queue << (action.release? ? 'm'.ord.to_u8 : 'M'.ord.to_u8)
    end

    def read_byte : UInt8?
      if @queue.empty?
        if @blocking
          # In blocking mode, wait (sleep) until queue has data
          while @queue.empty?
            sleep 10.milliseconds
          end
        else
          return nil
        end
      end
      @queue.shift
    end

    def start : Nil
      # Nothing to do for mock
    end

    def stop : Nil
      @queue.clear
    end

    def empty? : Bool
      @queue.empty?
    end

    def size : Int32
      @queue.size
    end

    private def push_csi_arrow(letter : Char, modifiers : Modifiers) : Nil
      @queue << 27_u8 << '['.ord.to_u8
      if modifiers != Modifiers::None
        mod_code = 1
        mod_code += 1 if modifiers.shift?
        mod_code += 2 if modifiers.alt?
        mod_code += 4 if modifiers.ctrl?
        "1;#{mod_code}".bytes.each { |b| @queue << b }
      end
      @queue << letter.ord.to_u8
    end
  end
end
