# TUML - TUI Markup Language Parser
# Supports three formats: Pug-style (.tui), YAML (.tui.yaml), JSON (.tui.json)

require "yaml"
require "json"

module Tui::TUML
  # Parsed node representing a widget
  class Node
    property type : String
    property id : String?
    property classes : Array(String)
    property attributes : Hash(String, String)
    property text : String?
    property children : Array(Node)

    def initialize(
      @type : String,
      @id : String? = nil,
      @classes : Array(String) = [] of String,
      @attributes : Hash(String, String) = {} of String => String,
      @text : String? = nil,
      @children : Array(Node) = [] of Node
    )
    end

    def to_s(indent : Int32 = 0) : String
      prefix = "  " * indent
      parts = [@type]
      parts << "##{@id}" if @id
      @classes.each { |c| parts << ".#{c}" }

      result = "#{prefix}#{parts.join}"
      result += "(#{@attributes.map { |k, v| "#{k}=\"#{v}\"" }.join(" ")})" unless @attributes.empty?
      result += " #{@text}" if @text && !@text.not_nil!.empty?

      @children.each do |child|
        result += "\n#{child.to_s(indent + 1)}"
      end

      result
    end
  end

  # Main parser - detects format and delegates
  class Parser
    def self.parse_file(path : String) : Node
      content = File.read(path)

      case path
      when /\.tui\.ya?ml$/i
        parse_yaml(content)
      when /\.tui\.json$/i
        parse_json(content)
      when /\.tui$/i
        parse_pug(content)
      else
        # Try to detect format from content
        if content.starts_with?("{")
          parse_json(content)
        elsif content.includes?(": ")
          parse_yaml(content)
        else
          parse_pug(content)
        end
      end
    end

    def self.parse(content : String, format : Symbol = :auto) : Node
      case format
      when :yaml
        parse_yaml(content)
      when :json
        parse_json(content)
      when :pug
        parse_pug(content)
      else
        # Auto-detect
        if content.strip.starts_with?("{")
          parse_json(content)
        elsif content.includes?(": ") && !content.includes?("(")
          parse_yaml(content)
        else
          parse_pug(content)
        end
      end
    end

    # Parse Pug-style format
    # Example:
    #   Panel#main.active(title="Hello")
    #     Button#submit Click me
    def self.parse_pug(content : String) : Node
      lines = content.lines.reject(&.blank?)
      return Node.new("App") if lines.empty?

      root, _ = parse_pug_lines(lines, 0, 0)
      root
    end

    private def self.parse_pug_lines(lines : Array(String), index : Int32, base_indent : Int32) : {Node, Int32}
      return {Node.new("App"), index} if index >= lines.size

      line = lines[index]
      indent = line.size - line.lstrip.size
      content = line.strip

      # Parse the line: Type#id.class.class(attr="val" attr2="val2") text content
      node = parse_pug_line(content)
      index += 1

      # Parse children (lines with greater indentation)
      while index < lines.size
        next_line = lines[index]
        next_indent = next_line.size - next_line.lstrip.size

        break if next_indent <= indent

        child, index = parse_pug_lines(lines, index, indent)
        node.children << child
      end

      {node, index}
    end

    private def self.parse_pug_line(line : String) : Node
      # Pattern: Type#id.class.class(attrs) text
      # Examples:
      #   Panel#main
      #   Button.primary.large
      #   Label#title(text="Hello") Some text
      #   Input(placeholder="Enter name")
      #   Button Click me

      type = ""
      id : String? = nil
      classes = [] of String
      attributes = {} of String => String
      text : String? = nil

      # Improved regex: selector is only valid chars, then optional attrs, then text
      # Selector: word chars, #, ., -
      if match = line.match(/^([a-zA-Z0-9_#.-]+)(?:\(([^)]*)\))?\s*(.*)$/)
        selector = match[1]
        attrs_str = match[2]?
        text = match[3]?.try(&.strip)
        text = nil if text && text.empty?

        # Parse selector: Type#id.class.class
        selector.scan(/([.#]?)([a-zA-Z0-9_-]+)/) do |m|
          prefix = m[1]
          value = m[2]

          case prefix
          when "#"
            id = value
          when "."
            classes << value
          else
            type = value if type.empty?
          end
        end

        # Parse attributes: key="value" key2='value2' key3=value4
        if attrs_str
          attrs_str.scan(/(\w+)=(?:"([^"]*)"|'([^']*)'|(\S+))/) do |m|
            key = m[1]
            value = m[2]? || m[3]? || m[4]? || ""
            attributes[key] = value
          end
        end
      end

      type = "Widget" if type.empty?

      Node.new(type, id, classes, attributes, text)
    end

    # Parse YAML format
    def self.parse_yaml(content : String) : Node
      yaml = YAML.parse(content)
      parse_yaml_node(yaml)
    end

    private def self.parse_yaml_node(yaml : YAML::Any) : Node
      case yaml.raw
      when Hash
        hash = yaml.as_h

        # Find the widget definition (first key that looks like Type#id.class)
        hash.each do |key, value|
          key_str = key.as_s

          # Parse key as selector
          type, id, classes = parse_selector(key_str)

          attributes = {} of String => String
          children = [] of Node
          text : String? = nil

          if value.raw.is_a?(Hash)
            value.as_h.each do |attr_key, attr_value|
              attr_key_str = attr_key.as_s

              if attr_key_str == "children"
                attr_value.as_a.each do |child|
                  children << parse_yaml_node(child)
                end
              elsif attr_key_str == "text"
                text = attr_value.as_s?
              else
                attributes[attr_key_str] = attr_value.raw.to_s
              end
            end
          elsif value.raw.is_a?(String)
            text = value.as_s
          end

          return Node.new(type, id, classes, attributes, text, children)
        end

        Node.new("Widget")
      else
        Node.new("Widget")
      end
    end

    # Parse JSON format
    def self.parse_json(content : String) : Node
      json = JSON.parse(content)
      parse_json_node(json)
    end

    private def self.parse_json_node(json : JSON::Any) : Node
      return Node.new("Widget") unless json.raw.is_a?(Hash)

      hash = json.as_h

      type = hash["type"]?.try(&.as_s?) || "Widget"
      id = hash["id"]?.try(&.as_s?)
      classes = hash["classes"]?.try(&.as_a?.try(&.map(&.as_s))) || [] of String
      text = hash["text"]?.try(&.as_s?)

      attributes = {} of String => String
      hash.each do |key, value|
        next if ["type", "id", "classes", "text", "children"].includes?(key)
        attributes[key] = value.raw.to_s
      end

      children = [] of Node
      if child_array = hash["children"]?.try(&.as_a?)
        child_array.each do |child|
          children << parse_json_node(child)
        end
      end

      Node.new(type, id, classes, attributes, text, children)
    end

    # Parse selector string like "Type#id.class1.class2"
    private def self.parse_selector(selector : String) : {String, String?, Array(String)}
      type = ""
      id : String? = nil
      classes = [] of String

      selector.scan(/([.#]?)([a-zA-Z0-9_-]+)/) do |m|
        prefix = m[1]
        value = m[2]

        case prefix
        when "#"
          id = value
        when "."
          classes << value
        else
          type = value if type.empty?
        end
      end

      type = "Widget" if type.empty?

      {type, id, classes}
    end
  end
end
