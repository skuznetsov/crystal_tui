# RichText widget - text with inline interactive elements
module Tui
  class RichText < Widget
    # Inline element types
    abstract class InlineElement
      property id : String?
      property focusable : Bool = false

      def initialize(@id = nil)
      end

      abstract def render(buffer : Buffer, x : Int32, y : Int32, clip : Rect, focused : Bool) : Int32  # Returns width
      abstract def width : Int32

      def handle_event(event : Event) : Bool
        false
      end
    end

    # Plain text span
    class TextSpan < InlineElement
      property text : String
      property style : Style

      def initialize(@text, @style = Style.new, id : String? = nil)
        super(id)
      end

      def render(buffer : Buffer, x : Int32, y : Int32, clip : Rect, focused : Bool) : Int32
        @text.each_char_with_index do |char, i|
          buffer.set(x + i, y, char, @style) if clip.contains?(x + i, y)
        end
        @text.size
      end

      def width : Int32
        @text.size
      end
    end

    # Clickable inline button [Action]
    class InlineButton < InlineElement
      property label : String
      property action : Proc(Nil)?
      property style : Style
      property focus_style : Style

      def initialize(@label, @action = nil, id : String? = nil)
        super(id)
        @focusable = true
        @style = Style.new(fg: Color.black, bg: Color.cyan)
        @focus_style = Style.new(fg: Color.white, bg: Color.blue, attrs: Attributes::Bold)
      end

      def render(buffer : Buffer, x : Int32, y : Int32, clip : Rect, focused : Bool) : Int32
        s = focused ? @focus_style : @style
        text = "[#{@label}]"
        text.each_char_with_index do |char, i|
          buffer.set(x + i, y, char, s) if clip.contains?(x + i, y)
        end
        text.size
      end

      def width : Int32
        @label.size + 2  # brackets
      end

      def handle_event(event : Event) : Bool
        case event
        when KeyEvent
          if event.key.enter? || event.key.space?
            @action.try &.call
            event.stop!
            return true
          end
        when MouseEvent
          if event.action.press?
            @action.try &.call
            event.stop!
            return true
          end
        end
        false
      end
    end

    # Inline code with copy action
    class InlineCode < InlineElement
      property code : String
      property style : Style
      property focus_style : Style
      @on_copy : Proc(String, Nil)?

      def initialize(@code, id : String? = nil)
        super(id)
        @focusable = true
        @style = Style.new(fg: Color.yellow, bg: Color.palette(8))
        @focus_style = Style.new(fg: Color.black, bg: Color.yellow)
      end

      def on_copy(&block : String -> Nil) : Nil
        @on_copy = block
      end

      def render(buffer : Buffer, x : Int32, y : Int32, clip : Rect, focused : Bool) : Int32
        s = focused ? @focus_style : @style
        text = "`#{@code}`"
        text.each_char_with_index do |char, i|
          buffer.set(x + i, y, char, s) if clip.contains?(x + i, y)
        end
        text.size
      end

      def width : Int32
        @code.size + 2  # backticks
      end

      def handle_event(event : Event) : Bool
        case event
        when KeyEvent
          if event.key.enter? || (event.char == 'c')
            @on_copy.try &.call(@code)
            event.stop!
            return true
          end
        end
        false
      end
    end

    # Link element
    class InlineLink < InlineElement
      property text : String
      property url : String
      property style : Style
      property focus_style : Style
      @on_activate : Proc(String, Nil)?

      def initialize(@text, @url, id : String? = nil)
        super(id)
        @focusable = true
        @style = Style.new(fg: Color.cyan, attrs: Attributes::Underline)
        @focus_style = Style.new(fg: Color.white, bg: Color.blue, attrs: Attributes::Bold)
      end

      def on_activate(&block : String -> Nil) : Nil
        @on_activate = block
      end

      def render(buffer : Buffer, x : Int32, y : Int32, clip : Rect, focused : Bool) : Int32
        s = focused ? @focus_style : @style
        @text.each_char_with_index do |char, i|
          buffer.set(x + i, y, char, s) if clip.contains?(x + i, y)
        end
        @text.size
      end

      def width : Int32
        @text.size
      end

      def handle_event(event : Event) : Bool
        case event
        when KeyEvent
          if event.key.enter?
            @on_activate.try &.call(@url)
            event.stop!
            return true
          end
        when MouseEvent
          if event.action.press?
            @on_activate.try &.call(@url)
            event.stop!
            return true
          end
        end
        false
      end
    end

    # A line of content (mix of text and inline elements)
    struct Line
      property elements : Array(InlineElement)

      def initialize
        @elements = [] of InlineElement
      end

      def <<(element : InlineElement)
        @elements << element
      end

      def width : Int32
        @elements.sum(&.width)
      end
    end

    @lines : Array(Line) = [] of Line
    @scroll : Int32 = 0
    @focused_line : Int32 = 0
    @focused_element : Int32 = 0
    @bg_color : Color = Color.default

    property bg_color : Color

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    def clear : Nil
      @lines.clear
      @scroll = 0
      @focused_line = 0
      @focused_element = 0
      mark_dirty!
    end

    def add_line : Line
      line = Line.new
      @lines << line
      mark_dirty!
      line
    end

    def add_text(text : String, style : Style = Style.new) : Nil
      line = @lines.last? || add_line
      line << TextSpan.new(text, style)
      mark_dirty!
    end

    def add_button(label : String, &action : -> Nil) : InlineButton
      line = @lines.last? || add_line
      button = InlineButton.new(label, action)
      line << button
      mark_dirty!
      button
    end

    def add_code(code : String) : InlineCode
      line = @lines.last? || add_line
      inline_code = InlineCode.new(code)
      line << inline_code
      mark_dirty!
      inline_code
    end

    def add_link(text : String, url : String) : InlineLink
      line = @lines.last? || add_line
      link = InlineLink.new(text, url)
      line << link
      mark_dirty!
      link
    end

    def newline : Nil
      add_line
    end

    def lines : Array(Line)
      @lines
    end

    # Get all focusable elements in order
    private def focusable_elements : Array({Int32, Int32, InlineElement})
      result = [] of {Int32, Int32, InlineElement}
      @lines.each_with_index do |line, li|
        line.elements.each_with_index do |elem, ei|
          if elem.focusable
            result << {li, ei, elem}
          end
        end
      end
      result
    end

    private def current_focusable_index : Int32
      elements = focusable_elements
      elements.each_with_index do |(li, ei, _), i|
        if li == @focused_line && ei == @focused_element
          return i
        end
      end
      0
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      bg_style = Style.new(bg: @bg_color)

      # Clear background
      @rect.height.times do |row|
        @rect.width.times do |col|
          buffer.set(@rect.x + col, @rect.y + row, ' ', bg_style) if clip.contains?(@rect.x + col, @rect.y + row)
        end
      end

      visible_lines = @rect.height
      visible_lines.times do |i|
        line_idx = @scroll + i
        break if line_idx >= @lines.size

        line = @lines[line_idx]
        y = @rect.y + i
        x = @rect.x

        line.elements.each_with_index do |elem, elem_idx|
          is_focused = focused? && line_idx == @focused_line && elem_idx == @focused_element && elem.focusable
          w = elem.render(buffer, x, y, clip, is_focused)
          x += w
        end
      end
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?
      return false unless focused?

      case event
      when KeyEvent
        # First, let focused element handle
        if (line = @lines[@focused_line]?) && (elem = line.elements[@focused_element]?)
          if elem.focusable && elem.handle_event(event)
            return true
          end
        end

        case event.key
        when .tab?
          if event.modifiers.shift?
            focus_prev_element
          else
            focus_next_element
          end
          event.stop!
          return true
        when .up?
          if @focused_line > 0
            focus_prev_line
          else
            scroll_up
          end
          event.stop!
          return true
        when .down?
          if @focused_line < @lines.size - 1
            focus_next_line
          else
            scroll_down
          end
          event.stop!
          return true
        when .page_up?
          scroll_by(-@rect.height)
          event.stop!
          return true
        when .page_down?
          scroll_by(@rect.height)
          event.stop!
          return true
        end

      when MouseEvent
        if event.action.press?
          # Find clicked element
          if element_at(event.x, event.y)
            return true
          end
        end
      end

      false
    end

    private def element_at(mx : Int32, my : Int32) : Bool
      line_idx = @scroll + (my - @rect.y)
      return false if line_idx < 0 || line_idx >= @lines.size

      line = @lines[line_idx]
      x = @rect.x

      line.elements.each_with_index do |elem, elem_idx|
        w = elem.width
        if mx >= x && mx < x + w
          @focused_line = line_idx
          @focused_element = elem_idx
          mark_dirty!

          if elem.focusable
            # Simulate enter on click
            elem.handle_event(MouseEvent.new(mx, my, MouseButton::Left, MouseAction::Press, Modifiers::None))
          end
          return true
        end
        x += w
      end

      false
    end

    private def focus_next_element : Nil
      elements = focusable_elements
      return if elements.empty?

      idx = current_focusable_index
      idx = (idx + 1) % elements.size
      @focused_line, @focused_element, _ = elements[idx]
      ensure_visible(@focused_line)
      mark_dirty!
    end

    private def focus_prev_element : Nil
      elements = focusable_elements
      return if elements.empty?

      idx = current_focusable_index
      idx = (idx - 1) % elements.size
      idx = elements.size - 1 if idx < 0
      @focused_line, @focused_element, _ = elements[idx]
      ensure_visible(@focused_line)
      mark_dirty!
    end

    private def focus_next_line : Nil
      @focused_line = (@focused_line + 1).clamp(0, @lines.size - 1)
      @focused_element = find_first_focusable_in_line(@focused_line)
      ensure_visible(@focused_line)
      mark_dirty!
    end

    private def focus_prev_line : Nil
      @focused_line = (@focused_line - 1).clamp(0, @lines.size - 1)
      @focused_element = find_first_focusable_in_line(@focused_line)
      ensure_visible(@focused_line)
      mark_dirty!
    end

    private def find_first_focusable_in_line(line_idx : Int32) : Int32
      return 0 unless line = @lines[line_idx]?
      line.elements.each_with_index do |elem, i|
        return i if elem.focusable
      end
      0
    end

    private def ensure_visible(line_idx : Int32) : Nil
      if line_idx < @scroll
        @scroll = line_idx
      elsif line_idx >= @scroll + @rect.height
        @scroll = line_idx - @rect.height + 1
      end
    end

    private def scroll_up : Nil
      @scroll = (@scroll - 1).clamp(0, (@lines.size - @rect.height).clamp(0, Int32::MAX))
      mark_dirty!
    end

    private def scroll_down : Nil
      @scroll = (@scroll + 1).clamp(0, (@lines.size - @rect.height).clamp(0, Int32::MAX))
      mark_dirty!
    end

    private def scroll_by(delta : Int32) : Nil
      max_scroll = (@lines.size - @rect.height).clamp(0, Int32::MAX)
      @scroll = (@scroll + delta).clamp(0, max_scroll)
      mark_dirty!
    end
  end
end
