# Flexbox-like layout engine
module Tui
  module Layout
    enum Direction
      Horizontal  # Row - children laid out left to right
      Vertical    # Column - children laid out top to bottom
    end

    enum Align
      Start   # Align to start (left/top)
      Center  # Center in available space
      End     # Align to end (right/bottom)
      Stretch # Stretch to fill (default for cross-axis)
    end

    struct FlexItem
      property widget : Widget
      property constraints : Constraints

      def initialize(@widget : Widget, @constraints : Constraints = Constraints.default)
      end

      # Check if this item uses fr units in main dimension
      def flexible?(direction : Direction) : Bool
        case direction
        when .horizontal?
          @constraints.width.is_a?(Dimension::Fr)
        when .vertical?
          @constraints.height.is_a?(Dimension::Fr)
        else
          false
        end
      end

      # Get the fr value if flexible
      def flex_factor(direction : Direction) : Int32
        dim = direction.horizontal? ? @constraints.width : @constraints.height
        if dim.is_a?(Dimension::Fr)
          dim.as(Dimension::Fr).value
        else
          0
        end
      end
    end

    class Flex
      property direction : Direction
      property gap : Int32
      property align_items : Align      # Cross-axis alignment
      property justify_content : Align  # Main-axis alignment

      def initialize(
        @direction : Direction = Direction::Vertical,
        @gap : Int32 = 0,
        @align_items : Align = Align::Stretch,
        @justify_content : Align = Align::Start
      )
      end

      # Compute layout for children within parent rect
      def compute(parent : Rect, items : Array(FlexItem)) : Array(Rect)
        return [] of Rect if items.empty?

        case @direction
        when .horizontal?
          compute_horizontal(parent, items)
        when .vertical?
          compute_vertical(parent, items)
        else
          [] of Rect
        end
      end

      private def compute_horizontal(parent : Rect, items : Array(FlexItem)) : Array(Rect)
        results = Array(Rect).new(items.size)

        # Calculate total gaps
        total_gap = @gap * (items.size - 1)
        available_width = parent.width - total_gap

        # First pass: calculate fixed sizes and sum up fr units
        fixed_width = 0
        total_fr = 0

        items.each do |item|
          if item.flexible?(@direction)
            total_fr += item.flex_factor(@direction)
          else
            width = item.constraints.width.resolve(available_width)
            width = item.constraints.constrain_width(width)
            fixed_width += width
          end
        end

        # Remaining space for fr units
        remaining = Math.max(0, available_width - fixed_width)

        # Second pass: compute actual rectangles
        current_x = parent.x

        items.each do |item|
          # Calculate width
          width = if item.flexible?(@direction)
                    fr_value = item.flex_factor(@direction)
                    (remaining * fr_value / total_fr).to_i32
                  else
                    item.constraints.width.resolve(available_width)
                  end
          width = item.constraints.constrain_width(width)

          # Calculate height based on cross-axis alignment
          height = case @align_items
                   when .stretch?
                     parent.height
                   else
                     item.constraints.height.resolve(parent.height)
                   end
          height = item.constraints.constrain_height(height)

          # Calculate y based on cross-axis alignment
          y = case @align_items
              when .start?, .stretch?
                parent.y
              when .center?
                parent.y + (parent.height - height) // 2
              when .end?
                parent.y + parent.height - height
              else
                parent.y
              end

          results << Rect.new(current_x, y, width, height)
          current_x += width + @gap
        end

        results
      end

      private def compute_vertical(parent : Rect, items : Array(FlexItem)) : Array(Rect)
        results = Array(Rect).new(items.size)

        # Calculate total gaps
        total_gap = @gap * (items.size - 1)
        available_height = parent.height - total_gap

        # First pass: calculate fixed sizes and sum up fr units
        fixed_height = 0
        total_fr = 0

        items.each do |item|
          if item.flexible?(@direction)
            total_fr += item.flex_factor(@direction)
          else
            height = item.constraints.height.resolve(available_height)
            height = item.constraints.constrain_height(height)
            fixed_height += height
          end
        end

        # Remaining space for fr units
        remaining = Math.max(0, available_height - fixed_height)

        # Second pass: compute actual rectangles
        current_y = parent.y

        items.each do |item|
          # Calculate height
          height = if item.flexible?(@direction)
                     fr_value = item.flex_factor(@direction)
                     if total_fr > 0
                       (remaining * fr_value / total_fr).to_i32
                     else
                       0
                     end
                   else
                     item.constraints.height.resolve(available_height)
                   end
          height = item.constraints.constrain_height(height)

          # Calculate width based on cross-axis alignment
          width = case @align_items
                  when .stretch?
                    parent.width
                  else
                    item.constraints.width.resolve(parent.width)
                  end
          width = item.constraints.constrain_width(width)

          # Calculate x based on cross-axis alignment
          x = case @align_items
              when .start?, .stretch?
                parent.x
              when .center?
                parent.x + (parent.width - width) // 2
              when .end?
                parent.x + parent.width - width
              else
                parent.x
              end

          results << Rect.new(x, current_y, width, height)
          current_y += height + @gap
        end

        results
      end
    end
  end
end
