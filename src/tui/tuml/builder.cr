# TUML Builder - Converts parsed nodes to actual widgets

module Tui::TUML
  # Registry of widget factories
  class WidgetRegistry
    @@factories = {} of String => Proc(Node, Widget)

    def self.register(type : String, &factory : Node -> Widget)
      @@factories[type.downcase] = factory
    end

    def self.build(node : Node) : Widget?
      factory = @@factories[node.type.downcase]?
      return nil unless factory

      widget = factory.call(node)

      # Apply common properties
      widget.id = node.id
      node.classes.each { |c| widget.add_class(c) }

      # Build and add children
      node.children.each do |child_node|
        if child = build(child_node)
          if widget.responds_to?(:add_child)
            widget.add_child(child)
          elsif widget.responds_to?(:content=)
            widget.content = child
          end
        end
      end

      widget
    end

    # Register all built-in widgets
    def self.register_defaults
      # Containers
      register("App") { |n| build_placeholder(n, "App") }
      register("Panel") { |n| build_panel(n) }
      register("VBox") { |n| VBox.new(id: n.id) }
      register("HBox") { |n| HBox.new(id: n.id) }
      register("Grid") { |n| build_grid(n) }

      # Display
      register("Label") { |n| build_label(n) }
      register("Header") { |n| build_header(n) }
      register("Footer") { |n| build_footer(n) }
      register("Rule") { |n| build_rule(n) }
      register("ProgressBar") { |n| build_progress_bar(n) }
      register("Placeholder") { |n| build_placeholder(n, n.type) }

      # Input
      register("Button") { |n| build_button(n) }
      register("Input") { |n| build_input(n) }
      register("Checkbox") { |n| build_checkbox(n) }
      register("Switch") { |n| build_switch(n) }
      register("Slider") { |n| build_slider(n) }

      # Data
      register("Tree") { |n| Tree(String).new(id: n.id) }
      register("ListView") { |n| ListView(String).new(id: n.id) }
      register("DataTable") { |n| DataTable.new(id: n.id) }
      register("TextEditor") { |n| TextEditor.new(id: n.id) }
      register("Log") { |n| Log.new(id: n.id) }
    end

    # Widget builders
    private def self.build_panel(node : Node) : Panel
      panel = Panel.new(
        title: node.attributes["title"]? || "",
        id: node.id
      )

      if border = node.attributes["border"]?
        panel.border_style = case border.downcase
                             when "light"  then Panel::BorderStyle::Light
                             when "heavy"  then Panel::BorderStyle::Heavy
                             when "double" then Panel::BorderStyle::Double
                             when "round"  then Panel::BorderStyle::Round
                             when "none"   then Panel::BorderStyle::None
                             else               Panel::BorderStyle::Light
                             end
      end

      panel
    end

    private def self.build_label(node : Node) : Label
      text = node.text || node.attributes["text"]? || ""
      Label.new(text, id: node.id)
    end

    private def self.build_button(node : Node) : Button
      label = node.text || node.attributes["label"]? || node.attributes["text"]? || "Button"
      Button.new(label, id: node.id)
    end

    private def self.build_input(node : Node) : Input
      input = Input.new(id: node.id)
      input.placeholder = node.attributes["placeholder"]? || ""
      input.value = node.attributes["value"]? || ""
      input
    end

    private def self.build_checkbox(node : Node) : Checkbox
      label = node.text || node.attributes["label"]? || ""
      checked = node.attributes["checked"]? == "true"
      Checkbox.new(label, checked: checked, id: node.id)
    end

    private def self.build_switch(node : Node) : Switch
      on = node.attributes["on"]? == "true"
      Switch.new(id: node.id, on: on)
    end

    private def self.build_slider(node : Node) : Slider
      min = node.attributes["min"]?.try(&.to_f?) || 0.0
      max = node.attributes["max"]?.try(&.to_f?) || 100.0
      value = node.attributes["value"]?.try(&.to_f?) || min
      Slider.new(min: min, max: max, value: value, id: node.id)
    end

    private def self.build_header(node : Node) : Header
      title = node.text || node.attributes["title"]? || ""
      Header.new(id: node.id, title: title)
    end

    private def self.build_footer(node : Node) : Footer
      Footer.new(id: node.id)
    end

    private def self.build_rule(node : Node) : Rule
      direction = node.attributes["direction"]?.try(&.downcase) == "vertical" ? Rule::Direction::Vertical : Rule::Direction::Horizontal
      Rule.new(id: node.id, direction: direction)
    end

    private def self.build_progress_bar(node : Node) : ProgressBar
      bar = ProgressBar.new(id: node.id)
      if value = node.attributes["value"]?.try(&.to_f?)
        bar.value = value
      end
      bar
    end

    private def self.build_grid(node : Node) : Grid
      grid = Grid.new(id: node.id)
      grid.columns = node.attributes["columns"]?.try(&.to_i?) || 2
      grid
    end

    private def self.build_placeholder(node : Node, label : String) : Placeholder
      text = node.text || node.attributes["text"]? || label
      Placeholder.new(text, id: node.id)
    end
  end

  # Builder class for creating widget trees from TUML
  class Builder
    @@registered = false

    def self.from_file(path : String) : Widget?
      ensure_registered
      node = Parser.parse_file(path)
      WidgetRegistry.build(node)
    end

    def self.from_string(content : String, format : Symbol = :auto) : Widget?
      ensure_registered
      node = Parser.parse(content, format)
      WidgetRegistry.build(node)
    end

    private def self.ensure_registered
      return if @@registered
      WidgetRegistry.register_defaults
      @@registered = true
    end
  end
end
