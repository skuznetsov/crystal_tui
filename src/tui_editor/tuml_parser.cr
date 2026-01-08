# TUML Parser - Parse Pug/YAML format back to CanvasNode tree
require "./widget_palette"
require "./canvas"

module TuiEditor
  class TumlParser
    struct ParseError
      property message : String
      property line : Int32
      property column : Int32

      def initialize(@message, @line = 0, @column = 0)
      end

      def to_s : String
        "Line #{@line + 1}: #{@message}"
      end
    end

    alias ParseResult = CanvasNode | ParseError

    # Widget lookup by name
    WIDGET_MAP = WidgetPalette::WIDGETS.to_h { |w| {w.name, w} }

    # Parse Pug format
    def self.parse_pug(source : String) : ParseResult
      lines = source.split('\n')
      return ParseError.new("Empty source") if lines.empty?

      # Build tree from indented lines
      root : CanvasNode? = nil
      stack = [] of {Int32, CanvasNode}  # indent level, node

      lines.each_with_index do |line, line_num|
        # Skip empty lines and comments
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')

        # Calculate indent (2 spaces per level)
        indent = 0
        line.each_char do |c|
          break unless c == ' '
          indent += 1
        end
        indent //= 2

        # Parse line: WidgetName#id(attr="val", attr2="val2") optional text
        result = parse_pug_line(stripped, line_num)
        return result if result.is_a?(ParseError)

        node = result.as(CanvasNode)

        if root.nil?
          root = node
          stack = [{0, node}]
        else
          # Find parent by indent level
          while stack.size > 0 && stack.last[0] >= indent
            stack.pop
          end

          if stack.empty?
            return ParseError.new("Invalid indentation - no parent found", line_num)
          end

          parent = stack.last[1]
          parent.add_child(node)
          stack << {indent, node}
        end
      end

      root || ParseError.new("No widgets found")
    end

    private def self.parse_pug_line(line : String, line_num : Int32) : ParseResult
      # Pattern: WidgetName#id(attrs) text
      # Examples:
      #   Panel
      #   Button#btn1
      #   Input(placeholder="Enter")
      #   Label#lbl(text="Hello") World

      pos = 0

      # Parse widget name (required)
      name_end = pos
      while name_end < line.size && line[name_end].alphanumeric?
        name_end += 1
      end

      if name_end == pos
        return ParseError.new("Expected widget name", line_num, pos)
      end

      widget_name = line[pos...name_end]
      pos = name_end

      # Check widget exists
      widget_def = WIDGET_MAP[widget_name]?
      unless widget_def
        return ParseError.new("Unknown widget: #{widget_name}", line_num, pos)
      end

      # Parse optional ID: #id
      id = ""
      if pos < line.size && line[pos] == '#'
        pos += 1
        id_end = pos
        while id_end < line.size && (line[id_end].alphanumeric? || line[id_end] == '_' || line[id_end] == '-')
          id_end += 1
        end
        id = line[pos...id_end]
        pos = id_end
      end

      # Parse optional attributes: (key="value", key2="value2")
      attrs = {} of String => String
      if pos < line.size && line[pos] == '('
        pos += 1
        result = parse_attrs(line, pos, line_num)
        case result
        when ParseError
          return result
        when {Hash(String, String), Int32}
          attrs, pos = result
        end
      end

      # Parse optional inline text (rest of line after space)
      if pos < line.size && line[pos] == ' '
        text = line[(pos + 1)..].strip
        if !text.empty?
          # Determine which attr to set based on widget type
          case widget_name
          when "Button"
            attrs["label"] = text unless attrs.has_key?("label")
          when "Label"
            attrs["text"] = text unless attrs.has_key?("text")
          when "Panel", "Header"
            attrs["title"] = text unless attrs.has_key?("title")
          when "Input"
            attrs["placeholder"] = text unless attrs.has_key?("placeholder")
          when "Checkbox"
            attrs["label"] = text unless attrs.has_key?("label")
          end
        end
      end

      # Generate ID if not provided
      id = CanvasNode.next_id(widget_name) if id.empty?

      CanvasNode.new(widget_def, id, attrs)
    end

    private def self.parse_attrs(line : String, start_pos : Int32, line_num : Int32) : {Hash(String, String), Int32} | ParseError
      attrs = {} of String => String
      pos = start_pos

      while pos < line.size && line[pos] != ')'
        # Skip whitespace and commas
        while pos < line.size && (line[pos].whitespace? || line[pos] == ',')
          pos += 1
        end

        break if pos >= line.size || line[pos] == ')'

        # Parse key
        key_start = pos
        while pos < line.size && (line[pos].alphanumeric? || line[pos] == '_')
          pos += 1
        end
        key = line[key_start...pos]

        if key.empty?
          return ParseError.new("Expected attribute name", line_num, pos)
        end

        # Expect =
        while pos < line.size && line[pos].whitespace?
          pos += 1
        end

        if pos >= line.size || line[pos] != '='
          return ParseError.new("Expected '=' after attribute name", line_num, pos)
        end
        pos += 1

        # Skip whitespace
        while pos < line.size && line[pos].whitespace?
          pos += 1
        end

        # Parse value (quoted string or bare word)
        if pos < line.size && (line[pos] == '"' || line[pos] == '\'')
          quote = line[pos]
          pos += 1
          value_start = pos
          while pos < line.size && line[pos] != quote
            pos += 1
          end
          value = line[value_start...pos]
          pos += 1 if pos < line.size  # Skip closing quote
        else
          # Bare value
          value_start = pos
          while pos < line.size && !line[pos].whitespace? && line[pos] != ',' && line[pos] != ')'
            pos += 1
          end
          value = line[value_start...pos]
        end

        attrs[key] = value
      end

      # Skip closing paren
      pos += 1 if pos < line.size && line[pos] == ')'

      {attrs, pos}
    end

    # Parse YAML format
    def self.parse_yaml(source : String) : ParseResult
      lines = source.split('\n')
      return ParseError.new("Empty source") if lines.empty?

      root : CanvasNode? = nil
      stack = [] of {Int32, CanvasNode, Symbol}  # indent, node, :attrs or :children

      current_attrs = {} of String => String
      current_node : CanvasNode? = nil
      current_indent = 0
      mode = :widget  # :widget, :attrs, :children

      lines.each_with_index do |line, line_num|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')

        # Calculate indent
        indent = 0
        line.each_char do |c|
          break unless c == ' '
          indent += 1
        end

        # Widget line: WidgetName#id:
        if stripped.matches?(/^[A-Z]\w*(#\w+)?:\s*$/)
          # Finalize previous node's attrs
          if current_node
            current_attrs.each { |k, v| current_node.not_nil!.attrs[k] = v }
            current_attrs.clear
          end

          result = parse_yaml_widget_line(stripped, line_num)
          return result if result.is_a?(ParseError)

          node = result.as(CanvasNode)

          if root.nil?
            root = node
            stack = [{indent, node, :attrs}]
          else
            # Find parent by indent
            while stack.size > 0 && stack.last[0] >= indent
              stack.pop
            end

            if stack.empty?
              return ParseError.new("Invalid indentation", line_num)
            end

            parent = stack.last[1]
            parent.add_child(node)
            stack << {indent, node, :attrs}
          end

          current_node = node
          current_indent = indent
          mode = :attrs

        elsif stripped == "children:"
          mode = :children

        elsif stripped.includes?(':') && mode == :attrs
          # Attribute line: key: value
          parts = stripped.split(':', 2)
          key = parts[0].strip
          value = parts[1]?.try(&.strip) || ""
          current_attrs[key] = value

        end
      end

      # Finalize last node
      if current_node
        current_attrs.each { |k, v| current_node.not_nil!.attrs[k] = v }
      end

      root || ParseError.new("No widgets found")
    end

    private def self.parse_yaml_widget_line(line : String, line_num : Int32) : ParseResult
      # Pattern: WidgetName#id:
      line = line.chomp(':').strip

      # Parse widget name
      name_end = 0
      while name_end < line.size && line[name_end].alphanumeric?
        name_end += 1
      end

      widget_name = line[0...name_end]
      widget_def = WIDGET_MAP[widget_name]?
      unless widget_def
        return ParseError.new("Unknown widget: #{widget_name}", line_num)
      end

      # Parse optional ID
      id = ""
      if name_end < line.size && line[name_end] == '#'
        id = line[(name_end + 1)..]
      end

      id = CanvasNode.next_id(widget_name) if id.empty?

      CanvasNode.new(widget_def, id)
    end

    # Detect format from source
    def self.detect_format(source : String) : Symbol
      lines = source.split('\n').reject(&.strip.empty?)
      return :pug if lines.empty?

      first_line = lines.first.strip

      # YAML: lines end with ':'
      if first_line.ends_with?(':')
        :yaml
      # JSON: starts with { or [
      elsif first_line.starts_with?('{') || first_line.starts_with?('[')
        :json
      else
        :pug
      end
    end

    # Parse with auto-detection
    def self.parse(source : String) : ParseResult
      format = detect_format(source)
      case format
      when :yaml
        parse_yaml(source)
      when :json
        ParseError.new("JSON parsing not yet implemented")
      else
        parse_pug(source)
      end
    end
  end
end
