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

    # Border characters: tl_title = left of title, tr_title = right of title
    # ┤ receives line from left, ├ sends line to right
    BORDERS = {
      BorderStyle::Light  => {h: '─', v: '│', tl: '┌', tr: '┐', bl: '└', br: '┘', tl_title: '┤', tr_title: '├'},
      BorderStyle::Heavy  => {h: '━', v: '┃', tl: '┏', tr: '┓', bl: '┗', br: '┛', tl_title: '┫', tr_title: '┣'},
      BorderStyle::Double => {h: '═', v: '║', tl: '╔', tr: '╗', bl: '╚', br: '╝', tl_title: '╡', tr_title: '╞'},
      BorderStyle::Round  => {h: '─', v: '│', tl: '╭', tr: '╮', bl: '╰', br: '╯', tl_title: '┤', tr_title: '├'},
      BorderStyle::Ascii  => {h: '-', v: '|', tl: '+', tr: '+', bl: '+', br: '+', tl_title: ']', tr_title: '['},
    }

    enum TitleStyle
      None      # No decorations
      Brackets  # ┤ Title ├
      Spaces    # Just spaces around title
    end

    enum TitleTruncate
      End     # Very long tit…
      Center  # Very…title
      Start   # …long title
    end

    # Which border sides to draw
    @[Flags]
    enum BorderSides
      Top
      Bottom
      Left
      Right

      def self.all : BorderSides
        Top | Bottom | Left | Right
      end

      def self.none : BorderSides
        BorderSides.new(0)
      end
    end

    property title : String = ""
    property show_borders : BorderSides = BorderSides.all
    property border_style : BorderStyle = BorderStyle::Light
    property border_color : Color = Color.white
    property title_color : Color = Color.yellow
    property title_align : Label::Align = Label::Align::Left
    property title_decor : TitleStyle = TitleStyle::Brackets  # Default to brackets
    property title_truncate : TitleTruncate = TitleTruncate::End

    # Focus highlighting (when widget is focused)
    property focus_border_color : Color? = nil    # nil = no change
    property focus_title_color : Color? = nil     # nil = no change
    property focus_highlight : Bool = true        # Enable/disable focus highlighting

    # Legacy uniform padding setter (use inherited BoxModel padding property)
    def padding=(value : Int32) : Nil
      @padding = BoxModel.all(value)
    end

    # Scrolling
    property scrollable : Bool = true
    property scroll_lines : Int32 = 3
    @scroll_y : Int32 = 0
    @content_height : Int32 = 0

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

    # Scrolling methods
    def scroll_y : Int32
      @scroll_y
    end

    def scroll_y=(value : Int32) : Nil
      @scroll_y = value.clamp(0, max_scroll_y)
      mark_dirty!
    end

    def content_height : Int32
      @content_height
    end

    def content_height=(value : Int32) : Nil
      @content_height = value
      @scroll_y = @scroll_y.clamp(0, max_scroll_y)
      mark_dirty!
    end

    def max_scroll_y : Int32
      visible_height = inner_rect.height
      Math.max(0, @content_height - visible_height)
    end

    def scroll_up(lines : Int32 = @scroll_lines) : Nil
      self.scroll_y = @scroll_y - lines
    end

    def scroll_down(lines : Int32 = @scroll_lines) : Nil
      self.scroll_y = @scroll_y + lines
    end

    # Convenience: set content via block
    def content(&block : -> Widget) : Nil
      self.content = block.call
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      if @border_style == BorderStyle::None || @show_borders == BorderSides.none
        # No border, layout and render content
        if content = @content
          content.rect = inner_rect
          content.render(buffer, clip)
        end
        return
      end

      border = BORDERS[@border_style]

      # Use focus colors if focused and highlighting enabled
      actual_border_color = if @focus_highlight && focused? && @focus_border_color
                              @focus_border_color.not_nil!
                            else
                              @border_color
                            end
      actual_title_color = if @focus_highlight && focused? && @focus_title_color
                             @focus_title_color.not_nil!
                           elsif @focus_highlight && focused? && @focus_border_color
                             @focus_border_color.not_nil!  # Use border color for title if only border color set
                           else
                             @title_color
                           end

      style = Style.new(fg: actual_border_color)
      title_style = Style.new(fg: actual_title_color, attrs: Attributes::Bold)

      has_top = @show_borders.top?
      has_bottom = @show_borders.bottom?
      has_left = @show_borders.left?
      has_right = @show_borders.right?


      # Draw corners (only if adjacent sides are visible)
      if has_top && has_left
        draw_if_visible(buffer, clip, @rect.x, @rect.y, border[:tl], style)
      end
      if has_top && has_right
        draw_if_visible(buffer, clip, @rect.right - 1, @rect.y, border[:tr], style)
      end
      if has_bottom && has_left
        draw_if_visible(buffer, clip, @rect.x, @rect.bottom - 1, border[:bl], style)
      end
      if has_bottom && has_right
        draw_if_visible(buffer, clip, @rect.right - 1, @rect.bottom - 1, border[:br], style)
      end

      # Draw top border with title (only if top is visible)
      title_start = 0
      title_end = 0

      if has_top
        if !@title.empty?
          # Calculate decoration overhead
          # Brackets connect directly to horizontal line, space only between bracket and title
          decor_left, decor_right = case @title_decor
                                    when .brackets? then {"#{border[:tl_title]} ", " #{border[:tr_title]}"}
                                    when .spaces?   then {" ", " "}
                                    else                 {"", ""}
                                    end

          # Account for hidden corners in available width
          left_corner = has_left ? 1 : 0
          right_corner = has_right ? 1 : 0
          available = @rect.width - left_corner - right_corner - 2  # corners + minimum padding
          display_title = truncate_title(@title, available)
          full_title = "#{decor_left}#{display_title}#{decor_right}"

          title_start = case @title_align
                        when .left?   then left_corner
                        when .center? then (@rect.width - full_title.size) // 2
                        when .right?  then @rect.width - full_title.size - right_corner
                        else               left_corner
                        end
          title_end = title_start + full_title.size

          # Draw full title with decorations
          full_title.each_char_with_index do |char, i|
            x = @rect.x + title_start + i
            # Use border color for brackets, title color for text
            char_style = if @title_decor.brackets? && (i < decor_left.size || i >= decor_left.size + display_title.size)
                           style  # Border style for brackets
                         else
                           title_style
                         end
            draw_if_visible(buffer, clip, x, @rect.y, char, char_style)
          end
        end

        # Draw top horizontal line (avoiding title area)
        start_x = has_left ? 1 : 0
        end_x = has_right ? @rect.width - 1 : @rect.width
        (start_x...end_x).each do |i|
          next if i >= title_start && i < title_end
          draw_if_visible(buffer, clip, @rect.x + i, @rect.y, border[:h], style)
        end
      end

      # Draw bottom horizontal line (only if bottom is visible)
      if has_bottom
        start_x = has_left ? 1 : 0
        end_x = has_right ? @rect.width - 1 : @rect.width
        (start_x...end_x).each do |i|
          draw_if_visible(buffer, clip, @rect.x + i, @rect.bottom - 1, border[:h], style)
        end
      end

      # Draw left vertical line (only if left is visible)
      if has_left
        start_y = has_top ? 1 : 0
        end_y = has_bottom ? @rect.height - 1 : @rect.height
        (start_y...end_y).each do |i|
          draw_if_visible(buffer, clip, @rect.x, @rect.y + i, border[:v], style)
        end
      end

      # Draw right vertical line (only if right is visible)
      if has_right
        start_y = has_top ? 1 : 0
        end_y = has_bottom ? @rect.height - 1 : @rect.height
        (start_y...end_y).each do |i|
          # BYPASS clip - direct buffer.set
          buffer.set(@rect.right - 1, @rect.y + i, border[:v], style)
        end
      end

      # Render content in inner area (with scroll offset)
      if content = @content
        inner = inner_rect
        # Apply scroll offset - move content up by scroll_y
        scrolled_rect = Rect.new(inner.x, inner.y - @scroll_y, inner.width, @content_height.clamp(inner.height, Int32::MAX))
        content.rect = scrolled_rect
        if content_clip = clip.intersect(inner)
          content.render(buffer, content_clip)
        end
      end
    end

    # Get inner rectangle (excluding border and padding)
    def inner_rect : Rect
      if @border_style == BorderStyle::None || @show_borders == BorderSides.none
        return Rect.new(
          @rect.x + @padding.left,
          @rect.y + @padding.top,
          Math.max(0, @rect.width - @padding.horizontal),
          Math.max(0, @rect.height - @padding.vertical)
        )
      end

      # Calculate insets based on which borders are visible
      left_inset = (@show_borders.left? ? 1 : 0) + @padding.left
      right_inset = (@show_borders.right? ? 1 : 0) + @padding.right
      top_inset = (@show_borders.top? ? 1 : 0) + @padding.top
      bottom_inset = (@show_borders.bottom? ? 1 : 0) + @padding.bottom

      Rect.new(
        @rect.x + left_inset,
        @rect.y + top_inset,
        Math.max(0, @rect.width - left_inset - right_inset),
        Math.max(0, @rect.height - top_inset - bottom_inset)
      )
    end

    private def draw_if_visible(buffer : Buffer, clip : Rect, x : Int32, y : Int32, char : Char, style : Style) : Nil
      buffer.set(x, y, char, style) if clip.contains?(x, y)
    end

    private def truncate_title(text : String, max_len : Int32) : String
      return text if text.size <= max_len
      return "…" if max_len <= 1

      case @title_truncate
      when .end?
        text[0, max_len - 1] + "…"
      when .center?
        left_len = (max_len - 1) // 2
        right_len = max_len - 1 - left_len
        text[0, left_len] + "…" + text[-(right_len)..]
      when .start?
        "…" + text[-(max_len - 1)..]
      else
        text[0, max_len - 1] + "…"
      end
    end

    # Override to handle Panel-specific CSS properties
    def apply_css_style(css_style : Hash(String, CSS::Value)) : Nil
      super(css_style)

      css_style.each do |property, value|
        case property
        when "border"
          # border: <style> <color> (e.g., "light white")
          parts = value.to_s.split(/\s+/, 2)
          if parts.size >= 1
            @border_style = parse_border_style(parts[0])
          end
          if parts.size >= 2
            if color = parse_css_color(parts[1])
              @border_color = color
            end
          end
        when "border-style"
          @border_style = parse_border_style(value.to_s)
        when "border-color"
          if color = parse_css_color(value.to_s)
            @border_color = color
          end
        when "border-title-color", "title-color"
          if color = parse_css_color(value.to_s)
            @title_color = color
          end
        when "border-title-style", "title-style"
          @title_decor = case value.to_s.downcase
                         when "brackets" then TitleStyle::Brackets
                         when "spaces"   then TitleStyle::Spaces
                         when "none"     then TitleStyle::None
                         else                 TitleStyle::Brackets
                         end
        when "title-align"
          @title_align = case value.to_s.downcase
                         when "left"   then Label::Align::Left
                         when "center" then Label::Align::Center
                         when "right"  then Label::Align::Right
                         else               Label::Align::Left
                         end
        end
      end
    end

    private def parse_border_style(value : String) : BorderStyle
      case value.downcase
      when "light"  then BorderStyle::Light
      when "heavy"  then BorderStyle::Heavy
      when "double" then BorderStyle::Double
      when "round"  then BorderStyle::Round
      when "ascii"  then BorderStyle::Ascii
      when "none"   then BorderStyle::None
      else               BorderStyle::Light
      end
    end

    private def parse_css_color(value : String) : Color?
      str = value.downcase.strip
      case str
      when "white"   then Color.white
      when "black"   then Color.black
      when "red"     then Color.red
      when "green"   then Color.green
      when "blue"    then Color.blue
      when "yellow"  then Color.yellow
      when "cyan"    then Color.cyan
      when "magenta" then Color.magenta
      when "default" then Color.default
      when /^#([0-9a-f]{6})$/i
        hex = $1
        r = hex[0, 2].to_i(16)
        g = hex[2, 2].to_i(16)
        b = hex[4, 2].to_i(16)
        Color.rgb(r, g, b)
      when /^#([0-9a-f]{3})$/i
        hex = $1
        r = hex[0, 1].to_i(16) * 17
        g = hex[1, 1].to_i(16) * 17
        b = hex[2, 1].to_i(16) * 17
        Color.rgb(r, g, b)
      when /^rgb\((\d+),\s*(\d+),\s*(\d+)\)$/
        Color.rgb($1.to_i, $2.to_i, $3.to_i)
      else
        nil
      end
    end

    def handle_event(event : Event) : Bool
      case event
      when MouseEvent
        # Handle wheel scrolling
        if @scrollable && event.action.press? && event.in_rect?(@rect)
          if event.button.wheel_up?
            scroll_up
            event.stop!
            return true
          elsif event.button.wheel_down?
            scroll_down
            event.stop!
            return true
          end
        end
      end

      # Pass events to content
      @content.try &.handle_event(event) || false
    end
  end
end
