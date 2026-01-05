# Horizontal box container - stacks children horizontally
module Tui
  class HBox < Widget
    def initialize(id : String? = nil, &block : -> Array(Widget))
      super(id)
      @compose_block = block
    end

    def initialize(id : String? = nil)
      super(id)
      @compose_block = nil
    end

    @compose_block : (-> Array(Widget))?

    def compose : Array(Widget)
      @compose_block.try(&.call) || [] of Widget
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?

      # Layout children horizontally
      layout_children

      # Render children
      @children.each do |child|
        next unless child.visible?
        if child_clip = clip.intersect(child.rect)
          child.render(buffer, child_clip)
        end
      end
    end

    private def layout_children : Nil
      return if @children.empty?

      # Simple equal distribution for now
      # TODO: Support flex sizing
      available_width = @rect.width
      child_count = @children.count(&.visible?)
      return if child_count == 0

      width_per_child = available_width // child_count
      current_x = @rect.x

      @children.each do |child|
        next unless child.visible?

        child.rect = Rect.new(
          current_x,
          @rect.y,
          width_per_child,
          @rect.height
        )
        current_x += width_per_child
      end
    end
  end
end
