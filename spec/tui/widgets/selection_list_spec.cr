require "../../spec_helper"

describe Tui::SelectionList do
  describe "#initialize" do
    it "creates empty selection list" do
      list = Tui::SelectionList(String).new
      list.items.should be_empty
      list.selected_indices.should be_empty
      list.cursor_index.should eq(0)
    end

    it "creates selection list with items" do
      items = ["apple", "banana", "cherry"]
      list = Tui::SelectionList(String).new(items: items)
      list.items.should eq(items)
    end

    it "accepts an id" do
      list = Tui::SelectionList(String).new(id: "my-list")
      list.id.should eq("my-list")
    end
  end

  describe "#toggle_selection" do
    it "selects unselected item" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.toggle_selection(1)
      list.selected?(1).should be_true
    end

    it "deselects selected item" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.toggle_selection(1)
      list.toggle_selection(1)
      list.selected?(1).should be_false
    end

    it "ignores invalid indices" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.toggle_selection(-1)
      list.toggle_selection(100)
      list.selected_indices.should be_empty
    end
  end

  describe "#select_all" do
    it "selects all items" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.select_all
      list.selected_indices.size.should eq(3)
      list.selected?(0).should be_true
      list.selected?(1).should be_true
      list.selected?(2).should be_true
    end
  end

  describe "#deselect_all" do
    it "clears all selections" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.select_all
      list.deselect_all
      list.selected_indices.should be_empty
    end
  end

  describe "#selected_items" do
    it "returns selected items in order" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c", "d"])
      list.toggle_selection(2)
      list.toggle_selection(0)
      list.selected_items.should eq(["a", "c"])
    end

    it "returns empty array when nothing selected" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.selected_items.should be_empty
    end
  end

  describe "#cursor movement" do
    it "moves cursor down" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.cursor_next
      list.cursor_index.should eq(1)
    end

    it "moves cursor up" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.move_cursor(2)
      list.cursor_prev
      list.cursor_index.should eq(1)
    end

    it "clamps cursor to valid range" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.move_cursor(100)
      list.cursor_index.should eq(2)
      list.move_cursor(-10)
      list.cursor_index.should eq(0)
    end

    it "goes to first item" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.move_cursor(2)
      list.cursor_first
      list.cursor_index.should eq(0)
    end

    it "goes to last item" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.cursor_last
      list.cursor_index.should eq(2)
    end
  end

  describe "#toggle_current" do
    it "toggles item at cursor" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c"])
      list.move_cursor(1)
      list.toggle_current
      list.selected?(1).should be_true
    end
  end

  describe "#select_range" do
    it "selects range of items" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c", "d", "e"])
      list.select_range(1, 3)
      list.selected?(0).should be_false
      list.selected?(1).should be_true
      list.selected?(2).should be_true
      list.selected?(3).should be_true
      list.selected?(4).should be_false
    end

    it "handles reversed range" do
      list = Tui::SelectionList(String).new(items: ["a", "b", "c", "d", "e"])
      list.select_range(3, 1)
      list.selected?(1).should be_true
      list.selected?(2).should be_true
      list.selected?(3).should be_true
    end
  end

  describe "#min_size" do
    it "returns minimum dimensions" do
      list = Tui::SelectionList(String).new
      min = list.min_size
      min[0].should be > 0  # width
      min[1].should be > 0  # height
    end
  end
end
