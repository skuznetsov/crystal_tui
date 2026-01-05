# Panel widget - container with border and optional title
module Tui
  class Panel < Widget
    enum BorderStyle
      None
      Light    # ─ │ ┌ ┐ └ ┘
      Heavy    # ━ ┃ ┏ ┓ ┗ ┛
      Double   # ═ ║ ╔ ╗ ╚ ╝
      Round    # ─ │ ╭ ╮ ╰ ╯
      Ascii    # - | + + + +
    end

    BORDERS = {
      BorderStyle::Light  => {h: '─', v: '│', tl: '┌', tr: '┐', bl: '└', br: '┘'},
      BorderStyle::Heavy  => {h: '━', v: '┃', tl: '┏', tr: '┓', bl: '┗', br: '┛'},
      BorderStyle::Double => {h: '═', v: '║', tl: '╔', tr: '╗', bl: '╚', br: '╝'},
      BorderStyle::Round  => {h: '─', v: '│', tl: '╭', tr: '╮', bl: '╰', br: '╯'},
      BorderStyle::Ascii  => {h: '-', v: '|', tl: '+', tr: '+', bl: '+', br: '+'},
    }

    property title : String = ""
    property border_style : BorderStyle = BorderStyle::Light
    property border_color : Color = Color.white
    property title_color : Color = Color.yellow
    property title_align : Label::Align = Label::Align::Left
    property padding : Int32 = 0

    # Content widget (single child)
    @content : Widget?

    def initialize(
      @title : String = "",
      id : String? = nil,
      @border_style : BorderStyle = BorderStyle::Light,
      @border_color : Color = Color.white
    )
      super(id)
    end

    # Set content widget
    def content=(widget : Widget) : Nil
      @content.try { |old| remove_child(old) }
      @content = widget
      add_child(widget)
      mark_dirty!
    end

    def content : Widget?
      @content
    end

    # Convenience: set content via block
    def content(&block : -> Widget) : Nil
      self.content = block.call
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      if @border_style == BorderStyle::None
        # No border, just render content
        @content.try &.render(buffer, clip)
        return
      end

      border = BORDERS[@border_style]
      style = Style.new(fg: @border_color)
      title_style = Style.new(fg: @title_color, attrs: Attributes::Bold)

      # Draw corners
      draw_if_visible(buffer, clip, @rect.x, @rect.y, border[:tl], style)
      draw_if_visible(buffer, clip, @rect.right - 1, @rect.y, border[:tr], style)
      draw_if_visible(buffer, clip, @rect.x, @rect.bottom - 1, border[:bl], style)
      draw_if_visible(buffer, clip, @rect.right - 1, @rect.bottom - 1, border[:br], style)

      # Draw top border with title
      title_start = 0
      title_end = 0

      if !@title.empty?
        available = @rect.width - 4  # 2 corners + 2 padding
        display_title = @title.size > available ? @title[0, available - 1] + "…" : @title

        title_start = case @title_align
                      when .left?   then 2
                      when .center? then (@rect.width - display_title.size) // 2
                      when .right?  then @rect.width - display_title.size - 2
                      else               2
                      end
        title_end = title_start + display_title.size

        # Draw title
        display_title.each_char_with_index do |char, i|
          x = @rect.x + title_start + i
          draw_if_visible(buffer, clip, x, @rect.y, char, title_style)
        end
      end

      # Draw top horizontal line (avoiding title)
      (1...(@rect.width - 1)).each do |i|
        next if i >= title_start && i < title_end
        draw_if_visible(buffer, clip, @rect.x + i, @rect.y, border[:h], style)
      end

      # Draw bottom horizontal line
      (1...(@rect.width - 1)).each do |i|
        draw_if_visible(buffer, clip, @rect.x + i, @rect.bottom - 1, border[:h], style)
      end

      # Draw vertical lines
      (1...(@rect.height - 1)).each do |i|
        draw_if_visible(buffer, clip, @rect.x, @rect.y + i, border[:v], style)
        draw_if_visible(buffer, clip, @rect.right - 1, @rect.y + i, border[:v], style)
      end

      # Render content in inner area
      if content = @content
        inner = inner_rect
        if content_clip = clip.intersect(inner)
          content.rect = inner
          content.render(buffer, content_clip)
        end
      end
    end

    # Get inner rectangle (excluding border and padding)
    def inner_rect : Rect
      border_size = @border_style == BorderStyle::None ? 0 : 1
      inset = border_size + @padding

      Rect.new(
        @rect.x + inset,
        @rect.y + inset,
        Math.max(0, @rect.width - inset * 2),
        Math.max(0, @rect.height - inset * 2)
      )
    end

    private def draw_if_visible(buffer : Buffer, clip : Rect, x : Int32, y : Int32, char : Char, style : Style) : Nil
      buffer.set(x, y, char, style) if clip.contains?(x, y)
    end

    def handle_event(event : Event) : Bool
      # Pass events to content
      @content.try &.handle_event(event) || false
    end
  end
end
