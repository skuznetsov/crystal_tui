# Slider - Range input widget
module Tui
  class Slider < Widget
    property value : Float64 = 0.0
    property min : Float64 = 0.0
    property max : Float64 = 100.0
    property step : Float64 = 1.0

    # Styling
    property track_char : Char = '─'
    property thumb_char : Char = '●'
    property filled_char : Char = '━'
    property track_style : Style = Style.new(fg: Color.palette(240))
    property filled_style : Style = Style.new(fg: Color.cyan)
    property thumb_style : Style = Style.new(fg: Color.white)
    property show_value : Bool = true
    property value_width : Int32 = 6

    @dragging : Bool = false
    @on_change : Proc(Float64, Nil)?

    def initialize(
      id : String? = nil,
      @min : Float64 = 0.0,
      @max : Float64 = 100.0,
      @value : Float64 = 0.0,
      @step : Float64 = 1.0
    )
      super(id)
      @focusable = true
      @value = @value.clamp(@min, @max)
    end

    # Callback when value changes
    def on_change(&block : Float64 -> Nil) : Nil
      @on_change = block
    end

    # Set value with bounds checking
    def value=(val : Float64) : Nil
      new_value = val.clamp(@min, @max)
      if new_value != @value
        @value = new_value
        @on_change.try &.call(@value)
        mark_dirty!
      end
    end

    # Increment/decrement
    def increment : Nil
      self.value = @value + @step
    end

    def decrement : Nil
      self.value = @value - @step
    end

    def increment_large : Nil
      self.value = @value + @step * 10
    end

    def decrement_large : Nil
      self.value = @value - @step * 10
    end

    # Get percentage (0.0 - 1.0)
    def percentage : Float64
      return 0.0 if @max <= @min
      (@value - @min) / (@max - @min)
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Calculate track width (leave space for value display)
      track_width = @show_value ? @rect.width - @value_width - 1 : @rect.width
      track_width = Math.max(3, track_width)

      y = @rect.y
      track_x = @rect.x

      # Calculate thumb position
      thumb_pos = (percentage * (track_width - 1)).round.to_i
      thumb_pos = thumb_pos.clamp(0, track_width - 1)

      # Draw track
      track_width.times do |i|
        x = track_x + i
        next unless clip.contains?(x, y)

        if i == thumb_pos
          # Thumb
          style = focused? ? Style.new(fg: Color.yellow, attrs: Attributes::Bold) : @thumb_style
          buffer.set(x, y, @thumb_char, style)
        elsif i < thumb_pos
          # Filled portion
          buffer.set(x, y, @filled_char, @filled_style)
        else
          # Empty portion
          buffer.set(x, y, @track_char, @track_style)
        end
      end

      # Draw value
      if @show_value
        value_x = track_x + track_width + 1
        value_str = format_value(@value)
        value_style = focused? ? Style.new(fg: Color.white) : Style.new(fg: Color.palette(250))

        value_str.each_char_with_index do |char, i|
          x = value_x + i
          break if x >= @rect.x + @rect.width
          buffer.set(x, y, char, value_style) if clip.contains?(x, y)
        end
      end
    end

    private def format_value(val : Float64) : String
      if val == val.to_i
        val.to_i.to_s.rjust(@value_width - 1)
      else
        ("%.1f" % val).rjust(@value_width - 1)
      end
    end

    def on_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when KeyEvent
        return false unless focused?

        case
        when event.matches?("left"), event.matches?("h")
          decrement
          event.stop!
          return true
        when event.matches?("right"), event.matches?("l")
          increment
          event.stop!
          return true
        when event.matches?("home")
          self.value = @min
          event.stop!
          return true
        when event.matches?("end")
          self.value = @max
          event.stop!
          return true
        when event.matches?("pageup"), event.matches?("shift+left")
          decrement_large
          event.stop!
          return true
        when event.matches?("pagedown"), event.matches?("shift+right")
          increment_large
          event.stop!
          return true
        end

      when MouseEvent
        if event.in_rect?(@rect)
          case event.action
          when .press?
            if event.button.left?
              @dragging = true
              update_value_from_mouse(event.x)
              focus
              event.stop!
              return true
            elsif event.button.wheel_up?
              increment
              event.stop!
              return true
            elsif event.button.wheel_down?
              decrement
              event.stop!
              return true
            end
          when .drag?
            if @dragging
              update_value_from_mouse(event.x)
              event.stop!
              return true
            end
          when .release?
            if @dragging
              @dragging = false
              event.stop!
              return true
            end
          end
        elsif event.action.release?
          @dragging = false
        end
      end

      super
    end

    private def update_value_from_mouse(mouse_x : Int32) : Nil
      track_width = @show_value ? @rect.width - @value_width - 1 : @rect.width
      track_width = Math.max(3, track_width)

      relative_x = mouse_x - @rect.x
      relative_x = relative_x.clamp(0, track_width - 1)

      new_percentage = relative_x.to_f / (track_width - 1)
      new_value = @min + new_percentage * (@max - @min)

      # Snap to step
      if @step > 0
        new_value = (new_value / @step).round * @step
      end

      self.value = new_value
    end

    def min_size : {Int32, Int32}
      width = @show_value ? 10 + @value_width : 10
      {width, 1}
    end
  end
end
