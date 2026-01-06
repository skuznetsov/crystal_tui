# Unicode display width utilities
# Based on Unicode Standard Annex #11 (East Asian Width)
module Tui
  module Unicode
    # Get display width of a single character
    def self.char_width(char : Char) : Int32
      codepoint = char.ord

      # Control characters and combining marks: 0 width
      return 0 if codepoint < 0x20                    # Control chars
      return 0 if codepoint >= 0x7F && codepoint < 0xA0  # More control chars
      return 0 if combining?(codepoint)

      # Wide characters: 2 width
      return 2 if wide?(codepoint)

      # Default: 1 width
      1
    end

    # Get display width of a string
    def self.display_width(text : String) : Int32
      text.each_char.sum { |c| char_width(c) }
    end

    # Truncate string to fit display width, adding suffix if truncated
    def self.truncate(text : String, max_width : Int32, suffix : String = "…") : String
      return text if display_width(text) <= max_width

      suffix_width = display_width(suffix)
      return suffix if max_width <= suffix_width

      target_width = max_width - suffix_width
      result = String.build do |s|
        current_width = 0
        text.each_char do |c|
          char_w = char_width(c)
          break if current_width + char_w > target_width
          s << c
          current_width += char_w
        end
        s << suffix
      end
      result
    end

    # Check if codepoint is a combining character (zero width)
    private def self.combining?(codepoint : Int32) : Bool
      # Combining Diacritical Marks
      return true if codepoint >= 0x0300 && codepoint <= 0x036F
      # Combining Diacritical Marks Extended
      return true if codepoint >= 0x1AB0 && codepoint <= 0x1AFF
      # Combining Diacritical Marks Supplement
      return true if codepoint >= 0x1DC0 && codepoint <= 0x1DFF
      # Combining Diacritical Marks for Symbols
      return true if codepoint >= 0x20D0 && codepoint <= 0x20FF
      # Combining Half Marks
      return true if codepoint >= 0xFE20 && codepoint <= 0xFE2F

      false
    end

    # Check if codepoint is a wide character (2 columns)
    private def self.wide?(codepoint : Int32) : Bool
      # CJK Radicals Supplement
      return true if codepoint >= 0x2E80 && codepoint <= 0x2EFF
      # Kangxi Radicals
      return true if codepoint >= 0x2F00 && codepoint <= 0x2FDF
      # CJK Symbols and Punctuation
      return true if codepoint >= 0x3000 && codepoint <= 0x303F
      # Hiragana
      return true if codepoint >= 0x3040 && codepoint <= 0x309F
      # Katakana
      return true if codepoint >= 0x30A0 && codepoint <= 0x30FF
      # Bopomofo
      return true if codepoint >= 0x3100 && codepoint <= 0x312F
      # Hangul Compatibility Jamo
      return true if codepoint >= 0x3130 && codepoint <= 0x318F
      # Kanbun
      return true if codepoint >= 0x3190 && codepoint <= 0x319F
      # Bopomofo Extended
      return true if codepoint >= 0x31A0 && codepoint <= 0x31BF
      # CJK Strokes
      return true if codepoint >= 0x31C0 && codepoint <= 0x31EF
      # Katakana Phonetic Extensions
      return true if codepoint >= 0x31F0 && codepoint <= 0x31FF
      # Enclosed CJK Letters and Months
      return true if codepoint >= 0x3200 && codepoint <= 0x32FF
      # CJK Compatibility
      return true if codepoint >= 0x3300 && codepoint <= 0x33FF
      # CJK Unified Ideographs Extension A
      return true if codepoint >= 0x3400 && codepoint <= 0x4DBF
      # CJK Unified Ideographs
      return true if codepoint >= 0x4E00 && codepoint <= 0x9FFF
      # Yi Syllables
      return true if codepoint >= 0xA000 && codepoint <= 0xA48F
      # Yi Radicals
      return true if codepoint >= 0xA490 && codepoint <= 0xA4CF
      # Hangul Syllables
      return true if codepoint >= 0xAC00 && codepoint <= 0xD7AF
      # CJK Compatibility Ideographs
      return true if codepoint >= 0xF900 && codepoint <= 0xFAFF
      # Fullwidth Forms
      return true if codepoint >= 0xFF00 && codepoint <= 0xFF60
      return true if codepoint >= 0xFFE0 && codepoint <= 0xFFE6
      # CJK Unified Ideographs Extension B-F
      return true if codepoint >= 0x20000 && codepoint <= 0x2FA1F

      # Common emoji ranges (simplified - many emoji are 2 wide)
      return true if codepoint >= 0x1F300 && codepoint <= 0x1F9FF  # Misc Symbols, Emoticons, etc.
      return true if codepoint >= 0x2600 && codepoint <= 0x26FF   # Misc Symbols
      return true if codepoint >= 0x2700 && codepoint <= 0x27BF   # Dingbats

      false
    end
  end
end
