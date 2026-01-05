# Dimension types for flexible sizing
module Tui
  # Represents a size dimension (width or height)
  abstract struct Dimension
    abstract def resolve(available : Int32, total_fr : Int32 = 1) : Int32

    # Auto - size to content
    struct Auto < Dimension
      def resolve(available : Int32, total_fr : Int32 = 1) : Int32
        available  # Will be constrained by content
      end

      def to_s(io : IO)
        io << "auto"
      end
    end

    # Fixed pixel size
    struct Px < Dimension
      getter value : Int32

      def initialize(@value : Int32)
      end

      def resolve(available : Int32, total_fr : Int32 = 1) : Int32
        @value
      end

      def to_s(io : IO)
        io << @value << "px"
      end
    end

    # Percentage of available space
    struct Percent < Dimension
      getter value : Float64

      def initialize(@value : Float64)
      end

      def resolve(available : Int32, total_fr : Int32 = 1) : Int32
        (available * @value / 100.0).to_i32
      end

      def to_s(io : IO)
        io << @value << "%"
      end
    end

    # Fraction unit (like CSS fr)
    struct Fr < Dimension
      getter value : Int32

      def initialize(@value : Int32 = 1)
      end

      def resolve(available : Int32, total_fr : Int32 = 1) : Int32
        return 0 if total_fr == 0
        (available * @value / total_fr).to_i32
      end

      def to_s(io : IO)
        io << @value << "fr"
      end
    end

    # Helper constructors
    def self.auto : Auto
      Auto.new
    end

    def self.px(value : Int32) : Px
      Px.new(value)
    end

    def self.percent(value : Float64) : Percent
      Percent.new(value)
    end

    def self.fr(value : Int32 = 1) : Fr
      Fr.new(value)
    end
  end

  # Size constraints
  struct Constraints
    property min_width : Int32?
    property max_width : Int32?
    property min_height : Int32?
    property max_height : Int32?
    property width : Dimension
    property height : Dimension

    def initialize(
      @width : Dimension = Dimension.auto,
      @height : Dimension = Dimension.auto,
      @min_width : Int32? = nil,
      @max_width : Int32? = nil,
      @min_height : Int32? = nil,
      @max_height : Int32? = nil
    )
    end

    def self.default : Constraints
      new
    end

    # Apply constraints to a value
    def constrain_width(value : Int32) : Int32
      result = value
      result = Math.max(result, @min_width.not_nil!) if @min_width
      result = Math.min(result, @max_width.not_nil!) if @max_width
      result
    end

    def constrain_height(value : Int32) : Int32
      result = value
      result = Math.max(result, @min_height.not_nil!) if @min_height
      result = Math.min(result, @max_height.not_nil!) if @max_height
      result
    end
  end
end
