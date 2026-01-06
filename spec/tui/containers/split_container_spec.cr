require "../../spec_helper"

describe Tui::SplitContainer do
  describe "#initialize" do
    it "creates horizontal split by default" do
      split = Tui::SplitContainer.new
      split.direction.should eq Tui::SplitContainer::Direction::Horizontal
      split.ratio.should eq 0.5
    end

    it "creates vertical split" do
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Vertical)
      split.direction.should eq Tui::SplitContainer::Direction::Vertical
    end

    it "accepts custom ratio" do
      split = Tui::SplitContainer.new(ratio: 0.3)
      split.ratio.should eq 0.3
    end

    it "accepts id" do
      split = Tui::SplitContainer.new(id: "my-split")
      split.id.should eq "my-split"
    end
  end

  describe "#first= and #second=" do
    it "sets first child" do
      split = Tui::SplitContainer.new
      label = Tui::Label.new("First")
      split.first = label
      split.first.should eq label
    end

    it "sets second child" do
      split = Tui::SplitContainer.new
      label = Tui::Label.new("Second")
      split.second = label
      split.second.should eq label
    end

    it "replaces previous child" do
      split = Tui::SplitContainer.new
      old_label = Tui::Label.new("Old")
      new_label = Tui::Label.new("New")

      split.first = old_label
      split.first = new_label

      split.first.should eq new_label
    end

    it "accepts nil" do
      split = Tui::SplitContainer.new
      label = Tui::Label.new("Test")
      split.first = label
      split.first = nil
      split.first.should be_nil
    end
  end

  describe "#splitter_x and #splitter_y" do
    it "returns splitter_x for horizontal split" do
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
      split.rect = Tui::Rect.new(0, 0, 20, 10)
      split.calculate_layout

      split.splitter_x.should be > 0
      split.splitter_y.should eq 0
    end

    it "returns splitter_y for vertical split" do
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Vertical)
      split.rect = Tui::Rect.new(0, 0, 20, 10)
      split.calculate_layout

      split.splitter_y.should be > 0
      split.splitter_x.should eq 0
    end
  end

  describe "#calculate_layout" do
    it "calculates splitter position based on ratio" do
      split = Tui::SplitContainer.new(
        direction: Tui::SplitContainer::Direction::Horizontal,
        ratio: 0.5
      )
      split.rect = Tui::Rect.new(0, 0, 21, 10)  # 21 = 2 borders + 18 content + 1 splitter
      split.calculate_layout

      # With show_border=true, inner_w = 21-2 = 19, total = 19-1 = 18 (for content)
      # At 0.5 ratio, first gets 9, splitter at x=1+9=10
      split.splitter_x.should eq 10
    end

    it "respects min_first constraint" do
      split = Tui::SplitContainer.new(
        direction: Tui::SplitContainer::Direction::Horizontal,
        ratio: 0.1  # Would give very small first area
      )
      split.min_first = 5
      split.rect = Tui::Rect.new(0, 0, 30, 10)
      split.calculate_layout

      # First area should be at least min_first
      split.splitter_x.should be >= 1 + 5  # border + min_first
    end

    it "respects min_second constraint" do
      split = Tui::SplitContainer.new(
        direction: Tui::SplitContainer::Direction::Horizontal,
        ratio: 0.9  # Would give very small second area
      )
      split.min_second = 5
      split.rect = Tui::Rect.new(0, 0, 30, 10)
      split.calculate_layout

      # Splitter should leave room for min_second
      inner_right = 30 - 1  # rect.right - border
      (inner_right - split.splitter_x - 1).should be >= 5  # room after splitter
    end
  end

  describe "#render" do
    it "renders horizontal split with border" do
      buffer = Tui::Buffer.new(20, 10)
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
      split.rect = Tui::Rect.new(0, 0, 20, 10)

      split.render(buffer, split.rect)

      # Corners
      buffer.get(0, 0).char.should eq '┌'
      buffer.get(19, 0).char.should eq '┐'
      buffer.get(0, 9).char.should eq '└'
      buffer.get(19, 9).char.should eq '┘'

      # Top junction at splitter
      splitter_x = split.splitter_x
      buffer.get(splitter_x, 0).char.should eq '┬'
      buffer.get(splitter_x, 9).char.should eq '┴'
    end

    it "renders vertical split with border" do
      buffer = Tui::Buffer.new(20, 10)
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Vertical)
      split.rect = Tui::Rect.new(0, 0, 20, 10)

      split.render(buffer, split.rect)

      # Corners
      buffer.get(0, 0).char.should eq '┌'
      buffer.get(19, 0).char.should eq '┐'

      # Side junctions at splitter
      splitter_y = split.splitter_y
      buffer.get(0, splitter_y).char.should eq '├'
      buffer.get(19, splitter_y).char.should eq '┤'
    end

    it "renders vertical splitter line for horizontal split" do
      buffer = Tui::Buffer.new(20, 10)
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
      split.rect = Tui::Rect.new(0, 0, 20, 10)

      split.render(buffer, split.rect)

      splitter_x = split.splitter_x
      # Middle of splitter should be │
      buffer.get(splitter_x, 5).char.should eq '│'
    end

    it "renders horizontal splitter line for vertical split" do
      buffer = Tui::Buffer.new(20, 10)
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Vertical)
      split.rect = Tui::Rect.new(0, 0, 20, 10)

      split.render(buffer, split.rect)

      splitter_y = split.splitter_y
      # Middle of splitter should be ─
      buffer.get(10, splitter_y).char.should eq '─'
    end

    it "renders first_title on top border" do
      buffer = Tui::Buffer.new(30, 10)
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
      split.first_title = "First"
      split.rect = Tui::Rect.new(0, 0, 30, 10)

      split.render(buffer, split.rect)

      # Title decorated as "─┤ First ├───" on top border
      # draw_horizontal_edge starts at x=1, title_start=1 means first decorated char at x=2
      # Position: 0=┌, 1=─, 2=┤, 3= , 4=F, 5=i, 6=r, 7=s, 8=t, 9= , 10=├
      buffer.get(0, 0).char.should eq '┌'
      buffer.get(1, 0).char.should eq '─'
      buffer.get(2, 0).char.should eq '┤'
      buffer.get(4, 0).char.should eq 'F'
      buffer.get(5, 0).char.should eq 'i'
      buffer.get(6, 0).char.should eq 'r'
      buffer.get(7, 0).char.should eq 's'
      buffer.get(8, 0).char.should eq 't'
      buffer.get(10, 0).char.should eq '├'
    end

    it "renders second_title on top border after splitter (horizontal)" do
      buffer = Tui::Buffer.new(40, 10)
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
      split.second_title = "Second"
      split.rect = Tui::Rect.new(0, 0, 40, 10)

      split.render(buffer, split.rect)

      # Second title should appear after splitter on top
      splitter_x = split.splitter_x
      # Look for 'S' somewhere after splitter
      found = false
      (splitter_x + 1...40).each do |x|
        if buffer.get(x, 0).char == 'S'
          found = true
          buffer.get(x + 1, 0).char.should eq 'e'
          break
        end
      end
      found.should be_true
    end

    it "renders second_title on splitter line (vertical)" do
      buffer = Tui::Buffer.new(30, 15)
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Vertical)
      split.second_title = "Bottom"
      split.rect = Tui::Rect.new(0, 0, 30, 15)

      split.render(buffer, split.rect)

      splitter_y = split.splitter_y
      # Look for 'B' on splitter line
      found = false
      (1...30).each do |x|
        if buffer.get(x, splitter_y).char == 'B'
          found = true
          buffer.get(x + 1, splitter_y).char.should eq 'o'
          break
        end
      end
      found.should be_true
    end

    it "renders without border when show_border is false" do
      buffer = Tui::Buffer.new(20, 10)
      split = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
      split.show_border = false
      split.rect = Tui::Rect.new(0, 0, 20, 10)

      split.render(buffer, split.rect)

      # Corners should not have border chars
      buffer.get(0, 0).char.should eq ' '
      buffer.get(19, 0).char.should eq ' '
    end

    it "renders children in their areas" do
      buffer = Tui::Buffer.new(30, 10)
      split = Tui::SplitContainer.new(
        direction: Tui::SplitContainer::Direction::Horizontal,
        ratio: 0.5
      )
      split.rect = Tui::Rect.new(0, 0, 30, 10)

      first = Tui::Label.new("AAA")
      second = Tui::Label.new("BBB")
      split.first = first
      split.second = second

      split.render(buffer, split.rect)

      # First child should render in first area
      buffer.get(1, 1).char.should eq 'A'

      # Second child should render in second area (after splitter)
      splitter_x = split.splitter_x
      buffer.get(splitter_x + 1, 1).char.should eq 'B'
    end

    it "does not render when not visible" do
      buffer = Tui::Buffer.new(20, 10)
      split = Tui::SplitContainer.new
      split.rect = Tui::Rect.new(0, 0, 20, 10)
      split.visible = false

      split.render(buffer, split.rect)

      buffer.get(0, 0).char.should eq ' '
    end
  end

  describe "nested splits" do
    it "draws junction for nested horizontal splitter" do
      buffer = Tui::Buffer.new(40, 20)

      # Main horizontal split
      main = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
      main.rect = Tui::Rect.new(0, 0, 40, 20)

      # Nested vertical split in second area
      nested = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Vertical)
      nested.show_border = false
      main.second = nested

      main.render(buffer, main.rect)

      # Should have ├ junction where main's vertical splitter meets nested's horizontal splitter
      main_splitter_x = main.splitter_x
      nested_splitter_y = nested.splitter_y

      buffer.get(main_splitter_x, nested_splitter_y).char.should eq '├'
    end

    it "draws ┤ junction on right border for nested horizontal splitter" do
      buffer = Tui::Buffer.new(40, 20)

      main = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Horizontal)
      main.rect = Tui::Rect.new(0, 0, 40, 20)

      nested = Tui::SplitContainer.new(direction: Tui::SplitContainer::Direction::Vertical)
      nested.show_border = false
      main.second = nested

      main.render(buffer, main.rect)

      nested_splitter_y = nested.splitter_y
      # Right border should have ┤ at nested splitter Y
      buffer.get(39, nested_splitter_y).char.should eq '┤'
    end
  end

  describe "Direction enum" do
    it "horizontal means left|right (vertical splitter)" do
      dir = Tui::SplitContainer::Direction::Horizontal
      dir.horizontal?.should be_true
      dir.vertical?.should be_false
    end

    it "vertical means top/bottom (horizontal splitter)" do
      dir = Tui::SplitContainer::Direction::Vertical
      dir.vertical?.should be_true
      dir.horizontal?.should be_false
    end
  end
end
