require "../../spec_helper"

describe Tui::TUML::Parser do
  describe ".parse_pug" do
    it "parses simple widget" do
      node = Tui::TUML::Parser.parse("Button", :pug)
      node.type.should eq "Button"
      node.id.should be_nil
      node.classes.should be_empty
    end

    it "parses widget with id" do
      node = Tui::TUML::Parser.parse("Button#submit", :pug)
      node.type.should eq "Button"
      node.id.should eq "submit"
    end

    it "parses widget with classes" do
      node = Tui::TUML::Parser.parse("Button.primary.large", :pug)
      node.type.should eq "Button"
      node.classes.should eq ["primary", "large"]
    end

    it "parses widget with id and classes" do
      node = Tui::TUML::Parser.parse("Button#submit.primary", :pug)
      node.type.should eq "Button"
      node.id.should eq "submit"
      node.classes.should eq ["primary"]
    end

    it "parses widget with attributes" do
      node = Tui::TUML::Parser.parse("Input(placeholder=\"Enter name\")", :pug)
      node.type.should eq "Input"
      node.attributes["placeholder"].should eq "Enter name"
    end

    it "parses widget with text content" do
      node = Tui::TUML::Parser.parse("Button Click me", :pug)
      node.type.should eq "Button"
      node.text.should eq "Click me"
    end

    it "parses widget with everything" do
      node = Tui::TUML::Parser.parse("Button#submit.primary(disabled=\"true\") Save", :pug)
      node.type.should eq "Button"
      node.id.should eq "submit"
      node.classes.should eq ["primary"]
      node.attributes["disabled"].should eq "true"
      node.text.should eq "Save"
    end

    it "parses nested widgets" do
      content = <<-TUI
      Panel#main
        Button#btn1 First
        Button#btn2 Second
      TUI

      node = Tui::TUML::Parser.parse(content, :pug)
      node.type.should eq "Panel"
      node.id.should eq "main"
      node.children.size.should eq 2
      node.children[0].type.should eq "Button"
      node.children[0].id.should eq "btn1"
      node.children[1].id.should eq "btn2"
    end

    it "parses deeply nested widgets" do
      content = <<-TUI
      Panel#outer
        Panel#inner
          Button Click
      TUI

      node = Tui::TUML::Parser.parse(content, :pug)
      node.children.size.should eq 1
      node.children[0].type.should eq "Panel"
      node.children[0].children.size.should eq 1
      node.children[0].children[0].type.should eq "Button"
    end
  end

  describe ".parse_yaml" do
    it "parses simple widget" do
      yaml = <<-YAML
      Button#submit:
        text: Click me
      YAML

      node = Tui::TUML::Parser.parse(yaml, :yaml)
      node.type.should eq "Button"
      node.id.should eq "submit"
      node.text.should eq "Click me"
    end

    it "parses widget with attributes" do
      yaml = <<-YAML
      Input#name:
        placeholder: Enter name
        value: default
      YAML

      node = Tui::TUML::Parser.parse(yaml, :yaml)
      node.type.should eq "Input"
      node.attributes["placeholder"].should eq "Enter name"
      node.attributes["value"].should eq "default"
    end

    it "parses nested widgets" do
      yaml = <<-YAML
      Panel#main:
        title: Main Panel
        children:
          - Button#btn1:
              text: First
          - Button#btn2:
              text: Second
      YAML

      node = Tui::TUML::Parser.parse(yaml, :yaml)
      node.type.should eq "Panel"
      node.attributes["title"].should eq "Main Panel"
      node.children.size.should eq 2
    end
  end

  describe ".parse_json" do
    it "parses simple widget" do
      json = %({"type": "Button", "id": "submit", "text": "Click me"})

      node = Tui::TUML::Parser.parse(json, :json)
      node.type.should eq "Button"
      node.id.should eq "submit"
      node.text.should eq "Click me"
    end

    it "parses widget with classes" do
      json = %({"type": "Button", "classes": ["primary", "large"]})

      node = Tui::TUML::Parser.parse(json, :json)
      node.classes.should eq ["primary", "large"]
    end

    it "parses nested widgets" do
      json = <<-JSON
      {
        "type": "Panel",
        "id": "main",
        "children": [
          {"type": "Button", "id": "btn1", "text": "First"},
          {"type": "Button", "id": "btn2", "text": "Second"}
        ]
      }
      JSON

      node = Tui::TUML::Parser.parse(json, :json)
      node.type.should eq "Panel"
      node.children.size.should eq 2
    end
  end

  describe ".parse (auto-detect)" do
    it "detects JSON" do
      node = Tui::TUML::Parser.parse(%({"type": "Button"}))
      node.type.should eq "Button"
    end

    it "detects YAML" do
      node = Tui::TUML::Parser.parse("Button#test:\n  text: Hello")
      node.type.should eq "Button"
    end

    it "detects Pug" do
      node = Tui::TUML::Parser.parse("Button#test Hello")
      node.type.should eq "Button"
    end
  end
end

describe Tui::TUML::Builder do
  it "builds button from pug" do
    widget = Tui::TUML::Builder.from_string("Button#submit.primary Click me", :pug)
    widget.should_not be_nil

    button = widget.as(Tui::Button)
    button.id.should eq "submit"
    button.has_class?("primary").should be_true
    button.label.should eq "Click me"
  end

  it "builds label from pug" do
    widget = Tui::TUML::Builder.from_string("Label#title Hello World", :pug)
    widget.should_not be_nil

    label = widget.as(Tui::Label)
    label.text.should eq "Hello World"
  end

  it "builds input from pug" do
    widget = Tui::TUML::Builder.from_string("Input#name(placeholder=\"Name\")", :pug)
    widget.should_not be_nil

    input = widget.as(Tui::Input)
    input.placeholder.should eq "Name"
  end

  it "builds panel with children" do
    content = <<-TUI
    Panel#main(title="Test")
      Label#lbl Hello
      Button#btn Click
    TUI

    widget = Tui::TUML::Builder.from_string(content, :pug)
    widget.should_not be_nil

    panel = widget.as(Tui::Panel)
    panel.title.should eq "Test"
    panel.children.size.should eq 2
  end
end
