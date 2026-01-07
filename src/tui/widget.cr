# Base widget class
module Tui
  # Box model for margins and padding (in cells)
  struct BoxModel
    property top : Int32
    property right : Int32
    property bottom : Int32
    property left : Int32

    def initialize(@top : Int32 = 0, @right : Int32 = 0, @bottom : Int32 = 0, @left : Int32 = 0)
    end

    def self.zero : BoxModel
      new(0, 0, 0, 0)
    end

    def self.all(value : Int32) : BoxModel
      new(value, value, value, value)
    end

    def self.symmetric(vertical : Int32, horizontal : Int32) : BoxModel
      new(vertical, horizontal, vertical, horizontal)
    end

    def horizontal : Int32
      @left + @right
    end

    def vertical : Int32
      @top + @bottom
    end
  end

  abstract class Widget
    include Reactive

    # Identity
    property id : String?
    property classes : Set(String) = Set(String).new

    # Hierarchy
    property parent : Widget?
    @children : Array(Widget) = [] of Widget

    # Geometry (set by layout engine)
    property rect : Rect = Rect.zero

    # Layout constraints (CSS-driven)
    property constraints : Constraints = Constraints.default
    property margin : BoxModel = BoxModel.zero
    property padding : BoxModel = BoxModel.zero

    # State
    property? visible : Bool = true
    property? mounted : Bool = false
    property? focusable : Bool = false  # Can receive focus
    @focused : Bool = false
    @hovered : Bool = false

    # Z-order (higher = on top)
    property z_index : Int32 = 0

    # Global focus and hover tracking
    class_property focused_widget : Widget? = nil
    class_property hovered_widget : Widget? = nil

    # Dirty flag for re-rendering
    @dirty : Bool = true

    def initialize(@id : String? = nil)
    end

    # Focus management
    def focused? : Bool
      @focused
    end

    def focused=(value : Bool) : Nil
      if value
        # Clear previous focus
        if old = Widget.focused_widget
          if old != self
            old.clear_focus_internal
          end
        end
        Widget.focused_widget = self
        @focused = true
        mark_dirty!
      else
        @focused = false
        Widget.focused_widget = nil if Widget.focused_widget == self
        mark_dirty!
      end
    end

    # Internal method to clear focus without triggering global update
    protected def clear_focus_internal : Nil
      @focused = false
      mark_dirty!
    end

    # Request focus (convenience method)
    def focus : Nil
      self.focused = true
    end

    def blur : Nil
      self.focused = false
    end

    # Alias for focus (bang version for Button etc.)
    def focus! : Nil
      focus
    end

    # Hover management
    def hovered? : Bool
      @hovered
    end

    def hovered=(value : Bool) : Nil
      if value
        # Clear previous hover
        if old = Widget.hovered_widget
          if old != self
            old.clear_hover_internal
          end
        end
        Widget.hovered_widget = self
        @hovered = true
        mark_dirty!
      else
        @hovered = false
        Widget.hovered_widget = nil if Widget.hovered_widget == self
        mark_dirty!
      end
    end

    protected def clear_hover_internal : Nil
      @hovered = false
      mark_dirty!
    end

    # Collect all focusable widgets in tree order (depth-first)
    def collect_focusable : Array(Widget)
      result = [] of Widget
      collect_focusable_recursive(result)
      result
    end

    protected def collect_focusable_recursive(result : Array(Widget)) : Nil
      result << self if @focusable && @visible
      @children.each { |child| child.collect_focusable_recursive(result) }
    end

    # Focus next focusable widget (Tab behavior)
    def focus_next : Widget?
      focusable = root_widget.collect_focusable
      return nil if focusable.empty?

      if focused_widget = Widget.focused_widget
        idx = focusable.index(focused_widget)
        if idx
          next_idx = (idx + 1) % focusable.size
          focusable[next_idx].focus
          return focusable[next_idx]
        end
      end

      # No current focus, focus first
      focusable.first.focus
      focusable.first
    end

    # Focus previous focusable widget (Shift+Tab behavior)
    def focus_prev : Widget?
      focusable = root_widget.collect_focusable
      return nil if focusable.empty?

      if focused_widget = Widget.focused_widget
        idx = focusable.index(focused_widget)
        if idx
          prev_idx = (idx - 1) % focusable.size
          focusable[prev_idx].focus
          return focusable[prev_idx]
        end
      end

      # No current focus, focus last
      focusable.last.focus
      focusable.last
    end

    # --- Hierarchy ---

    def children : Array(Widget)
      @children
    end

    def add_child(child : Widget) : Nil
      child.parent = self
      @children << child
      child.on_mount if @mounted
    end

    def remove_child(child : Widget) : Nil
      if @children.delete(child)
        child.on_unmount if child.mounted?
        child.parent = nil
      end
    end

    def clear_children : Nil
      @children.each do |child|
        child.on_unmount if child.mounted?
        child.parent = nil
      end
      @children.clear
    end

    # --- Lifecycle ---

    # Override to return child widgets
    def compose : Array(Widget)
      [] of Widget
    end

    # Called when widget is added to tree
    def on_mount : Nil
      @mounted = true
      composed = compose
      composed.each { |child| add_child(child) }
    end

    # Called when widget is removed from tree
    def on_unmount : Nil
      @mounted = false
      @children.each(&.on_unmount)
    end

    # --- Rendering ---

    # Returns the rect needed for rendering (may be larger than layout rect)
    # Override for widgets like dropdowns that render outside their bounds
    def render_rect : Rect
      @rect
    end

    # Override to render widget content
    def render(buffer : Buffer, clip : Rect) : Nil
      # Default: render children sorted by z_index (lower first, higher on top)
      @children.sort_by(&.z_index).each do |child|
        next unless child.visible?
        if child_clip = clip.intersect(child.rect)
          child.render(buffer, child_clip)
        end
      end
    end

    def dirty? : Bool
      @dirty
    end

    def mark_dirty! : Nil
      @dirty = true
      @parent.try(&.mark_dirty!)
    end

    def mark_clean! : Nil
      @dirty = false
    end

    def request_render : Nil
      mark_dirty!
    end

    # --- Events ---

    # Mouse capture - widget that captures gets all mouse events
    class_property mouse_capture : Widget? = nil

    # Capture all mouse events (for dragging)
    def capture_mouse : Nil
      Widget.mouse_capture = self
    end

    # Release mouse capture
    def release_mouse : Nil
      Widget.mouse_capture = nil if Widget.mouse_capture == self
    end

    # Handle an event, return true if handled
    def handle_event(event : Event) : Bool
      return false if event.stopped?

      # If a widget has captured mouse, send mouse events directly to it
      if event.is_a?(MouseEvent)
        if captured = Widget.mouse_capture
          return captured.handle_event(event) if captured != self
        end
      end

      # Try children first (in reverse z-order)
      @children.reverse_each do |child|
        next unless child.visible?

        # For mouse events, check if in bounds (unless it's the capturing widget)
        if event.is_a?(MouseEvent)
          next unless event.in_rect?(child.render_rect) || child == Widget.mouse_capture
        end

        if child.handle_event(event)
          return true
        end
      end

      # Then handle ourselves
      on_event(event)
    end

    # Override to handle events
    def on_event(event : Event) : Bool
      false
    end

    # Handle key event specifically
    def on_key(event : KeyEvent) : Bool
      false
    end

    # Handle mouse event specifically
    def on_mouse(event : MouseEvent) : Bool
      false
    end

    # --- CSS Classes ---

    def add_class(name : String) : Nil
      if @classes.add?(name)
        mark_dirty!
      end
    end

    def remove_class(name : String) : Nil
      if @classes.delete(name)
        mark_dirty!
      end
    end

    def has_class?(name : String) : Bool
      @classes.includes?(name)
    end

    def toggle_class(name : String) : Nil
      if has_class?(name)
        remove_class(name)
      else
        add_class(name)
      end
    end

    # --- Query ---

    # Find single widget by selector
    def query_one(selector : String) : Widget?
      query_all(selector).first?
    end

    # Find single widget by selector and type
    def query_one(selector : String, type : T.class) : T? forall T
      query_all(selector).find { |w| w.is_a?(T) }.as?(T)
    end

    # Find all widgets matching selector
    def query_all(selector : String) : Array(Widget)
      results = [] of Widget
      query_recursive(selector, results)
      results
    end

    private def query_recursive(selector : String, results : Array(Widget)) : Nil
      if matches_selector?(selector)
        results << self
      end
      @children.each { |child| child.query_recursive(selector, results) }
    end

    # Check if widget matches a simple selector
    def matches_selector?(selector : String) : Bool
      case selector[0]?
      when '#'
        # ID selector
        @id == selector[1..]
      when '.'
        # Class selector
        has_class?(selector[1..])
      else
        # Type selector (class name)
        self.class.name.split("::").last.downcase == selector.downcase
      end
    end

    # Find root widget (named root_widget to avoid conflict with WindowManager.root)
    def root_widget : Widget
      @parent.try(&.root_widget) || self
    end

    # Find app (if attached)
    def app : App?
      if self.is_a?(App)
        self.as(App)
      else
        @parent.try(&.app)
      end
    end

    # Apply CSS style properties to this widget
    # Override in subclasses to handle specific properties
    def apply_css_style(style : Hash(String, CSS::Value)) : Nil
      style.each do |property, value|
        case property
        when "visible"
          @visible = value == true || value == "true"
        when "z-index"
          @z_index = value.as?(Int32) || 0

        # Layout dimensions
        when "width"
          @constraints = Constraints.new(
            width: parse_dimension(value),
            height: @constraints.height,
            min_width: @constraints.min_width,
            max_width: @constraints.max_width,
            min_height: @constraints.min_height,
            max_height: @constraints.max_height
          )
        when "height"
          @constraints = Constraints.new(
            width: @constraints.width,
            height: parse_dimension(value),
            min_width: @constraints.min_width,
            max_width: @constraints.max_width,
            min_height: @constraints.min_height,
            max_height: @constraints.max_height
          )
        when "min-width"
          @constraints = Constraints.new(
            width: @constraints.width,
            height: @constraints.height,
            min_width: value.as?(Int32),
            max_width: @constraints.max_width,
            min_height: @constraints.min_height,
            max_height: @constraints.max_height
          )
        when "max-width"
          @constraints = Constraints.new(
            width: @constraints.width,
            height: @constraints.height,
            min_width: @constraints.min_width,
            max_width: value.as?(Int32),
            min_height: @constraints.min_height,
            max_height: @constraints.max_height
          )
        when "min-height"
          @constraints = Constraints.new(
            width: @constraints.width,
            height: @constraints.height,
            min_width: @constraints.min_width,
            max_width: @constraints.max_width,
            min_height: value.as?(Int32),
            max_height: @constraints.max_height
          )
        when "max-height"
          @constraints = Constraints.new(
            width: @constraints.width,
            height: @constraints.height,
            min_width: @constraints.min_width,
            max_width: @constraints.max_width,
            min_height: @constraints.min_height,
            max_height: value.as?(Int32)
          )

        # Box model - margins
        when "margin"
          @margin = parse_box_model(value.to_s)
        when "margin-top"
          @margin = BoxModel.new(value.as?(Int32) || 0, @margin.right, @margin.bottom, @margin.left)
        when "margin-right"
          @margin = BoxModel.new(@margin.top, value.as?(Int32) || 0, @margin.bottom, @margin.left)
        when "margin-bottom"
          @margin = BoxModel.new(@margin.top, @margin.right, value.as?(Int32) || 0, @margin.left)
        when "margin-left"
          @margin = BoxModel.new(@margin.top, @margin.right, @margin.bottom, value.as?(Int32) || 0)

        # Box model - padding
        when "padding"
          @padding = parse_box_model(value.to_s)
        when "padding-top"
          @padding = BoxModel.new(value.as?(Int32) || 0, @padding.right, @padding.bottom, @padding.left)
        when "padding-right"
          @padding = BoxModel.new(@padding.top, value.as?(Int32) || 0, @padding.bottom, @padding.left)
        when "padding-bottom"
          @padding = BoxModel.new(@padding.top, @padding.right, value.as?(Int32) || 0, @padding.left)
        when "padding-left"
          @padding = BoxModel.new(@padding.top, @padding.right, @padding.bottom, value.as?(Int32) || 0)
        end
      end
      mark_dirty!
    end

    # Parse dimension value from CSS (e.g., "50", "50%", "1fr", "auto")
    private def parse_dimension(value : CSS::Value) : Dimension
      str = value.to_s.strip
      case str
      when "auto"
        Dimension.auto
      when /^(\d+)fr$/
        Dimension.fr($1.to_i)
      when /^(\d+(?:\.\d+)?)%$/
        Dimension.percent($1.to_f)
      when /^(\d+)(?:px)?$/
        Dimension.px($1.to_i)
      else
        Dimension.auto
      end
    end

    # Parse box model value (margin/padding) - supports 1, 2, or 4 values
    private def parse_box_model(value : String) : BoxModel
      parts = value.strip.split(/\s+/).map(&.to_i?)
      case parts.size
      when 1
        v = parts[0] || 0
        BoxModel.all(v)
      when 2
        vert = parts[0] || 0
        horiz = parts[1] || 0
        BoxModel.symmetric(vert, horiz)
      when 4
        BoxModel.new(parts[0] || 0, parts[1] || 0, parts[2] || 0, parts[3] || 0)
      else
        BoxModel.zero
      end
    end
  end
end
