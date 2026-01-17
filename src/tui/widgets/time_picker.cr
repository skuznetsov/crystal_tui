# TimePicker - Time selection widget
module Tui
  class TimePicker < Widget
    property hour : Int32 = 0
    property minute : Int32 = 0
    property second : Int32 = 0
    property show_seconds : Bool = true
    property use_24h : Bool = true

    # Styling
    property style : Style = Style.default
    property selected_style : Style = Style.new(fg: Color.black, bg: Color.cyan)
    property separator_style : Style = Style.new(fg: Color.palette(240))

    enum Field
      Hour
      Minute
      Second
    end

    @active_field : Field = Field::Hour
    @on_change : Proc(Int32, Int32, Int32, Nil)?

    def initialize(id : String? = nil, hour : Int32 = 0, minute : Int32 = 0, second : Int32 = 0)
      super(id)
      @focusable = true
      @hour = hour.clamp(0, 23)
      @minute = minute.clamp(0, 59)
      @second = second.clamp(0, 59)
    end

    # Callback when time changes
    def on_change(&block : Int32, Int32, Int32 -> Nil) : Nil
      @on_change = block
    end

    # Set time from Time object
    def time=(t : Time) : Nil
      @hour = t.hour
      @minute = t.minute
      @second = t.second
      @on_change.try &.call(@hour, @minute, @second)
      mark_dirty!
    end

    # Get as Time (today with this time)
    def time : Time
      today = Time.local
      Time.local(today.year, today.month, today.day, @hour, @minute, @second)
    end

    # Set to current time
    def now : Nil
      self.time = Time.local
    end

    # Format time as string
    def to_s : String
      if @use_24h
        if @show_seconds
          "%02d:%02d:%02d" % [@hour, @minute, @second]
        else
          "%02d:%02d" % [@hour, @minute]
        end
      else
        h = @hour % 12
        h = 12 if h == 0
        ampm = @hour < 12 ? "AM" : "PM"
        if @show_seconds
          "%02d:%02d:%02d %s" % [h, @minute, @second, ampm]
        else
          "%02d:%02d %s" % [h, @minute, ampm]
        end
      end
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      y = @rect.y
      x = @rect.x

      # Hours
      hour_str = if @use_24h
                   "%02d" % @hour
                 else
                   h = @hour % 12
                   h = 12 if h == 0
                   "%02d" % h
                 end
      hour_style = (@active_field == Field::Hour && focused?) ? @selected_style : @style
      render_text(buffer, clip, x, y, hour_str, hour_style)
      x += 2

      # Separator
      buffer.set(x, y, ':', @separator_style) if clip.contains?(x, y)
      x += 1

      # Minutes
      minute_str = "%02d" % @minute
      minute_style = (@active_field == Field::Minute && focused?) ? @selected_style : @style
      render_text(buffer, clip, x, y, minute_str, minute_style)
      x += 2

      if @show_seconds
        # Separator
        buffer.set(x, y, ':', @separator_style) if clip.contains?(x, y)
        x += 1

        # Seconds
        second_str = "%02d" % @second
        second_style = (@active_field == Field::Second && focused?) ? @selected_style : @style
        render_text(buffer, clip, x, y, second_str, second_style)
        x += 2
      end

      # AM/PM indicator for 12h mode
      unless @use_24h
        buffer.set(x, y, ' ', @style) if clip.contains?(x, y)
        x += 1
        ampm = @hour < 12 ? "AM" : "PM"
        render_text(buffer, clip, x, y, ampm, @style)
      end
    end

    private def render_text(buffer : Buffer, clip : Rect, x : Int32, y : Int32, text : String, style : Style) : Nil
      text.each_char_with_index do |char, i|
        px = x + i
        buffer.set(px, y, char, style) if clip.contains?(px, y)
      end
    end

    def handle_event(event : Event) : Bool
      return false unless focused?
      return false if event.stopped?

      case event
      when KeyEvent
        case
        when event.matches?("left"), event.matches?("h")
          prev_field
          event.stop!
          return true
        when event.matches?("right"), event.matches?("l")
          next_field
          event.stop!
          return true
        when event.matches?("up"), event.matches?("k")
          increment_field
          event.stop!
          return true
        when event.matches?("down"), event.matches?("j")
          decrement_field
          event.stop!
          return true
        when event.matches?("tab")
          next_field
          event.stop!
          return true
        when event.matches?("shift+tab")
          prev_field
          event.stop!
          return true
        when event.matches?("n")
          now
          event.stop!
          return true
        when event.matches?("a")
          # Toggle AM/PM in 12h mode
          unless @use_24h
            @hour = (@hour + 12) % 24
            @on_change.try &.call(@hour, @minute, @second)
            mark_dirty!
          end
          event.stop!
          return true
        else
          # Direct digit input
          if char = event.char
            if char.ascii_number?
              input_digit(char.to_i)
              event.stop!
              return true
            end
          end
        end

      when MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          # Determine which field was clicked
          relative_x = event.x - @rect.x
          if relative_x < 2
            @active_field = Field::Hour
          elsif relative_x < 5
            @active_field = Field::Minute
          elsif @show_seconds && relative_x < 8
            @active_field = Field::Second
          end
          focus
          mark_dirty!
          event.stop!
          return true
        elsif event.action.press? && event.in_rect?(@rect)
          if event.button.wheel_up?
            increment_field
            event.stop!
            return true
          elsif event.button.wheel_down?
            decrement_field
            event.stop!
            return true
          end
        end
      end

      super
    end

    private def next_field : Nil
      @active_field = case @active_field
                      when .hour?   then Field::Minute
                      when .minute? then @show_seconds ? Field::Second : Field::Hour
                      when .second? then Field::Hour
                      else               Field::Hour
                      end
      mark_dirty!
    end

    private def prev_field : Nil
      @active_field = case @active_field
                      when .hour?   then @show_seconds ? Field::Second : Field::Minute
                      when .minute? then Field::Hour
                      when .second? then Field::Minute
                      else               Field::Hour
                      end
      mark_dirty!
    end

    private def increment_field : Nil
      case @active_field
      when .hour?
        @hour = (@hour + 1) % 24
      when .minute?
        @minute = (@minute + 1) % 60
      when .second?
        @second = (@second + 1) % 60
      end
      @on_change.try &.call(@hour, @minute, @second)
      mark_dirty!
    end

    private def decrement_field : Nil
      case @active_field
      when .hour?
        @hour = (@hour - 1 + 24) % 24
      when .minute?
        @minute = (@minute - 1 + 60) % 60
      when .second?
        @second = (@second - 1 + 60) % 60
      end
      @on_change.try &.call(@hour, @minute, @second)
      mark_dirty!
    end

    @input_buffer : String = ""
    @input_timer : Time::Instant?

    private def input_digit(digit : Int32) : Nil
      now = Time.instant

      # Reset buffer if too much time passed (500ms)
      if (last = @input_timer) && (now - last) > 500.milliseconds
        @input_buffer = ""
      end
      @input_timer = now

      @input_buffer += digit.to_s

      # Try to parse and apply
      if value = @input_buffer.to_i?
        case @active_field
        when .hour?
          if value <= 23
            @hour = value
            if @input_buffer.size >= 2 || value > 2
              @input_buffer = ""
              next_field
            end
          else
            @input_buffer = digit.to_s
            @hour = digit
          end
        when .minute?
          if value <= 59
            @minute = value
            if @input_buffer.size >= 2 || value > 5
              @input_buffer = ""
              next_field
            end
          else
            @input_buffer = digit.to_s
            @minute = digit
          end
        when .second?
          if value <= 59
            @second = value
            if @input_buffer.size >= 2 || value > 5
              @input_buffer = ""
              next_field
            end
          else
            @input_buffer = digit.to_s
            @second = digit
          end
        end
      end

      @on_change.try &.call(@hour, @minute, @second)
      mark_dirty!
    end

    def min_size : {Int32, Int32}
      width = @show_seconds ? 8 : 5  # HH:MM:SS or HH:MM
      width += 3 unless @use_24h     # " AM" or " PM"
      {width, 1}
    end
  end
end
