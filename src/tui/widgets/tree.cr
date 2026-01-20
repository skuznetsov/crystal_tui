# Tree - Generic tree view widget
module Tui
  class Tree(T) < Widget
    class Node(T)
      property data : T
      property label : String
      property children : Array(Node(T)) = [] of Node(T)
      property expanded : Bool = false
      property parent : Node(T)?
      property icon : Char?
      property icon_expanded : Char?

      def initialize(@data : T, @label : String, @icon : Char? = nil, @icon_expanded : Char? = nil)
      end

      def leaf? : Bool
        @children.empty?
      end

      def add_child(child : Node(T)) : Node(T)
        child.parent = self
        @children << child
        child
      end

      def add(data : T, label : String, icon : Char? = nil, icon_expanded : Char? = nil) : Node(T)
        add_child(Node(T).new(data, label, icon, icon_expanded))
      end

      def toggle : Nil
        @expanded = !@expanded unless leaf?
      end

      def expand : Nil
        @expanded = true unless leaf?
      end

      def collapse : Nil
        @expanded = false
      end

      def depth : Int32
        parent.try(&.depth.+(1)) || 0
      end
    end

    property root : Node(T)?
    property show_root : Bool = true
    property indent : Int32 = 2
    property guide_lines : Bool = true

    # Colors
    property node_color : Color = Color.white
    property node_bg : Color = Color.default  # Background for non-selected nodes
    property selected_bg : Color = Color.blue
    property selected_fg : Color = Color.white
    property guide_color : Color = Color.palette(240)
    property icon_color : Color = Color.yellow

    # Icons
    property icon_expanded : Char = '▼'
    property icon_collapsed : Char = '▶'
    property icon_leaf : Char = '•'

    @visible_nodes : Array(Node(T)) = [] of Node(T)
    @selected_index : Int32 = 0
    @scroll_offset : Int32 = 0

    # Double-click detection
    @last_click_time : Time = Time.utc
    @last_click_index : Int32 = -1
    DOUBLE_CLICK_MS = 400

    @on_select : Proc(Node(T), Nil)?
    @on_expand : Proc(Node(T), Nil)?
    @on_collapse : Proc(Node(T), Nil)?
    @on_activate : Proc(Node(T), Nil)?  # Called on Enter or double-click

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    def on_select(&block : Node(T) -> Nil) : Nil
      @on_select = block
    end

    def on_expand(&block : Node(T) -> Nil) : Nil
      @on_expand = block
    end

    def on_collapse(&block : Node(T) -> Nil) : Nil
      @on_collapse = block
    end

    def on_activate(&block : Node(T) -> Nil) : Nil
      @on_activate = block
    end

    def selected_node : Node(T)?
      @visible_nodes[@selected_index]?
    end

    # Select a specific node by reference
    def select_node(node : Node(T)) : Bool
      build_visible_nodes
      if idx = @visible_nodes.index(node)
        @selected_index = idx
        ensure_visible
        mark_dirty!
        return true
      end
      false
    end

    # Ensure selected item is visible (scroll if needed)
    def ensure_visible : Nil
      return if @rect.empty?
      h = @rect.height
      return if h <= 0

      if @selected_index < @scroll_offset
        @scroll_offset = @selected_index
      elsif @selected_index >= @scroll_offset + h
        @scroll_offset = @selected_index - h + 1
      end
    end

    private def build_visible_nodes : Nil
      @visible_nodes.clear
      return unless root = @root

      if @show_root
        collect_visible(root)
      else
        root.children.each { |child| collect_visible(child) }
      end
    end

    private def collect_visible(node : Node(T)) : Nil
      @visible_nodes << node
      if node.expanded
        node.children.each { |child| collect_visible(child) }
      end
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      build_visible_nodes

      x, y, w, h = @rect.x, @rect.y, @rect.width, @rect.height

      # Adjust scroll to keep selection visible
      if @selected_index < @scroll_offset
        @scroll_offset = @selected_index
      elsif @selected_index >= @scroll_offset + h
        @scroll_offset = @selected_index - h + 1
      end

      # Render visible nodes
      h.times do |row|
        node_index = @scroll_offset + row
        break if node_index >= @visible_nodes.size

        node = @visible_nodes[node_index]
        render_node(buffer, clip, x, y + row, w, node, node_index == @selected_index)
      end
    end

    private def render_node(buffer : Buffer, clip : Rect, x : Int32, y : Int32, width : Int32, node : Node(T), selected : Bool) : Nil
      depth = @show_root ? node.depth : node.depth - 1
      indent_x = x + depth * @indent

      # Selection background
      if selected && focused?
        sel_style = Style.new(bg: @selected_bg)
        width.times do |i|
          buffer.set(x + i, y, ' ', sel_style) if clip.contains?(x + i, y)
        end
      end

      # Guide lines
      if @guide_lines && depth > 0
        guide_style = Style.new(fg: @guide_color)
        # Draw vertical guide for each ancestor level
        depth.times do |d|
          guide_x = x + d * @indent
          buffer.set(guide_x, y, '│', guide_style) if clip.contains?(guide_x, y)
        end
        # Draw horizontal connector
        connector_x = x + (depth - 1) * @indent
        buffer.set(connector_x, y, '├', guide_style) if clip.contains?(connector_x, y)
        ((depth - 1) * @indent + 1...depth * @indent).each do |i|
          buffer.set(x + i, y, '─', guide_style) if clip.contains?(x + i, y)
        end
      end

      # Expand/collapse icon or leaf icon
      bg = selected && focused? ? @selected_bg : @node_bg
      icon_style = Style.new(fg: @icon_color, bg: bg)
      icon = if node.leaf?
               node.icon || @icon_leaf
             elsif node.expanded
               node.icon_expanded || @icon_expanded
             else
               node.icon || @icon_collapsed
             end
      buffer.set(indent_x, y, icon, icon_style) if clip.contains?(indent_x, y)

      # Label
      label_style = Style.new(
        fg: selected && focused? ? @selected_fg : @node_color,
        bg: bg
      )
      label_x = indent_x + 2
      node.label.each_char_with_index do |char, i|
        break if label_x + i >= x + width
        buffer.set(label_x + i, y, char, label_style) if clip.contains?(label_x + i, y)
      end
    end

    def on_event(event : Event) : Bool
      case event
      when KeyEvent
        return false unless focused?

        case
        when event.matches?("up"), event.matches?("k")
          move_selection(-1)
          return true
        when event.matches?("down"), event.matches?("j")
          move_selection(1)
          return true
        when event.matches?("enter"), event.matches?("space")
          # Enter/Space: activate if leaf, toggle if folder
          if node = selected_node
            if node.leaf?
              @on_activate.try &.call(node)
            else
              toggle_selected
            end
          end
          return true
        when event.matches?("right"), event.matches?("l")
          expand_selected
          return true
        when event.matches?("left"), event.matches?("h")
          collapse_selected
          return true
        when event.matches?("home")
          @selected_index = 0
          mark_dirty!
          return true
        when event.matches?("end")
          build_visible_nodes
          @selected_index = @visible_nodes.size - 1
          mark_dirty!
          return true
        when event.matches?("pageup"), event.matches?("ctrl+u")
          page_size = @rect.height > 0 ? @rect.height : 10
          move_selection(-page_size)
          return true
        when event.matches?("pagedown"), event.matches?("ctrl+d")
          page_size = @rect.height > 0 ? @rect.height : 10
          move_selection(page_size)
          return true
        end

      when MouseEvent
        # Wheel scrolling works without focus (hover scroll)
        if event.in_rect?(@rect)
          if event.button.wheel_up?
            @scroll_offset = (@scroll_offset - 3).clamp(0, (@visible_nodes.size - @rect.height).clamp(0, Int32::MAX))
            mark_dirty!
            return true
          elsif event.button.wheel_down?
            @scroll_offset = (@scroll_offset + 3).clamp(0, (@visible_nodes.size - @rect.height).clamp(0, Int32::MAX))
            mark_dirty!
            return true
          end
        end

        # Click handling
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          clicked_index = @scroll_offset + (event.y - @rect.y)
          if clicked_index >= 0 && clicked_index < @visible_nodes.size
            now = Time.utc
            is_double_click = clicked_index == @last_click_index &&
                              (now - @last_click_time).total_milliseconds < DOUBLE_CLICK_MS

            @last_click_time = now
            @last_click_index = clicked_index

            @selected_index = clicked_index
            @on_select.try &.call(@visible_nodes[@selected_index])

            if is_double_click
              # Double-click: activate if leaf, toggle if folder
              if node = @visible_nodes[clicked_index]?
                if node.leaf?
                  @on_activate.try &.call(node)
                else
                  toggle_selected
                end
              end
            end
            mark_dirty!
            return true
          end
        end
      end

      false
    end

    private def move_selection(delta : Int32) : Nil
      build_visible_nodes
      return if @visible_nodes.empty?

      @selected_index = (@selected_index + delta).clamp(0, @visible_nodes.size - 1)
      @on_select.try &.call(@visible_nodes[@selected_index])
      mark_dirty!
    end

    private def toggle_selected : Nil
      if node = selected_node
        node.toggle
        if node.expanded
          @on_expand.try &.call(node)
        else
          @on_collapse.try &.call(node)
        end
        mark_dirty!
      end
    end

    private def expand_selected : Nil
      if node = selected_node
        unless node.leaf? || node.expanded
          node.expand
          @on_expand.try &.call(node)
          mark_dirty!
        end
      end
    end

    private def collapse_selected : Nil
      if node = selected_node
        if node.expanded
          node.collapse
          @on_collapse.try &.call(node)
          mark_dirty!
        elsif parent = node.parent
          # Move to parent
          build_visible_nodes
          if idx = @visible_nodes.index(parent)
            @selected_index = idx
            @on_select.try &.call(parent)
            mark_dirty!
          end
        end
      end
    end

    # Expand all nodes
    def expand_all : Nil
      expand_recursive(@root)
      mark_dirty!
    end

    # Collapse all nodes
    def collapse_all : Nil
      collapse_recursive(@root)
      mark_dirty!
    end

    private def expand_recursive(node : Node(T)?) : Nil
      return unless node
      node.expand
      node.children.each { |child| expand_recursive(child) }
    end

    private def collapse_recursive(node : Node(T)?) : Nil
      return unless node
      node.collapse
      node.children.each { |child| collapse_recursive(child) }
    end
  end
end
