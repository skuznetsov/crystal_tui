# Calendar - Date picker widget
module Tui
  class Calendar < Widget
    property selected_date : Time
    property show_week_numbers : Bool = false

    # Styling
    property header_style : Style = Style.new(fg: Color.cyan, attrs: Attributes::Bold)
    property weekday_style : Style = Style.new(fg: Color.yellow)
    property day_style : Style = Style.default
    property today_style : Style = Style.new(fg: Color.green, attrs: Attributes::Bold)
    property selected_style : Style = Style.new(fg: Color.black, bg: Color.cyan)
    property other_month_style : Style = Style.new(fg: Color.palette(240))

    @view_date : Time  # Currently displayed month
    @on_select : Proc(Time, Nil)?

    WEEKDAYS       = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    WEEKDAYS_SHORT = ["M", "T", "W", "T", "F", "S", "S"]

    def initialize(id : String? = nil, date : Time? = nil)
      super(id)
      @focusable = true
      @selected_date = date || Time.local
      @view_date = @selected_date
    end

    # Callback when date is selected
    def on_select(&block : Time -> Nil) : Nil
      @on_select = block
    end

    # Navigate months
    def next_month : Nil
      @view_date = @view_date + 1.month
      mark_dirty!
    end

    def prev_month : Nil
      @view_date = @view_date - 1.month
      mark_dirty!
    end

    def next_year : Nil
      @view_date = @view_date + 1.year
      mark_dirty!
    end

    def prev_year : Nil
      @view_date = @view_date - 1.year
      mark_dirty!
    end

    # Go to today
    def today : Nil
      @view_date = Time.local
      @selected_date = @view_date
      @on_select.try &.call(@selected_date)
      mark_dirty!
    end

    # Select date
    def select_date(date : Time) : Nil
      @selected_date = date
      @view_date = date
      @on_select.try &.call(@selected_date)
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      y = @rect.y

      # Header: < Month Year >
      render_header(buffer, clip, y)
      y += 1

      return if y >= @rect.y + @rect.height

      # Weekday names
      render_weekdays(buffer, clip, y)
      y += 1

      return if y >= @rect.y + @rect.height

      # Days grid
      render_days(buffer, clip, y)
    end

    private def render_header(buffer : Buffer, clip : Rect, y : Int32) : Nil
      return unless y >= clip.y && y < clip.y + clip.height

      month_year = @view_date.to_s("%B %Y")
      header = "< #{month_year} >"

      # Center the header
      x = @rect.x + (@rect.width - header.size) // 2
      x = @rect.x if x < @rect.x

      header.each_char_with_index do |char, i|
        px = x + i
        break if px >= @rect.x + @rect.width
        buffer.set(px, y, char, @header_style) if clip.contains?(px, y)
      end
    end

    private def render_weekdays(buffer : Buffer, clip : Rect, y : Int32) : Nil
      return unless y >= clip.y && y < clip.y + clip.height

      x = @rect.x
      cell_width = (@rect.width // 7).clamp(2, 4)

      WEEKDAYS.each_with_index do |day, i|
        label = cell_width >= 3 ? day : day[0].to_s
        px = x + i * cell_width + (cell_width - label.size) // 2

        label.each_char_with_index do |char, j|
          buffer.set(px + j, y, char, @weekday_style) if clip.contains?(px + j, y)
        end
      end
    end

    private def render_days(buffer : Buffer, clip : Rect, start_y : Int32) : Nil
      cell_width = (@rect.width // 7).clamp(2, 4)
      today = Time.local

      # First day of month
      first_of_month = Time.local(@view_date.year, @view_date.month, 1)

      # Day of week for first day (0 = Monday in our grid)
      first_weekday = (first_of_month.day_of_week.to_i - 1) % 7

      # Days in month
      days_in_month = Time.days_in_month(@view_date.year, @view_date.month)

      # Start from previous month to fill grid
      current_day = first_of_month - first_weekday.days

      6.times do |week|
        y = start_y + week
        break if y >= @rect.y + @rect.height
        next unless y >= clip.y && y < clip.y + clip.height

        7.times do |day_of_week|
          x = @rect.x + day_of_week * cell_width

          # Determine style
          style = if same_day?(current_day, @selected_date) && focused?
                    @selected_style
                  elsif same_day?(current_day, today)
                    @today_style
                  elsif current_day.month != @view_date.month
                    @other_month_style
                  else
                    @day_style
                  end

          # Render day number
          day_str = current_day.day.to_s.rjust(cell_width - 1)
          day_str.each_char_with_index do |char, i|
            px = x + i
            buffer.set(px, y, char, style) if clip.contains?(px, y)
          end

          current_day += 1.day
        end
      end
    end

    private def same_day?(a : Time, b : Time) : Bool
      a.year == b.year && a.month == b.month && a.day == b.day
    end

    def on_event(event : Event) : Bool
      return false unless focused?
      return false if event.stopped?

      case event
      when KeyEvent
        case
        when event.matches?("left"), event.matches?("h")
          @selected_date -= 1.day
          ensure_visible
          @on_select.try &.call(@selected_date)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("right"), event.matches?("l")
          @selected_date += 1.day
          ensure_visible
          @on_select.try &.call(@selected_date)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("up"), event.matches?("k")
          @selected_date -= 7.days
          ensure_visible
          @on_select.try &.call(@selected_date)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("down"), event.matches?("j")
          @selected_date += 7.days
          ensure_visible
          @on_select.try &.call(@selected_date)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("pageup")
          prev_month
          event.stop!
          return true
        when event.matches?("pagedown")
          next_month
          event.stop!
          return true
        when event.matches?("home")
          # Go to first of month
          @selected_date = Time.local(@view_date.year, @view_date.month, 1)
          @on_select.try &.call(@selected_date)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("end")
          # Go to last of month
          days = Time.days_in_month(@view_date.year, @view_date.month)
          @selected_date = Time.local(@view_date.year, @view_date.month, days)
          @on_select.try &.call(@selected_date)
          mark_dirty!
          event.stop!
          return true
        when event.matches?("t")
          today
          event.stop!
          return true
        when event.matches?("enter"), event.matches?("space")
          @on_select.try &.call(@selected_date)
          event.stop!
          return true
        end
      when MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          # Try to calculate clicked date
          if clicked_date = date_at_position(event.x, event.y)
            select_date(clicked_date)
            focus
            event.stop!
            return true
          end
        end
      end

      super
    end

    private def ensure_visible : Nil
      # If selected date is not in view month, update view
      if @selected_date.month != @view_date.month || @selected_date.year != @view_date.year
        @view_date = @selected_date
      end
    end

    private def date_at_position(mouse_x : Int32, mouse_y : Int32) : Time?
      # Account for header and weekday rows
      row = mouse_y - @rect.y - 2
      return nil if row < 0 || row >= 6

      cell_width = (@rect.width // 7).clamp(2, 4)
      col = (mouse_x - @rect.x) // cell_width
      return nil if col < 0 || col >= 7

      # Calculate the date
      first_of_month = Time.local(@view_date.year, @view_date.month, 1)
      first_weekday = (first_of_month.day_of_week.to_i - 1) % 7
      day_offset = row * 7 + col - first_weekday

      first_of_month + day_offset.days
    end

    def min_size : {Int32, Int32}
      {21, 8}  # 7 days * 3 chars, header + weekdays + 6 weeks
    end
  end
end
