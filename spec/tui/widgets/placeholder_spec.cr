require "../../spec_helper"

describe Tui::Placeholder do
  describe "#initialize" do
    it "creates placeholder with default label" do
      ph = Tui::Placeholder.new
      ph.label.should eq("Placeholder")
    end

    it "creates placeholder with custom label" do
      ph = Tui::Placeholder.new("Sidebar")
      ph.label.should eq("Sidebar")
    end

    it "accepts an id" do
      ph = Tui::Placeholder.new("Test", id: "sidebar")
      ph.id.should eq("sidebar")
    end
  end

  describe "#label" do
    it "can be changed" do
      ph = Tui::Placeholder.new
      ph.label = "New Label"
      ph.label.should eq("New Label")
    end
  end

  describe "#show_dimensions" do
    it "defaults to true" do
      ph = Tui::Placeholder.new
      ph.show_dimensions.should be_true
    end

    it "can be disabled" do
      ph = Tui::Placeholder.new
      ph.show_dimensions = false
      ph.show_dimensions.should be_false
    end
  end

  describe "#fill_char" do
    it "defaults to middle dot" do
      ph = Tui::Placeholder.new
      ph.fill_char.should eq('·')
    end

    it "can be customized" do
      ph = Tui::Placeholder.new
      ph.fill_char = '#'
      ph.fill_char.should eq('#')
    end
  end

  describe "#min_size" do
    it "returns minimum dimensions" do
      ph = Tui::Placeholder.new
      min = ph.min_size
      min[0].should be >= 10
      min[1].should eq(5)
    end

    it "accounts for label length" do
      ph = Tui::Placeholder.new("Very Long Placeholder Label")
      min = ph.min_size
      min[0].should be >= 10
    end
  end
end
