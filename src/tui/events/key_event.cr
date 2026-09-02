# Keyboard event
module Tui
  class KeyEvent < Event
    getter key : Key
    getter char : Char?
    getter modifiers : Modifiers

    def initialize(
      @key : Key = Key::Unknown,
      @modifiers : Modifiers = Modifiers::None,
      @char : Char? = nil,
    )
    end

    def initialize(char : Char, @modifiers : Modifiers = Modifiers::None)
      @char = char
      @key = char_to_key(char)
    end

    # Check if this is a printable character
    def printable? : Bool
      if c = @char
        c.printable? && @key == Key::Unknown
      else
        false
      end
    end

    # Check modifiers
    def shift? : Bool
      @modifiers.shift?
    end

    def alt? : Bool
      @modifiers.alt?
    end

    def ctrl? : Bool
      @modifiers.ctrl?
    end

    def meta? : Bool
      @modifiers.meta?
    end

    # macOS Option+key often arrives as a composed Unicode character with no
    # Alt bit, unless the terminal maps Option to Meta/Esc+.
    def self.mac_option_key(char : Char) : Char?
      case char
      when 'å' then 'a'
      when '∫' then 'b'
      when 'ç' then 'c'
      when '∂' then 'd'
      when 'ƒ' then 'f'
      when '©' then 'g'
      when '˙' then 'h'
      when '∆' then 'j'
      when '˚' then 'k'
      when '¬' then 'l'
      when 'µ' then 'm'
      when 'ø' then 'o'
      when 'π' then 'p'
      when 'œ' then 'q'
      when '®' then 'r'
      when 'ß' then 's'
      when '†' then 't'
      when '√' then 'v'
      when '∑' then 'w'
      when '≈' then 'x'
      when '¥' then 'y'
      when 'Ω' then 'z'
      when '¡' then '1'
      when '™' then '2'
      when '£' then '3'
      when '¢' then '4'
      when '∞' then '5'
      when '§' then '6'
      when '¶' then '7'
      when '•' then '8'
      when 'ª' then '9'
      when 'º' then '0'
      when '÷' then '/'
      when '“' then '['
      when '‘' then ']'
      else          nil
      end
    end

    # Match against key string like "ctrl+s", "f5", "enter"
    def matches?(key_string : String) : Bool
      parts = key_string.downcase.split('+')
      target_key = parts.pop
      target_mods = Modifiers::None

      parts.each do |mod|
        case mod
        when "ctrl"                 then target_mods |= Modifiers::Ctrl
        when "alt", "option", "opt" then target_mods |= Modifiers::Alt
        when "shift"                then target_mods |= Modifiers::Shift
        when "meta"                 then target_mods |= Modifiers::Meta
        end
      end

      # Special handling for ctrl+letter: terminals send control characters directly
      # without setting the Ctrl modifier. Ctrl+A = '\u0001', Ctrl+Z = '\u001A'
      if target_mods.ctrl? && !target_mods.alt? && !target_mods.shift? && target_key.size == 1
        if char = @char
          ctrl_char_code = target_key[0].ord - 'a'.ord + 1
          if char.ord == ctrl_char_code && @modifiers == Modifiers::None
            return true
          end
        end
      end

      # Option+letter on macOS: ƒ for Option+F, etc.
      if target_mods.alt? && !target_mods.ctrl? && !target_mods.shift? && target_key.size == 1
        if char = @char
          if @modifiers == Modifiers::None && KeyEvent.mac_option_key(char) == target_key[0]
            return true
          end
        end
      end

      return false unless @modifiers == target_mods

      case target_key
      when "enter", "return" then @key == Key::Enter || @char == '\r' || @char == '\n'
      when "tab"             then @key == Key::Tab || @char == '\t'
      when "backspace"       then @key == Key::Backspace || @char == '\u007f'
      when "escape", "esc"   then @key == Key::Escape || @char == '\e'
      when "space"           then @key == Key::Space || @char == ' '
      when "up"              then @key == Key::Up
      when "down"            then @key == Key::Down
      when "left"            then @key == Key::Left
      when "right"           then @key == Key::Right
      when "home"            then @key == Key::Home
      when "end"             then @key == Key::End
      when "pageup"          then @key == Key::PageUp
      when "pagedown"        then @key == Key::PageDown
      when "insert"          then @key == Key::Insert
      when "delete"          then @key == Key::Delete
      when "f1"              then @key == Key::F1
      when "f2"              then @key == Key::F2
      when "f3"              then @key == Key::F3
      when "f4"              then @key == Key::F4
      when "f5"              then @key == Key::F5
      when "f6"              then @key == Key::F6
      when "f7"              then @key == Key::F7
      when "f8"              then @key == Key::F8
      when "f9"              then @key == Key::F9
      when "f10"             then @key == Key::F10
      when "f11"             then @key == Key::F11
      when "f12"             then @key == Key::F12
      else
        # Single character
        if target_key.size == 1
          @char.try(&.downcase) == target_key[0]
        else
          false
        end
      end
    end

    private def char_to_key(char : Char) : Key
      case char
      when '\r', '\n' then Key::Enter
      when '\t'       then Key::Tab
      when '\u007f'   then Key::Backspace # DEL
      when '\b'       then Key::Backspace # BS
      when '\e'       then Key::Escape
      when ' '        then Key::Space
      else                 Key::Unknown
      end
    end
  end
end
