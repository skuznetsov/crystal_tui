require "../../spec_helper"

describe Tui::TextEditor do
  it "takes focus on left click when unfocused" do
    Tui::Widget.focused_widget = nil
    editor = Tui::TextEditor.new("mouse-focus")
    editor.rect = Tui::Rect.new(0, 0, 40, 10)
    editor.text = "line1\nline2\nline3\n"
    editor.focused?.should be_false

    event = Tui::MouseEvent.new(10, 2, Tui::MouseButton::Left, Tui::MouseAction::Press)
    editor.handle_event(event).should be_true
    editor.focused?.should be_true
  end

  it "scrolls the viewport with the mouse wheel without requiring focus" do
    Tui::Widget.focused_widget = nil
    editor = Tui::TextEditor.new("mouse-wheel")
    editor.rect = Tui::Rect.new(0, 0, 40, 5)
    editor.text = (0..20).map { |i| "line #{i}" }.join("\n")
    editor.focused?.should be_false
    editor.scroll_y.should eq 0

    down = Tui::MouseEvent.new(10, 2, Tui::MouseButton::WheelDown, Tui::MouseAction::Press)
    editor.handle_event(down).should be_true
    editor.scroll_y.should be > 0

    scrolled = editor.scroll_y
    up = Tui::MouseEvent.new(10, 2, Tui::MouseButton::WheelUp, Tui::MouseAction::Press)
    editor.handle_event(up).should be_true
    editor.scroll_y.should be < scrolled
  end

  it "shows a ScrollBar when content exceeds the viewport" do
    editor = Tui::TextEditor.new("mouse-scrollbar")
    editor.rect = Tui::Rect.new(0, 0, 40, 5)
    editor.text = (0..20).map { |i| "line #{i}" }.join("\n")
    editor.v_scrollbar.needed?.should be_false

    buffer = Tui::Buffer.new(40, 5)
    editor.render(buffer, editor.rect)
    editor.v_scrollbar.needed?.should be_true
    editor.v_scrollbar.total.should eq 21
    editor.v_scrollbar.viewport.should eq 5
  end
end
