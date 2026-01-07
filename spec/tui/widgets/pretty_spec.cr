require "../../spec_helper"

describe Tui::Pretty do
  describe "#initialize" do
    it "creates empty pretty widget" do
      pretty = Tui::Pretty.new
      pretty.data.should eq("")
    end

    it "accepts an id" do
      pretty = Tui::Pretty.new(id: "json-view")
      pretty.id.should eq("json-view")
    end

    it "is focusable" do
      pretty = Tui::Pretty.new
      pretty.focusable?.should be_true
    end
  end

  describe "#data=" do
    it "sets raw string data" do
      pretty = Tui::Pretty.new
      pretty.data = "test data"
      pretty.data.should eq("test data")
    end
  end

  describe "#object=" do
    it "formats nil" do
      pretty = Tui::Pretty.new
      pretty.object = nil
      pretty.data.should eq("null")
    end

    it "formats boolean" do
      pretty = Tui::Pretty.new
      pretty.object = true
      pretty.data.should eq("true")

      pretty.object = false
      pretty.data.should eq("false")
    end

    it "formats numbers" do
      pretty = Tui::Pretty.new
      pretty.object = 42
      pretty.data.should eq("42")

      pretty.object = 3.14
      pretty.data.should eq("3.14")
    end

    it "formats strings with quotes" do
      pretty = Tui::Pretty.new
      pretty.object = "hello"
      pretty.data.should eq("\"hello\"")
    end

    it "escapes special characters in strings" do
      pretty = Tui::Pretty.new
      pretty.object = "line1\nline2"
      pretty.data.should eq("\"line1\\nline2\"")
    end

    it "formats empty array" do
      pretty = Tui::Pretty.new
      pretty.object = [] of Int32
      pretty.data.should eq("[]")
    end

    it "formats array with items" do
      pretty = Tui::Pretty.new
      pretty.object = [1, 2, 3]
      pretty.data.should contain("1")
      pretty.data.should contain("2")
      pretty.data.should contain("3")
    end

    it "formats empty hash" do
      pretty = Tui::Pretty.new
      pretty.object = {} of String => Int32
      pretty.data.should eq("{}")
    end

    it "formats hash with items" do
      pretty = Tui::Pretty.new
      pretty.object = {"name" => "test", "value" => 42}
      pretty.data.should contain("name")
      pretty.data.should contain("test")
      pretty.data.should contain("value")
      pretty.data.should contain("42")
    end
  end

  describe "#scroll_offset" do
    it "defaults to 0" do
      pretty = Tui::Pretty.new
      pretty.scroll_offset.should eq(0)
    end
  end

  describe "#min_size" do
    it "returns minimum dimensions" do
      pretty = Tui::Pretty.new
      min = pretty.min_size
      min[0].should be > 0
      min[1].should be > 0
    end
  end
end
