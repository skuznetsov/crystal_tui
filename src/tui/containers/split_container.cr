# SplitContainer - IDE-style split layout with draggable splitter
# SIMPLE: SplitContainer draws outer border + splitter. Children rendered inside without own borders.
module Tui
  class SplitContainer < Widget
    enum Direction
      Horizontal  # Left | Right (splitter is vertical │)
      Vertical    # Top / Bottom (splitter is horizontal ─)
    end

    property direction : Direction = Direction::Horizontal
    property ratio : Float64 = 0.5
    property min_first : Int32 = 3
    property min_second : Int32 = 3
    property border_color : Color = Color.white
    property splitter_color : Color = Color.white
    property splitter_drag_color : Color = Color.yellow
    property show_border : Bool = true
    property first_title : String = ""
    property second_title : String = ""
    property title_color : Color = Color.yellow

    @first : Widget?
    @second : Widget?
    @first_area : Rect = Rect.zero   # Content area for first child
    @second_area : Rect = Rect.zero  # Content area for second child
    @splitter_pos : Int32 = 0        # x or y position of splitter line
    @dragging : Bool = false

    # Callbacks
    @on_resize : Proc(Float64, Nil)?

    def initialize(@direction : Direction = Direction::Horizontal, @ratio : Float64 = 0.5, id : String? = nil)
      super(id)
    end

    def first : Widget?
      @first
    end

    def first=(widget : Widget?) : Nil
      @first.try { |old| remove_child(old) }
      @first = widget
      widget.try { |w| add_child(w) }
      mark_dirty!
    end

    def second : Widget?
      @second
    end

    def second=(widget : Widget?) : Nil
      @second.try { |old| remove_child(old) }
      @second = widget
      widget.try { |w| add_child(w) }
      mark_dirty!
    end

    def on_resize(&block : Float64 -> Nil) : Nil
      @on_resize = block
    end

    # Expose splitter position for nested containers
    def splitter_y : Int32
      @direction.vertical? ? @splitter_pos : 0
    end

    def splitter_x : Int32
      @direction.horizontal? ? @splitter_pos : 0
    end

    # Public method to trigger layout calculation (for nested junction detection)
    def calculate_layout : Nil
      layout_areas
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      layout_areas

      # Set child rects BEFORE drawing (needed for nested junction detection)
      @first.try { |c| c.rect = @first_area }
      @second.try { |c| c.rect = @second_area }

      style = Style.new(fg: @border_color)

      if @show_border
        # Draw outer border
        draw_outer_border(buffer, clip, style)
      end

      # Draw splitter
      draw_splitter(buffer, clip)

      # Render children in their areas
      render_child(@first, @first_area, buffer, clip)
      render_child(@second, @second_area, buffer, clip)
    end

    private def layout_areas : Nil
      return if @rect.empty?

      border = @show_border ? 1 : 0
      inner_x = @rect.x + border
      inner_y = @rect.y + border
      inner_w = @rect.width - border * 2
      inner_h = @rect.height - border * 2

      return if inner_w <= 1 || inner_h <= 0

      case @direction
      when .horizontal?
        # Vertical splitter: [first | second]
        total = inner_w - 1  # 1 for splitter
        first_w = (total * @ratio).to_i.clamp(@min_first, total - @min_second)
        second_w = total - first_w
        @splitter_pos = inner_x + first_w

        @first_area = Rect.new(inner_x, inner_y, first_w, inner_h)
        @second_area = Rect.new(@splitter_pos + 1, inner_y, second_w, inner_h)

      when .vertical?
        # Horizontal splitter: [first / second]
        total = inner_h - 1  # 1 for splitter
        first_h = (total * @ratio).to_i.clamp(@min_first, total - @min_second)
        second_h = total - first_h
        @splitter_pos = inner_y + first_h

        @first_area = Rect.new(inner_x, inner_y, inner_w, first_h)
        @second_area = Rect.new(inner_x, @splitter_pos + 1, inner_w, second_h)
      end
    end

    private def draw_outer_border(buffer : Buffer, clip : Rect, style : Style) : Nil
      x, y, w, h = @rect.x, @rect.y, @rect.width, @rect.height

      # Corners
      buffer.set(x, y, '┌', style) if clip.contains?(x, y)
      buffer.set(x + w - 1, y, '┐', style) if clip.contains?(x + w - 1, y)
      buffer.set(x, y + h - 1, '└', style) if clip.contains?(x, y + h - 1)
      buffer.set(x + w - 1, y + h - 1, '┘', style) if clip.contains?(x + w - 1, y + h - 1)

      # Top edge (with first title if horizontal, or first_title if vertical)
      title = @direction.horizontal? ? @first_title : @first_title
      draw_horizontal_edge(buffer, clip, x + 1, y, w - 2, title, style)

      # Bottom edge (with second title for vertical splits shown at splitter)
      draw_horizontal_edge(buffer, clip, x + 1, y + h - 1, w - 2, "", style)

      # Left edge
      (1...h - 1).each do |i|
        buffer.set(x, y + i, '│', style) if clip.contains?(x, y + i)
      end

      # Right edge (with junction for nested horizontal splitter)
      nested_y = find_nested_horizontal_splitter_y
      (1...h - 1).each do |i|
        py = y + i
        next unless clip.contains?(x + w - 1, py)
        char = (nested_y == py) ? '┤' : '│'
        buffer.set(x + w - 1, py, char, style)
      end
    end

    private def draw_horizontal_edge(buffer : Buffer, clip : Rect, x : Int32, y : Int32, width : Int32, title : String, style : Style) : Nil
      title_style = Style.new(fg: @title_color, attrs: Attributes::Bold)

      if title.empty?
        width.times { |i| buffer.set(x + i, y, '─', style) if clip.contains?(x + i, y) }
      else
        # Draw: ─┤ Title ├───
        decorated = "┤ #{title} ├"
        title_start = 1
        title_end = title_start + decorated.size

        width.times do |i|
          px = x + i
          next unless clip.contains?(px, y)

          if i >= title_start && i < title_end
            char = decorated[i - title_start]
            char_style = (char == '┤' || char == '├') ? style : title_style
            buffer.set(px, y, char, char_style)
          else
            buffer.set(px, y, '─', style)
          end
        end
      end
    end

    private def draw_splitter(buffer : Buffer, clip : Rect) : Nil
      style = Style.new(fg: @dragging ? @splitter_drag_color : @splitter_color)
      title_style = Style.new(fg: @title_color, attrs: Attributes::Bold)
      border = @show_border ? 1 : 0

      case @direction
      when .horizontal?
        # Vertical splitter line │
        x = @splitter_pos
        y_start = @rect.y + border
        y_end = @rect.y + @rect.height - border

        # Top junction with border
        if @show_border
          buffer.set(x, @rect.y, '┬', style) if clip.contains?(x, @rect.y)
          buffer.set(x, @rect.y + @rect.height - 1, '┴', style) if clip.contains?(x, @rect.y + @rect.height - 1)
        end

        # Splitter line + junction with nested horizontal splitters
        nested_y = find_nested_horizontal_splitter_y
        (y_start...y_end).each do |py|
          next unless clip.contains?(x, py)
          char = nested_y == py ? '├' : '│'
          buffer.set(x, py, char, style)
        end

        # Draw second_title on top edge after splitter
        if !@second_title.empty? && @show_border
          draw_title_on_edge(buffer, clip, @splitter_pos + 1, @rect.y, @rect.x + @rect.width - 1 - @splitter_pos - 1, @second_title, style, title_style)
        end

      when .vertical?
        # Horizontal splitter line ─
        y = @splitter_pos
        x_start = @rect.x + border
        x_end = @rect.x + @rect.width - border

        # Left/right junctions with border
        if @show_border
          buffer.set(@rect.x, y, '├', style) if clip.contains?(@rect.x, y)
          buffer.set(@rect.x + @rect.width - 1, y, '┤', style) if clip.contains?(@rect.x + @rect.width - 1, y)
        end

        # Splitter line with second_title
        if @second_title.empty?
          (x_start...x_end).each do |px|
            buffer.set(px, y, '─', style) if clip.contains?(px, y)
          end
        else
          # Draw: ─┤ Title ├───
          decorated = "┤ #{@second_title} ├"
          title_start = 1
          title_end = title_start + decorated.size
          line_width = x_end - x_start

          line_width.times do |i|
            px = x_start + i
            next unless clip.contains?(px, y)

            if i >= title_start && i < title_end
              char = decorated[i - title_start]
              char_style = (char == '┤' || char == '├') ? style : title_style
              buffer.set(px, y, char, char_style)
            else
              buffer.set(px, y, '─', style)
            end
          end
        end
      end
    end

    private def draw_title_on_edge(buffer : Buffer, clip : Rect, x : Int32, y : Int32, width : Int32, title : String, style : Style, title_style : Style) : Nil
      return if width <= 0
      decorated = "┤ #{title} ├"
      title_start = 1

      Math.min(width, decorated.size + 2).times do |i|
        px = x + i
        next unless clip.contains?(px, y)

        if i >= title_start && i < title_start + decorated.size
          char = decorated[i - title_start]
          char_style = (char == '┤' || char == '├') ? style : title_style
          buffer.set(px, y, char, char_style)
        else
          buffer.set(px, y, '─', style)
        end
      end
    end

    private def find_nested_horizontal_splitter_y : Int32?
      # Check if second child is a vertical SplitContainer
      if second = @second
        if second.is_a?(SplitContainer) && second.direction.vertical?
          # Trigger layout calculation so splitter_y is computed
          second.calculate_layout
          return second.splitter_y
        end
      end
      nil
    end

    private def render_child(child : Widget?, area : Rect, buffer : Buffer, clip : Rect) : Nil
      return unless child
      return unless child.visible?
      return if area.empty?

      child.rect = area
      if child_clip = clip.intersect(area)
        child.render(buffer, child_clip)
      end
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?

      # Ensure layout is calculated for accurate hit testing
      layout_areas
      @first.try { |c| c.rect = @first_area }
      @second.try { |c| c.rect = @second_area }

      case event
      when MouseEvent
        splitter_rect = splitter_hit_rect

        case event.action
        when .press?
          if event.in_rect?(splitter_rect)
            @dragging = true
            capture_mouse
            mark_dirty!
            event.stop!
            return true
          end

          # Forward to children
          @first.try { |w| return w.handle_event(event) if w.visible? && event.in_rect?(w.rect) }
          @second.try { |w| return w.handle_event(event) if w.visible? && event.in_rect?(w.rect) }

        when .drag?
          if @dragging
            update_ratio_from_mouse(event.x, event.y)
            mark_dirty!
            event.stop!
            return true
          end
          @first.try { |w| return true if w.visible? && w.handle_event(event) }
          @second.try { |w| return true if w.visible? && w.handle_event(event) }

        when .release?
          if @dragging
            @dragging = false
            release_mouse
            @on_resize.try &.call(@ratio)
            mark_dirty!
            event.stop!
            return true
          end
          @first.try { |w| return true if w.visible? && w.handle_event(event) }
          @second.try { |w| return true if w.visible? && w.handle_event(event) }
        end

        # Wheel events
        if event.button.wheel_up? || event.button.wheel_down?
          @first.try { |w| return w.handle_event(event) if w.visible? && event.in_rect?(w.rect) }
          @second.try { |w| return w.handle_event(event) if w.visible? && event.in_rect?(w.rect) }
        end

      when KeyEvent
        @first.try { |w| return true if w.visible? && w.handle_event(event) }
        @second.try { |w| return true if w.visible? && w.handle_event(event) }
      end

      false
    end

    private def splitter_hit_rect : Rect
      case @direction
      when .horizontal?
        Rect.new(@splitter_pos, @rect.y, 1, @rect.height)
      when .vertical?
        Rect.new(@rect.x, @splitter_pos, @rect.width, 1)
      else
        Rect.zero
      end
    end

    private def update_ratio_from_mouse(mx : Int32, my : Int32) : Nil
      border = @show_border ? 1 : 0

      case @direction
      when .horizontal?
        total = @rect.width - border * 2 - 1
        return if total <= 0
        pos = mx - @rect.x - border
        @ratio = (pos.to_f / total).clamp(@min_first.to_f / total, 1.0 - @min_second.to_f / total)
      when .vertical?
        total = @rect.height - border * 2 - 1
        return if total <= 0
        pos = my - @rect.y - border
        @ratio = (pos.to_f / total).clamp(@min_first.to_f / total, 1.0 - @min_second.to_f / total)
      end
    end
  end
end
