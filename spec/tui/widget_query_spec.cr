require "../spec_helper"

private class RemountProbe < Tui::Widget
  getter compose_calls : Int32 = 0

  def compose : Array(Tui::Widget)
    @compose_calls += 1
    [Tui::Label.new("Fresh", id: "fresh")] of Tui::Widget
  end
end

describe "Widget queries" do
  it "finds nested widgets by id, class, and type" do
    label = Tui::Label.new("Nested", id: "target")
    label.add_class("primary")

    inner = Tui::Panel.new("Inner", id: "inner")
    inner.content = label

    root = Tui::Panel.new("Root", id: "root")
    root.content = inner

    root.query_one("#target", Tui::Label).should be(label)
    root.query_all(".primary").should eq([label] of Tui::Widget)
    root.query_all("Label").should eq([label] of Tui::Widget)
  end

  it "mounts children configured before their parent is attached" do
    label = Tui::Label.new("Nested", id: "target")
    root = Tui::Panel.new("Root") do |panel|
      panel.content = Tui::VBox.new do
        [label] of Tui::Widget
      end
    end

    root.on_mount
    root.on_mount

    label.mounted?.should be_true
    root.query_one("#target", Tui::Label).should be(label)
    root.children.size.should eq(1)
    root.children.first.children.size.should eq(1)
  end

  it "reuses composed children when remounted" do
    root = RemountProbe.new
    root.on_mount
    original_child = root.children.first

    root.on_unmount
    root.on_mount

    root.compose_calls.should eq(1)
    root.children.should eq([original_child] of Tui::Widget)
    original_child.mounted?.should be_true
  end
end
