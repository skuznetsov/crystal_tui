# Canvas - Visual widget placement area for TUI Editor
require "./widget_palette"
require "./clipboard"

module TuiEditor
  # Represents a placed widget in the canvas
  class CanvasNode
    property widget_def : WidgetDef
    property id : String
    property attrs : Hash(String, String)
    property children : Array(CanvasNode)
    property parent : CanvasNode?
    property expanded : Bool = true

    def initialize(@widget_def, @id = "", @attrs = {} of String => String)
      @children = [] of CanvasNode
      # Copy default attrs
      @widget_def.default_attrs.each { |k, v| @attrs[k] = v unless @attrs.has_key?(k) }
    end

    def name : String
      @widget_def.name
    end

    def container? : Bool
      %w[Panel VBox HBox VStack HStack Grid].includes?(@widget_def.name)
    end

    def stack? : Bool
      %w[VStack HStack].includes?(@widget_def.name)
    end

    def alignment : String
      @attrs["align"]? || "stretch"
    end

    def add_child(node : CanvasNode) : Nil
      node.parent = self
      @children << node
    end

    def remove_child(node : CanvasNode) : Nil
      @children.delete(node)
      node.parent = nil
    end

    # Generate unique ID
    def self.next_id(prefix : String) : String
      @@counter ||= 0
      @@counter = @@counter.not_nil! + 1
      "#{prefix.downcase}#{@@counter}"
    end

    @@counter : Int32?
  end

  class Canvas < Tui::Panel
    @root : CanvasNode?
    @selected : CanvasNode?
    @scroll_offset : Int32 = 0
    @on_select : Proc(CanvasNode?, Nil)?

    # Clipboard with history
    @clipboard_history : ClipboardHistory = ClipboardHistory.new

    def initialize
      super("Canvas", id: "canvas")
      @focusable = true
      @border_style = BorderStyle::None  # SplitContainer draws border
    end

    def clipboard_history : ClipboardHistory
      @clipboard_history
    end

    def clipboard : CanvasNode?
      @clipboard_history.latest.try(&.node)
    end

    def cut_mode? : Bool
      @clipboard_history.latest.try(&.cut) || false
    end

    def root : CanvasNode?
      @root
    end

    def root=(node : CanvasNode?) : Nil
      @root = node
      @selected = node
      mark_dirty!
    end

    def selected : CanvasNode?
      @selected
    end

    def on_select(&block : CanvasNode? -> Nil)
      @on_select = block
    end

    # Add widget to currently selected container (or root)
    def add_widget(widget_def : WidgetDef) : CanvasNode?
      node = CanvasNode.new(widget_def, CanvasNode.next_id(widget_def.name))

      if root = @root
        # Find target container
        target = find_container(@selected) || root
        if target.container?
          target.add_child(node)
        else
          # Add as sibling
          if parent = target.parent
            parent.add_child(node)
          else
            # Can't add to non-container root
            return nil
          end
        end
      else
        # First widget becomes root
        @root = node
      end

      @selected = node
      @on_select.try &.call(node)
      mark_dirty!
      node
    end

    # Delete selected widget
    def delete_selected : Bool
      return false unless selected = @selected

      if parent = selected.parent
        parent.remove_child(selected)
        @selected = parent
      elsif selected == @root
        @root = nil
        @selected = nil
      else
        return false
      end

      @on_select.try &.call(@selected)
      mark_dirty!
      true
    end

    # Cut selected widget to clipboard
    def cut_selected : Bool
      return false unless selected = @selected
      return false if selected == @root && @root.not_nil!.children.empty?  # Can't cut empty root

      @clipboard_history.push(deep_copy(selected), cut: true)

      # Remove from tree
      delete_selected
      true
    end

    # Copy selected widget to clipboard
    def copy_selected : Bool
      return false unless selected = @selected

      @clipboard_history.push(deep_copy(selected), cut: false)
      mark_dirty!
      true
    end

    # Paste clipboard content (latest from history)
    def paste : Bool
      entry = @clipboard_history.latest
      return false unless entry
      paste_node(entry.node)
    end

    # Paste specific node (from history selection)
    def paste_node(node : CanvasNode) : Bool
      return false unless node

      # Deep copy to allow multiple pastes
      copy = deep_copy(node)
      regenerate_ids(copy)  # Give new IDs to avoid conflicts

      if root = @root
        # Find target container
        target = find_container(@selected) || root
        if target.container?
          target.add_child(copy)
        else
          # Add as sibling
          if parent = target.parent
            parent.add_child(copy)
          else
            return false
          end
        end
      else
        # Empty canvas - paste as root
        @root = copy
      end

      @selected = copy
      @on_select.try &.call(copy)
      mark_dirty!
      true
    end

    # Move selected widget up in parent's children list
    def move_up : Bool
      return false unless selected = @selected
      return false unless parent = selected.parent

      idx = parent.children.index(selected)
      return false unless idx && idx > 0

      # Swap with previous sibling
      parent.children[idx] = parent.children[idx - 1]
      parent.children[idx - 1] = selected
      mark_dirty!
      true
    end

    # Move selected widget down in parent's children list
    def move_down : Bool
      return false unless selected = @selected
      return false unless parent = selected.parent

      idx = parent.children.index(selected)
      return false unless idx && idx < parent.children.size - 1

      # Swap with next sibling
      parent.children[idx] = parent.children[idx + 1]
      parent.children[idx + 1] = selected
      mark_dirty!
      true
    end

    # Move selected widget to a different parent (reparent)
    def move_to_parent(new_parent : CanvasNode) : Bool
      return false unless selected = @selected
      return false unless new_parent.container?
      return false if new_parent == selected  # Can't move to self
      return false if is_ancestor?(selected, new_parent)  # Can't move to descendant

      # Remove from current parent
      if parent = selected.parent
        parent.remove_child(selected)
      elsif selected == @root
        return false  # Can't move root
      end

      # Add to new parent
      new_parent.add_child(selected)
      mark_dirty!
      true
    end

    # Check if 'ancestor' is an ancestor of 'node'
    private def is_ancestor?(ancestor : CanvasNode, node : CanvasNode) : Bool
      current = node.parent
      while current
        return true if current == ancestor
        current = current.parent
      end
      false
    end

    # Deep copy a node and its children
    private def deep_copy(node : CanvasNode) : CanvasNode
      copy = CanvasNode.new(node.widget_def, node.id, node.attrs.dup)
      copy.expanded = node.expanded
      node.children.each do |child|
        child_copy = deep_copy(child)
        copy.add_child(child_copy)
      end
      copy
    end

    # Regenerate IDs for a node tree (for paste to avoid conflicts)
    private def regenerate_ids(node : CanvasNode) : Nil
      node.id = CanvasNode.next_id(node.widget_def.name)
      node.children.each { |child| regenerate_ids(child) }
    end

    # Find nearest container (self or parent)
    private def find_container(node : CanvasNode?) : CanvasNode?
      current = node
      while current
        return current if current.container?
        current = current.parent
      end
      nil
    end

    def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
      super

      inner = inner_rect
      return if inner.empty?

      if root = @root
        # Render the widget tree visually
        render_widget_tree(buffer, clip, root, inner.x, inner.y, inner.width, inner.height)
      else
        # Empty canvas message
        msg = "Drop a widget here to start"
        x = inner.x + (inner.width - msg.size) // 2
        y = inner.y + inner.height // 2
        style = Tui::Style.new(fg: Tui::Color.rgb(100, 100, 100))
        msg.each_char_with_index do |char, i|
          buffer.set(x + i, y, char, style) if clip.contains?(x + i, y)
        end
      end
    end

    private def render_widget_tree(buffer : Tui::Buffer, clip : Tui::Rect,
                                   node : CanvasNode, x : Int32, y : Int32,
                                   width : Int32, height : Int32) : Nil
      return if width < 3 || height < 1

      is_selected = node == @selected
      is_container = node.container?

      # Determine style
      border_color = if is_selected && focused?
                       Tui::Color.cyan
                     elsif is_selected
                       Tui::Color.white
                     else
                       Tui::Color.rgb(80, 80, 80)
                     end

      if is_container
        if node.stack?
          # Draw stack (no border)
          render_stack(buffer, clip, node, x, y, width, height, border_color)
        else
          # Draw container with border
          render_container(buffer, clip, node, x, y, width, height, border_color)
        end
      else
        # Draw leaf widget
        render_leaf(buffer, clip, node, x, y, width, border_color)
      end
    end

    private def render_container(buffer : Tui::Buffer, clip : Tui::Rect,
                                 node : CanvasNode, x : Int32, y : Int32,
                                 width : Int32, height : Int32, color : Tui::Color) : Nil
      style = Tui::Style.new(fg: color)
      title_style = Tui::Style.new(fg: color, attrs: Tui::Attributes::Bold)

      # Draw border
      # Top
      buffer.set(x, y, '┌', style) if clip.contains?(x, y)
      (1...width - 1).each do |i|
        buffer.set(x + i, y, '─', style) if clip.contains?(x + i, y)
      end
      buffer.set(x + width - 1, y, '┐', style) if clip.contains?(x + width - 1, y)

      # Title
      title = " #{node.widget_def.icon} #{display_name(node)} "
      title_x = x + 2
      title.each_char_with_index do |char, i|
        break if title_x + i >= x + width - 1
        buffer.set(title_x + i, y, char, title_style) if clip.contains?(title_x + i, y)
      end

      # Sides
      (1...height - 1).each do |i|
        buffer.set(x, y + i, '│', style) if clip.contains?(x, y + i)
        buffer.set(x + width - 1, y + i, '│', style) if clip.contains?(x + width - 1, y + i)
      end

      # Bottom
      buffer.set(x, y + height - 1, '└', style) if clip.contains?(x, y + height - 1)
      (1...width - 1).each do |i|
        buffer.set(x + i, y + height - 1, '─', style) if clip.contains?(x + i, y + height - 1)
      end
      buffer.set(x + width - 1, y + height - 1, '┘', style) if clip.contains?(x + width - 1, y + height - 1)

      # Render children inside
      if node.children.any? && node.expanded
        inner_x = x + 1
        inner_y = y + 1
        inner_w = width - 2
        inner_h = height - 2

        render_children(buffer, clip, node, inner_x, inner_y, inner_w, inner_h)
      end
    end

    # Render stack container (no border)
    private def render_stack(buffer : Tui::Buffer, clip : Tui::Rect,
                             node : CanvasNode, x : Int32, y : Int32,
                             width : Int32, height : Int32, color : Tui::Color) : Nil
      is_selected = node == @selected

      # Draw subtle indicator for stack (dotted outline when selected)
      if is_selected && focused?
        style = Tui::Style.new(fg: color)
        # Top-left corner indicator
        buffer.set(x, y, '·', style) if clip.contains?(x, y)
        buffer.set(x + width - 1, y, '·', style) if clip.contains?(x + width - 1, y)
        buffer.set(x, y + height - 1, '·', style) if clip.contains?(x, y + height - 1)
        buffer.set(x + width - 1, y + height - 1, '·', style) if clip.contains?(x + width - 1, y + height - 1)
      end

      # Render children
      if node.children.any? && node.expanded
        render_children(buffer, clip, node, x, y, width, height)
      else
        # Show placeholder for empty stack
        text = "#{node.widget_def.icon} #{node.widget_def.name}"
        style = Tui::Style.new(fg: Tui::Color.rgb(80, 80, 80))
        text.each_char_with_index do |c, i|
          buffer.set(x + i, y, c, style) if clip.contains?(x + i, y) && i < width
        end
      end
    end

    # Shared child rendering logic with alignment support
    private def render_children(buffer : Tui::Buffer, clip : Tui::Rect,
                                node : CanvasNode, inner_x : Int32, inner_y : Int32,
                                inner_w : Int32, inner_h : Int32) : Nil
      align = node.alignment

      case node.widget_def.name
      when "VBox", "VStack"
        render_vchildren(buffer, clip, node, inner_x, inner_y, inner_w, inner_h, align)
      when "HBox", "HStack"
        render_hchildren(buffer, clip, node, inner_x, inner_y, inner_w, inner_h, align)
      else
        # Panel/Grid - vertical layout
        render_vchildren(buffer, clip, node, inner_x, inner_y, inner_w, inner_h, align)
      end
    end

    private def render_vchildren(buffer : Tui::Buffer, clip : Tui::Rect,
                                 node : CanvasNode, inner_x : Int32, inner_y : Int32,
                                 inner_w : Int32, inner_h : Int32, align : String) : Nil
      case align
      when "top"
        # Stack children at top with minimum height (1 row each for leaves)
        current_y = inner_y
        node.children.each do |child|
          child_h = child.container? ? 3 : 1  # Minimum heights
          break if current_y + child_h > inner_y + inner_h
          render_widget_tree(buffer, clip, child, inner_x, current_y, inner_w, child_h)
          current_y += child_h
        end
      when "bottom"
        # Stack children at bottom
        total_h = node.children.sum { |c| c.container? ? 3 : 1 }
        current_y = inner_y + inner_h - total_h
        node.children.each do |child|
          child_h = child.container? ? 3 : 1
          next if current_y < inner_y
          render_widget_tree(buffer, clip, child, inner_x, current_y, inner_w, child_h)
          current_y += child_h
        end
      when "center"
        # Center children vertically
        total_h = node.children.sum { |c| c.container? ? 3 : 1 }
        current_y = inner_y + (inner_h - total_h) // 2
        node.children.each do |child|
          child_h = child.container? ? 3 : 1
          render_widget_tree(buffer, clip, child, inner_x, current_y, inner_w, child_h)
          current_y += child_h
        end
      else  # "stretch" - fill available space
        child_height = inner_h // node.children.size
        node.children.each_with_index do |child, i|
          child_y = inner_y + i * child_height
          h = (i == node.children.size - 1) ? inner_h - i * child_height : child_height
          render_widget_tree(buffer, clip, child, inner_x, child_y, inner_w, h)
        end
      end
    end

    private def render_hchildren(buffer : Tui::Buffer, clip : Tui::Rect,
                                 node : CanvasNode, inner_x : Int32, inner_y : Int32,
                                 inner_w : Int32, inner_h : Int32, align : String) : Nil
      case align
      when "left"
        # Stack children at left with minimum width
        current_x = inner_x
        node.children.each do |child|
          child_w = child.container? ? 10 : 12  # Minimum widths
          break if current_x + child_w > inner_x + inner_w
          render_widget_tree(buffer, clip, child, current_x, inner_y, child_w, inner_h)
          current_x += child_w
        end
      when "right"
        # Stack children at right
        total_w = node.children.sum { |c| c.container? ? 10 : 12 }
        current_x = inner_x + inner_w - total_w
        node.children.each do |child|
          child_w = child.container? ? 10 : 12
          next if current_x < inner_x
          render_widget_tree(buffer, clip, child, current_x, inner_y, child_w, inner_h)
          current_x += child_w
        end
      when "center"
        # Center children horizontally
        total_w = node.children.sum { |c| c.container? ? 10 : 12 }
        current_x = inner_x + (inner_w - total_w) // 2
        node.children.each do |child|
          child_w = child.container? ? 10 : 12
          render_widget_tree(buffer, clip, child, current_x, inner_y, child_w, inner_h)
          current_x += child_w
        end
      else  # "stretch" - fill available space
        child_width = inner_w // node.children.size
        node.children.each_with_index do |child, i|
          child_x = inner_x + i * child_width
          w = (i == node.children.size - 1) ? inner_w - i * child_width : child_width
          render_widget_tree(buffer, clip, child, child_x, inner_y, w, inner_h)
        end
      end
    end

    private def render_leaf(buffer : Tui::Buffer, clip : Tui::Rect,
                            node : CanvasNode, x : Int32, y : Int32,
                            width : Int32, color : Tui::Color) : Nil
      is_selected = node == @selected

      # Render widget-specific visual representation
      case node.widget_def.name
      when "Button"
        render_button(buffer, clip, node, x, y, width, color, is_selected)
      when "Input"
        render_input(buffer, clip, node, x, y, width, color, is_selected)
      when "Checkbox"
        render_checkbox(buffer, clip, node, x, y, width, color, is_selected)
      when "Switch"
        render_switch(buffer, clip, node, x, y, width, color, is_selected)
      when "Slider"
        render_slider(buffer, clip, node, x, y, width, color, is_selected)
      when "Label"
        render_label(buffer, clip, node, x, y, width, color, is_selected)
      when "Header"
        render_header_widget(buffer, clip, node, x, y, width, color, is_selected)
      when "Footer"
        render_footer_widget(buffer, clip, node, x, y, width, color, is_selected)
      when "ProgressBar"
        render_progress(buffer, clip, node, x, y, width, color, is_selected)
      when "Rule"
        render_rule(buffer, clip, node, x, y, width, color, is_selected)
      else
        # Default: icon + name
        render_default_leaf(buffer, clip, node, x, y, width, color, is_selected)
      end
    end

    private def render_button(buffer, clip, node, x, y, width, color, selected)
      label = node.attrs["label"]? || "Button"
      text = "[ #{label} ]"
      style = if selected
                Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.cyan)
              else
                Tui::Style.new(fg: Tui::Color.white, bg: Tui::Color.blue)
              end
      draw_centered(buffer, clip, text, x, y, width, style)
    end

    private def render_input(buffer, clip, node, x, y, width, color, selected)
      placeholder = node.attrs["placeholder"]? || ""
      # Draw input box: [________]
      box_width = [width, 20].min
      style = if selected
                Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.cyan)
              else
                Tui::Style.new(fg: Tui::Color.rgb(150, 150, 150), bg: Tui::Color.rgb(40, 40, 40))
              end
      buffer.set(x, y, '[', style) if clip.contains?(x, y)
      text = placeholder.size > box_width - 2 ? placeholder[0...(box_width - 3)] + "…" : placeholder.ljust(box_width - 2)
      text.each_char_with_index do |char, i|
        buffer.set(x + 1 + i, y, char, style) if clip.contains?(x + 1 + i, y)
      end
      buffer.set(x + box_width - 1, y, ']', style) if clip.contains?(x + box_width - 1, y)
    end

    private def render_checkbox(buffer, clip, node, x, y, width, color, selected)
      label = node.attrs["label"]? || "Checkbox"
      text = "☐ #{label}"
      style = selected ? Tui::Style.new(fg: Tui::Color.black, bg: color) : Tui::Style.new(fg: color)
      draw_text_styled(buffer, clip, text, x, y, width, style, selected)
    end

    private def render_switch(buffer, clip, node, x, y, width, color, selected)
      text = "◯━━●"  # Off state visual
      style = selected ? Tui::Style.new(fg: Tui::Color.black, bg: color) : Tui::Style.new(fg: Tui::Color.rgb(100, 100, 100))
      draw_text_styled(buffer, clip, text, x, y, width, style, selected)
    end

    private def render_slider(buffer, clip, node, x, y, width, color, selected)
      # Draw slider: ───●───
      slider_width = [width, 15].min
      pos = slider_width // 2
      style = selected ? Tui::Style.new(fg: Tui::Color.black, bg: color) : Tui::Style.new(fg: color)
      slider_width.times do |i|
        char = i == pos ? '●' : '─'
        buffer.set(x + i, y, char, style) if clip.contains?(x + i, y)
      end
    end

    private def render_label(buffer, clip, node, x, y, width, color, selected)
      text = node.attrs["text"]? || "Label"
      style = selected ? Tui::Style.new(fg: Tui::Color.black, bg: color) : Tui::Style.new(fg: Tui::Color.white)
      draw_text_styled(buffer, clip, text, x, y, width, style, selected)
    end

    private def render_header_widget(buffer, clip, node, x, y, width, color, selected)
      title = node.attrs["title"]? || "Header"
      style = if selected
                Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.cyan)
              else
                Tui::Style.new(fg: Tui::Color.white, bg: Tui::Color.blue)
              end
      # Fill background
      width.times { |i| buffer.set(x + i, y, ' ', style) if clip.contains?(x + i, y) }
      title.each_char_with_index { |c, i| buffer.set(x + 1 + i, y, c, style) if clip.contains?(x + 1 + i, y) && i < width - 2 }
    end

    private def render_footer_widget(buffer, clip, node, x, y, width, color, selected)
      style = if selected
                Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.cyan)
              else
                Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.white)
              end
      text = "1Help  2...  10Quit"
      width.times { |i| buffer.set(x + i, y, ' ', style) if clip.contains?(x + i, y) }
      text.each_char_with_index { |c, i| buffer.set(x + i, y, c, style) if clip.contains?(x + i, y) && i < width }
    end

    private def render_progress(buffer, clip, node, x, y, width, color, selected)
      value = (node.attrs["value"]?.try(&.to_f) || 0.5).clamp(0.0, 1.0)
      bar_width = [width, 20].min
      filled = (bar_width * value).to_i
      style = selected ? Tui::Style.new(fg: Tui::Color.black, bg: color) : Tui::Style.new(fg: Tui::Color.green)
      empty_style = selected ? style : Tui::Style.new(fg: Tui::Color.rgb(60, 60, 60))
      bar_width.times do |i|
        char = i < filled ? '█' : '░'
        s = i < filled ? style : empty_style
        buffer.set(x + i, y, char, s) if clip.contains?(x + i, y)
      end
    end

    private def render_rule(buffer, clip, node, x, y, width, color, selected)
      style = selected ? Tui::Style.new(fg: Tui::Color.black, bg: color) : Tui::Style.new(fg: Tui::Color.rgb(80, 80, 80))
      width.times { |i| buffer.set(x + i, y, '─', style) if clip.contains?(x + i, y) }
    end

    private def render_default_leaf(buffer, clip, node, x, y, width, color, selected)
      text = "#{node.widget_def.icon} #{display_name(node)}"
      style = selected ? Tui::Style.new(fg: Tui::Color.black, bg: color) : Tui::Style.new(fg: color)
      draw_text_styled(buffer, clip, text, x, y, width, style, selected)
    end

    private def draw_text_styled(buffer, clip, text, x, y, width, style, fill_bg)
      if fill_bg
        width.times { |i| buffer.set(x + i, y, ' ', style) if clip.contains?(x + i, y) }
      end
      text.each_char_with_index { |c, i| buffer.set(x + i, y, c, style) if clip.contains?(x + i, y) && i < width }
    end

    private def draw_centered(buffer, clip, text, x, y, width, style)
      start_x = x + (width - text.size) // 2
      start_x = x if start_x < x
      text.each_char_with_index { |c, i| buffer.set(start_x + i, y, c, style) if clip.contains?(start_x + i, y) && start_x + i < x + width }
    end

    private def display_name(node : CanvasNode) : String
      if node.id.empty?
        node.widget_def.name
      else
        "#{node.widget_def.name}##{node.id}"
      end
    end

    def handle_event(event : Tui::Event) : Bool
      return false if event.stopped?

      case event
      when Tui::KeyEvent
        return false unless focused?

        case
        when event.matches?("up"), event.matches?("k")
          select_prev
          return true
        when event.matches?("down"), event.matches?("j")
          select_next
          return true
        when event.matches?("left"), event.matches?("h")
          # Go to parent
          if selected = @selected
            if parent = selected.parent
              @selected = parent
              @on_select.try &.call(@selected)
              mark_dirty!
            end
          end
          return true
        when event.matches?("right"), event.matches?("l")
          # Go to first child
          if selected = @selected
            if selected.children.any?
              @selected = selected.children.first
              @on_select.try &.call(@selected)
              mark_dirty!
            end
          end
          return true
        when event.matches?("delete"), event.matches?("backspace"), event.matches?("d")
          delete_selected
          return true
        when event.matches?("ctrl+x")
          cut_selected
          return true
        when event.matches?("ctrl+c")
          copy_selected
          return true
        when event.matches?("ctrl+v")
          paste
          return true
        when event.matches?("shift+up"), event.matches?("K")
          move_up
          return true
        when event.matches?("shift+down"), event.matches?("J")
          move_down
          return true
        end
      when Tui::MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          # Focus on click
          focus unless focused?

          # Find clicked node
          if root = @root
            if node = find_node_at(root, event.x, event.y, inner_rect)
              @selected = node
              @on_select.try &.call(node)
              mark_dirty!
              return true
            end
          end
        end
      end

      super
    end

    private def find_node_at(node : CanvasNode, mx : Int32, my : Int32, rect : Tui::Rect) : CanvasNode?
      # Use flattened tree order - return clicked item or nearest based on Y
      nodes = flatten_tree(node)
      return nil if nodes.empty?

      # For now, use simple Y-based selection (1 row per widget in flattened view)
      inner = inner_rect
      relative_y = my - inner.y

      # Each node takes ~1-3 rows depending on type
      # Simplified: just return the node at that index in flat list
      idx = relative_y.clamp(0, nodes.size - 1)
      nodes[idx]?
    end

    private def select_prev
      return unless root = @root
      nodes = flatten_tree(root)
      return if nodes.empty?

      current_idx = nodes.index(@selected) || 0
      new_idx = (current_idx - 1).clamp(0, nodes.size - 1)
      @selected = nodes[new_idx]
      @on_select.try &.call(@selected)
      mark_dirty!
    end

    private def select_next
      return unless root = @root
      nodes = flatten_tree(root)
      return if nodes.empty?

      current_idx = nodes.index(@selected) || 0
      new_idx = (current_idx + 1).clamp(0, nodes.size - 1)
      @selected = nodes[new_idx]
      @on_select.try &.call(@selected)
      mark_dirty!
    end

    private def flatten_tree(node : CanvasNode) : Array(CanvasNode)
      result = [node]
      node.children.each do |child|
        result.concat(flatten_tree(child))
      end
      result
    end

    # Generate TUML from canvas
    def to_tuml(format : Symbol = :pug) : String
      return "" unless root = @root
      case format
      when :pug
        to_pug(root, 0)
      when :yaml
        to_yaml(root, 0)
      else
        to_json(root)
      end
    end

    private def to_pug(node : CanvasNode, indent : Int32) : String
      prefix = "  " * indent
      line = "#{prefix}#{node.widget_def.name}"
      line += "##{node.id}" unless node.id.empty?

      # Add attributes
      attrs = node.attrs.reject { |k, _| node.widget_def.default_attrs[k]? == node.attrs[k]? }
      if attrs.any?
        attr_str = attrs.map { |k, v| "#{k}=\"#{v}\"" }.join(", ")
        line += "(#{attr_str})"
      end

      # Add text for labels/buttons
      if text = node.attrs["text"]? || node.attrs["label"]?
        line += " #{text}"
      end

      lines = [line]
      node.children.each do |child|
        lines << to_pug(child, indent + 1)
      end
      lines.join("\n")
    end

    private def to_yaml(node : CanvasNode, indent : Int32) : String
      prefix = "  " * indent
      line = "#{prefix}#{node.widget_def.name}"
      line += "##{node.id}" unless node.id.empty?
      line += ":"

      lines = [line]

      # Attributes
      attrs = node.attrs.reject { |k, _| node.widget_def.default_attrs[k]? == node.attrs[k]? }
      attrs.each do |k, v|
        lines << "#{prefix}  #{k}: #{v}"
      end

      # Children
      if node.children.any?
        lines << "#{prefix}  children:"
        node.children.each do |child|
          lines << to_yaml(child, indent + 2)
        end
      end

      lines.join("\n")
    end

    private def to_json(node : CanvasNode) : String
      # Simple JSON generation
      parts = [] of String
      parts << %("type": "#{node.widget_def.name}")
      parts << %("id": "#{node.id}") unless node.id.empty?

      node.attrs.each do |k, v|
        parts << %("#{k}": "#{v}")
      end

      if node.children.any?
        children_json = node.children.map { |c| to_json(c) }.join(", ")
        parts << %("children": [#{children_json}])
      end

      "{#{parts.join(", ")}}"
    end
  end
end
