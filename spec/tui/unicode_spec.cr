require "../spec_helper"

describe Tui::Unicode do
  describe ".char_width" do
    it "returns 1 for ASCII characters" do
      Tui::Unicode.char_width('a').should eq 1
      Tui::Unicode.char_width('Z').should eq 1
      Tui::Unicode.char_width('0').should eq 1
      Tui::Unicode.char_width(' ').should eq 1
      Tui::Unicode.char_width('~').should eq 1
    end

    it "returns 0 for control characters" do
      Tui::Unicode.char_width('\t').should eq 0
      Tui::Unicode.char_width('\n').should eq 0
      Tui::Unicode.char_width('\r').should eq 0
      Tui::Unicode.char_width('\0').should eq 0
    end

    it "returns 2 for CJK characters" do
      Tui::Unicode.char_width('中').should eq 2
      Tui::Unicode.char_width('日').should eq 2
      Tui::Unicode.char_width('本').should eq 2
      Tui::Unicode.char_width('語').should eq 2
    end

    it "returns 2 for Japanese hiragana/katakana" do
      Tui::Unicode.char_width('あ').should eq 2
      Tui::Unicode.char_width('ア').should eq 2
    end

    it "returns 2 for Korean hangul" do
      Tui::Unicode.char_width('한').should eq 2
      Tui::Unicode.char_width('글').should eq 2
    end

    it "returns 2 for fullwidth forms" do
      Tui::Unicode.char_width('Ａ').should eq 2  # Fullwidth A
      Tui::Unicode.char_width('１').should eq 2  # Fullwidth 1
    end

    it "returns 2 for common emoji" do
      Tui::Unicode.char_width('😀').should eq 2
      Tui::Unicode.char_width('🎉').should eq 2
      Tui::Unicode.char_width('💬').should eq 2  # Speech balloon
      Tui::Unicode.char_width('📁').should eq 2  # Folder
    end

    it "returns 2 for emoji-style symbols in the dingbats range" do
      Tui::Unicode.char_width('⚡').should eq 2
      Tui::Unicode.char_width('✅').should eq 2
      Tui::Unicode.char_width('☀').should eq 2
    end

    it "returns 0 for combining characters" do
      Tui::Unicode.char_width('\u0301').should eq 0  # Combining acute accent
      Tui::Unicode.char_width('\u0308').should eq 0  # Combining diaeresis
    end

    it "returns 1 for standard Latin extended" do
      Tui::Unicode.char_width('é').should eq 1
      Tui::Unicode.char_width('ñ').should eq 1
      Tui::Unicode.char_width('ü').should eq 1
    end

    it "returns 1 for Cyrillic" do
      Tui::Unicode.char_width('А').should eq 1
      Tui::Unicode.char_width('Я').should eq 1
      Tui::Unicode.char_width('ы').should eq 1
    end

    it "returns 1 for box drawing characters" do
      Tui::Unicode.char_width('─').should eq 1
      Tui::Unicode.char_width('│').should eq 1
      Tui::Unicode.char_width('┌').should eq 1
    end
  end

  describe ".display_width" do
    it "returns length for ASCII strings" do
      Tui::Unicode.display_width("Hello").should eq 5
      Tui::Unicode.display_width("World!").should eq 6
    end

    it "counts wide characters as 2" do
      Tui::Unicode.display_width("中文").should eq 4
      Tui::Unicode.display_width("日本語").should eq 6
    end

    it "handles mixed ASCII and wide characters" do
      Tui::Unicode.display_width("Hello中文").should eq 9  # 5 + 4
      Tui::Unicode.display_width("A中B").should eq 4       # 1 + 2 + 1
    end

    it "handles emoji" do
      Tui::Unicode.display_width("Hi😀").should eq 4  # 2 + 2
    end

    it "handles emoji presentation sequences" do
      # Heart + VS16 should render as emoji (width 2)
      Tui::Unicode.display_width("❤️").should eq 2
    end

    it "returns 0 for empty string" do
      Tui::Unicode.display_width("").should eq 0
    end

    it "ignores combining characters" do
      # e + combining acute = 1 display width
      Tui::Unicode.display_width("e\u0301").should eq 1
    end
  end

  describe ".truncate" do
    it "returns string unchanged if within width" do
      Tui::Unicode.truncate("Hello", 10).should eq "Hello"
    end

    it "truncates ASCII string with ellipsis" do
      Tui::Unicode.truncate("Hello World", 8).should eq "Hello W…"
    end

    it "truncates at character boundary, not byte boundary" do
      Tui::Unicode.truncate("日本語テスト", 7).should eq "日本語…"
    end

    it "handles custom suffix" do
      Tui::Unicode.truncate("Hello World", 8, "...").should eq "Hello..."
    end

    it "handles empty suffix" do
      Tui::Unicode.truncate("Hello World", 5, "").should eq "Hello"
    end

    it "returns suffix only if width too small" do
      Tui::Unicode.truncate("Hello", 1).should eq "…"
    end

    it "handles mixed content" do
      result = Tui::Unicode.truncate("Hello中文World", 10)
      Tui::Unicode.display_width(result).should be <= 10
    end

    it "doesn't leave half a wide character" do
      # If we have "中" (width 2) and max_width allows only 1 more,
      # we shouldn't output half a character
      result = Tui::Unicode.truncate("A中B", 3, "")
      # "A" (1) + "中" (2) = 3, so "A中" should fit
      result.should eq "A中"

      result2 = Tui::Unicode.truncate("A中B", 2, "")
      # Only "A" (1) fits, "中" (2) would overflow
      result2.should eq "A"
    end
  end
end
