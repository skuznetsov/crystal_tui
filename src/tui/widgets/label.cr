# Label widget - displays text
module Tui
  class Label < Widget
    include Reactive

    enum Align
      Left
      Center
      Right
    end

    reactive text : String = ""
    property style : Style = Style.default
    property align : Align = Align::Left

    def initialize(
      @text : String = "",
      id : String? = nil,
      @style : Style = Style.default,
      @align : Align = Align::Left
    )
      super(id)
    end

    # Convenience constructor with named style
    def self.new(
      text : String,
      id : String? = nil,
      fg : Color? = nil,
      bg : Color? = nil,
      bold : Bool = false,
      align : Align = Align::Left
    ) : Label
      attrs = Attributes::None
      attrs |= Attributes::Bold if bold

      style = Style.new(
        fg: fg || Color.default,
        bg: bg || Color.default,
        attrs: attrs
      )

      new(text, id, style, align)
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?

      # Clear background
      @rect.each_cell do |x, y|
        next unless clip.contains?(x, y)
        buffer.set(x, y, ' ', @style)
      end

      # Calculate text position based on alignment
      display_text = @text[0, @rect.width]?  || @text
      text_x = case @align
               when .left?
                 @rect.x
               when .center?
                 @rect.x + (@rect.width - display_text.size) // 2
               when .right?
                 @rect.x + @rect.width - display_text.size
               else
                 @rect.x
               end

      # Draw text
      text_y = @rect.y + @rect.height // 2  # Vertically centered
      display_text.each_char_with_index do |char, i|
        x = text_x + i
        next unless clip.contains?(x, text_y)
        buffer.set(x, text_y, char, @style)
      end
    end

    def watch_text(value : String)
      mark_dirty!
    end
  end
end
