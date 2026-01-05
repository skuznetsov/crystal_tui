# Mouse event
module Tui
  class MouseEvent < Event
    getter x : Int32
    getter y : Int32
    getter button : MouseButton
    getter action : MouseAction
    getter modifiers : Modifiers

    def initialize(
      @x : Int32,
      @y : Int32,
      @button : MouseButton = MouseButton::Left,
      @action : MouseAction = MouseAction::Press,
      @modifiers : Modifiers = Modifiers::None
    )
    end

    # Check action types
    def press? : Bool
      @action == MouseAction::Press
    end

    def release? : Bool
      @action == MouseAction::Release
    end

    def drag? : Bool
      @action == MouseAction::Drag
    end

    def move? : Bool
      @action == MouseAction::Move
    end

    def click? : Bool
      press?
    end

    # Check buttons
    def left? : Bool
      @button == MouseButton::Left
    end

    def right? : Bool
      @button == MouseButton::Right
    end

    def middle? : Bool
      @button == MouseButton::Middle
    end

    def wheel_up? : Bool
      @button == MouseButton::WheelUp
    end

    def wheel_down? : Bool
      @button == MouseButton::WheelDown
    end

    def wheel? : Bool
      wheel_up? || wheel_down?
    end

    # Check modifiers
    def shift? : Bool
      @modifiers.shift?
    end

    def alt? : Bool
      @modifiers.alt?
    end

    def ctrl? : Bool
      @modifiers.ctrl?
    end

    # Check if position is within bounds
    def in_rect?(rx : Int32, ry : Int32, rw : Int32, rh : Int32) : Bool
      @x >= rx && @x < rx + rw && @y >= ry && @y < ry + rh
    end

    def in_rect?(rect : Rect) : Bool
      in_rect?(rect.x, rect.y, rect.width, rect.height)
    end

    # Get position relative to a rectangle
    def relative_to(rx : Int32, ry : Int32) : {Int32, Int32}
      {@x - rx, @y - ry}
    end

    def relative_to(rect : Rect) : {Int32, Int32}
      relative_to(rect.x, rect.y)
    end
  end
end
