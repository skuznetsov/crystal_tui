require "../../spec_helper"

describe Tui::Panel do
  describe "#initialize" do
    it "creates panel with default values" do
      panel = Tui::Panel.new
      panel.title.should eq ""
      panel.border_style.should eq Tui::Panel::BorderStyle::Light
      panel.show_borders.should eq Tui::Panel::BorderSides.all
    end

    it "creates panel with title" do
      panel = Tui::Panel.new("My Panel")
      panel.title.should eq "My Panel"
    end

    it "creates panel with custom border style" do
      panel = Tui::Panel.new(border_style: Tui::Panel::BorderStyle::Double)
      panel.border_style.should eq Tui::Panel::BorderStyle::Double
    end
  end

  describe "#content=" do
    it "sets content widget" do
      panel = Tui::Panel.new
      label = Tui::Label.new("Content")
      panel.content = label
      panel.content.should eq label
    end

    it "replaces previous content" do
      panel = Tui::Panel.new
      old_label = Tui::Label.new("Old")
      new_label = Tui::Label.new("New")

      panel.content = old_label
      panel.content = new_label

      panel.content.should eq new_label
    end
  end

  describe "#inner_rect" do
    it "returns rect minus border" do
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 20, 10)

      inner = panel.inner_rect
      inner.x.should eq 1      # left border
      inner.y.should eq 1      # top border
      inner.width.should eq 18  # 20 - 2 borders
      inner.height.should eq 8  # 10 - 2 borders
    end

    it "accounts for padding" do
      panel = Tui::Panel.new
      panel.padding = 2
      panel.rect = Tui::Rect.new(0, 0, 20, 10)

      inner = panel.inner_rect
      inner.x.should eq 3      # border + padding
      inner.y.should eq 3
      inner.width.should eq 14  # 20 - 2*border - 2*padding
      inner.height.should eq 4  # 10 - 2*border - 2*padding
    end

    it "returns full rect when no borders" do
      panel = Tui::Panel.new(border_style: Tui::Panel::BorderStyle::None)
      panel.rect = Tui::Rect.new(5, 5, 20, 10)

      inner = panel.inner_rect
      inner.x.should eq 5
      inner.y.should eq 5
      inner.width.should eq 20
      inner.height.should eq 10
    end

    it "accounts for partial borders" do
      panel = Tui::Panel.new
      panel.show_borders = Tui::Panel::BorderSides::Top | Tui::Panel::BorderSides::Left
      panel.rect = Tui::Rect.new(0, 0, 20, 10)

      inner = panel.inner_rect
      inner.x.should eq 1      # left border
      inner.y.should eq 1      # top border
      inner.width.should eq 19  # no right border
      inner.height.should eq 9  # no bottom border
    end

    it "clamps to zero for small rects" do
      panel = Tui::Panel.new
      panel.padding = 10
      panel.rect = Tui::Rect.new(0, 0, 5, 5)

      inner = panel.inner_rect
      inner.width.should be >= 0
      inner.height.should be >= 0
    end
  end

  describe "#render" do
    it "renders light border" do
      buffer = Tui::Buffer.new(10, 5)
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 10, 5)

      panel.render(buffer, panel.rect)

      buffer.get(0, 0).char.should eq '┌'
      buffer.get(9, 0).char.should eq '┐'
      buffer.get(0, 4).char.should eq '└'
      buffer.get(9, 4).char.should eq '┘'
      buffer.get(5, 0).char.should eq '─'
      buffer.get(0, 2).char.should eq '│'
    end

    it "renders double border" do
      buffer = Tui::Buffer.new(10, 5)
      panel = Tui::Panel.new(border_style: Tui::Panel::BorderStyle::Double)
      panel.rect = Tui::Rect.new(0, 0, 10, 5)

      panel.render(buffer, panel.rect)

      buffer.get(0, 0).char.should eq '╔'
      buffer.get(9, 0).char.should eq '╗'
      buffer.get(5, 0).char.should eq '═'
    end

    it "renders round border" do
      buffer = Tui::Buffer.new(10, 5)
      panel = Tui::Panel.new(border_style: Tui::Panel::BorderStyle::Round)
      panel.rect = Tui::Rect.new(0, 0, 10, 5)

      panel.render(buffer, panel.rect)

      buffer.get(0, 0).char.should eq '╭'
      buffer.get(9, 0).char.should eq '╮'
      buffer.get(0, 4).char.should eq '╰'
      buffer.get(9, 4).char.should eq '╯'
    end

    it "renders title with brackets" do
      buffer = Tui::Buffer.new(20, 5)
      panel = Tui::Panel.new("Test")
      panel.title_decor = Tui::Panel::TitleStyle::Brackets
      panel.rect = Tui::Rect.new(0, 0, 20, 5)

      panel.render(buffer, panel.rect)

      # Should have ┤ Test ├ on top border
      buffer.get(1, 0).char.should eq '┤'
      buffer.get(3, 0).char.should eq 'T'
      buffer.get(4, 0).char.should eq 'e'
      buffer.get(5, 0).char.should eq 's'
      buffer.get(6, 0).char.should eq 't'
      buffer.get(8, 0).char.should eq '├'
    end

    it "renders no border when style is None" do
      buffer = Tui::Buffer.new(10, 5)
      panel = Tui::Panel.new(border_style: Tui::Panel::BorderStyle::None)
      panel.rect = Tui::Rect.new(0, 0, 10, 5)

      panel.render(buffer, panel.rect)

      # Should be empty (no border characters)
      buffer.get(0, 0).char.should eq ' '
      buffer.get(9, 0).char.should eq ' '
    end

    it "renders partial borders" do
      buffer = Tui::Buffer.new(10, 5)
      panel = Tui::Panel.new
      panel.show_borders = Tui::Panel::BorderSides::Top | Tui::Panel::BorderSides::Bottom
      panel.rect = Tui::Rect.new(0, 0, 10, 5)

      panel.render(buffer, panel.rect)

      # Top and bottom should have horizontal lines
      buffer.get(5, 0).char.should eq '─'
      buffer.get(5, 4).char.should eq '─'
      # Left and right should be empty (no vertical lines)
      buffer.get(0, 2).char.should eq ' '
      buffer.get(9, 2).char.should eq ' '
    end

    it "does not render when not visible" do
      buffer = Tui::Buffer.new(10, 5)
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 10, 5)
      panel.visible = false

      panel.render(buffer, panel.rect)

      buffer.get(0, 0).char.should eq ' '
    end

    it "renders content widget inside panel" do
      buffer = Tui::Buffer.new(20, 10)
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 20, 10)

      label = Tui::Label.new("Hello")
      panel.content = label

      panel.render(buffer, panel.rect)

      # Content should be inside border
      buffer.get(1, 1).char.should eq 'H'
      buffer.get(5, 1).char.should eq 'o'
    end
  end

  describe "scrolling" do
    it "initializes with scroll_y at 0" do
      panel = Tui::Panel.new
      panel.scroll_y.should eq 0
    end

    it "sets scroll_y within bounds" do
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 20, 10)
      panel.content_height = 20

      panel.scroll_y = 5
      panel.scroll_y.should eq 5
    end

    it "clamps scroll_y to max" do
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 20, 10)  # inner height = 8
      panel.content_height = 20  # max_scroll = 20 - 8 = 12

      panel.scroll_y = 100
      panel.scroll_y.should eq 12
    end

    it "clamps scroll_y to 0" do
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 20, 10)
      panel.content_height = 20

      panel.scroll_y = -10
      panel.scroll_y.should eq 0
    end

    it "scrolls up by scroll_lines" do
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 20, 10)
      panel.content_height = 30
      panel.scroll_lines = 3
      panel.scroll_y = 10

      panel.scroll_up
      panel.scroll_y.should eq 7
    end

    it "scrolls down by scroll_lines" do
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 20, 10)
      panel.content_height = 30
      panel.scroll_lines = 3
      panel.scroll_y = 5

      panel.scroll_down
      panel.scroll_y.should eq 8
    end

    it "max_scroll_y returns 0 when content fits" do
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 20, 10)  # inner height = 8
      panel.content_height = 5  # fits in panel

      panel.max_scroll_y.should eq 0
    end
  end

  describe "BorderSides flags" do
    it "all includes all sides" do
      sides = Tui::Panel::BorderSides.all
      sides.top?.should be_true
      sides.bottom?.should be_true
      sides.left?.should be_true
      sides.right?.should be_true
    end

    it "none includes no sides" do
      sides = Tui::Panel::BorderSides.none
      sides.top?.should be_false
      sides.bottom?.should be_false
      sides.left?.should be_false
      sides.right?.should be_false
    end

    it "can combine individual sides" do
      sides = Tui::Panel::BorderSides::Top | Tui::Panel::BorderSides::Left
      sides.top?.should be_true
      sides.left?.should be_true
      sides.bottom?.should be_false
      sides.right?.should be_false
    end
  end
end
