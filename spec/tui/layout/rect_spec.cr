require "../../spec_helper"

describe Tui::Rect do
  describe "#initialize" do
    it "creates rect with given values" do
      rect = Tui::Rect.new(10, 20, 100, 50)
      rect.x.should eq 10
      rect.y.should eq 20
      rect.width.should eq 100
      rect.height.should eq 50
    end

    it "defaults to zero values" do
      rect = Tui::Rect.new
      rect.x.should eq 0
      rect.y.should eq 0
      rect.width.should eq 0
      rect.height.should eq 0
    end
  end

  describe ".zero" do
    it "creates a zero rect" do
      rect = Tui::Rect.zero
      rect.should eq Tui::Rect.new(0, 0, 0, 0)
    end
  end

  describe "#right" do
    it "returns x + width" do
      rect = Tui::Rect.new(10, 0, 50, 10)
      rect.right.should eq 60
    end

    it "handles zero width" do
      rect = Tui::Rect.new(10, 0, 0, 10)
      rect.right.should eq 10
    end
  end

  describe "#bottom" do
    it "returns y + height" do
      rect = Tui::Rect.new(0, 20, 10, 30)
      rect.bottom.should eq 50
    end

    it "handles zero height" do
      rect = Tui::Rect.new(0, 20, 10, 0)
      rect.bottom.should eq 20
    end
  end

  describe "#contains?" do
    it "returns true for point inside rect" do
      rect = Tui::Rect.new(10, 10, 20, 20)
      rect.contains?(15, 15).should be_true
      rect.contains?(10, 10).should be_true  # top-left corner
      rect.contains?(29, 29).should be_true  # just inside bottom-right
    end

    it "returns false for point outside rect" do
      rect = Tui::Rect.new(10, 10, 20, 20)
      rect.contains?(5, 15).should be_false   # left of rect
      rect.contains?(35, 15).should be_false  # right of rect
      rect.contains?(15, 5).should be_false   # above rect
      rect.contains?(15, 35).should be_false  # below rect
    end

    it "returns false for point on exclusive edges (right, bottom)" do
      rect = Tui::Rect.new(10, 10, 20, 20)
      rect.contains?(30, 15).should be_false  # on right edge (exclusive)
      rect.contains?(15, 30).should be_false  # on bottom edge (exclusive)
    end

    it "returns false for empty rect" do
      rect = Tui::Rect.new(10, 10, 0, 0)
      rect.contains?(10, 10).should be_false
    end

    it "handles negative coordinates" do
      rect = Tui::Rect.new(-10, -10, 20, 20)
      rect.contains?(0, 0).should be_true
      rect.contains?(-5, -5).should be_true
      rect.contains?(-15, 0).should be_false
    end
  end

  describe "#empty?" do
    it "returns true for zero width" do
      Tui::Rect.new(10, 10, 0, 20).empty?.should be_true
    end

    it "returns true for zero height" do
      Tui::Rect.new(10, 10, 20, 0).empty?.should be_true
    end

    it "returns true for negative width" do
      Tui::Rect.new(10, 10, -5, 20).empty?.should be_true
    end

    it "returns true for negative height" do
      Tui::Rect.new(10, 10, 20, -5).empty?.should be_true
    end

    it "returns false for positive dimensions" do
      Tui::Rect.new(10, 10, 20, 20).empty?.should be_false
      Tui::Rect.new(0, 0, 1, 1).empty?.should be_false
    end
  end

  describe "#intersect" do
    it "returns intersection of overlapping rects" do
      a = Tui::Rect.new(0, 0, 20, 20)
      b = Tui::Rect.new(10, 10, 20, 20)
      result = a.intersect(b)
      result.should_not be_nil
      result.should eq Tui::Rect.new(10, 10, 10, 10)
    end

    it "returns nil for non-overlapping rects" do
      a = Tui::Rect.new(0, 0, 10, 10)
      b = Tui::Rect.new(20, 20, 10, 10)
      a.intersect(b).should be_nil
    end

    it "returns nil for adjacent rects (no overlap)" do
      a = Tui::Rect.new(0, 0, 10, 10)
      b = Tui::Rect.new(10, 0, 10, 10)  # touches on right edge
      a.intersect(b).should be_nil
    end

    it "returns contained rect when one contains other" do
      outer = Tui::Rect.new(0, 0, 100, 100)
      inner = Tui::Rect.new(20, 20, 30, 30)
      outer.intersect(inner).should eq inner
    end

    it "handles empty rect" do
      a = Tui::Rect.new(0, 0, 20, 20)
      b = Tui::Rect.new(5, 5, 0, 0)
      a.intersect(b).should be_nil
    end
  end

  describe "#union" do
    it "returns bounding box of two rects" do
      a = Tui::Rect.new(0, 0, 10, 10)
      b = Tui::Rect.new(20, 20, 10, 10)
      result = a.union(b)
      result.should eq Tui::Rect.new(0, 0, 30, 30)
    end

    it "returns larger rect when one contains other" do
      outer = Tui::Rect.new(0, 0, 100, 100)
      inner = Tui::Rect.new(20, 20, 30, 30)
      outer.union(inner).should eq outer
    end

    it "handles overlapping rects" do
      a = Tui::Rect.new(0, 0, 20, 20)
      b = Tui::Rect.new(10, 10, 20, 20)
      a.union(b).should eq Tui::Rect.new(0, 0, 30, 30)
    end
  end

  describe "#offset" do
    it "moves rect by given delta" do
      rect = Tui::Rect.new(10, 20, 30, 40)
      result = rect.offset(5, -10)
      result.should eq Tui::Rect.new(15, 10, 30, 40)
    end

    it "does not modify original rect" do
      rect = Tui::Rect.new(10, 20, 30, 40)
      rect.offset(5, 5)
      rect.x.should eq 10
      rect.y.should eq 20
    end

    it "handles negative offset" do
      rect = Tui::Rect.new(10, 10, 20, 20)
      rect.offset(-20, -20).should eq Tui::Rect.new(-10, -10, 20, 20)
    end
  end

  describe "#inset" do
    it "shrinks rect by uniform amount" do
      rect = Tui::Rect.new(0, 0, 100, 100)
      result = rect.inset(10)
      result.should eq Tui::Rect.new(10, 10, 80, 80)
    end

    it "shrinks rect by individual amounts" do
      rect = Tui::Rect.new(0, 0, 100, 100)
      result = rect.inset(5, 10, 15, 20)  # top, right, bottom, left
      result.should eq Tui::Rect.new(20, 5, 70, 80)
    end

    it "clamps to zero for excessive inset" do
      rect = Tui::Rect.new(0, 0, 20, 20)
      result = rect.inset(50)
      result.width.should eq 0
      result.height.should eq 0
    end

    it "does not modify original" do
      rect = Tui::Rect.new(0, 0, 100, 100)
      rect.inset(10)
      rect.width.should eq 100
    end
  end

  describe "#expand" do
    it "grows rect by given amount" do
      rect = Tui::Rect.new(10, 10, 20, 20)
      result = rect.expand(5)
      result.should eq Tui::Rect.new(5, 5, 30, 30)
    end
  end

  describe "#each_cell" do
    it "iterates over all cells" do
      rect = Tui::Rect.new(5, 10, 3, 2)
      cells = [] of Tuple(Int32, Int32)
      rect.each_cell { |x, y| cells << {x, y} }

      cells.size.should eq 6
      cells.should contain({5, 10})
      cells.should contain({6, 10})
      cells.should contain({7, 10})
      cells.should contain({5, 11})
      cells.should contain({6, 11})
      cells.should contain({7, 11})
    end

    it "yields nothing for empty rect" do
      rect = Tui::Rect.new(0, 0, 0, 0)
      count = 0
      rect.each_cell { |_, _| count += 1 }
      count.should eq 0
    end
  end

  describe "#==" do
    it "returns true for equal rects" do
      a = Tui::Rect.new(10, 20, 30, 40)
      b = Tui::Rect.new(10, 20, 30, 40)
      (a == b).should be_true
    end

    it "returns false for different rects" do
      a = Tui::Rect.new(10, 20, 30, 40)
      (a == Tui::Rect.new(11, 20, 30, 40)).should be_false
      (a == Tui::Rect.new(10, 21, 30, 40)).should be_false
      (a == Tui::Rect.new(10, 20, 31, 40)).should be_false
      (a == Tui::Rect.new(10, 20, 30, 41)).should be_false
    end
  end
end
