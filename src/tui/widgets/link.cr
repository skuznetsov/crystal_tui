# Link - Clickable URL/text widget
module Tui
  class Link < Widget
    property text : String
    property url : String
    property style : Style = Style.new(fg: Color.cyan, attrs: Attributes::Underline)
    property hover_style : Style = Style.new(fg: Color.blue, attrs: Attributes::Underline | Attributes::Bold)
    property visited_style : Style = Style.new(fg: Color.magenta, attrs: Attributes::Underline)

    @visited : Bool = false
    @on_click : Proc(String, Nil)?

    def initialize(@text : String, @url : String = "", id : String? = nil)
      super(id)
      @url = @text if @url.empty?
      @focusable = true
    end

    # Callback when link is activated
    def on_click(&block : String -> Nil) : Nil
      @on_click = block
    end

    # Mark as visited
    def visited? : Bool
      @visited
    end

    def visited=(value : Bool) : Nil
      @visited = value
      mark_dirty!
    end

    # Activate the link
    def activate : Nil
      @visited = true
      @on_click.try &.call(@url)
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?

      # Choose style based on state
      current_style = if focused?
                        @hover_style
                      elsif @visited
                        @visited_style
                      else
                        @style
                      end

      # Render text
      display_text = Unicode.truncate(@text, @rect.width, "...")
      x = @rect.x
      y = @rect.y

      display_text.each_char do |char|
        break if x >= @rect.x + @rect.width
        if clip.contains?(x, y)
          buffer.set(x, y, char, current_style)
        end
        x += Unicode.char_width(char)
      end

      # Fill remaining space
      while x < @rect.x + @rect.width
        buffer.set(x, y, ' ', current_style) if clip.contains?(x, y)
        x += 1
      end
    end

    def on_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when KeyEvent
        if focused? && (event.matches?("enter") || event.matches?("space"))
          activate
          event.stop!
          return true
        end
      when MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          focus
          activate
          event.stop!
          return true
        end
      end

      false
    end

    def min_size : {Int32, Int32}
      {Unicode.display_width(@text), 1}
    end
  end
end
