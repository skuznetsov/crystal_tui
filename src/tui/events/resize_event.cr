# Terminal resize event
module Tui
  class ResizeEvent < Event
    getter width : Int32
    getter height : Int32

    def initialize(@width : Int32, @height : Int32)
    end

    def size : {Int32, Int32}
      {@width, @height}
    end
  end
end
