# TCSS (TUI CSS) Parser
# Simplified CSS-like syntax for styling TUI widgets
#
# Example:
#   $primary: cyan;
#   $panel-bg: rgb(30, 30, 40);
#
#   Button {
#     background: blue;
#     color: white;
#   }
#
#   Button:focus {
#     background: $primary;
#   }
#
#   #my-button {
#     color: yellow;
#   }
#
#   .active {
#     border: heavy cyan;
#   }

module Tui::CSS
  class ParseError < Exception
  end

  # CSS property value
  alias Value = String | Color | Int32 | Bool

  # Single CSS rule
  struct Rule
    property selector : Selector
    property properties : Hash(String, Value)

    def initialize(@selector : Selector, @properties : Hash(String, Value) = {} of String => Value)
    end
  end

  # Parsed stylesheet
  class Stylesheet
    property rules : Array(Rule) = [] of Rule
    property variables : Hash(String, Value) = {} of String => Value

    def initialize
    end

    # Find matching rules for a widget (in specificity order)
    def rules_for(widget : Widget) : Array(Rule)
      @rules.select { |rule| rule.selector.matches?(widget) }
            .sort_by { |rule| rule.selector.specificity }
    end

    # Get computed style for widget
    def style_for(widget : Widget) : Hash(String, Value)
      result = {} of String => Value
      rules_for(widget).each do |rule|
        rule.properties.each { |k, v| result[k] = v }
      end
      result
    end
  end

  # CSS Selector
  abstract class Selector
    abstract def matches?(widget : Widget) : Bool
    abstract def specificity : Int32

    # Type selector: Button, Label, etc.
    class Type < Selector
      getter name : String

      def initialize(@name : String)
      end

      def matches?(widget : Widget) : Bool
        widget.class.name.split("::").last.downcase == @name.downcase
      end

      def specificity : Int32
        1
      end
    end

    # ID selector: #my-id
    class Id < Selector
      getter id : String

      def initialize(@id : String)
      end

      def matches?(widget : Widget) : Bool
        widget.id == @id
      end

      def specificity : Int32
        100
      end
    end

    # Class selector: .active
    class Class < Selector
      getter class_name : String

      def initialize(@class_name : String)
      end

      def matches?(widget : Widget) : Bool
        widget.has_class?(@class_name)
      end

      def specificity : Int32
        10
      end
    end

    # Pseudo-class selector: :focus, :hover, :first-child, etc.
    class Pseudo < Selector
      getter base : Selector
      getter pseudo : String

      def initialize(@base : Selector, @pseudo : String)
      end

      def matches?(widget : Widget) : Bool
        return false unless @base.matches?(widget)

        case @pseudo
        when "focus", "focused"
          widget.focused?
        when "hover", "hovered"
          widget.responds_to?(:hovered?) && widget.hovered?
        when "visible"
          widget.visible?
        when "disabled"
          widget.responds_to?(:disabled?) && widget.disabled?
        when "enabled"
          !widget.responds_to?(:disabled?) || !widget.disabled?
        when "empty"
          widget.children.empty?
        when "first-child"
          is_first_child?(widget)
        when "last-child"
          is_last_child?(widget)
        when "only-child"
          is_only_child?(widget)
        when "even"
          child_index(widget).try { |i| i.even? } || false
        when "odd"
          child_index(widget).try { |i| i.odd? } || false
        else
          # Handle :nth-child(n)
          if @pseudo.starts_with?("nth-child(") && @pseudo.ends_with?(")")
            n = @pseudo[10..-2].to_i?
            n ? child_index(widget) == n - 1 : false
          else
            false
          end
        end
      end

      private def is_first_child?(widget : Widget) : Bool
        if parent = widget.parent
          parent.children.first? == widget
        else
          false
        end
      end

      private def is_last_child?(widget : Widget) : Bool
        if parent = widget.parent
          parent.children.last? == widget
        else
          false
        end
      end

      private def is_only_child?(widget : Widget) : Bool
        if parent = widget.parent
          parent.children.size == 1 && parent.children.first? == widget
        else
          false
        end
      end

      private def child_index(widget : Widget) : Int32?
        if parent = widget.parent
          parent.children.index(widget)
        else
          nil
        end
      end

      def specificity : Int32
        @base.specificity + 10
      end
    end

    # Compound selector: Button.active
    class Compound < Selector
      getter selectors : Array(Selector)

      def initialize(@selectors : Array(Selector))
      end

      def matches?(widget : Widget) : Bool
        @selectors.all? &.matches?(widget)
      end

      def specificity : Int32
        @selectors.sum &.specificity
      end
    end

    # Universal selector: *
    class Universal < Selector
      def matches?(widget : Widget) : Bool
        true
      end

      def specificity : Int32
        0
      end
    end

    # Descendant selector: Panel Button (Button anywhere inside Panel)
    class Descendant < Selector
      getter ancestor : Selector
      getter descendant : Selector

      def initialize(@ancestor : Selector, @descendant : Selector)
      end

      def matches?(widget : Widget) : Bool
        return false unless @descendant.matches?(widget)

        # Walk up the parent chain looking for ancestor match
        current = widget.parent
        while current
          return true if @ancestor.matches?(current)
          current = current.parent
        end
        false
      end

      def specificity : Int32
        @ancestor.specificity + @descendant.specificity
      end
    end

    # Child selector: Panel > Button (Button is direct child of Panel)
    class Child < Selector
      getter parent_sel : Selector
      getter child_sel : Selector

      def initialize(@parent_sel : Selector, @child_sel : Selector)
      end

      def matches?(widget : Widget) : Bool
        return false unless @child_sel.matches?(widget)

        # Check if direct parent matches
        if parent = widget.parent
          @parent_sel.matches?(parent)
        else
          false
        end
      end

      def specificity : Int32
        @parent_sel.specificity + @child_sel.specificity
      end
    end
  end

  # TCSS Parser
  class Parser
    @input : String
    @pos : Int32 = 0
    @variables : Hash(String, Value) = {} of String => Value

    def initialize(@input : String)
    end

    def parse : Stylesheet
      stylesheet = Stylesheet.new

      skip_whitespace_and_comments

      while !eof?
        if peek == '$'
          # Variable definition
          name, value = parse_variable
          @variables[name] = value
          stylesheet.variables[name] = value
        else
          # Rule
          rule = parse_rule
          stylesheet.rules << rule if rule
        end
        skip_whitespace_and_comments
      end

      stylesheet
    end

    private def parse_variable : {String, Value}
      expect('$')
      name = parse_identifier
      skip_whitespace
      expect(':')
      skip_whitespace
      value = parse_value
      expect(';')
      {name, value}
    end

    private def parse_rule : Rule?
      selector = parse_selector
      return nil unless selector

      skip_whitespace
      expect('{')

      properties = {} of String => Value

      loop do
        skip_whitespace_and_comments
        break if peek == '}'

        prop_name = parse_identifier
        skip_whitespace
        expect(':')
        skip_whitespace
        prop_value = parse_value
        properties[prop_name] = prop_value

        skip_whitespace
        if peek == ';'
          advance
        end
      end

      expect('}')
      Rule.new(selector, properties)
    end

    private def parse_selector : Selector?
      skip_whitespace
      return nil if eof? || peek == '{'

      # Parse first selector (may be compound like Button.active)
      left = parse_compound_selector
      return nil unless left

      loop do
        # Save position to detect whitespace
        whitespace_seen = peek.try(&.whitespace?)
        skip_whitespace

        # Check for combinators or end of selector
        case peek
        when '{', nil
          break
        when '>'
          # Child combinator: Panel > Button
          advance
          skip_whitespace
          right = parse_compound_selector
          break unless right
          left = Selector::Child.new(left, right)
        else
          # If we saw whitespace and next char starts a selector, it's descendant
          if whitespace_seen && selector_start?(peek)
            right = parse_compound_selector
            break unless right
            left = Selector::Descendant.new(left, right)
          else
            break
          end
        end
      end

      left
    end

    # Check if character can start a selector
    private def selector_start?(char : Char?) : Bool
      return false unless char
      char.letter? || char == '.' || char == '#' || char == '*' || char == ':'
    end

    # Parse a compound selector (e.g., Button.active:focus)
    private def parse_compound_selector : Selector?
      selectors = [] of Selector

      loop do
        sel = parse_simple_selector
        break unless sel
        selectors << sel

        # Check for pseudo-class (attached directly, no whitespace)
        while peek == ':'
          advance
          pseudo = parse_identifier
          selectors[-1] = Selector::Pseudo.new(selectors[-1], pseudo)
        end

        # Continue only if next char continues compound selector (no whitespace)
        break unless peek == '.' || peek == '#'
      end

      case selectors.size
      when 0 then nil
      when 1 then selectors.first
      else        Selector::Compound.new(selectors)
      end
    end

    private def parse_simple_selector : Selector?
      case peek
      when '#'
        advance
        Selector::Id.new(parse_identifier)
      when '.'
        advance
        Selector::Class.new(parse_identifier)
      when '*'
        advance
        Selector::Universal.new
      when .try(&.letter?)
        Selector::Type.new(parse_identifier)
      else
        nil
      end
    end

    private def parse_value : Value
      skip_whitespace

      if peek == '$'
        # Variable reference
        advance
        var_name = parse_identifier
        @variables[var_name]? || ""
      elsif peek == '#'
        # Hex color
        parse_hex_color
      elsif current_matches?("rgb(")
        parse_rgb_color
      elsif current_matches?("true")
        advance(4)
        true
      elsif current_matches?("false")
        advance(5)
        false
      elsif peek.try(&.ascii_number?)
        # Look ahead to see if this is a multi-value property (e.g., "1 2 3 4" for margin)
        # Or a dimension value (e.g., "1fr", "50%")
        if looks_like_multi_value? || looks_like_dimension?
          parse_string_value
        else
          parse_number
        end
      else
        parse_string_value
      end
    end

    # Check if current position looks like multiple space-separated values
    private def looks_like_multi_value? : Bool
      # Save position
      saved_pos = @pos

      # Skip past first number
      while peek.try(&.ascii_number?)
        advance
      end

      # Check if there's a space followed by another number (multi-value)
      is_whitespace = peek.try(&.whitespace?) == true
      skip_whitespace
      has_more = (peek.try(&.ascii_number?) == true) || (peek.try(&.letter?) == true)

      # Restore position
      @pos = saved_pos

      is_whitespace && has_more
    end

    # Check if current position looks like a dimension (1fr, 50%, 10px)
    private def looks_like_dimension? : Bool
      # Save position
      saved_pos = @pos

      # Skip past number (including decimals)
      while peek.try { |c| c.ascii_number? || c == '.' }
        advance
      end

      # Check for dimension suffix (fr, %, px, em, etc.)
      has_suffix = peek == '%' || (peek.try(&.letter?) == true)

      # Restore position
      @pos = saved_pos

      has_suffix
    end

    private def parse_hex_color : Color
      expect('#')
      hex = ""
      while peek.try { |c| c.hex? }
        hex += advance.to_s
      end

      case hex.size
      when 3
        r = hex[0].to_i(16) * 17
        g = hex[1].to_i(16) * 17
        b = hex[2].to_i(16) * 17
        Color.rgb(r, g, b)
      when 6
        r = hex[0..1].to_i(16)
        g = hex[2..3].to_i(16)
        b = hex[4..5].to_i(16)
        Color.rgb(r, g, b)
      else
        Color.default
      end
    end

    private def parse_rgb_color : Color
      advance(4)  # "rgb("
      skip_whitespace
      r = parse_number.as(Int32)
      skip_whitespace
      expect(',') if peek == ','
      skip_whitespace
      g = parse_number.as(Int32)
      skip_whitespace
      expect(',') if peek == ','
      skip_whitespace
      b = parse_number.as(Int32)
      skip_whitespace
      expect(')')
      Color.rgb(r, g, b)
    end

    private def parse_number : Int32
      num = ""
      while peek.try(&.ascii_number?)
        num += advance.to_s
      end
      num.to_i32? || 0
    end

    private def parse_string_value : String
      result = ""
      while !eof? && peek != ';' && peek != '}' && peek != '\n'
        result += advance.to_s
      end
      result.strip
    end

    private def parse_identifier : String
      result = ""
      while peek.try { |c| c.alphanumeric? || c == '-' || c == '_' }
        result += advance.to_s
      end
      result
    end

    private def skip_whitespace : Nil
      while peek.try(&.whitespace?)
        advance
      end
    end

    private def skip_whitespace_and_comments : Nil
      loop do
        skip_whitespace

        if current_matches?("/*")
          # Block comment
          advance(2)
          until current_matches?("*/") || eof?
            advance
          end
          advance(2) if !eof?
        elsif current_matches?("//")
          # Line comment
          until peek == '\n' || eof?
            advance
          end
        else
          break
        end
      end
    end

    private def current_matches?(str : String) : Bool
      str.each_char_with_index do |char, i|
        return false if @pos + i >= @input.size
        return false if @input[@pos + i] != char
      end
      true
    end

    private def peek : Char?
      return nil if @pos >= @input.size
      @input[@pos]
    end

    private def advance(n : Int32 = 1) : Char
      char = @input[@pos]
      @pos += n
      char
    end

    private def expect(char : Char) : Nil
      if peek != char
        raise ParseError.new("Expected '#{char}' at position #{@pos}, got '#{peek}'")
      end
      advance
    end

    private def eof? : Bool
      @pos >= @input.size
    end
  end

  # Helper to parse TCSS string
  def self.parse(source : String) : Stylesheet
    Parser.new(source).parse
  end

  # Helper to parse TCSS file
  def self.parse_file(path : String) : Stylesheet
    parse(File.read(path))
  end
end
