# FilePanel - MC-like file panel with path display and file listing
module Tui
  class FilePanel < Widget
    enum TitleTruncate
      End     # /very/long/path/to/di…
      Center  # /very/lo…th/to/dir
      Start   # …long/path/to/dir
    end

    # Current directory path
    @path : Path
    @entries : Array(FileEntry) = [] of FileEntry
    @cursor : Int32 = 0
    @scroll : Int32 = 0

    # Style - MC classic colors
    property border_style : Panel::BorderStyle = Panel::BorderStyle::Light
    property border_color : Color = Color.cyan
    property active_border_color : Color = Color.cyan
    property title_color : Color = Color.cyan
    property title_align : Label::Align = Label::Align::Left
    property title_truncate : TitleTruncate = TitleTruncate::Start
    property bg_color : Color = Color.blue
    property dir_color : Color = Color.white
    property file_color : Color = Color.cyan
    property cursor_color : Color = Color.cyan    # fg when on cursor
    property cursor_bg : Color = Color.cyan       # bg of cursor line
    property selected_color : Color = Color.yellow

    # Multi-selection
    @selected : Set(Int32) = Set(Int32).new

    # Activation callback
    @on_activate : Proc(FileEntry, Nil)?

    struct FileEntry
      property name : String
      property size : Int64
      property is_dir : Bool
      property modified : Time?

      def initialize(@name, @size, @is_dir, @modified = nil)
      end

      def display_size : String
        return "<DIR>" if @is_dir
        case @size
        when 0...1024          then "#{@size}B"
        when 1024...1048576    then "#{@size // 1024}K"
        when 1048576...1073741824 then "#{@size // 1048576}M"
        else                        "#{@size // 1073741824}G"
        end
      end
    end

    def initialize(@path : Path = Path.home, id : String? = nil)
      super(id)
      @focusable = true
      refresh
    end

    def path : Path
      @path
    end

    def path=(new_path : Path) : Nil
      @path = new_path
      refresh
    end

    def on_activate(&block : FileEntry -> Nil) : Nil
      @on_activate = block
    end

    def current_entry : FileEntry?
      @entries[@cursor]? if @entries.any?
    end

    def selected_entries : Array(FileEntry)
      @selected.map { |i| @entries[i]? }.compact
    end

    def refresh : Nil
      @entries.clear
      @cursor = 0
      @scroll = 0
      @selected.clear

      begin
        # Add parent directory entry (unless at root)
        @entries << FileEntry.new("..", 0, true) unless @path == @path.root

        # Read directory
        items = Dir.children(@path.to_s).sort_by { |name| {File.directory?((@path / name).to_s) ? 0 : 1, name.downcase} }

        items.each do |name|
          full_path = (@path / name).to_s
          begin
            info = File.info(full_path)
            @entries << FileEntry.new(
              name,
              info.size,
              info.directory?,
              info.modification_time
            )
          rescue
            # Skip inaccessible files
          end
        end
      rescue ex
        # Directory not accessible
        @entries << FileEntry.new("(error: #{ex.message})", 0, false)
      end

      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      border = Panel::BORDERS[@border_style]
      color = focused? ? @active_border_color : @border_color
      style = Style.new(fg: color)
      title_style = Style.new(fg: @title_color, attrs: Attributes::Bold)

      # Draw border
      draw_border(buffer, clip, border, style)

      # Draw path as title
      draw_title(buffer, clip, border, style, title_style)

      # Draw file list in inner area
      draw_files(buffer, clip)
    end

    private def draw_border(buffer : Buffer, clip : Rect, border, style : Style) : Nil
      # Corners
      draw_char(buffer, clip, @rect.x, @rect.y, border[:tl], style)
      draw_char(buffer, clip, @rect.right - 1, @rect.y, border[:tr], style)
      draw_char(buffer, clip, @rect.x, @rect.bottom - 1, border[:bl], style)
      draw_char(buffer, clip, @rect.right - 1, @rect.bottom - 1, border[:br], style)

      # Horizontal lines
      (1...(@rect.width - 1)).each do |i|
        draw_char(buffer, clip, @rect.x + i, @rect.bottom - 1, border[:h], style)
      end

      # Vertical lines
      (1...(@rect.height - 1)).each do |i|
        draw_char(buffer, clip, @rect.x, @rect.y + i, border[:v], style)
        draw_char(buffer, clip, @rect.right - 1, @rect.y + i, border[:v], style)
      end
    end

    private def draw_title(buffer : Buffer, clip : Rect, border, style : Style, title_style : Style) : Nil
      # Format: ┌───┤ /path/to/dir ├───┐
      max_len = @rect.width - 6  # corners + brackets + padding
      path_str = @path.to_s

      if path_str.size > max_len
        path_str = truncate_path(path_str, max_len)
      end

      title = "#{border[:tl_title]} #{path_str} #{border[:tr_title]}"
      available = @rect.width - 2  # excluding corners

      title_start = case @title_align
                    when .left?   then 1
                    when .center? then (@rect.width - title.size) // 2
                    when .right?  then @rect.width - title.size - 1
                    else               1
                    end

      # Draw top border with title
      (1...(@rect.width - 1)).each do |i|
        x = @rect.x + i
        rel_pos = i - title_start

        if rel_pos >= 0 && rel_pos < title.size
          char = title[rel_pos]
          char_style = if rel_pos == 0 || rel_pos == title.size - 1
                         style  # Brackets in border color
                       else
                         title_style
                       end
          draw_char(buffer, clip, x, @rect.y, char, char_style)
        else
          draw_char(buffer, clip, x, @rect.y, border[:h], style)
        end
      end
    end

    private def draw_files(buffer : Buffer, clip : Rect) : Nil
      inner = inner_rect
      return if inner.height <= 0

      # Ensure cursor is visible
      if @cursor < @scroll
        @scroll = @cursor
      elsif @cursor >= @scroll + inner.height
        @scroll = @cursor - inner.height + 1
      end

      visible_count = Math.min(inner.height, @entries.size - @scroll)

      visible_count.times do |i|
        entry_idx = @scroll + i
        entry = @entries[entry_idx]
        y = inner.y + i

        # Determine style - MC colors
        is_cursor = entry_idx == @cursor && focused?
        is_selected = @selected.includes?(entry_idx)

        bg = if is_cursor
               @cursor_bg
             elsif is_selected
               @bg_color  # Keep blue bg for selected, just change fg
             else
               @bg_color
             end

        fg = if is_cursor
               Color.black
             elsif is_selected
               @selected_color
             elsif entry.is_dir
               @dir_color
             else
               @file_color
             end

        style = Style.new(fg: fg, bg: bg)
        dir_style = if entry.is_dir && !is_cursor && !is_selected
                      Style.new(fg: fg, bg: bg, attrs: Attributes::Bold)
                    else
                      nil
                    end

        # Format: name + size right-aligned
        name = entry.name
        size_str = entry.display_size
        max_name = inner.width - size_str.size - 2

        if name.size > max_name
          name = name[0, max_name - 1] + "…"
        end

        # Draw name
        x = inner.x
        name.each_char do |char|
          draw_char(buffer, clip, x, y, char, dir_style || style)
          x += 1
        end

        # Fill middle with spaces
        while x < inner.x + inner.width - size_str.size - 1
          draw_char(buffer, clip, x, y, ' ', style)
          x += 1
        end

        # Draw size
        size_str.each_char do |char|
          draw_char(buffer, clip, x, y, char, style)
          x += 1
        end

        # Final space
        draw_char(buffer, clip, x, y, ' ', style) if x < inner.right
      end

      # Fill empty lines with background color
      bg_style = Style.new(fg: @file_color, bg: @bg_color)
      ((inner.y + visible_count)...inner.bottom).each do |y|
        inner.width.times do |i|
          draw_char(buffer, clip, inner.x + i, y, ' ', bg_style)
        end
      end
    end

    private def inner_rect : Rect
      Rect.new(
        @rect.x + 1,
        @rect.y + 1,
        Math.max(0, @rect.width - 2),
        Math.max(0, @rect.height - 2)
      )
    end

    private def draw_char(buffer : Buffer, clip : Rect, x : Int32, y : Int32, char : Char, style : Style) : Nil
      buffer.set(x, y, char, style) if clip.contains?(x, y)
    end

    private def truncate_path(path : String, max_len : Int32) : String
      return path if path.size <= max_len
      return "…" if max_len <= 1

      case @title_truncate
      when .end?
        # /very/long/path/to/di…
        path[0, max_len - 1] + "…"
      when .center?
        # /very/lo…th/to/dir
        left_len = (max_len - 1) // 2
        right_len = max_len - 1 - left_len
        path[0, left_len] + "…" + path[-(right_len)..]
      when .start?
        # …long/path/to/dir
        "…" + path[-(max_len - 1)..]
      else
        path[0, max_len - 1] + "…"
      end
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?
      return false unless focused?

      case event
      when KeyEvent
        if handle_key(event)
          event.stop!
          return true
        end
      when MouseEvent
        if event.button.left? && event.action.press?
          if @rect.contains?(event.x, event.y)
            handle_click(event.x, event.y)
            event.stop!
            return true
          end
        elsif event.button.wheel_up?
          move_cursor(-3)
          event.stop!
          return true
        elsif event.button.wheel_down?
          move_cursor(3)
          event.stop!
          return true
        end
      end

      false
    end

    private def handle_key(event : KeyEvent) : Bool
      case event.key
      when .up?
        move_cursor(-1)
        true
      when .down?
        move_cursor(1)
        true
      when .page_up?
        move_cursor(-(inner_rect.height))
        true
      when .page_down?
        move_cursor(inner_rect.height)
        true
      when .home?
        @cursor = 0
        mark_dirty!
        true
      when .end?
        @cursor = @entries.size - 1 if @entries.any?
        mark_dirty!
        true
      when .enter?
        activate_current
        true
      when .backspace?
        go_up
        true
      when .space?, .insert?
        toggle_selection
        true
      else
        false
      end
    end

    private def handle_click(x : Int32, y : Int32) : Nil
      inner = inner_rect
      return unless inner.contains?(x, y)

      row = y - inner.y
      new_cursor = @scroll + row
      if new_cursor < @entries.size
        if new_cursor == @cursor
          # Double-click simulation: activate on second click
          activate_current
        else
          @cursor = new_cursor
          mark_dirty!
        end
      end
    end

    private def move_cursor(delta : Int32) : Nil
      return if @entries.empty?
      @cursor = (@cursor + delta).clamp(0, @entries.size - 1)
      mark_dirty!
    end

    private def toggle_selection : Nil
      return if @entries.empty?
      entry = @entries[@cursor]?
      return unless entry
      return if entry.name == ".."  # Don't select parent dir

      if @selected.includes?(@cursor)
        @selected.delete(@cursor)
      else
        @selected.add(@cursor)
      end
      move_cursor(1)  # Move to next after toggle
    end

    private def activate_current : Nil
      return unless entry = @entries[@cursor]?

      if entry.is_dir
        if entry.name == ".."
          go_up
        else
          @path = @path / entry.name
          refresh
        end
      else
        @on_activate.try &.call(entry)
      end
    end

    private def go_up : Nil
      parent = @path.parent
      if parent != @path
        old_name = @path.basename
        @path = parent
        refresh

        # Try to position cursor on the directory we came from
        @entries.each_with_index do |entry, i|
          if entry.name == old_name
            @cursor = i
            break
          end
        end
        mark_dirty!
      end
    end
  end
end
