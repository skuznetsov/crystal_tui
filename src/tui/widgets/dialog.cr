# Dialog widget - Modal dialog with title, content and buttons
module Tui
  class Dialog < Widget
    enum Result
      None
      OK
      Cancel
    end

    enum ResizeEdge
      None
      Top
      Bottom
      Left
      Right
      TopLeft
      TopRight
      BottomLeft
      BottomRight
    end

    struct Button
      property label : String
      property result : Result
      property hotkey : Char?

      def initialize(@label, @result, @hotkey = nil)
      end
    end

    @title : String
    @message : String?
    @buttons : Array(Button)
    @input : Input?
    @focused_button : Int32 = 0
    @result : Result = Result::None

    # Resize state
    @resizing : ResizeEdge = ResizeEdge::None
    @resize_start_x : Int32 = 0
    @resize_start_y : Int32 = 0
    @resize_start_rect : Rect = Rect.new(0, 0, 0, 0)

    # Resize settings
    property resizable : Bool = true
    property min_width : Int32 = 20
    property min_height : Int32 = 6

    # Style - MC dialog colors (classic gray dialogs)
    property border_style : Panel::BorderStyle = Panel::BorderStyle::Light
    property border_color : Color = Color.black
    property bg_color : Color = Color.white          # ANSI white = light gray
    property title_color : Color = Color.blue
    property message_color : Color = Color.black
    property button_color : Color = Color.black       # Normal button: black on dialog bg
    property button_bg : Color = Color.white          # Match dialog background
    property button_focus_color : Color = Color.black # Focused: black on cyan
    property button_focus_bg : Color = Color.cyan     # Cyan background for active
    property button_focus_attrs : Attributes = Attributes::None
    property input_color : Color = Color.black
    property input_bg : Color = Color.cyan
    property shadow : Bool = true
    property shadow_fg : Color = Color.palette(8)  # Dark gray for dimmed text
    property shadow_bg : Color = Color.black

    # Callbacks
    @on_close : Proc(Result, String?, Nil)?

    def initialize(@title : String, @message : String? = nil, id : String? = nil)
      super(id)
      @focusable = true
      @buttons = [
        Button.new("[ OK ]", Result::OK, 'o'),
        Button.new("[ Cancel ]", Result::Cancel, 'c'),
      ]
    end

    def self.input_dialog(title : String, prompt : String, default_value : String = "") : Dialog
      dialog = Dialog.new(title, prompt)
      dialog.add_input(default_value)
      dialog
    end

    # MC-style mask dialog - no buttons, just Enter/Esc
    def self.mask_dialog(title : String, default_value : String = "*") : Dialog
      dialog = Dialog.new(title)
      dialog.buttons = [] of Button  # No buttons
      dialog.add_input(default_value)
      dialog
    end

    # Confirmation dialog with Yes/No buttons
    def self.confirm_dialog(title : String, message : String) : Dialog
      dialog = Dialog.new(title, message)
      dialog.buttons = [
        Button.new("[ Yes ]", Result::OK, 'y'),
        Button.new("[ No ]", Result::Cancel, 'n'),
      ]
      dialog
    end

    def add_input(default_value : String = "", placeholder : String = "") : Input
      input = Input.new(default_value, placeholder)
      input.style = Style.new(fg: @input_color, bg: @input_bg)
      input.focus_style = Style.new(fg: Color.black, bg: Color.cyan)
      @input = input
      add_child(input)
      input
    end

    def input_value : String?
      @input.try &.value
    end

    def buttons : Array(Button)
      @buttons
    end

    def buttons=(buttons : Array(Button))
      @buttons = buttons
      @focused_button = 0
    end

    def on_close(&block : Result, String? -> Nil) : Nil
      @on_close = block
    end

    def result : Result
      @result
    end

    # Content rect (excludes shadow area)
    private def content_rect : Rect
      if @shadow
        Rect.new(@rect.x, @rect.y, @rect.width - 2, @rect.height - 1)
      else
        @rect
      end
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      cr = content_rect
      border = Panel::BORDERS[@border_style]
      style = Style.new(fg: @border_color, bg: @bg_color)
      title_style = Style.new(fg: @title_color, bg: @bg_color, attrs: Attributes::Bold)
      msg_style = Style.new(fg: @message_color, bg: @bg_color)

      # Draw shadow first
      if @shadow
        draw_shadow(buffer, clip, cr)
      end

      # Clear background
      cr.height.times do |row|
        cr.width.times do |col|
          draw_char(buffer, clip, cr.x + col, cr.y + row, ' ', style)
        end
      end

      # Draw border
      draw_border(buffer, clip, border, style, cr)

      # Draw title centered in top border
      draw_title(buffer, clip, border, style, title_style, cr)

      # Draw message
      if msg = @message
        y = cr.y + 2
        x = cr.x + 2
        msg.each_char do |char|
          draw_char(buffer, clip, x, y, char, msg_style)
          x += 1
        end
      end

      # Draw input if present
      if input = @input
        # Position: after message if present, otherwise right after title
        input_y = if @message
                    cr.y + 4
                  elsif @buttons.empty?
                    cr.y + 1  # MC-style: input directly after title (no gap)
                  else
                    cr.y + 2
                  end
        input.rect = Rect.new(
          cr.x + 1,
          input_y,
          cr.width - 2,
          1
        )
        input.render(buffer, clip)
      end

      # Draw buttons (if any)
      draw_buttons(buffer, clip, cr) unless @buttons.empty?
    end

    private def draw_border(buffer : Buffer, clip : Rect, border, style : Style, cr : Rect) : Nil
      # Corners
      draw_char(buffer, clip, cr.x, cr.y, border[:tl], style)
      draw_char(buffer, clip, cr.right - 1, cr.y, border[:tr], style)
      draw_char(buffer, clip, cr.x, cr.bottom - 1, border[:bl], style)
      draw_char(buffer, clip, cr.right - 1, cr.bottom - 1, border[:br], style)

      # Horizontal lines
      (1...(cr.width - 1)).each do |i|
        draw_char(buffer, clip, cr.x + i, cr.y, border[:h], style)
        draw_char(buffer, clip, cr.x + i, cr.bottom - 1, border[:h], style)
      end

      # Vertical lines
      (1...(cr.height - 1)).each do |i|
        draw_char(buffer, clip, cr.x, cr.y + i, border[:v], style)
        draw_char(buffer, clip, cr.right - 1, cr.y + i, border[:v], style)
      end
    end

    private def draw_title(buffer : Buffer, clip : Rect, border, style : Style, title_style : Style, cr : Rect) : Nil
      return if @title.empty?

      max_width = cr.width - 6
      display_title = Unicode.truncate(@title, max_width, "…")
      full_title = "#{border[:tl_title]} #{display_title} #{border[:tr_title]}"

      # Center title
      full_title_width = Unicode.display_width(full_title)
      title_start = (cr.width - full_title_width) // 2
      x = cr.x + title_start

      # Draw with proper width tracking
      current_x = x
      char_pos = 0
      full_title.each_char do |char|
        char_style = (char_pos == 0 || char_pos >= full_title_width - 1) ? style : title_style
        char_width = Unicode.char_width(char)
        draw_char(buffer, clip, current_x, cr.y, char, char_style)
        current_x += char_width
        char_pos += char_width
      end
    end

    private def draw_buttons(buffer : Buffer, clip : Rect, cr : Rect) : Nil
      return if @buttons.empty?

      # Check if input has focus (buttons have focus when input doesn't)
      input_has_focus = @input.try(&.focused?) || false
      buttons_have_focus = focused? && !input_has_focus

      # Build transformed labels first
      labels = @buttons.map_with_index do |button, i|
        is_focused = i == @focused_button && buttons_have_focus
        label = button.label
        if label.starts_with?("[ ") && label.ends_with?(" ]")
          inner = label[2...-2]
          if is_focused
            "[< #{inner} >]"
          else
            "[  #{inner}  ]"
          end
        else
          label
        end
      end

      # Calculate total width with transformed labels
      total_width = labels.sum(&.size) + (@buttons.size - 1) * 2  # 2 spaces between

      # Center buttons
      y = cr.bottom - 2
      x = cr.x + (cr.width - total_width) // 2

      @buttons.each_with_index do |button, i|
        is_focused = i == @focused_button && buttons_have_focus
        label = labels[i]

        btn_style = if is_focused
                      Style.new(fg: @button_focus_color, bg: @button_focus_bg)
                    else
                      Style.new(fg: @button_color, bg: @button_bg)
                    end

        label.each_char do |char|
          draw_char(buffer, clip, x, y, char, btn_style)
          x += 1
        end

        x += 2  # Space between buttons
      end
    end

    private def draw_char(buffer : Buffer, clip : Rect, x : Int32, y : Int32, char : Char, style : Style) : Nil
      buffer.set(x, y, char, style) if clip.contains?(x, y)
    end

    private def draw_shadow(buffer : Buffer, clip : Rect, cr : Rect) : Nil
      shadow_style = Style.new(fg: @shadow_fg, bg: @shadow_bg)

      # Right shadow (2 chars wide) - dim existing content
      (cr.y + 1).upto(cr.bottom) do |y|
        [cr.right, cr.right + 1].each do |x|
          next unless clip.contains?(x, y)
          # Get existing char and redraw with shadow colors
          existing = buffer.get(x, y)
          char = existing.char.printable? ? existing.char : ' '
          buffer.set(x, y, char, shadow_style)
        end
      end

      # Bottom shadow - dim existing content
      (cr.x + 2).upto(cr.right + 1) do |x|
        y = cr.bottom
        next unless clip.contains?(x, y)
        existing = buffer.get(x, y)
        char = existing.char.printable? ? existing.char : ' '
        buffer.set(x, y, char, shadow_style)
      end
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?

      # Handle mouse events before focus check (resize should work regardless)
      case event
      when MouseEvent
        return handle_mouse(event)
      end

      return false unless focused?

      case event
      when KeyEvent
        # If input is present and focused, let it handle first
        if input = @input
          if input.focused?
            case event.key
            when .tab?
              # Tab from input to buttons
              input.focused = false
              event.stop!
              mark_dirty!
              return true
            when .enter?
              # Enter in input = OK
              close_with(Result::OK)
              event.stop!
              return true
            when .escape?
              close_with(Result::Cancel)
              event.stop!
              return true
            else
              if input.handle_event(event)
                return true
              end
            end
          end
        end

        if handle_key(event)
          event.stop!
          return true
        end
      end

      false
    end

    private def handle_mouse(event : MouseEvent) : Bool
      cr = content_rect

      # Handle resize drag
      if @resizing != ResizeEdge::None
        if event.action.drag? || event.action.press?
          apply_resize(event.x, event.y)
          event.stop!
          return true
        elsif event.action.release?
          @resizing = ResizeEdge::None
          event.stop!
          return true
        end
      end

      # Check for resize start on border/corners (any click, not just press)
      if @resizable && (event.action.press? || event.button.left?)
        edge = detect_resize_edge(event.x, event.y, cr)
        if edge != ResizeEdge::None
          @resizing = edge
          @resize_start_x = event.x
          @resize_start_y = event.y
          @resize_start_rect = @rect
          event.stop!
          return true
        end
      end

      # Check button clicks - only for actual button area, not entire dialog
      if event.action.press? && event.button.left?
        btn_y = cr.bottom - 2
        if event.y == btn_y && !@buttons.empty?
          # Calculate button positions
          labels = @buttons.map { |b| b.label }
          total_width = labels.sum(&.size) + (@buttons.size - 1) * 2
          btn_x = cr.x + (cr.width - total_width) // 2

          x = btn_x
          @buttons.each_with_index do |button, i|
            label_end = x + labels[i].size
            if event.x >= x && event.x < label_end
              close_with(button.result)
              event.stop!
              return true
            end
            x = label_end + 2
          end
        end
        # Don't consume all clicks - let subclasses handle them
      end

      false
    end

    # Detect which edge/corner the mouse is on for resize
    # Uses 1-cell tolerance for easier targeting
    private def detect_resize_edge(mx : Int32, my : Int32, cr : Rect) : ResizeEdge
      # Check if on border (exact match for single-cell borders)
      on_top = my == cr.y
      on_bottom = my == cr.bottom - 1
      on_left = mx == cr.x
      on_right = mx == cr.right - 1

      # Must be on at least one edge to be a resize target
      return ResizeEdge::None unless on_top || on_bottom || on_left || on_right

      # Corners: within 2 cells of corner on the border
      near_left = mx <= cr.x + 2
      near_right = mx >= cr.right - 3

      if on_top && near_left
        ResizeEdge::TopLeft
      elsif on_top && near_right
        ResizeEdge::TopRight
      elsif on_bottom && near_left
        ResizeEdge::BottomLeft
      elsif on_bottom && near_right
        ResizeEdge::BottomRight
      elsif on_top
        ResizeEdge::Top
      elsif on_bottom
        ResizeEdge::Bottom
      elsif on_left
        ResizeEdge::Left
      elsif on_right
        ResizeEdge::Right
      else
        ResizeEdge::None
      end
    end

    # Apply resize based on current drag position
    private def apply_resize(mx : Int32, my : Int32) : Nil
      dx = mx - @resize_start_x
      dy = my - @resize_start_y
      r = @resize_start_rect

      new_x = r.x
      new_y = r.y
      new_w = r.width
      new_h = r.height

      case @resizing
      when .top?
        new_y = r.y + dy
        new_h = r.height - dy
      when .bottom?
        new_h = r.height + dy
      when .left?
        new_x = r.x + dx
        new_w = r.width - dx
      when .right?
        new_w = r.width + dx
      when .top_left?
        new_x = r.x + dx
        new_y = r.y + dy
        new_w = r.width - dx
        new_h = r.height - dy
      when .top_right?
        new_y = r.y + dy
        new_w = r.width + dx
        new_h = r.height - dy
      when .bottom_left?
        new_x = r.x + dx
        new_w = r.width - dx
        new_h = r.height + dy
      when .bottom_right?
        new_w = r.width + dx
        new_h = r.height + dy
      end

      # Enforce minimum size
      if new_w < @min_width
        if @resizing.left? || @resizing.top_left? || @resizing.bottom_left?
          new_x = r.x + r.width - @min_width
        end
        new_w = @min_width
      end
      if new_h < @min_height
        if @resizing.top? || @resizing.top_left? || @resizing.top_right?
          new_y = r.y + r.height - @min_height
        end
        new_h = @min_height
      end

      @rect = Rect.new(new_x, new_y, new_w, new_h)
      mark_dirty!
    end

    private def handle_key(event : KeyEvent) : Bool
      case event.key
      when .escape?
        close_with(Result::Cancel)
        true
      when .enter?
        close_with(@buttons[@focused_button]?.try(&.result) || Result::OK)
        true
      when .tab?, .right?
        next_button
        true
      when .left?
        prev_button
        true
      else
        # Check hotkeys
        if char = event.char
          @buttons.each do |button|
            if button.hotkey == char.downcase
              close_with(button.result)
              return true
            end
          end
        end
        false
      end
    end

    private def next_button : Nil
      if input = @input
        if !input.focused?
          @focused_button = (@focused_button + 1) % @buttons.size
          if @focused_button == 0
            input.focused = true
          end
        end
      else
        @focused_button = (@focused_button + 1) % @buttons.size
      end
      mark_dirty!
    end

    private def prev_button : Nil
      if input = @input
        if !input.focused?
          @focused_button -= 1
          if @focused_button < 0
            @focused_button = @buttons.size - 1
            input.focused = true
          end
        end
      else
        @focused_button = (@focused_button - 1) % @buttons.size
        @focused_button = @buttons.size - 1 if @focused_button < 0
      end
      mark_dirty!
    end

    private def close_with(result : Result) : Nil
      @result = result
      @on_close.try &.call(result, @input.try(&.value))
    end

    # Show dialog and focus input if present
    def show : Nil
      if input = @input
        input.focused = true
      end
      self.focused = true
      mark_dirty!
    end
  end
end
