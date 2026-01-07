require "../../spec_helper"

describe Tui::MaskedInput do
  describe "#initialize" do
    it "creates masked input with mask" do
      input = Tui::MaskedInput.new("(999) 999-9999")
      input.mask.should eq("(999) 999-9999")
    end

    it "accepts an id" do
      input = Tui::MaskedInput.new("999", id: "phone")
      input.id.should eq("phone")
    end

    it "is focusable" do
      input = Tui::MaskedInput.new("999")
      input.focusable?.should be_true
    end
  end

  describe "#raw_value" do
    it "returns empty string when nothing entered" do
      input = Tui::MaskedInput.new("999-999")
      input.raw_value.should eq("")
    end

    it "returns only user-entered characters" do
      input = Tui::MaskedInput.new("999-999")
      input.raw_value = "123456"
      input.raw_value.should eq("123456")
    end
  end

  describe "#formatted_value" do
    it "shows placeholders when empty" do
      input = Tui::MaskedInput.new("99/99")
      input.formatted_value.should eq("__/__")
    end

    it "includes mask literals" do
      input = Tui::MaskedInput.new("99/99/9999")
      input.raw_value = "12252023"
      input.formatted_value.should eq("12/25/2023")
    end
  end

  describe "#raw_value=" do
    it "sets value correctly" do
      input = Tui::MaskedInput.new("(999) 999-9999")
      input.raw_value = "5551234567"
      input.raw_value.should eq("5551234567")
    end

    it "ignores invalid characters" do
      input = Tui::MaskedInput.new("999")  # digits only
      input.raw_value = "1a2b3"
      input.raw_value.should eq("123")
    end
  end

  describe "#complete?" do
    it "returns false when not all fields filled" do
      input = Tui::MaskedInput.new("999-999")
      input.raw_value = "123"
      input.complete?.should be_false
    end

    it "returns true when all fields filled" do
      input = Tui::MaskedInput.new("999-999")
      input.raw_value = "123456"
      input.complete?.should be_true
    end
  end

  describe "#clear" do
    it "clears all input" do
      input = Tui::MaskedInput.new("999")
      input.raw_value = "123"
      input.clear
      input.raw_value.should eq("")
    end
  end

  describe "mask patterns" do
    it "handles digit mask (9)" do
      input = Tui::MaskedInput.new("999")
      input.raw_value = "abc"  # letters not allowed
      input.raw_value.should eq("")
    end

    it "handles letter mask (a)" do
      input = Tui::MaskedInput.new("aaa")
      input.raw_value = "123"  # digits not allowed
      input.raw_value.should eq("")
      input.raw_value = "ABC"
      input.raw_value.should eq("ABC")
    end

    it "handles alphanumeric mask (*)" do
      input = Tui::MaskedInput.new("***")
      input.raw_value = "A1B"
      input.raw_value.should eq("A1B")
    end
  end

  describe "#min_size" do
    it "returns width based on mask length" do
      input = Tui::MaskedInput.new("(999) 999-9999")
      min = input.min_size
      min[0].should eq(14)
      min[1].should eq(1)
    end
  end
end
