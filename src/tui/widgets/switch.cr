# Switch widget - iOS-style toggle
module Tui
  class Switch < Widget
    property on : Bool = false
    property on_label : String = "ON"
    property off_label : String = "OFF"
    property on_color : Color = Color.green
    property off_color : Color = Color.palette(240)
    property thumb_color : Color = Color.white
    property track_width : Int32 = 6

    @on_change : Proc(Bool, Nil)?

    def initialize(id : String? = nil, @on : Bool = false)
      super(id)
      @focusable = true
    end

    def on_change(&block : Bool -> Nil) : Nil
      @on_change = block
    end

    def toggle : Nil
      @on = !@on
      @on_change.try &.call(@on)
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      x, y = @rect.x, @rect.y

      # Track background
      track_color = @on ? @on_color : @off_color
      track_style = Style.new(bg: track_color)

      # Draw track: [████  ] or [  ████]
      @track_width.times do |i|
        buffer.set(x + i, y, ' ', track_style) if clip.contains?(x + i, y)
      end

      # Draw thumb (2 chars wide)
      thumb_style = Style.new(bg: @thumb_color)
      thumb_pos = @on ? x + @track_width - 2 : x
      buffer.set(thumb_pos, y, ' ', thumb_style) if clip.contains?(thumb_pos, y)
      buffer.set(thumb_pos + 1, y, ' ', thumb_style) if clip.contains?(thumb_pos + 1, y)

      # Draw border chars
      border_style = Style.new(fg: track_color)
      buffer.set(x - 1, y, '▐', border_style) if x > 0 && clip.contains?(x - 1, y)
      buffer.set(x + @track_width, y, '▌', border_style) if clip.contains?(x + @track_width, y)

      # Draw label after switch
      label = @on ? @on_label : @off_label
      label_style = Style.new(fg: track_color)
      label_x = x + @track_width + 2
      label.each_char_with_index do |char, i|
        buffer.set(label_x + i, y, char, label_style) if clip.contains?(label_x + i, y)
      end

      # Focus indicator
      if focused?
        focus_style = Style.new(fg: Color.yellow)
        buffer.set(x - 2, y, '>', focus_style) if x > 1 && clip.contains?(x - 2, y)
      end
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when KeyEvent
        if event.matches?("enter") || event.matches?("space")
          toggle
          event.stop!
          return true
        end
      when MouseEvent
        if event.action.press? && event.in_rect?(@rect)
          toggle
          event.stop!
          return true
        end
      end

      false
    end

    def min_size : {Int32, Int32}
      {@track_width + @on_label.size.max(@off_label.size) + 4, 1}
    end
  end
end
