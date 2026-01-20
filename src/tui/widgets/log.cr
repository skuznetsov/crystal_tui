# Log - Scrolling log viewer with timestamps and levels
module Tui
  class Log < Widget
    enum Level
      Debug
      Info
      Warning
      Error
      Success
    end

    struct Entry
      property timestamp : Time
      property level : Level
      property message : String
      property source : String?

      def initialize(@message : String, @level : Level = Level::Info, @source : String? = nil)
        @timestamp = Time.local
      end
    end

    property entries : Array(Entry) = [] of Entry
    property max_entries : Int32 = 1000
    property scroll_offset : Int32 = 0
    property auto_scroll : Bool = true
    property show_timestamp : Bool = true
    property show_level : Bool = true
    property timestamp_format : String = "%H:%M:%S"

    # Styling
    property debug_style : Style = Style.new(fg: Color.palette(245))
    property info_style : Style = Style.new(fg: Color.white)
    property warning_style : Style = Style.new(fg: Color.yellow)
    property error_style : Style = Style.new(fg: Color.red)
    property success_style : Style = Style.new(fg: Color.green)
    property timestamp_style : Style = Style.new(fg: Color.palette(240))
    property source_style : Style = Style.new(fg: Color.cyan)

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    # Add log entry
    def log(message : String, level : Level = Level::Info, source : String? = nil) : Nil
      @entries << Entry.new(message, level, source)

      # Trim old entries
      while @entries.size > @max_entries
        @entries.shift
      end

      # Auto-scroll to bottom
      if @auto_scroll
        scroll_to_bottom
      end

      mark_dirty!
    end

    # Convenience methods
    def debug(message : String, source : String? = nil) : Nil
      log(message, Level::Debug, source)
    end

    def info(message : String, source : String? = nil) : Nil
      log(message, Level::Info, source)
    end

    def warning(message : String, source : String? = nil) : Nil
      log(message, Level::Warning, source)
    end

    def error(message : String, source : String? = nil) : Nil
      log(message, Level::Error, source)
    end

    def success(message : String, source : String? = nil) : Nil
      log(message, Level::Success, source)
    end

    # Write method for IO compatibility
    def write(message : String) : Nil
      # Split by newlines and log each line
      message.split('\n').each do |line|
        next if line.empty?
        log(line)
      end
    end

    def clear : Nil
      @entries.clear
      @scroll_offset = 0
      mark_dirty!
    end

    def visible_count : Int32
      @rect.height
    end

    def scroll_to_bottom : Nil
      @scroll_offset = Math.max(0, @entries.size - visible_count)
    end

    def scroll_to_top : Nil
      @scroll_offset = 0
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Clear background
      @rect.each_cell do |x, y|
        buffer.set(x, y, ' ', @info_style) if clip.contains?(x, y)
      end

      visible = visible_count
      return if visible == 0

      # Render visible entries
      visible.times do |i|
        entry_index = @scroll_offset + i
        break if entry_index >= @entries.size

        entry = @entries[entry_index]
        y = @rect.y + i
        next unless clip.contains?(@rect.x, y)

        render_entry(buffer, clip, entry, y)
      end

      # Draw scrollbar if needed
      if @entries.size > visible
        draw_scrollbar(buffer, clip, visible)
      end
    end

    private def render_entry(buffer : Buffer, clip : Rect, entry : Entry, y : Int32) : Nil
      x = @rect.x
      max_x = @rect.x + @rect.width

      # Timestamp
      if @show_timestamp
        ts = entry.timestamp.to_s(@timestamp_format)
        ts.each_char do |char|
          break if x >= max_x
          buffer.set(x, y, char, @timestamp_style) if clip.contains?(x, y)
          x += 1
        end
        buffer.set(x, y, ' ', @timestamp_style) if x < max_x && clip.contains?(x, y)
        x += 1
      end

      # Level indicator
      if @show_level
        level_char, level_style = case entry.level
                                  when .debug?   then {'D', @debug_style}
                                  when .info?    then {'I', @info_style}
                                  when .warning? then {'W', @warning_style}
                                  when .error?   then {'E', @error_style}
                                  when .success? then {'✓', @success_style}
                                  else                {'?', @info_style}
                                  end
        buffer.set(x, y, level_char, level_style) if x < max_x && clip.contains?(x, y)
        x += 1
        buffer.set(x, y, ' ', @info_style) if x < max_x && clip.contains?(x, y)
        x += 1
      end

      # Source (if present)
      if source = entry.source
        buffer.set(x, y, '[', @source_style) if x < max_x && clip.contains?(x, y)
        x += 1
        source.each_char do |char|
          break if x >= max_x
          buffer.set(x, y, char, @source_style) if clip.contains?(x, y)
          x += 1
        end
        buffer.set(x, y, ']', @source_style) if x < max_x && clip.contains?(x, y)
        x += 1
        buffer.set(x, y, ' ', @info_style) if x < max_x && clip.contains?(x, y)
        x += 1
      end

      # Message
      message_style = case entry.level
                      when .debug?   then @debug_style
                      when .info?    then @info_style
                      when .warning? then @warning_style
                      when .error?   then @error_style
                      when .success? then @success_style
                      else                @info_style
                      end

      entry.message.each_char do |char|
        break if x >= max_x
        buffer.set(x, y, char, message_style) if clip.contains?(x, y)
        x += Unicode.char_width(char)
      end
    end

    private def draw_scrollbar(buffer : Buffer, clip : Rect, visible : Int32) : Nil
      return if @rect.width < 2

      scrollbar_x = @rect.x + @rect.width - 1
      total = @entries.size
      return if total <= visible

      thumb_height = Math.max(1, (visible * @rect.height / total).to_i)
      thumb_pos = (@scroll_offset * (@rect.height - thumb_height) / (total - visible)).to_i

      track_style = Style.new(fg: Color.palette(240))
      thumb_style = Style.new(fg: Color.white)

      @rect.height.times do |i|
        y = @rect.y + i
        next unless clip.contains?(scrollbar_x, y)

        if i >= thumb_pos && i < thumb_pos + thumb_height
          buffer.set(scrollbar_x, y, '█', thumb_style)
        else
          buffer.set(scrollbar_x, y, '│', track_style)
        end
      end
    end

    def on_event(event : Event) : Bool
      return false unless focused?
      return false if event.stopped?

      case event
      when KeyEvent
        case
        when event.matches?("up"), event.matches?("k")
          @scroll_offset = Math.max(0, @scroll_offset - 1)
          @auto_scroll = false
          mark_dirty!
          event.stop!
          return true
        when event.matches?("down"), event.matches?("j")
          max_offset = Math.max(0, @entries.size - visible_count)
          @scroll_offset = Math.min(max_offset, @scroll_offset + 1)
          @auto_scroll = @scroll_offset >= max_offset
          mark_dirty!
          event.stop!
          return true
        when event.matches?("home"), event.matches?("g")
          scroll_to_top
          @auto_scroll = false
          mark_dirty!
          event.stop!
          return true
        when event.matches?("end"), event.matches?("G")
          scroll_to_bottom
          @auto_scroll = true
          mark_dirty!
          event.stop!
          return true
        when event.matches?("pageup"), event.matches?("ctrl+u")
          @scroll_offset = Math.max(0, @scroll_offset - visible_count)
          @auto_scroll = false
          mark_dirty!
          event.stop!
          return true
        when event.matches?("pagedown"), event.matches?("ctrl+d")
          max_offset = Math.max(0, @entries.size - visible_count)
          @scroll_offset = Math.min(max_offset, @scroll_offset + visible_count)
          @auto_scroll = @scroll_offset >= max_offset
          mark_dirty!
          event.stop!
          return true
        when event.matches?("c")
          clear
          event.stop!
          return true
        end
      when MouseEvent
        if event.action.press? && event.in_rect?(@rect)
          if event.button.wheel_up?
            @scroll_offset = Math.max(0, @scroll_offset - 3)
            @auto_scroll = false
            mark_dirty!
            event.stop!
            return true
          elsif event.button.wheel_down?
            max_offset = Math.max(0, @entries.size - visible_count)
            @scroll_offset = Math.min(max_offset, @scroll_offset + 3)
            @auto_scroll = @scroll_offset >= max_offset
            mark_dirty!
            event.stop!
            return true
          end
        end
      end

      super
    end

    def min_size : {Int32, Int32}
      {20, 3}
    end
  end
end
