require "../../spec_helper"

describe Tui::MouseEvent do
  describe "#initialize" do
    it "creates mouse event with position" do
      event = Tui::MouseEvent.new(10, 20)
      event.x.should eq 10
      event.y.should eq 20
    end

    it "defaults to left button press" do
      event = Tui::MouseEvent.new(0, 0)
      event.button.should eq Tui::MouseButton::Left
      event.action.should eq Tui::MouseAction::Press
    end
  end

  describe "action helpers" do
    it "detects press" do
      event = Tui::MouseEvent.new(0, 0, action: Tui::MouseAction::Press)
      event.press?.should be_true
      event.release?.should be_false
      event.drag?.should be_false
    end

    it "detects release" do
      event = Tui::MouseEvent.new(0, 0, action: Tui::MouseAction::Release)
      event.release?.should be_true
      event.press?.should be_false
    end

    it "detects drag" do
      event = Tui::MouseEvent.new(0, 0, action: Tui::MouseAction::Drag)
      event.drag?.should be_true
    end

    it "detects move" do
      event = Tui::MouseEvent.new(0, 0, action: Tui::MouseAction::Move)
      event.move?.should be_true
    end
  end

  describe "button helpers" do
    it "detects left button" do
      event = Tui::MouseEvent.new(0, 0, button: Tui::MouseButton::Left)
      event.left?.should be_true
      event.right?.should be_false
    end

    it "detects right button" do
      event = Tui::MouseEvent.new(0, 0, button: Tui::MouseButton::Right)
      event.right?.should be_true
    end

    it "detects middle button" do
      event = Tui::MouseEvent.new(0, 0, button: Tui::MouseButton::Middle)
      event.middle?.should be_true
    end

    it "detects wheel up" do
      event = Tui::MouseEvent.new(0, 0, button: Tui::MouseButton::WheelUp)
      event.wheel_up?.should be_true
      event.wheel?.should be_true
    end

    it "detects wheel down" do
      event = Tui::MouseEvent.new(0, 0, button: Tui::MouseButton::WheelDown)
      event.wheel_down?.should be_true
      event.wheel?.should be_true
    end
  end

  describe "#in_rect?" do
    it "returns true for position inside rect" do
      event = Tui::MouseEvent.new(15, 25)
      event.in_rect?(10, 20, 20, 20).should be_true
    end

    it "returns false for position outside rect" do
      event = Tui::MouseEvent.new(5, 25)
      event.in_rect?(10, 20, 20, 20).should be_false
    end

    it "accepts Rect object" do
      event = Tui::MouseEvent.new(15, 25)
      rect = Tui::Rect.new(10, 20, 20, 20)
      event.in_rect?(rect).should be_true
    end
  end

  describe "#relative_to" do
    it "returns position relative to point" do
      event = Tui::MouseEvent.new(15, 25)
      rx, ry = event.relative_to(10, 20)
      rx.should eq 5
      ry.should eq 5
    end

    it "accepts Rect object" do
      event = Tui::MouseEvent.new(15, 25)
      rect = Tui::Rect.new(10, 20, 100, 100)
      rx, ry = event.relative_to(rect)
      rx.should eq 5
      ry.should eq 5
    end
  end

  describe "#stop!" do
    it "stops event propagation" do
      event = Tui::MouseEvent.new(0, 0)
      event.stopped?.should be_false
      event.stop!
      event.stopped?.should be_true
    end
  end

  describe "modifiers" do
    it "detects shift" do
      event = Tui::MouseEvent.new(0, 0, modifiers: Tui::Modifiers::Shift)
      event.shift?.should be_true
      event.ctrl?.should be_false
    end

    it "detects ctrl" do
      event = Tui::MouseEvent.new(0, 0, modifiers: Tui::Modifiers::Ctrl)
      event.ctrl?.should be_true
    end

    it "detects alt" do
      event = Tui::MouseEvent.new(0, 0, modifiers: Tui::Modifiers::Alt)
      event.alt?.should be_true
    end
  end
end

describe "Panel scroll events" do
  it "scrolls down on wheel down" do
    panel = Tui::Panel.new
    panel.rect = Tui::Rect.new(0, 0, 20, 10)
    panel.content_height = 30
    panel.scroll_lines = 3

    initial_scroll = panel.scroll_y
    event = Tui::MouseEvent.new(10, 5, button: Tui::MouseButton::WheelDown)
    panel.handle_event(event)

    panel.scroll_y.should eq initial_scroll + 3
  end

  it "scrolls up on wheel up" do
    panel = Tui::Panel.new
    panel.rect = Tui::Rect.new(0, 0, 20, 10)
    panel.content_height = 30
    panel.scroll_y = 10

    event = Tui::MouseEvent.new(10, 5, button: Tui::MouseButton::WheelUp)
    panel.handle_event(event)

    panel.scroll_y.should eq 7
  end

  it "stops event after handling scroll" do
    panel = Tui::Panel.new
    panel.rect = Tui::Rect.new(0, 0, 20, 10)
    panel.content_height = 30

    event = Tui::MouseEvent.new(10, 5, button: Tui::MouseButton::WheelDown)
    panel.handle_event(event)

    event.stopped?.should be_true
  end

  it "ignores scroll when not scrollable" do
    panel = Tui::Panel.new
    panel.rect = Tui::Rect.new(0, 0, 20, 10)
    panel.content_height = 30
    panel.scrollable = false

    event = Tui::MouseEvent.new(10, 5, button: Tui::MouseButton::WheelDown)
    panel.handle_event(event)

    panel.scroll_y.should eq 0
    event.stopped?.should be_false
  end

  it "ignores scroll outside panel" do
    panel = Tui::Panel.new
    panel.rect = Tui::Rect.new(10, 10, 20, 10)
    panel.content_height = 30

    event = Tui::MouseEvent.new(5, 5, button: Tui::MouseButton::WheelDown)  # outside
    panel.handle_event(event)

    panel.scroll_y.should eq 0
  end
end

describe "SplitContainer drag events" do
  it "starts dragging on press over splitter" do
    split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
    split.rect = Tui::Rect.new(0, 0, 40, 20)
    split.calculate_layout

    splitter_x = split.splitter_x
    event = Tui::MouseEvent.new(splitter_x, 10, action: Tui::MouseAction::Press)
    result = split.handle_event(event)

    result.should be_true
    event.stopped?.should be_true
  end

  it "updates ratio on drag" do
    split = Tui::SplitContainer.new(
      direction: Tui::SplitContainer::Direction::Horizontal,
      ratio: 0.5
    )
    split.rect = Tui::Rect.new(0, 0, 40, 20)
    split.calculate_layout

    initial_ratio = split.ratio
    splitter_x = split.splitter_x

    # Start drag
    press = Tui::MouseEvent.new(splitter_x, 10, action: Tui::MouseAction::Press)
    split.handle_event(press)

    # Drag to the right
    drag = Tui::MouseEvent.new(splitter_x + 5, 10, action: Tui::MouseAction::Drag)
    split.handle_event(drag)

    split.ratio.should be > initial_ratio
  end

  it "calls on_resize callback on release" do
    split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
    split.rect = Tui::Rect.new(0, 0, 40, 20)
    split.calculate_layout

    callback_called = false
    callback_ratio = 0.0
    split.on_resize do |ratio|
      callback_called = true
      callback_ratio = ratio
    end

    splitter_x = split.splitter_x

    # Press, drag, release sequence
    split.handle_event(Tui::MouseEvent.new(splitter_x, 10, action: Tui::MouseAction::Press))
    split.handle_event(Tui::MouseEvent.new(splitter_x + 3, 10, action: Tui::MouseAction::Drag))
    split.handle_event(Tui::MouseEvent.new(splitter_x + 3, 10, action: Tui::MouseAction::Release))

    callback_called.should be_true
    callback_ratio.should be > 0
  end

  it "ignores press outside splitter" do
    split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
    split.rect = Tui::Rect.new(0, 0, 40, 20)
    split.calculate_layout

    # Press far from splitter
    event = Tui::MouseEvent.new(5, 10, action: Tui::MouseAction::Press)
    result = split.handle_event(event)

    result.should be_false
    event.stopped?.should be_false
  end

  it "respects min_first constraint during drag" do
    split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
    split.min_first = 10
    split.rect = Tui::Rect.new(0, 0, 40, 20)
    split.calculate_layout

    splitter_x = split.splitter_x

    # Start drag and try to move splitter to far left
    split.handle_event(Tui::MouseEvent.new(splitter_x, 10, action: Tui::MouseAction::Press))
    split.handle_event(Tui::MouseEvent.new(2, 10, action: Tui::MouseAction::Drag))

    # Splitter should not go below min_first
    split.calculate_layout
    (split.splitter_x - 1).should be >= split.min_first  # -1 for border
  end

  it "works for vertical split" do
    split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Vertical)
    split.rect = Tui::Rect.new(0, 0, 40, 20)
    split.calculate_layout

    splitter_y = split.splitter_y
    initial_ratio = split.ratio

    # Press on horizontal splitter
    split.handle_event(Tui::MouseEvent.new(20, splitter_y, action: Tui::MouseAction::Press))
    # Drag down
    split.handle_event(Tui::MouseEvent.new(20, splitter_y + 3, action: Tui::MouseAction::Drag))

    split.ratio.should be > initial_ratio
  end
end
