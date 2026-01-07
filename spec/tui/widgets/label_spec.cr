require "../../spec_helper"

describe Tui::Label do
  describe "#initialize" do
    it "creates label with default values" do
      label = Tui::Label.new
      label.text.should eq ""
      label.align.should eq Tui::Label::Align::Left
    end

    it "creates label with text" do
      label = Tui::Label.new("Hello")
      label.text.should eq "Hello"
    end

    it "creates label with id" do
      label = Tui::Label.new("Test", id: "my-label")
      label.id.should eq "my-label"
    end

    it "creates label with style" do
      style = Tui::Style.new(fg: Tui::Color.red)
      label = Tui::Label.new("Test", style: style)
      label.style.fg.should eq Tui::Color.red
    end

    it "creates label with convenience constructor" do
      label = Tui::Label.new("Test", fg: Tui::Color.green, bold: true)
      label.style.fg.should eq Tui::Color.green
      label.style.attrs.bold?.should be_true
    end

    it "creates label with alignment" do
      label = Tui::Label.new("Test", align: Tui::Label::Align::Center)
      label.align.should eq Tui::Label::Align::Center
    end
  end

  describe "#text=" do
    it "updates text and marks dirty" do
      label = Tui::Label.new("Old")
      label.text = "New"
      label.text.should eq "New"
      label.dirty?.should be_true
    end
  end

  describe "#render" do
    it "renders text at left alignment" do
      buffer = Tui::Buffer.new(20, 3)
      label = Tui::Label.new("Hello", align: Tui::Label::Align::Left)
      label.rect = Tui::Rect.new(0, 0, 20, 1)

      label.render(buffer, label.rect)

      buffer.get(0, 0).char.should eq 'H'
      buffer.get(4, 0).char.should eq 'o'
      buffer.get(5, 0).char.should eq ' '  # padding
    end

    it "renders text at center alignment" do
      buffer = Tui::Buffer.new(20, 3)
      label = Tui::Label.new("Hi", align: Tui::Label::Align::Center)
      label.rect = Tui::Rect.new(0, 0, 10, 1)

      label.render(buffer, label.rect)

      # "Hi" is 2 chars, width is 10, so starts at (10-2)/2 = 4
      buffer.get(3, 0).char.should eq ' '
      buffer.get(4, 0).char.should eq 'H'
      buffer.get(5, 0).char.should eq 'i'
      buffer.get(6, 0).char.should eq ' '
    end

    it "renders text at right alignment" do
      buffer = Tui::Buffer.new(20, 3)
      label = Tui::Label.new("Hi", align: Tui::Label::Align::Right)
      label.rect = Tui::Rect.new(0, 0, 10, 1)

      label.render(buffer, label.rect)

      # "Hi" is 2 chars, width is 10, so starts at 10-2 = 8
      buffer.get(7, 0).char.should eq ' '
      buffer.get(8, 0).char.should eq 'H'
      buffer.get(9, 0).char.should eq 'i'
    end

    it "renders multiline text" do
      buffer = Tui::Buffer.new(20, 5)
      label = Tui::Label.new("Line1\nLine2\nLine3")
      label.rect = Tui::Rect.new(0, 0, 20, 5)

      label.render(buffer, label.rect)

      buffer.get(0, 0).char.should eq 'L'
      buffer.get(4, 0).char.should eq '1'
      buffer.get(0, 1).char.should eq 'L'
      buffer.get(4, 1).char.should eq '2'
      buffer.get(0, 2).char.should eq 'L'
      buffer.get(4, 2).char.should eq '3'
    end

    it "truncates long lines to fit width with ellipsis" do
      buffer = Tui::Buffer.new(10, 1)
      label = Tui::Label.new("This is a very long text")
      label.rect = Tui::Rect.new(0, 0, 5, 1)

      label.render(buffer, label.rect)

      buffer.get(0, 0).char.should eq 'T'
      buffer.get(4, 0).char.should eq '…'  # ellipsis at end
      buffer.get(5, 0).char.should eq ' '  # outside rect, unchanged
    end

    it "truncates long lines with clip mode" do
      buffer = Tui::Buffer.new(10, 1)
      label = Tui::Label.new("This is a very long text")
      label.text_overflow = Tui::Label::TextOverflow::Clip
      label.rect = Tui::Rect.new(0, 0, 5, 1)

      label.render(buffer, label.rect)

      buffer.get(0, 0).char.should eq 'T'
      buffer.get(4, 0).char.should eq ' '  # "This " clipped
    end

    it "truncates lines beyond height" do
      buffer = Tui::Buffer.new(20, 5)
      label = Tui::Label.new("L1\nL2\nL3\nL4\nL5")
      label.rect = Tui::Rect.new(0, 0, 20, 2)  # only 2 lines visible

      label.render(buffer, label.rect)

      buffer.get(0, 0).char.should eq 'L'
      buffer.get(1, 0).char.should eq '1'
      buffer.get(0, 1).char.should eq 'L'
      buffer.get(1, 1).char.should eq '2'
      buffer.get(0, 2).char.should eq ' '  # L3 not rendered
    end

    it "applies style to rendered characters" do
      buffer = Tui::Buffer.new(10, 1)
      style = Tui::Style.new(fg: Tui::Color.yellow)
      label = Tui::Label.new("ABC", style: style)
      label.rect = Tui::Rect.new(0, 0, 10, 1)

      label.render(buffer, label.rect)

      buffer.get(0, 0).style.fg.should eq Tui::Color.yellow
      buffer.get(1, 0).style.fg.should eq Tui::Color.yellow
      buffer.get(2, 0).style.fg.should eq Tui::Color.yellow
    end

    it "does not render when not visible" do
      buffer = Tui::Buffer.new(10, 1)
      label = Tui::Label.new("Hello")
      label.rect = Tui::Rect.new(0, 0, 10, 1)
      label.visible = false

      label.render(buffer, label.rect)

      buffer.get(0, 0).char.should eq ' '  # unchanged
    end

    it "respects clip region" do
      buffer = Tui::Buffer.new(20, 5)
      label = Tui::Label.new("Hello World")
      label.rect = Tui::Rect.new(0, 0, 20, 1)
      clip = Tui::Rect.new(3, 0, 5, 1)  # only show chars 3-7

      # Pre-fill buffer to detect what's NOT rendered
      buffer.draw_string(0, 0, "....................")

      label.render(buffer, clip)

      # "Hello World" = H(0)e(1)l(2)l(3)o(4) (5)W(6)o(7)r(8)l(9)d(10)
      buffer.get(0, 0).char.should eq '.'  # outside clip
      buffer.get(2, 0).char.should eq '.'  # outside clip
      buffer.get(3, 0).char.should eq 'l'  # inside clip (pos 3 = 'l')
      buffer.get(6, 0).char.should eq 'W'  # inside clip (pos 6 = 'W')
      buffer.get(7, 0).char.should eq 'o'  # inside clip (pos 7 = 'o')
      buffer.get(8, 0).char.should eq '.'  # outside clip (clip ends at 3+5=8)
    end

    it "handles empty text" do
      buffer = Tui::Buffer.new(10, 1)
      label = Tui::Label.new("")
      label.rect = Tui::Rect.new(0, 0, 10, 1)

      label.render(buffer, label.rect)  # should not crash
    end

    it "handles empty rect" do
      buffer = Tui::Buffer.new(10, 1)
      label = Tui::Label.new("Hello")
      label.rect = Tui::Rect.new(0, 0, 0, 0)

      label.render(buffer, label.rect)  # should not crash
    end
  end
end
