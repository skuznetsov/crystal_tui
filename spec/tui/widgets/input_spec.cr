require "../../spec_helper"

describe Tui::Input do
  describe "#render" do
    it "places text and cursor by display width for wide characters" do
      buffer = Tui::Buffer.new(12, 1)
      input = Tui::Input.new("A中B")
      input.rect = Tui::Rect.new(0, 0, 10, 1)
      input.focus

      input.render(buffer, input.rect)

      buffer.get(1, 0).char.should eq('A')
      buffer.get(2, 0).char.should eq('中')
      buffer.get(2, 0).wide?.should be_true
      buffer.get(3, 0).continuation?.should be_true
      buffer.get(4, 0).char.should eq('B')
      buffer.get(5, 0).style.bg.should eq(Tui::Color.white)
    end

    it "does not draw half of a wide character at the visible boundary" do
      buffer = Tui::Buffer.new(8, 1)
      input = Tui::Input.new("AB中")
      input.rect = Tui::Rect.new(0, 0, 5, 1)
      input.focus
      input.on_event(Tui::MouseEvent.new(1, 0, action: Tui::MouseAction::Press))

      input.render(buffer, input.rect)

      buffer.get(1, 0).char.should eq('A')
      buffer.get(2, 0).char.should eq('B')
      buffer.get(3, 0).char.should eq(' ')
      buffer.get(4, 0).char.should eq(' ')
    end
  end

  describe "#on_event" do
    it "maps mouse clicks to character index by display column" do
      input = Tui::Input.new("A中B")
      input.rect = Tui::Rect.new(0, 0, 10, 1)
      input.focus

      event = Tui::MouseEvent.new(4, 0, Tui::MouseButton::Left, Tui::MouseAction::Press)
      input.on_event(event).should be_true

      buffer = Tui::Buffer.new(12, 1)
      input.render(buffer, input.rect)

      buffer.get(4, 0).style.bg.should eq(Tui::Color.white)
      buffer.get(4, 0).char.should eq('B')
    end
  end

  describe "#initialize" do
    it "creates input with default value" do
      input = Tui::Input.new
      input.value.should eq("")
    end

    it "creates input with initial value" do
      input = Tui::Input.new("hello")
      input.value.should eq("hello")
    end

    it "accepts an id" do
      input = Tui::Input.new(id: "search")
      input.id.should eq("search")
    end

    it "is focusable" do
      input = Tui::Input.new
      input.focusable?.should be_true
    end
  end

  describe "printable character input" do
    it "inserts ASCII letters" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('a'))
      input.on_event(Tui::KeyEvent.new('b'))
      input.on_event(Tui::KeyEvent.new('c'))
      input.value.should eq("abc")
    end

    it "inserts ASCII digits" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('1'))
      input.on_event(Tui::KeyEvent.new('2'))
      input.on_event(Tui::KeyEvent.new('3'))
      input.value.should eq("123")
    end

    it "inserts ASCII punctuation" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('!'))
      input.on_event(Tui::KeyEvent.new('@'))
      input.value.should eq("!@")
    end

    it "inserts Unicode Cyrillic characters" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('п'))
      input.on_event(Tui::KeyEvent.new('р'))
      input.value.should eq("пр")
    end

    it "inserts mixed ASCII and Unicode" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('h'))
      input.on_event(Tui::KeyEvent.new('и'))
      input.value.should eq("hи")
    end

    it "does not insert carriage return" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('\r'))
      input.value.should eq("")
    end

    it "does not insert newline" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('\n'))
      input.value.should eq("")
    end

    it "does not insert tab" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('\t'))
      input.value.should eq("")
    end

    it "does not insert escape" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('\e'))
      input.value.should eq("")
    end

    it "does not insert DEL" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('\u007f'))
      input.value.should eq("")
    end
  end

  describe "cursor management" do
    it "advances cursor after each character" do
      input = Tui::Input.new
      input.focused = true
      input.on_event(Tui::KeyEvent.new('п'))
      input.on_event(Tui::KeyEvent.new('р'))
      input.on_event(Tui::KeyEvent.new('и'))
      input.value.should eq("при")
    end
  end

  describe "on_change callback" do
    it "fires on_change when ASCII character inserted" do
      input = Tui::Input.new
      input.focused = true
      last_value = ""
      input.on_change { |v| last_value = v }
      input.on_event(Tui::KeyEvent.new('x'))
      last_value.should eq("x")
    end

    it "fires on_change when Unicode character inserted" do
      input = Tui::Input.new
      input.focused = true
      last_value = ""
      input.on_change { |v| last_value = v }
      input.on_event(Tui::KeyEvent.new('п'))
      last_value.should eq("п")
    end
  end
end
