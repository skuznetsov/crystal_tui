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
end
