# Base event class with DOM-like propagation model
#
# Events flow through the widget tree in three phases:
#   1. CAPTURE - Event travels from root DOWN to target (allows interception)
#   2. TARGET  - Event is at the target widget
#   3. BUBBLE  - Event travels from target UP to root (allows reaction)
#
# Example flow for click on deeply nested button:
#   CAPTURE: App → Panel → Container → Button
#   TARGET:  Button handles the event
#   BUBBLE:  Button → Container → Panel → App
#
# Widgets can:
#   - stop_propagation! - Stop event from continuing to next phase/widget
#   - stop_immediate!   - Stop event immediately (no more handlers even on same widget)
#   - prevent_default!  - Prevent default action (widget-specific)
#
module Tui
  # Forward declaration for Widget (defined in widget.cr)
  abstract class Widget; end

  abstract class Event
    # Event propagation phase
    enum Phase
      None     # Not yet dispatched
      Capture  # Traveling down from root to target
      Target   # At the target widget
      Bubble   # Traveling up from target to root
    end

    property phase : Phase = Phase::None
    property? propagation_stopped : Bool = false
    property? immediate_stopped : Bool = false
    property? default_prevented : Bool = false

    # Target widget (set during dispatch)
    property target : Widget? = nil

    # Current widget receiving the event (changes during propagation)
    property current_target : Widget? = nil

    # Stop propagation to next widget (but current widget's other handlers still run)
    def stop_propagation! : Nil
      @propagation_stopped = true
    end

    # Stop immediately (no more handlers at all)
    def stop_immediate! : Nil
      @propagation_stopped = true
      @immediate_stopped = true
    end

    # Prevent default action
    def prevent_default! : Nil
      @default_prevented = true
    end

    # Legacy compatibility - maps to stop_propagation!
    def stop! : Nil
      stop_propagation!
    end

    # Legacy compatibility - maps to propagation_stopped?
    def stopped? : Bool
      @propagation_stopped
    end

    # Check if event is in capture phase
    def capturing? : Bool
      @phase == Phase::Capture
    end

    # Check if event is in bubble phase
    def bubbling? : Bool
      @phase == Phase::Bubble
    end

    # Check if event is at target
    def at_target? : Bool
      @phase == Phase::Target
    end

    # Reset event state for reuse (e.g., in event pools)
    def reset! : Nil
      @phase = Phase::None
      @propagation_stopped = false
      @immediate_stopped = false
      @default_prevented = false
      @target = nil
      @current_target = nil
    end
  end

  # Key codes for special keys
  enum Key
    # Letters and numbers handled via char
    Unknown

    # Arrow keys
    Up
    Down
    Left
    Right

    # Navigation
    Home
    End
    PageUp
    PageDown
    Insert
    Delete

    # Control keys
    Enter
    Tab
    Backspace
    Escape
    Space

    # Function keys
    F1
    F2
    F3
    F4
    F5
    F6
    F7
    F8
    F9
    F10
    F11
    F12
  end

  # Mouse buttons
  enum MouseButton
    Left
    Middle
    Right
    WheelUp
    WheelDown
  end

  # Mouse actions
  enum MouseAction
    Press
    Release
    Drag
    Move
  end

  # Modifier keys
  @[Flags]
  enum Modifiers
    Shift
    Alt
    Ctrl
    Meta  # Windows/Cmd key
  end
end
