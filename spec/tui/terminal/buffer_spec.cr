require "../../spec_helper"

describe Tui::Buffer do
  describe "#initialize" do
    it "creates buffer with given dimensions" do
      buffer = Tui::Buffer.new(80, 24)
      buffer.width.should eq 80
      buffer.height.should eq 24
    end

    it "initializes cells as empty" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.get(0, 0).char.should eq ' '
      buffer.get(5, 5).char.should eq ' '
    end
  end

  describe "#set and #get" do
    it "sets and gets cell at position" do
      buffer = Tui::Buffer.new(10, 10)
      cell = Tui::Cell.new('X', Tui::Style.new(fg: Tui::Color.red))
      buffer.set(5, 5, cell)
      buffer.get(5, 5).should eq cell
    end

    it "sets cell with char and style" do
      buffer = Tui::Buffer.new(10, 10)
      style = Tui::Style.new(fg: Tui::Color.green)
      buffer.set(3, 3, 'A', style)
      buffer.get(3, 3).char.should eq 'A'
      buffer.get(3, 3).style.fg.should eq Tui::Color.green
    end

    it "ignores out of bounds set" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.set(-1, 5, 'X')  # should not crash
      buffer.set(5, -1, 'X')  # should not crash
      buffer.set(10, 5, 'X')  # should not crash
      buffer.set(5, 10, 'X')  # should not crash
    end

    it "returns empty cell for out of bounds get" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.get(-1, 5).should eq Tui::Cell.empty
      buffer.get(10, 5).should eq Tui::Cell.empty
      buffer.get(5, -1).should eq Tui::Cell.empty
      buffer.get(5, 10).should eq Tui::Cell.empty
    end

    it "handles edge positions correctly" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.set(0, 0, 'A')
      buffer.set(9, 0, 'B')
      buffer.set(0, 9, 'C')
      buffer.set(9, 9, 'D')

      buffer.get(0, 0).char.should eq 'A'
      buffer.get(9, 0).char.should eq 'B'
      buffer.get(0, 9).char.should eq 'C'
      buffer.get(9, 9).char.should eq 'D'
    end
  end

  describe "#in_bounds?" do
    it "returns true for valid positions" do
      buffer = Tui::Buffer.new(80, 24)
      buffer.in_bounds?(0, 0).should be_true
      buffer.in_bounds?(79, 23).should be_true
      buffer.in_bounds?(40, 12).should be_true
    end

    it "returns false for negative positions" do
      buffer = Tui::Buffer.new(80, 24)
      buffer.in_bounds?(-1, 0).should be_false
      buffer.in_bounds?(0, -1).should be_false
      buffer.in_bounds?(-1, -1).should be_false
    end

    it "returns false for positions at or beyond edges" do
      buffer = Tui::Buffer.new(80, 24)
      buffer.in_bounds?(80, 0).should be_false
      buffer.in_bounds?(0, 24).should be_false
      buffer.in_bounds?(80, 24).should be_false
    end
  end

  describe "#clear" do
    it "fills buffer with empty cells" do
      buffer = Tui::Buffer.new(5, 5)
      buffer.set(2, 2, 'X')
      buffer.clear
      buffer.get(2, 2).char.should eq ' '
    end

    it "fills buffer with given cell" do
      buffer = Tui::Buffer.new(5, 5)
      cell = Tui::Cell.new('.', Tui::Style.new(fg: Tui::Color.blue))
      buffer.clear(cell)
      buffer.get(0, 0).should eq cell
      buffer.get(4, 4).should eq cell
    end
  end

  describe "#draw_string" do
    it "draws string at position" do
      buffer = Tui::Buffer.new(20, 5)
      buffer.draw_string(2, 1, "Hello")
      buffer.get(2, 1).char.should eq 'H'
      buffer.get(3, 1).char.should eq 'e'
      buffer.get(4, 1).char.should eq 'l'
      buffer.get(5, 1).char.should eq 'l'
      buffer.get(6, 1).char.should eq 'o'
    end

    it "applies style to all characters" do
      buffer = Tui::Buffer.new(20, 5)
      style = Tui::Style.new(fg: Tui::Color.yellow)
      buffer.draw_string(0, 0, "ABC", style)
      buffer.get(0, 0).style.fg.should eq Tui::Color.yellow
      buffer.get(2, 0).style.fg.should eq Tui::Color.yellow
    end

    it "clips string at buffer edge" do
      buffer = Tui::Buffer.new(5, 1)
      buffer.draw_string(3, 0, "Hello")  # Only "He" should fit
      buffer.get(3, 0).char.should eq 'H'
      buffer.get(4, 0).char.should eq 'e'
    end

    it "handles empty string" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_string(0, 0, "")  # should not crash
    end
  end

  describe "#draw_hline" do
    it "draws horizontal line" do
      buffer = Tui::Buffer.new(10, 5)
      buffer.draw_hline(1, 2, 5)
      buffer.get(1, 2).char.should eq '─'
      buffer.get(2, 2).char.should eq '─'
      buffer.get(5, 2).char.should eq '─'
      buffer.get(6, 2).char.should eq ' '  # not part of line
    end

    it "uses custom character" do
      buffer = Tui::Buffer.new(10, 5)
      buffer.draw_hline(0, 0, 3, '=')
      buffer.get(0, 0).char.should eq '='
      buffer.get(2, 0).char.should eq '='
    end

    it "handles zero length" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_hline(0, 0, 0)  # should not crash
    end
  end

  describe "#draw_vline" do
    it "draws vertical line" do
      buffer = Tui::Buffer.new(5, 10)
      buffer.draw_vline(2, 1, 5)
      buffer.get(2, 1).char.should eq '│'
      buffer.get(2, 2).char.should eq '│'
      buffer.get(2, 5).char.should eq '│'
      buffer.get(2, 6).char.should eq ' '  # not part of line
    end

    it "uses custom character" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_vline(0, 0, 3, '|')
      buffer.get(0, 0).char.should eq '|'
      buffer.get(0, 2).char.should eq '|'
    end
  end

  describe "#draw_box" do
    it "draws light box" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_box(0, 0, 5, 4)

      # Corners
      buffer.get(0, 0).char.should eq '┌'
      buffer.get(4, 0).char.should eq '┐'
      buffer.get(0, 3).char.should eq '└'
      buffer.get(4, 3).char.should eq '┘'

      # Edges
      buffer.get(2, 0).char.should eq '─'
      buffer.get(2, 3).char.should eq '─'
      buffer.get(0, 1).char.should eq '│'
      buffer.get(4, 2).char.should eq '│'
    end

    it "draws heavy box" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_box(0, 0, 5, 4, border_style: :heavy)
      buffer.get(0, 0).char.should eq '┏'
      buffer.get(4, 0).char.should eq '┓'
      buffer.get(2, 0).char.should eq '━'
    end

    it "draws double box" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_box(0, 0, 5, 4, border_style: :double)
      buffer.get(0, 0).char.should eq '╔'
      buffer.get(4, 0).char.should eq '╗'
      buffer.get(2, 0).char.should eq '═'
    end

    it "draws round box" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.draw_box(0, 0, 5, 4, border_style: :round)
      buffer.get(0, 0).char.should eq '╭'
      buffer.get(4, 0).char.should eq '╮'
    end
  end

  describe "#fill" do
    it "fills rectangular area" do
      buffer = Tui::Buffer.new(10, 10)
      cell = Tui::Cell.new('#')
      buffer.fill(2, 2, 3, 3, cell)

      buffer.get(2, 2).char.should eq '#'
      buffer.get(4, 4).char.should eq '#'
      buffer.get(1, 2).char.should eq ' '  # outside fill area
      buffer.get(5, 2).char.should eq ' '  # outside fill area
    end

    it "handles zero dimensions" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.fill(0, 0, 0, 5)  # should not crash
      buffer.fill(0, 0, 5, 0)  # should not crash
    end
  end

  describe "#resize" do
    it "increases buffer size" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.set(5, 5, 'X')
      buffer.resize(20, 20)

      buffer.width.should eq 20
      buffer.height.should eq 20
      buffer.get(5, 5).char.should eq 'X'  # preserved
      buffer.in_bounds?(15, 15).should be_true
    end

    it "decreases buffer size" do
      buffer = Tui::Buffer.new(20, 20)
      buffer.set(15, 15, 'X')
      buffer.set(5, 5, 'Y')
      buffer.resize(10, 10)

      buffer.width.should eq 10
      buffer.height.should eq 10
      buffer.get(5, 5).char.should eq 'Y'  # preserved (within new bounds)
      buffer.in_bounds?(15, 15).should be_false  # now out of bounds
    end

    it "does nothing for same size" do
      buffer = Tui::Buffer.new(10, 10)
      buffer.set(5, 5, 'X')
      buffer.resize(10, 10)
      buffer.get(5, 5).char.should eq 'X'
    end
  end

  describe "#to_s" do
    it "returns buffer content as string" do
      buffer = Tui::Buffer.new(5, 3)
      buffer.draw_string(0, 0, "Hello")
      buffer.draw_string(0, 1, "World")
      buffer.draw_string(0, 2, "12345")

      buffer.to_s.should eq "Hello\nWorld\n12345"
    end

    it "pads short lines with spaces" do
      buffer = Tui::Buffer.new(5, 2)
      buffer.set(0, 0, 'A')
      buffer.set(4, 1, 'B')

      buffer.to_s.should eq "A    \n    B"
    end
  end
end
