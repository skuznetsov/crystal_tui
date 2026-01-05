# Rectangle for widget positioning and clipping
module Tui
  struct Rect
    property x : Int32
    property y : Int32
    property width : Int32
    property height : Int32

    def initialize(@x : Int32 = 0, @y : Int32 = 0, @width : Int32 = 0, @height : Int32 = 0)
    end

    def self.zero : Rect
      new(0, 0, 0, 0)
    end

    # Right edge (exclusive)
    def right : Int32
      @x + @width
    end

    # Bottom edge (exclusive)
    def bottom : Int32
      @y + @height
    end

    # Check if point is inside rectangle
    def contains?(px : Int32, py : Int32) : Bool
      px >= @x && px < right && py >= @y && py < bottom
    end

    # Check if rectangle is empty
    def empty? : Bool
      @width <= 0 || @height <= 0
    end

    # Intersect with another rectangle
    def intersect(other : Rect) : Rect?
      new_x = Math.max(@x, other.x)
      new_y = Math.max(@y, other.y)
      new_right = Math.min(right, other.right)
      new_bottom = Math.min(bottom, other.bottom)

      if new_right > new_x && new_bottom > new_y
        Rect.new(new_x, new_y, new_right - new_x, new_bottom - new_y)
      else
        nil
      end
    end

    # Union with another rectangle
    def union(other : Rect) : Rect
      new_x = Math.min(@x, other.x)
      new_y = Math.min(@y, other.y)
      new_right = Math.max(right, other.right)
      new_bottom = Math.max(bottom, other.bottom)
      Rect.new(new_x, new_y, new_right - new_x, new_bottom - new_y)
    end

    # Create offset copy
    def offset(dx : Int32, dy : Int32) : Rect
      Rect.new(@x + dx, @y + dy, @width, @height)
    end

    # Create inset copy (shrink by amount)
    def inset(amount : Int32) : Rect
      inset(amount, amount, amount, amount)
    end

    def inset(top : Int32, right : Int32, bottom : Int32, left : Int32) : Rect
      Rect.new(
        @x + left,
        @y + top,
        Math.max(0, @width - left - right),
        Math.max(0, @height - top - bottom)
      )
    end

    # Create expanded copy
    def expand(amount : Int32) : Rect
      inset(-amount)
    end

    # Iterate over all cells in rectangle
    def each_cell(&block : Int32, Int32 -> Nil) : Nil
      @height.times do |dy|
        @width.times do |dx|
          block.call(@x + dx, @y + dy)
        end
      end
    end

    # Check equality
    def ==(other : Rect) : Bool
      @x == other.x && @y == other.y && @width == other.width && @height == other.height
    end

    def to_s(io : IO) : Nil
      io << "Rect(#{@x}, #{@y}, #{@width}x#{@height})"
    end
  end
end
