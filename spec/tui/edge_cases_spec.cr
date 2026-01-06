require "../spec_helper"

describe "Edge Cases" do
  describe "SplitContainer ratio extremes" do
    it "handles ratio = 0.0" do
      split = Tui::SplitContainer.new(ratio: 0.0)
      split.rect = Tui::Rect.new(0, 0, 40, 20)
      split.calculate_layout

      # Should clamp to min_first
      split.splitter_x.should be >= split.min_first
    end

    it "handles ratio = 1.0" do
      split = Tui::SplitContainer.new(ratio: 1.0)
      split.rect = Tui::Rect.new(0, 0, 40, 20)
      split.calculate_layout

      # Should clamp to leave room for min_second
      inner_right = 40 - 1  # border
      (inner_right - split.splitter_x - 1).should be >= split.min_second
    end

    it "handles very small container" do
      split = Tui::SplitContainer.new
      split.min_first = 3
      split.min_second = 3
      split.rect = Tui::Rect.new(0, 0, 10, 5)  # Barely fits min_first + min_second + splitter + borders

      # Should not crash
      split.calculate_layout

      buffer = Tui::Buffer.new(10, 5)
      split.render(buffer, split.rect)  # Should not crash
    end

    it "handles container smaller than minimums" do
      split = Tui::SplitContainer.new
      split.min_first = 10
      split.min_second = 10
      split.rect = Tui::Rect.new(0, 0, 10, 5)  # Too small for minimums

      # Should not crash, will clamp as best it can
      split.calculate_layout
    end
  end

  describe "Rect with negative/zero dimensions" do
    it "handles zero width" do
      rect = Tui::Rect.new(10, 10, 0, 20)
      rect.empty?.should be_true
      rect.contains?(10, 15).should be_false
    end

    it "handles zero height" do
      rect = Tui::Rect.new(10, 10, 20, 0)
      rect.empty?.should be_true
      rect.contains?(15, 10).should be_false
    end

    it "handles negative width" do
      rect = Tui::Rect.new(10, 10, -5, 20)
      rect.empty?.should be_true
      rect.right.should eq 5  # x + width = 10 + (-5)
    end

    it "handles negative height" do
      rect = Tui::Rect.new(10, 10, 20, -5)
      rect.empty?.should be_true
      rect.bottom.should eq 5
    end

    it "handles negative position" do
      rect = Tui::Rect.new(-10, -10, 20, 20)
      rect.empty?.should be_false
      rect.contains?(0, 0).should be_true
      rect.contains?(-5, -5).should be_true
      rect.right.should eq 10
      rect.bottom.should eq 10
    end

    it "inset with large value clamps to zero" do
      rect = Tui::Rect.new(0, 0, 10, 10)
      result = rect.inset(100)
      result.width.should eq 0
      result.height.should eq 0
    end
  end

  describe "Buffer edge cases" do
    it "handles zero dimensions" do
      buffer = Tui::Buffer.new(0, 0)
      buffer.width.should eq 0
      buffer.height.should eq 0
      buffer.in_bounds?(0, 0).should be_false
    end

    it "handles 1x1 buffer" do
      buffer = Tui::Buffer.new(1, 1)
      buffer.set(0, 0, 'X')
      buffer.get(0, 0).char.should eq 'X'
      buffer.in_bounds?(1, 0).should be_false
      buffer.in_bounds?(0, 1).should be_false
    end

    it "handles very large coordinates" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.set(Int32::MAX, 5, 'X')  # Should not crash, just ignore
      buffer.set(5, Int32::MAX, 'X')  # Should not crash, just ignore
      buffer.get(Int32::MAX, 5).should eq Tui::Cell.empty
    end

    it "handles negative coordinates" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.set(-1, 5, 'X')  # Should not crash
      buffer.set(5, -1, 'X')  # Should not crash
      buffer.get(-1, 5).should eq Tui::Cell.empty
      buffer.get(5, -1).should eq Tui::Cell.empty
    end

    it "draw_hline with zero length" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_hline(5, 5, 0)  # Should not crash
    end

    it "draw_vline with zero length" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_vline(5, 5, 0)  # Should not crash
    end

    it "draw_box with 1x1 size" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_box(0, 0, 1, 1)  # Degenerate case
      # All corners overlap at (0,0), last one (br) wins
      buffer.get(0, 0).char.should eq '┘'
    end

    it "draw_box with 2x2 size" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_box(0, 0, 2, 2)
      buffer.get(0, 0).char.should eq '┌'
      buffer.get(1, 0).char.should eq '┐'
      buffer.get(0, 1).char.should eq '└'
      buffer.get(1, 1).char.should eq '┘'
    end

    it "resize to same size is no-op" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.set(5, 5, 'X')
      buffer.resize(10, 10)
      buffer.get(5, 5).char.should eq 'X'
    end

    it "resize to zero" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.resize(0, 0)
      buffer.width.should eq 0
      buffer.height.should eq 0
    end
  end

  describe "Label edge cases" do
    it "renders empty text" do
      buffer = Tui::Buffer.new(10, 1)
      label = Tui::Label.new("")
      label.rect = Tui::Rect.new(0, 0, 10, 1)
      label.render(buffer, label.rect)  # Should not crash
    end

    it "renders with zero-width rect" do
      buffer = Tui::Buffer.new(10, 10)
      label = Tui::Label.new("Hello")
      label.rect = Tui::Rect.new(5, 5, 0, 1)
      label.render(buffer, label.rect)  # Should not crash
    end

    it "renders with zero-height rect" do
      buffer = Tui::Buffer.new(10, 10)
      label = Tui::Label.new("Hello")
      label.rect = Tui::Rect.new(5, 5, 10, 0)
      label.render(buffer, label.rect)  # Should not crash
    end

    it "handles text with only newlines" do
      buffer = Tui::Buffer.new(10, 5)
      label = Tui::Label.new("\n\n\n")
      label.rect = Tui::Rect.new(0, 0, 10, 5)
      label.render(buffer, label.rect)  # Should not crash
    end

    it "handles very long single line" do
      buffer = Tui::Buffer.new(10, 1)
      label = Tui::Label.new("A" * 1000)
      label.rect = Tui::Rect.new(0, 0, 10, 1)
      label.render(buffer, label.rect)
      # Should truncate and not crash
      buffer.get(9, 0).char.should_not eq ' '
    end
  end

  describe "Panel edge cases" do
    it "renders with zero-size rect" do
      buffer = Tui::Buffer.new(10, 10)
      panel = Tui::Panel.new("Test")
      panel.rect = Tui::Rect.new(0, 0, 0, 0)
      panel.render(buffer, panel.rect)  # Should not crash
    end

    it "inner_rect with excessive padding" do
      panel = Tui::Panel.new
      panel.padding = 100
      panel.rect = Tui::Rect.new(0, 0, 10, 10)
      inner = panel.inner_rect
      inner.width.should eq 0
      inner.height.should eq 0
    end

    it "scroll with content_height = 0" do
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 20, 10)
      panel.content_height = 0
      panel.max_scroll_y.should eq 0
      panel.scroll_down  # Should not crash
      panel.scroll_y.should eq 0
    end

    it "scroll with negative content_height" do
      panel = Tui::Panel.new
      panel.rect = Tui::Rect.new(0, 0, 20, 10)
      panel.content_height = -10
      panel.max_scroll_y.should eq 0
    end
  end

  describe "Unicode edge cases" do
    it "handles empty string" do
      Tui::Unicode.display_width("").should eq 0
      Tui::Unicode.truncate("", 10).should eq ""
    end

    it "handles string of only combining characters" do
      # Combining characters have 0 width
      Tui::Unicode.display_width("\u0301\u0302\u0303").should eq 0
    end

    it "truncate to width 0" do
      Tui::Unicode.truncate("Hello", 0, "").should eq ""
    end

    it "truncate to width 1 with multi-byte suffix" do
      result = Tui::Unicode.truncate("Hello", 1, "…")
      result.should eq "…"
    end

    it "handles null character" do
      Tui::Unicode.char_width('\0').should eq 0
    end
  end

  describe "Color edge cases" do
    it "RGB with max values" do
      color = Tui::Color.rgb(255, 255, 255)
      r, g, b = color.to_rgb
      r.should eq 255
      g.should eq 255
      b.should eq 255
    end

    it "RGB with zero values" do
      color = Tui::Color.rgb(0, 0, 0)
      r, g, b = color.to_rgb
      r.should eq 0
      g.should eq 0
      b.should eq 0
    end

    it "palette with edge indices" do
      Tui::Color.palette(0).value.should eq 0
      Tui::Color.palette(255).value.should eq 255
    end
  end
end
