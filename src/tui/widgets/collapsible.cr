# Collapsible widget - expandable/collapsible section
module Tui
  class Collapsible < Widget
    @title : String
    @expanded : Bool = false
    @content : Widget?
    @content_height : Int32 = 0

    # Style
    property title_fg : Color = Color.white
    property title_bg : Color = Color.blue
    property title_expanded_fg : Color = Color.yellow
    property title_expanded_bg : Color = Color.blue
    property border_color : Color = Color.cyan
    property content_bg : Color = Color.blue
    property arrow_color : Color = Color.cyan
    property show_border : Bool = true

    # Callbacks
    @on_toggle : Proc(Bool, Nil)?
    @on_extract : Proc(Nil)?  # Called when user wants to extract to panel

    def initialize(@title : String, id : String? = nil, @expanded : Bool = false)
      super(id)
      @focusable = true
    end

    def title : String
      @title
    end

    def title=(value : String)
      @title = value
      mark_dirty!
    end

    def expanded? : Bool
      @expanded
    end

    def expanded=(value : Bool)
      @expanded = value
      @on_toggle.try &.call(value)
      mark_dirty!
    end

    def toggle : Nil
      self.expanded = !@expanded
    end

    def expand : Nil
      self.expanded = true
    end

    def collapse : Nil
      self.expanded = false
    end

    def content : Widget?
      @content
    end

    def content=(widget : Widget?)
      if old = @content
        remove_child(old)
      end
      @content = widget
      if widget
        add_child(widget)
      end
      mark_dirty!
    end

    def set_content(&block : -> Widget) : Nil
      self.content = block.call
    end

    def on_toggle(&block : Bool -> Nil) : Nil
      @on_toggle = block
    end

    def on_extract(&block : -> Nil) : Nil
      @on_extract = block
    end

    # Calculate height needed
    def preferred_height : Int32
      if @expanded && @content
        header_height + @content_height + (show_border ? 1 : 0)
      else
        header_height
      end
    end

    private def header_height : Int32
      1
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Draw header
      draw_header(buffer, clip)

      # Draw content if expanded
      if @expanded && @content
        draw_content(buffer, clip)
      end
    end

    private def draw_header(buffer : Buffer, clip : Rect) : Nil
      is_focused = focused?
      style = if @expanded
                Style.new(fg: @title_expanded_fg, bg: @title_expanded_bg,
                         attrs: is_focused ? Attributes::Bold : Attributes::None)
              else
                Style.new(fg: @title_fg, bg: @title_bg,
                         attrs: is_focused ? Attributes::Bold : Attributes::None)
              end
      arrow_style = Style.new(fg: @arrow_color, bg: style.bg)

      y = @rect.y

      # Clear header line
      @rect.width.times do |i|
        buffer.set(@rect.x + i, y, ' ', style) if clip.contains?(@rect.x + i, y)
      end

      x = @rect.x

      # Arrow indicator
      arrow = @expanded ? '▼' : '▶'
      buffer.set(x, y, arrow, arrow_style) if clip.contains?(x, y)
      x += 2

      # Title
      @title.each_char do |char|
        break if x >= @rect.right - 4  # Leave room for extract button
        buffer.set(x, y, char, style) if clip.contains?(x, y)
        x += 1
      end

      # Horizontal line after title
      border_style = Style.new(fg: @border_color, bg: style.bg)
      while x < @rect.right - 4
        buffer.set(x, y, '─', border_style) if clip.contains?(x, y)
        x += 1
      end

      # Extract button [⤢] if callback set
      if @on_extract
        button_style = Style.new(fg: Color.cyan, bg: style.bg)
        buffer.set(@rect.right - 3, y, '[', button_style) if clip.contains?(@rect.right - 3, y)
        buffer.set(@rect.right - 2, y, '⤢', button_style) if clip.contains?(@rect.right - 2, y)
        buffer.set(@rect.right - 1, y, ']', button_style) if clip.contains?(@rect.right - 1, y)
      end
    end

    private def draw_content(buffer : Buffer, clip : Rect) : Nil
      return unless @expanded
      return unless content = @content

      content_y = @rect.y + header_height
      content_height = @rect.height - header_height - (@show_border ? 1 : 0)
      return if content_height <= 0

      # Draw left border
      if @show_border
        border_style = Style.new(fg: @border_color, bg: @content_bg)
        content_height.times do |i|
          buffer.set(@rect.x, content_y + i, '│', border_style) if clip.contains?(@rect.x, content_y + i)
        end
        # Bottom corner
        buffer.set(@rect.x, content_y + content_height, '└', border_style) if clip.contains?(@rect.x, content_y + content_height)
        # Bottom line
        (@rect.width - 1).times do |i|
          buffer.set(@rect.x + 1 + i, content_y + content_height, '─', border_style) if clip.contains?(@rect.x + 1 + i, content_y + content_height)
        end
      end

      # Render content widget
      content_x = @rect.x + (@show_border ? 2 : 1)
      content_width = @rect.width - (@show_border ? 3 : 1)

      content.rect = Rect.new(content_x, content_y, content_width, content_height)
      content.render(buffer, clip)
    end

    def on_event(event : Event) : Bool
      return false if event.stopped?
      return false unless focused?

      case event
      when KeyEvent
        case event.key
        when .enter?, .space?
          toggle
          event.stop!
          return true
        when .left?
          if @expanded
            collapse
            event.stop!
            return true
          end
        when .right?
          if !@expanded
            expand
            event.stop!
            return true
          end
        end

        # 'e' or 'x' to extract
        if char = event.char
          if (char == 'e' || char == 'x') && @on_extract
            @on_extract.try &.call
            event.stop!
            return true
          end
        end

      when MouseEvent
        if event.action.press?
          # Click on header
          if event.y == @rect.y
            # Check if clicked on extract button
            if event.x >= @rect.right - 3 && @on_extract
              @on_extract.try &.call
            else
              toggle
            end
            event.stop!
            return true
          end
        end
      end

      # Forward events to content if expanded and focused
      if @expanded && (content = @content)
        if content.handle_event(event)
          return true
        end
      end

      false
    end
  end
end
