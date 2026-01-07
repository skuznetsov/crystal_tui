require "../../spec_helper"

describe Tui::Link do
  describe "#initialize" do
    it "creates link with text" do
      link = Tui::Link.new("Click me")
      link.text.should eq("Click me")
      link.url.should eq("Click me")  # URL defaults to text
    end

    it "creates link with text and url" do
      link = Tui::Link.new("Google", "https://google.com")
      link.text.should eq("Google")
      link.url.should eq("https://google.com")
    end

    it "accepts an id" do
      link = Tui::Link.new("Test", id: "my-link")
      link.id.should eq("my-link")
    end

    it "is focusable" do
      link = Tui::Link.new("Test")
      link.focusable?.should be_true
    end
  end

  describe "#visited" do
    it "starts as not visited" do
      link = Tui::Link.new("Test")
      link.visited?.should be_false
    end

    it "can be set to visited" do
      link = Tui::Link.new("Test")
      link.visited = true
      link.visited?.should be_true
    end
  end

  describe "#activate" do
    it "marks link as visited" do
      link = Tui::Link.new("Test")
      link.activate
      link.visited?.should be_true
    end

    it "calls on_click callback" do
      clicked_url = nil
      link = Tui::Link.new("Test", "https://example.com")
      link.on_click { |url| clicked_url = url }
      link.activate
      clicked_url.should eq("https://example.com")
    end
  end

  describe "#min_size" do
    it "returns width based on text length" do
      link = Tui::Link.new("Hello")
      min = link.min_size
      min[0].should eq(5)  # "Hello" is 5 chars
      min[1].should eq(1)  # single line
    end

    it "handles unicode text" do
      link = Tui::Link.new("日本語")
      min = link.min_size
      min[0].should eq(6)  # 3 wide chars
    end
  end
end
