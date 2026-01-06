require "../spec_helper"

# Test widget that's focusable
class FocusableWidget < Tui::Widget
  property name : String

  def initialize(@name : String)
    super()
    @focusable = true
  end
end

# Test widget that's not focusable
class NonFocusableWidget < Tui::Widget
  def initialize
    super()
    @focusable = false
  end
end

describe "Focus Management" do
  before_each do
    # Clear global focus state between tests
    Tui::Widget.focused_widget = nil
  end

  describe "Widget focus state" do
    it "starts unfocused" do
      widget = FocusableWidget.new("test")
      widget.focused?.should be_false
    end

    it "can be focused" do
      widget = FocusableWidget.new("test")
      widget.focus
      widget.focused?.should be_true
    end

    it "can be blurred" do
      widget = FocusableWidget.new("test")
      widget.focus
      widget.blur
      widget.focused?.should be_false
    end

    it "focus! is alias for focus" do
      widget = FocusableWidget.new("test")
      widget.focus!
      widget.focused?.should be_true
    end

    it "updates global focused_widget" do
      widget = FocusableWidget.new("test")
      widget.focus
      Tui::Widget.focused_widget.should eq widget
    end

    it "clears previous focus when new widget focused" do
      widget1 = FocusableWidget.new("one")
      widget2 = FocusableWidget.new("two")

      widget1.focus
      widget1.focused?.should be_true
      widget2.focused?.should be_false

      widget2.focus
      widget1.focused?.should be_false
      widget2.focused?.should be_true
      Tui::Widget.focused_widget.should eq widget2
    end

    it "blur clears global focus" do
      widget = FocusableWidget.new("test")
      widget.focus
      widget.blur
      Tui::Widget.focused_widget.should be_nil
    end
  end

  describe "collect_focusable" do
    it "returns empty array for non-focusable tree" do
      parent = NonFocusableWidget.new
      parent.collect_focusable.should be_empty
    end

    it "returns single focusable widget" do
      widget = FocusableWidget.new("test")
      focusables = widget.collect_focusable
      focusables.size.should eq 1
      focusables.first.should eq widget
    end

    it "collects focusable children in depth-first order" do
      parent = NonFocusableWidget.new
      child1 = FocusableWidget.new("one")
      child2 = FocusableWidget.new("two")
      child3 = FocusableWidget.new("three")

      parent.add_child(child1)
      parent.add_child(child2)
      parent.add_child(child3)

      focusables = parent.collect_focusable
      focusables.size.should eq 3
      focusables[0].as(FocusableWidget).name.should eq "one"
      focusables[1].as(FocusableWidget).name.should eq "two"
      focusables[2].as(FocusableWidget).name.should eq "three"
    end

    it "collects nested focusable widgets depth-first" do
      root = NonFocusableWidget.new
      container1 = NonFocusableWidget.new
      container2 = NonFocusableWidget.new

      btn1 = FocusableWidget.new("btn1")
      btn2 = FocusableWidget.new("btn2")
      btn3 = FocusableWidget.new("btn3")
      btn4 = FocusableWidget.new("btn4")

      root.add_child(container1)
      root.add_child(container2)
      container1.add_child(btn1)
      container1.add_child(btn2)
      container2.add_child(btn3)
      container2.add_child(btn4)

      focusables = root.collect_focusable
      focusables.size.should eq 4
      focusables.map { |w| w.as(FocusableWidget).name }.should eq ["btn1", "btn2", "btn3", "btn4"]
    end

    it "skips invisible widgets" do
      parent = NonFocusableWidget.new
      child1 = FocusableWidget.new("visible")
      child2 = FocusableWidget.new("invisible")
      child2.visible = false

      parent.add_child(child1)
      parent.add_child(child2)

      focusables = parent.collect_focusable
      focusables.size.should eq 1
      focusables.first.as(FocusableWidget).name.should eq "visible"
    end
  end

  describe "focus_next" do
    it "focuses first widget when nothing focused" do
      parent = NonFocusableWidget.new
      child1 = FocusableWidget.new("one")
      child2 = FocusableWidget.new("two")
      parent.add_child(child1)
      parent.add_child(child2)

      result = parent.focus_next
      result.should eq child1
      child1.focused?.should be_true
    end

    it "cycles to next widget" do
      parent = NonFocusableWidget.new
      child1 = FocusableWidget.new("one")
      child2 = FocusableWidget.new("two")
      child3 = FocusableWidget.new("three")
      parent.add_child(child1)
      parent.add_child(child2)
      parent.add_child(child3)

      child1.focus
      parent.focus_next
      child2.focused?.should be_true

      parent.focus_next
      child3.focused?.should be_true
    end

    it "wraps around from last to first" do
      parent = NonFocusableWidget.new
      child1 = FocusableWidget.new("one")
      child2 = FocusableWidget.new("two")
      parent.add_child(child1)
      parent.add_child(child2)

      child2.focus
      parent.focus_next
      child1.focused?.should be_true
    end

    it "returns nil for empty focusable list" do
      parent = NonFocusableWidget.new
      result = parent.focus_next
      result.should be_nil
    end
  end

  describe "focus_prev" do
    it "focuses last widget when nothing focused" do
      parent = NonFocusableWidget.new
      child1 = FocusableWidget.new("one")
      child2 = FocusableWidget.new("two")
      parent.add_child(child1)
      parent.add_child(child2)

      result = parent.focus_prev
      result.should eq child2
      child2.focused?.should be_true
    end

    it "cycles to previous widget" do
      parent = NonFocusableWidget.new
      child1 = FocusableWidget.new("one")
      child2 = FocusableWidget.new("two")
      child3 = FocusableWidget.new("three")
      parent.add_child(child1)
      parent.add_child(child2)
      parent.add_child(child3)

      child3.focus
      parent.focus_prev
      child2.focused?.should be_true

      parent.focus_prev
      child1.focused?.should be_true
    end

    it "wraps around from first to last" do
      parent = NonFocusableWidget.new
      child1 = FocusableWidget.new("one")
      child2 = FocusableWidget.new("two")
      parent.add_child(child1)
      parent.add_child(child2)

      child1.focus
      parent.focus_prev
      child2.focused?.should be_true
    end

    it "returns nil for empty focusable list" do
      parent = NonFocusableWidget.new
      result = parent.focus_prev
      result.should be_nil
    end
  end

  describe "focusable widgets" do
    it "Button is focusable by default" do
      button = Tui::Button.new("Test")
      button.focusable?.should be_true
    end

    it "Input is focusable by default" do
      input = Tui::Input.new
      input.focusable?.should be_true
    end

    it "Label is not focusable by default" do
      label = Tui::Label.new("Test")
      label.focusable?.should be_false
    end

    it "Panel is not focusable by default" do
      panel = Tui::Panel.new
      panel.focusable?.should be_false
    end
  end

  describe "focus style" do
    it "Button has focus_style property" do
      button = Tui::Button.new("Test")
      button.focus_style.should be_a(Tui::Style)
    end

    it "Input has focus_style property" do
      input = Tui::Input.new
      input.focus_style.should be_a(Tui::Style)
    end
  end
end
