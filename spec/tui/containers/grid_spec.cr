require "../../spec_helper"

describe Tui::Grid do
  describe "#initialize" do
    it "creates grid with default columns" do
      grid = Tui::Grid.new
      grid.columns.should eq(2)
    end

    it "creates grid with custom columns" do
      grid = Tui::Grid.new(columns: 4)
      grid.columns.should eq(4)
    end

    it "accepts an id" do
      grid = Tui::Grid.new(id: "my-grid", columns: 3)
      grid.id.should eq("my-grid")
    end
  end

  describe "#columns" do
    it "can be modified" do
      grid = Tui::Grid.new
      grid.columns = 5
      grid.columns.should eq(5)
    end
  end

  describe "#rows" do
    it "defaults to auto (0)" do
      grid = Tui::Grid.new
      grid.rows.should eq(0)
    end

    it "can be set explicitly" do
      grid = Tui::Grid.new
      grid.rows = 3
      grid.rows.should eq(3)
    end
  end

  describe "#gap" do
    it "defaults to 0" do
      grid = Tui::Grid.new
      grid.column_gap.should eq(0)
      grid.row_gap.should eq(0)
    end

    it "can be set independently" do
      grid = Tui::Grid.new
      grid.column_gap = 2
      grid.row_gap = 1
      grid.column_gap.should eq(2)
      grid.row_gap.should eq(1)
    end
  end

  describe "#column_span" do
    it "defaults to 1" do
      grid = Tui::Grid.new
      grid.column_span(0).should eq(1)
      grid.column_span(5).should eq(1)
    end

    it "can be set per child" do
      grid = Tui::Grid.new(columns: 4)
      grid.set_column_span(0, 2)
      grid.column_span(0).should eq(2)
      grid.column_span(1).should eq(1)  # Others unchanged
    end

    it "clamps to max columns" do
      grid = Tui::Grid.new(columns: 3)
      grid.set_column_span(0, 10)
      grid.column_span(0).should eq(3)
    end
  end

  describe "#row_span" do
    it "defaults to 1" do
      grid = Tui::Grid.new
      grid.row_span(0).should eq(1)
    end

    it "can be set per child" do
      grid = Tui::Grid.new
      grid.set_row_span(0, 2)
      grid.row_span(0).should eq(2)
    end
  end

  describe "#apply_css_style" do
    it "handles grid-columns" do
      grid = Tui::Grid.new
      grid.apply_css_style({"grid-columns" => "4"})
      grid.columns.should eq(4)
    end

    it "handles grid-rows" do
      grid = Tui::Grid.new
      grid.apply_css_style({"grid-rows" => "3"})
      grid.rows.should eq(3)
    end

    it "handles gap" do
      grid = Tui::Grid.new
      grid.apply_css_style({"gap" => "2"})
      grid.column_gap.should eq(2)
      grid.row_gap.should eq(2)
    end

    it "handles grid-gutter" do
      grid = Tui::Grid.new
      grid.apply_css_style({"grid-gutter" => "1"})
      grid.column_gap.should eq(1)
      grid.row_gap.should eq(1)
    end

    it "handles column-gap and row-gap separately" do
      grid = Tui::Grid.new
      grid.apply_css_style({"column-gap" => "3", "row-gap" => "1"})
      grid.column_gap.should eq(3)
      grid.row_gap.should eq(1)
    end
  end
end
