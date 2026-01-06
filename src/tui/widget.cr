# Base widget class
module Tui
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

    # State
    property? visible : Bool = true
    property? mounted : Bool = false
    property? focusable : Bool = false  # Can receive focus
    @focused : Bool = false

    # Z-order (higher = on top)
    property z_index : Int32 = 0

    # Global focus tracking
    class_property focused_widget : Widget? = nil

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
  end
end
