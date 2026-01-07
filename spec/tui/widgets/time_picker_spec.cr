require "../../spec_helper"

describe Tui::TimePicker do
  describe "#initialize" do
    it "creates time picker with defaults" do
      picker = Tui::TimePicker.new
      picker.hour.should eq(0)
      picker.minute.should eq(0)
      picker.second.should eq(0)
    end

    it "creates with specific time" do
      picker = Tui::TimePicker.new(hour: 14, minute: 30, second: 45)
      picker.hour.should eq(14)
      picker.minute.should eq(30)
      picker.second.should eq(45)
    end

    it "clamps values to valid range" do
      picker = Tui::TimePicker.new(hour: 25, minute: 70, second: 100)
      picker.hour.should eq(23)
      picker.minute.should eq(59)
      picker.second.should eq(59)
    end

    it "accepts an id" do
      picker = Tui::TimePicker.new(id: "alarm")
      picker.id.should eq("alarm")
    end

    it "is focusable" do
      picker = Tui::TimePicker.new
      picker.focusable?.should be_true
    end
  end

  describe "#time=" do
    it "sets time from Time object" do
      picker = Tui::TimePicker.new
      t = Time.local(2023, 1, 1, 15, 45, 30)
      picker.time = t
      picker.hour.should eq(15)
      picker.minute.should eq(45)
      picker.second.should eq(30)
    end
  end

  describe "#time" do
    it "returns Time object" do
      picker = Tui::TimePicker.new(hour: 10, minute: 20, second: 30)
      t = picker.time
      t.hour.should eq(10)
      t.minute.should eq(20)
      t.second.should eq(30)
    end
  end

  describe "#to_s" do
    it "formats 24h time with seconds" do
      picker = Tui::TimePicker.new(hour: 14, minute: 5, second: 9)
      picker.use_24h = true
      picker.show_seconds = true
      picker.to_s.should eq("14:05:09")
    end

    it "formats 24h time without seconds" do
      picker = Tui::TimePicker.new(hour: 14, minute: 5, second: 9)
      picker.use_24h = true
      picker.show_seconds = false
      picker.to_s.should eq("14:05")
    end

    it "formats 12h AM time" do
      picker = Tui::TimePicker.new(hour: 9, minute: 30, second: 0)
      picker.use_24h = false
      picker.show_seconds = false
      picker.to_s.should eq("09:30 AM")
    end

    it "formats 12h PM time" do
      picker = Tui::TimePicker.new(hour: 14, minute: 30, second: 0)
      picker.use_24h = false
      picker.show_seconds = false
      picker.to_s.should eq("02:30 PM")
    end

    it "handles midnight in 12h format" do
      picker = Tui::TimePicker.new(hour: 0, minute: 0, second: 0)
      picker.use_24h = false
      picker.show_seconds = false
      picker.to_s.should eq("12:00 AM")
    end

    it "handles noon in 12h format" do
      picker = Tui::TimePicker.new(hour: 12, minute: 0, second: 0)
      picker.use_24h = false
      picker.show_seconds = false
      picker.to_s.should eq("12:00 PM")
    end
  end

  describe "#min_size" do
    it "returns minimum dimensions for 24h with seconds" do
      picker = Tui::TimePicker.new
      picker.use_24h = true
      picker.show_seconds = true
      min = picker.min_size
      min[0].should eq(8)  # HH:MM:SS
      min[1].should eq(1)
    end

    it "returns minimum dimensions for 12h without seconds" do
      picker = Tui::TimePicker.new
      picker.use_24h = false
      picker.show_seconds = false
      min = picker.min_size
      min[0].should eq(8)  # HH:MM + " AM"
      min[1].should eq(1)
    end
  end
end
