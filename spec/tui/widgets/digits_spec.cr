require "../../spec_helper"

describe Tui::Digits do
  describe "#initialize" do
    it "creates digits display with default value" do
      digits = Tui::Digits.new
      digits.value.should eq("0")
    end

    it "creates digits display with custom value" do
      digits = Tui::Digits.new(value: "123")
      digits.value.should eq("123")
    end

    it "accepts an id" do
      digits = Tui::Digits.new(id: "counter")
      digits.id.should eq("counter")
    end
  end

  describe "#value" do
    it "can be set directly" do
      digits = Tui::Digits.new
      digits.value = "42"
      digits.value.should eq("42")
    end
  end

  describe "#number=" do
    it "sets integer value" do
      digits = Tui::Digits.new
      digits.number = 123
      digits.value.should eq("123")
    end

    it "sets float value" do
      digits = Tui::Digits.new
      digits.number = 3.14
      digits.value.should eq("3.14")
    end

    it "handles negative numbers" do
      digits = Tui::Digits.new
      digits.number = -42
      digits.value.should eq("-42")
    end
  end

  describe "#min_size" do
    it "returns correct width for single digit" do
      digits = Tui::Digits.new(value: "0")
      min = digits.min_size
      min[0].should eq(3)  # DIGIT_WIDTH
      min[1].should eq(5)  # DIGIT_HEIGHT
    end

    it "returns correct width for multiple digits" do
      digits = Tui::Digits.new(value: "123")
      min = digits.min_size
      # 3 digits * (3 width + 1 spacing) - 1 = 11
      min[0].should eq(11)
      min[1].should eq(5)
    end

    it "accounts for special characters" do
      digits = Tui::Digits.new(value: "12:34")
      min = digits.min_size
      # 5 chars * (3 + 1) - 1 = 19
      min[0].should eq(19)
    end
  end

  describe "patterns" do
    it "has patterns for all digits" do
      (0..9).each do |n|
        Tui::Digits::PATTERNS[n.to_s[0]].should_not be_nil
      end
    end

    it "has patterns for special characters" do
      ['-', '+', '.', ':', ' '].each do |char|
        Tui::Digits::PATTERNS[char].should_not be_nil
      end
    end

    it "patterns are correct size" do
      Tui::Digits::PATTERNS.each_value do |pattern|
        pattern.size.should eq(5)  # DIGIT_HEIGHT
        pattern.each do |line|
          line.size.should eq(3)  # DIGIT_WIDTH
        end
      end
    end
  end
end
