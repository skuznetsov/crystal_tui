require "../../spec_helper"

describe Tui::Slider do
  describe "#initialize" do
    it "creates slider with defaults" do
      slider = Tui::Slider.new
      slider.value.should eq(0.0)
      slider.min.should eq(0.0)
      slider.max.should eq(100.0)
      slider.step.should eq(1.0)
    end

    it "creates slider with custom range" do
      slider = Tui::Slider.new(min: 10.0, max: 50.0, value: 30.0)
      slider.min.should eq(10.0)
      slider.max.should eq(50.0)
      slider.value.should eq(30.0)
    end

    it "clamps initial value to range" do
      slider = Tui::Slider.new(min: 0.0, max: 100.0, value: 150.0)
      slider.value.should eq(100.0)
    end

    it "accepts an id" do
      slider = Tui::Slider.new(id: "volume")
      slider.id.should eq("volume")
    end

    it "is focusable" do
      slider = Tui::Slider.new
      slider.focusable?.should be_true
    end
  end

  describe "#value=" do
    it "sets value within range" do
      slider = Tui::Slider.new(min: 0.0, max: 100.0)
      slider.value = 50.0
      slider.value.should eq(50.0)
    end

    it "clamps value to min" do
      slider = Tui::Slider.new(min: 0.0, max: 100.0)
      slider.value = -10.0
      slider.value.should eq(0.0)
    end

    it "clamps value to max" do
      slider = Tui::Slider.new(min: 0.0, max: 100.0)
      slider.value = 150.0
      slider.value.should eq(100.0)
    end

    it "triggers on_change callback" do
      changed_value = nil
      slider = Tui::Slider.new
      slider.on_change { |v| changed_value = v }
      slider.value = 42.0
      changed_value.should eq(42.0)
    end
  end

  describe "#increment" do
    it "increases value by step" do
      slider = Tui::Slider.new(value: 50.0, step: 5.0)
      slider.increment
      slider.value.should eq(55.0)
    end

    it "does not exceed max" do
      slider = Tui::Slider.new(value: 98.0, max: 100.0, step: 5.0)
      slider.increment
      slider.value.should eq(100.0)
    end
  end

  describe "#decrement" do
    it "decreases value by step" do
      slider = Tui::Slider.new(value: 50.0, step: 5.0)
      slider.decrement
      slider.value.should eq(45.0)
    end

    it "does not go below min" do
      slider = Tui::Slider.new(value: 2.0, min: 0.0, step: 5.0)
      slider.decrement
      slider.value.should eq(0.0)
    end
  end

  describe "#percentage" do
    it "returns 0 at min" do
      slider = Tui::Slider.new(min: 0.0, max: 100.0, value: 0.0)
      slider.percentage.should eq(0.0)
    end

    it "returns 1 at max" do
      slider = Tui::Slider.new(min: 0.0, max: 100.0, value: 100.0)
      slider.percentage.should eq(1.0)
    end

    it "returns 0.5 at midpoint" do
      slider = Tui::Slider.new(min: 0.0, max: 100.0, value: 50.0)
      slider.percentage.should eq(0.5)
    end

    it "handles custom range" do
      slider = Tui::Slider.new(min: 10.0, max: 20.0, value: 15.0)
      slider.percentage.should eq(0.5)
    end
  end

  describe "#min_size" do
    it "returns minimum dimensions" do
      slider = Tui::Slider.new
      min = slider.min_size
      min[0].should be > 0
      min[1].should eq(1)
    end
  end
end
