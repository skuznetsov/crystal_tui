# Toast - Popup notification system
module Tui
  class Toast < Widget
    enum Level
      Info
      Success
      Warning
      Error
    end

    COLORS = {
      Level::Info    => {fg: Color.white, bg: Color.blue, icon: 'ℹ'},
      Level::Success => {fg: Color.white, bg: Color.green, icon: '✓'},
      Level::Warning => {fg: Color.black, bg: Color.yellow, icon: '⚠'},
      Level::Error   => {fg: Color.white, bg: Color.red, icon: '✗'},
    }

    struct Message
      property text : String
      property level : Level
      property duration : Time::Span
      property created_at : Time::Span

      def initialize(@text : String, @level : Level = Level::Info, @duration : Time::Span = 3.seconds)
        @created_at = Time.monotonic
      end

      def expired? : Bool
        Time.monotonic - @created_at > @duration
      end
    end

    property position : Symbol = :top_right  # :top_left, :top_right, :bottom_left, :bottom_right, :top_center, :bottom_center
    property max_visible : Int32 = 5
    property toast_width : Int32 = 40

    @messages : Array(Message) = [] of Message
    @cleanup_fiber : Fiber?

    def initialize(id : String? = nil)
      super(id)
      @z_index = 1000  # Always on top
      start_cleanup
    end

    # Show a toast message
    def show(text : String, level : Level = Level::Info, duration : Time::Span = 3.seconds) : Nil
      @messages << Message.new(text, level, duration)
      @messages.shift if @messages.size > @max_visible
      mark_dirty!
    end

    def info(text : String, duration : Time::Span = 3.seconds) : Nil
      show(text, Level::Info, duration)
    end

    def success(text : String, duration : Time::Span = 3.seconds) : Nil
      show(text, Level::Success, duration)
    end

    def warning(text : String, duration : Time::Span = 3.seconds) : Nil
      show(text, Level::Warning, duration)
    end

    def error(text : String, duration : Time::Span = 3.seconds) : Nil
      show(text, Level::Error, duration)
    end

    def clear : Nil
      @messages.clear
      mark_dirty!
    end

    private def start_cleanup : Nil
      @cleanup_fiber = spawn(name: "toast-cleanup") do
        loop do
          sleep 500.milliseconds
          old_size = @messages.size
          @messages.reject!(&.expired?)
          mark_dirty! if @messages.size != old_size
        end
      end
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @messages.empty?

      # Calculate position based on screen rect
      screen_width = clip.width
      screen_height = clip.height

      @messages.each_with_index do |msg, index|
        toast_height = 3
        colors = COLORS[msg.level]

        # Calculate X position
        toast_x = case @position
                  when :top_left, :bottom_left
                    1
                  when :top_center, :bottom_center
                    (screen_width - @toast_width) // 2
                  else  # :top_right, :bottom_right
                    screen_width - @toast_width - 1
                  end

        # Calculate Y position
        toast_y = case @position
                  when :bottom_left, :bottom_right, :bottom_center
                    screen_height - (index + 1) * (toast_height + 1)
                  else  # :top_*
                    1 + index * (toast_height + 1)
                  end

        # Draw toast box
        draw_toast(buffer, clip, toast_x, toast_y, msg, colors)
      end
    end

    private def draw_toast(buffer : Buffer, clip : Rect, x : Int32, y : Int32, msg : Message, colors : NamedTuple(fg: Color, bg: Color, icon: Char)) : Nil
      style = Style.new(fg: colors[:fg], bg: colors[:bg])
      border_style = Style.new(fg: colors[:fg], bg: colors[:bg])

      # Top border
      buffer.set(x, y, '┌', border_style) if clip.contains?(x, y)
      (@toast_width - 2).times do |i|
        buffer.set(x + 1 + i, y, '─', border_style) if clip.contains?(x + 1 + i, y)
      end
      buffer.set(x + @toast_width - 1, y, '┐', border_style) if clip.contains?(x + @toast_width - 1, y)

      # Content line
      content_y = y + 1
      buffer.set(x, content_y, '│', border_style) if clip.contains?(x, content_y)
      buffer.set(x + @toast_width - 1, content_y, '│', border_style) if clip.contains?(x + @toast_width - 1, content_y)

      # Fill background
      (1...@toast_width - 1).each do |i|
        buffer.set(x + i, content_y, ' ', style) if clip.contains?(x + i, content_y)
      end

      # Icon
      buffer.set(x + 2, content_y, colors[:icon], style) if clip.contains?(x + 2, content_y)

      # Text (truncate if needed)
      text = msg.text
      max_text_len = @toast_width - 6
      text = text[0, max_text_len - 1] + "…" if text.size > max_text_len
      text.each_char_with_index do |char, i|
        buffer.set(x + 4 + i, content_y, char, style) if clip.contains?(x + 4 + i, content_y)
      end

      # Bottom border
      bottom_y = y + 2
      buffer.set(x, bottom_y, '└', border_style) if clip.contains?(x, bottom_y)
      (@toast_width - 2).times do |i|
        buffer.set(x + 1 + i, bottom_y, '─', border_style) if clip.contains?(x + 1 + i, bottom_y)
      end
      buffer.set(x + @toast_width - 1, bottom_y, '┘', border_style) if clip.contains?(x + @toast_width - 1, bottom_y)
    end

    # Override to render as overlay
    def render_rect : Rect
      # Return full screen rect so we can draw anywhere
      if app = Tui.current_app
        app.rect
      else
        @rect
      end
    end
  end
end
