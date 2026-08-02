require "../spec_helper"

private class CSSLifecycleApp < Tui::App
  getter label : Tui::Label

  def initialize
    @label = Tui::Label.new("Styled", id: "styled")
    super
  end

  def compose : Array(Tui::Widget)
    [@label] of Tui::Widget
  end
end

describe "App CSS lifecycle" do
  it "applies a stylesheet loaded before mount to composed widgets" do
    app = CSSLifecycleApp.new
    app.load_css_string("Label { color: red; }")

    app.mount_headless(40, 10)

    app.label.style.fg.should eq(Tui::Color.red)
  end

  it "applies parsed hex colors to labels" do
    app = CSSLifecycleApp.new
    app.load_css_string("Label { color: #666; }")

    app.mount_headless(40, 10)

    app.label.style.fg.should eq(Tui::Color.rgb(102, 102, 102))
  end
end
