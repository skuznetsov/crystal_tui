# Header - Application title bar with optional clock/status
module Tui
  class Header < Widget
    property title : String = ""
    property subtitle : String = ""
    property show_clock : Bool = true
    property bg_color : Color = Color.blue
    property fg_color : Color = Color.white
    property title_color : Color = Color.white
    property subtitle_color : Color = Color.palette(250)
    property clock_color : Color = Color.yellow
    property icon : String = ""

    @clock_fiber : Fiber?
    @current_time : String = ""

    def initialize(id : String? = nil, @title : String = "")
      super(id)
      update_clock
    end

    def start_clock : Nil
      return if @clock_fiber
      @clock_fiber = spawn(name: "header-clock") do
        loop do
          sleep 1.second
          old_time = @current_time
          update_clock
          mark_dirty! if @current_time != old_time
        end
      end
    end

    def stop_clock : Nil
      @clock_fiber = nil
    end

    private def update_clock : Nil
      @current_time = Time.local.to_s("%H:%M:%S")
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      x, y, w = @rect.x, @rect.y, @rect.width

      # Background
      bg_style = Style.new(bg: @bg_color)
      w.times do |i|
        buffer.set(x + i, y, ' ', bg_style) if clip.contains?(x + i, y)
      end

      # Icon (if any)
      current_x = x + 1
      unless @icon.empty?
        icon_style = Style.new(fg: @title_color, bg: @bg_color)
        @icon.each_char do |char|
          buffer.set(current_x, y, char, icon_style) if clip.contains?(current_x, y)
          current_x += Unicode.display_width(char.to_s)
        end
        current_x += 1
      end

      # Title
      title_style = Style.new(fg: @title_color, bg: @bg_color, attrs: Attributes::Bold)
      @title.each_char do |char|
        break if current_x >= x + w - 10  # Leave room for clock
        buffer.set(current_x, y, char, title_style) if clip.contains?(current_x, y)
        current_x += 1
      end

      # Subtitle (if fits)
      unless @subtitle.empty?
        current_x += 1
        sub_style = Style.new(fg: @subtitle_color, bg: @bg_color)
        buffer.set(current_x, y, '-', sub_style) if clip.contains?(current_x, y)
        current_x += 2
        @subtitle.each_char do |char|
          break if current_x >= x + w - 10
          buffer.set(current_x, y, char, sub_style) if clip.contains?(current_x, y)
          current_x += 1
        end
      end

      # Clock (right-aligned)
      if @show_clock
        update_clock
        clock_style = Style.new(fg: @clock_color, bg: @bg_color)
        clock_x = x + w - @current_time.size - 1
        @current_time.each_char_with_index do |char, i|
          buffer.set(clock_x + i, y, char, clock_style) if clip.contains?(clock_x + i, y)
        end
      end
    end

    def min_size : {Int32, Int32}
      {20, 1}
    end
  end
end
