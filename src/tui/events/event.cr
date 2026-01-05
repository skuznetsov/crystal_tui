# Base event class
module Tui
  abstract class Event
    property? stopped : Bool = false

    # Stop event propagation
    def stop! : Nil
      @stopped = true
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
