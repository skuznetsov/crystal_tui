require "../../spec_helper"

describe Tui::ColorPicker do
  describe "#initialize" do
    it "creates color picker" do
      picker = Tui::ColorPicker.new
      picker.selected_index.should eq(0)
    end

    it "accepts an id" do
      picker = Tui::ColorPicker.new(id: "fg-color")
      picker.id.should eq("fg-color")
    end

    it "is focusable" do
      picker = Tui::ColorPicker.new
      picker.focusable?.should be_true
    end
  end

  describe "#selected_color" do
    it "returns color at selected index" do
      picker = Tui::ColorPicker.new
      picker.selected_index = 0
      picker.selected_color.should eq(Tui::Color.black)

      picker.selected_index = 1
      picker.selected_color.should eq(Tui::Color.red)
    end
  end

  describe "#selected_color=" do
    it "sets selected index from color" do
      picker = Tui::ColorPicker.new
      picker.selected_color = Tui::Color.green
      picker.selected_index.should eq(2)  # Green is at index 2
    end
  end

  describe "BASIC_COLORS" do
    it "has 16 basic colors" do
      Tui::ColorPicker::BASIC_COLORS.size.should eq(16)
    end

    it "includes standard colors" do
      colors = Tui::ColorPicker::BASIC_COLORS
      colors.should contain(Tui::Color.black)
      colors.should contain(Tui::Color.red)
      colors.should contain(Tui::Color.green)
      colors.should contain(Tui::Color.blue)
      colors.should contain(Tui::Color.white)
    end
  end

  describe "COLOR_NAMES" do
    it "has 16 color names" do
      Tui::ColorPicker::COLOR_NAMES.size.should eq(16)
    end

    it "matches BASIC_COLORS count" do
      Tui::ColorPicker::COLOR_NAMES.size.should eq(Tui::ColorPicker::BASIC_COLORS.size)
    end
  end

  describe "#min_size" do
    it "returns minimum dimensions" do
      picker = Tui::ColorPicker.new
      min = picker.min_size
      min[0].should be > 0
      min[1].should be > 0
    end
  end
end
