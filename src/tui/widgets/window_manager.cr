# Window Manager - Vim/tmux style split layouts
module Tui
  class WindowManager < Widget
    @@id_counter : Int64 = 0

    def self.next_id : String
      @@id_counter += 1
      "wm-#{@@id_counter}"
    end

    enum SplitDirection
      Horizontal  # Children arranged left-to-right
      Vertical    # Children arranged top-to-bottom
    end

    # Abstract layout node
    abstract class LayoutNode
      property id : String
      property rect : Rect = Rect.new(0, 0, 0, 0)
      property parent : SplitNode?
      property ratio : Float64 = 1.0  # Size ratio within parent

      def initialize(@id = WindowManager.next_id)
      end

      abstract def render(buffer : Buffer, clip : Rect) : Nil
      abstract def handle_event(event : Event) : Bool
      abstract def focused_window : WindowNode?
      abstract def all_windows : Array(WindowNode)
      abstract def find_window(id : String) : WindowNode?
    end

    # Split node - contains child nodes
    class SplitNode < LayoutNode
      property direction : SplitDirection
      property children : Array(LayoutNode) = [] of LayoutNode
      property border_color : Color = Color.cyan
      property show_borders : Bool = true

      def initialize(direction : SplitDirection = SplitDirection::Horizontal, id : String = WindowManager.next_id)
        super(id)
        @direction = direction
      end

      def add_child(node : LayoutNode, ratio : Float64 = 1.0) : Nil
        node.parent = self
        node.ratio = ratio
        @children << node
        normalize_ratios
      end

      def remove_child(node : LayoutNode) : Nil
        @children.delete(node)
        node.parent = nil
        normalize_ratios
      end

      def insert_before(existing : LayoutNode, new_node : LayoutNode, ratio : Float64 = 1.0) : Nil
        idx = @children.index(existing)
        return unless idx
        new_node.parent = self
        new_node.ratio = ratio
        @children.insert(idx, new_node)
        normalize_ratios
      end

      def insert_after(existing : LayoutNode, new_node : LayoutNode, ratio : Float64 = 1.0) : Nil
        idx = @children.index(existing)
        return unless idx
        new_node.parent = self
        new_node.ratio = ratio
        @children.insert(idx + 1, new_node)
        normalize_ratios
      end

      private def normalize_ratios : Nil
        return if @children.empty?
        total = @children.sum(&.ratio)
        @children.each { |c| c.ratio = c.ratio / total }
      end

      def layout : Nil
        return if @children.empty?

        if @direction.horizontal?
          layout_horizontal
        else
          layout_vertical
        end

        # Recursively layout children
        @children.each do |child|
          if child.is_a?(SplitNode)
            child.layout
          end
        end
      end

      private def layout_horizontal : Nil
        available_width = @rect.width - (@show_borders ? @children.size - 1 : 0)
        x = @rect.x

        @children.each_with_index do |child, i|
          width = (available_width * child.ratio).to_i
          # Last child gets remaining space
          if i == @children.size - 1
            width = @rect.right - x - (@show_borders && i > 0 ? 0 : 0)
          end

          child.rect = Rect.new(x, @rect.y, width, @rect.height)
          x += width + (@show_borders ? 1 : 0)  # +1 for border
        end
      end

      private def layout_vertical : Nil
        available_height = @rect.height - (@show_borders ? @children.size - 1 : 0)
        y = @rect.y

        @children.each_with_index do |child, i|
          height = (available_height * child.ratio).to_i
          # Last child gets remaining space
          if i == @children.size - 1
            height = @rect.bottom - y
          end

          child.rect = Rect.new(@rect.x, y, @rect.width, height)
          y += height + (@show_borders ? 1 : 0)  # +1 for border
        end
      end

      def render(buffer : Buffer, clip : Rect) : Nil
        layout

        # Draw children
        @children.each { |child| child.render(buffer, clip) }

        # Draw borders between children
        if @show_borders && @children.size > 1
          draw_borders(buffer, clip)
        end
      end

      private def draw_borders(buffer : Buffer, clip : Rect) : Nil
        border_style = Style.new(fg: @border_color)

        if @direction.horizontal?
          # Vertical borders between horizontal splits
          @children[0...-1].each do |child|
            x = child.rect.right
            (@rect.y...@rect.bottom).each do |y|
              buffer.set(x, y, '│', border_style) if clip.contains?(x, y)
            end
          end
        else
          # Horizontal borders between vertical splits
          @children[0...-1].each do |child|
            y = child.rect.bottom
            (@rect.x...@rect.right).each do |x|
              buffer.set(x, y, '─', border_style) if clip.contains?(x, y)
            end
          end
        end
      end

      def handle_event(event : Event) : Bool
        @children.each do |child|
          if child.handle_event(event)
            return true
          end
        end
        false
      end

      def focused_window : WindowNode?
        @children.each do |child|
          if w = child.focused_window
            return w
          end
        end
        nil
      end

      def all_windows : Array(WindowNode)
        result = [] of WindowNode
        @children.each do |child|
          result.concat(child.all_windows)
        end
        result
      end

      def find_window(id : String) : WindowNode?
        @children.each do |child|
          if w = child.find_window(id)
            return w
          end
        end
        nil
      end
    end

    # Window node - leaf containing actual content
    class WindowNode < LayoutNode
      property title : String = ""
      property content : Widget?
      property focused : Bool = false
      property show_title : Bool = true

      # Style
      property title_fg : Color = Color.white
      property title_bg : Color = Color.blue
      property title_focused_fg : Color = Color.yellow
      property title_focused_bg : Color = Color.blue
      property border_color : Color = Color.cyan
      property border_focused_color : Color = Color.yellow
      property content_bg : Color = Color.blue

      def initialize(title : String = "", id : String = WindowManager.next_id)
        super(id)
        @title = title
      end

      def content=(widget : Widget?)
        @content = widget
      end

      def focus : Nil
        @focused = true
      end

      def blur : Nil
        @focused = false
      end

      def content_rect : Rect
        y_offset = @show_title ? 1 : 0
        Rect.new(
          @rect.x,
          @rect.y + y_offset,
          @rect.width,
          Math.max(0, @rect.height - y_offset)
        )
      end

      def render(buffer : Buffer, clip : Rect) : Nil
        return if @rect.empty?

        # Draw title bar if enabled
        if @show_title
          draw_title(buffer, clip)
        end

        # Draw content
        if content = @content
          cr = content_rect
          content.rect = cr

          # Clear content area
          content_style = Style.new(bg: @content_bg)
          cr.height.times do |row|
            cr.width.times do |col|
              buffer.set(cr.x + col, cr.y + row, ' ', content_style) if clip.contains?(cr.x + col, cr.y + row)
            end
          end

          content.render(buffer, clip)
        end
      end

      private def draw_title(buffer : Buffer, clip : Rect) : Nil
        style = if @focused
                  Style.new(fg: @title_focused_fg, bg: @title_focused_bg, attrs: Attributes::Bold)
                else
                  Style.new(fg: @title_fg, bg: @title_bg)
                end

        y = @rect.y

        # Clear title line
        @rect.width.times do |i|
          buffer.set(@rect.x + i, y, ' ', style) if clip.contains?(@rect.x + i, y)
        end

        # Draw title centered
        title_x = @rect.x + (@rect.width - @title.size) // 2
        @title.each_char_with_index do |char, i|
          buffer.set(title_x + i, y, char, style) if clip.contains?(title_x + i, y)
        end

        # Draw focus indicator
        if @focused
          indicator_style = Style.new(fg: @border_focused_color, bg: style.bg)
          buffer.set(@rect.x, y, '▌', indicator_style) if clip.contains?(@rect.x, y)
        end
      end

      def handle_event(event : Event) : Bool
        return false unless @focused

        if content = @content
          return content.handle_event(event)
        end

        false
      end

      def focused_window : WindowNode?
        @focused ? self : nil
      end

      def all_windows : Array(WindowNode)
        [self]
      end

      def find_window(id : String) : WindowNode?
        @id == id ? self : nil
      end
    end

    # Main window manager
    @root : LayoutNode?
    @windows : Array(WindowNode) = [] of WindowNode
    @focused_index : Int32 = 0

    # Style
    property border_color : Color = Color.cyan

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    def root : LayoutNode?
      @root
    end

    def root=(node : LayoutNode)
      @root = node
      @windows = node.all_windows
      if @windows.size > 0
        @windows.first.focus
        @focused_index = 0
      end
      mark_dirty!
    end

    # Create a simple window
    def create_window(title : String, content : Widget? = nil) : WindowNode
      window = WindowNode.new(title)
      window.content = content
      window
    end

    # Create a horizontal split containing windows
    def hsplit(*windows : WindowNode) : SplitNode
      split = SplitNode.new(SplitDirection::Horizontal)
      windows.each { |w| split.add_child(w) }
      split
    end

    # Create a vertical split containing windows
    def vsplit(*windows : WindowNode) : SplitNode
      split = SplitNode.new(SplitDirection::Vertical)
      windows.each { |w| split.add_child(w) }
      split
    end

    # Split focused window horizontally
    def split_horizontal(new_window : WindowNode? = nil) : WindowNode?
      focused = focused_window
      return nil unless focused

      new_win = new_window || WindowNode.new("New")
      split_window(focused, new_win, SplitDirection::Horizontal)
      new_win
    end

    # Split focused window vertically
    def split_vertical(new_window : WindowNode? = nil) : WindowNode?
      focused = focused_window
      return nil unless focused

      new_win = new_window || WindowNode.new("New")
      split_window(focused, new_win, SplitDirection::Vertical)
      new_win
    end

    private def split_window(target : WindowNode, new_window : WindowNode, direction : SplitDirection) : Nil
      parent = target.parent

      # Create new split containing both windows
      new_split = SplitNode.new(direction)
      new_split.add_child(target)
      new_split.add_child(new_window)

      if parent
        # Replace target with new split in parent
        idx = parent.children.index(target)
        if idx
          parent.children[idx] = new_split
          new_split.parent = parent
          new_split.ratio = target.ratio
        end
      else
        # Target was root
        @root = new_split
      end

      @windows = @root.try(&.all_windows) || [] of WindowNode
      focus_window(new_window)
      mark_dirty!
    end

    # Close focused window
    def close_window : Bool
      return false if @windows.size <= 1
      focused = focused_window
      return false unless focused

      parent = focused.parent
      return false unless parent

      parent.remove_child(focused)

      # If parent has only one child, collapse it
      if parent.children.size == 1
        collapse_split(parent)
      end

      @windows = @root.try(&.all_windows) || [] of WindowNode
      @focused_index = @focused_index.clamp(0, @windows.size - 1)
      @windows[@focused_index]?.try(&.focus)
      mark_dirty!
      true
    end

    private def collapse_split(split : SplitNode) : Nil
      return unless split.children.size == 1

      child = split.children.first
      grandparent = split.parent

      if grandparent
        idx = grandparent.children.index(split)
        if idx
          grandparent.children[idx] = child
          child.parent = grandparent
          child.ratio = split.ratio
        end
      else
        # Split was root
        @root = child
        child.parent = nil
      end
    end

    def focused_window : WindowNode?
      @windows[@focused_index]?
    end

    def focus_window(window : WindowNode) : Nil
      @windows.each(&.blur)
      window.focus
      @focused_index = @windows.index(window) || 0
      mark_dirty!
    end

    def focus_next : Nil
      return if @windows.empty?
      @windows[@focused_index]?.try(&.blur)
      @focused_index = (@focused_index + 1) % @windows.size
      @windows[@focused_index].focus
      mark_dirty!
    end

    def focus_prev : Nil
      return if @windows.empty?
      @windows[@focused_index]?.try(&.blur)
      @focused_index = (@focused_index - 1) % @windows.size
      @focused_index = @windows.size - 1 if @focused_index < 0
      @windows[@focused_index].focus
      mark_dirty!
    end

    # Directional focus
    def focus_left : Nil
      move_focus(-1, 0)
    end

    def focus_right : Nil
      move_focus(1, 0)
    end

    def focus_up : Nil
      move_focus(0, -1)
    end

    def focus_down : Nil
      move_focus(0, 1)
    end

    private def move_focus(dx : Int32, dy : Int32) : Nil
      current = focused_window
      return unless current

      # Find window in the given direction
      best : WindowNode? = nil
      best_distance = Int32::MAX

      current_center_x = current.rect.x + current.rect.width // 2
      current_center_y = current.rect.y + current.rect.height // 2

      @windows.each do |window|
        next if window == current

        center_x = window.rect.x + window.rect.width // 2
        center_y = window.rect.y + window.rect.height // 2

        # Check if window is in the right direction
        if dx > 0 && center_x <= current_center_x
          next
        elsif dx < 0 && center_x >= current_center_x
          next
        elsif dy > 0 && center_y <= current_center_y
          next
        elsif dy < 0 && center_y >= current_center_y
          next
        end

        # Calculate distance
        distance = (center_x - current_center_x).abs + (center_y - current_center_y).abs
        if distance < best_distance
          best_distance = distance
          best = window
        end
      end

      if best
        focus_window(best)
      end
    end

    # Resize focused window
    def resize_focused(delta : Float64) : Nil
      focused = focused_window
      return unless focused
      parent = focused.parent
      return unless parent

      focused.ratio = (focused.ratio + delta).clamp(0.1, 0.9)
      parent.children.each do |child|
        next if child == focused
        child.ratio = (1.0 - focused.ratio) / (parent.children.size - 1)
      end
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      if root = @root
        root.rect = @rect
        root.render(buffer, clip)
      end
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?
      return false unless focused?

      case event
      when KeyEvent
        # Window management keys (Ctrl+W prefix like vim)
        if event.modifiers.ctrl?
          case event.char
          when 'w'
            # Ctrl+W is prefix, wait for next key
            # For now, just cycle windows
            focus_next
            event.stop!
            return true
          when 'h'
            focus_left
            event.stop!
            return true
          when 'l'
            focus_right
            event.stop!
            return true
          when 'j'
            focus_down
            event.stop!
            return true
          when 'k'
            focus_up
            event.stop!
            return true
          when 'v'
            split_vertical
            event.stop!
            return true
          when 's'
            split_horizontal
            event.stop!
            return true
          when 'q'
            close_window
            event.stop!
            return true
          when '+'
            resize_focused(0.05)
            event.stop!
            return true
          when '-'
            resize_focused(-0.05)
            event.stop!
            return true
          end
        end

        # Forward to focused window
        if root = @root
          if root.handle_event(event)
            return true
          end
        end
      end

      false
    end
  end
end
