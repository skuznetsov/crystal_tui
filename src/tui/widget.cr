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
    property? focused : Bool = false
    property? visible : Bool = true
    property? mounted : Bool = false
    property? focusable : Bool = false  # Can receive focus

    # Dirty flag for re-rendering
    @dirty : Bool = true

    def initialize(@id : String? = nil)
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

    # Override to render widget content
    def render(buffer : Buffer, clip : Rect) : Nil
      # Default: render children
      @children.each do |child|
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

    # Handle an event, return true if handled
    def handle_event(event : Event) : Bool
      return false if event.stopped?

      # Try children first (in reverse z-order)
      @children.reverse_each do |child|
        next unless child.visible?

        # For mouse events, check if in bounds
        if event.is_a?(MouseEvent)
          next unless event.in_rect?(child.rect)
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

    # --- Focus ---

    def focus : Nil
      return unless @focusable
      @focused = true
      mark_dirty!
    end

    # Alias for focus (bang version)
    def focus! : Nil
      focus
    end

    def blur : Nil
      @focused = false
      mark_dirty!
    end

    # Find root widget
    def root : Widget
      @parent.try(&.root) || self
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
