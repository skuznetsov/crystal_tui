# Vertical box container - stacks children vertically
module Tui
  class VBox < Widget
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

      # Layout children vertically
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
      available_height = @rect.height
      child_count = @children.count(&.visible?)
      return if child_count == 0

      height_per_child = available_height // child_count
      current_y = @rect.y

      @children.each do |child|
        next unless child.visible?

        child.rect = Rect.new(
          @rect.x,
          current_y,
          @rect.width,
          height_per_child
        )
        current_y += height_per_child
      end
    end
  end
end
