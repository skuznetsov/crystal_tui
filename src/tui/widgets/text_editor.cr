# Text Editor widget - Full-featured text editing
module Tui
  class TextEditor < Widget
    struct Cursor
      property line : Int32 = 0
      property col : Int32 = 0

      def initialize(@line = 0, @col = 0)
      end
    end

    struct Selection
      property start_line : Int32
      property start_col : Int32
      property end_line : Int32
      property end_col : Int32

      def initialize(@start_line = 0, @start_col = 0, @end_line = 0, @end_col = 0)
      end

      def empty? : Bool
        @start_line == @end_line && @start_col == @end_col
      end

      def normalize : Selection
        if @start_line > @end_line || (@start_line == @end_line && @start_col > @end_col)
          Selection.new(@end_line, @end_col, @start_line, @start_col)
        else
          self
        end
      end
    end

    @lines : Array(String) = [""]
    @cursor : Cursor = Cursor.new
    @selection : Selection?
    @scroll_x : Int32 = 0
    @scroll_y : Int32 = 0
    @modified : Bool = false
    @path : Path?
    @title : String = "Untitled"

    # Style
    property text_fg : Color = Color.white
    property text_bg : Color = Color.blue
    property cursor_fg : Color = Color.black
    property cursor_bg : Color = Color.white
    property selection_fg : Color = Color.white
    property selection_bg : Color = Color.cyan
    property line_number_fg : Color = Color.yellow
    property line_number_bg : Color = Color.blue
    property current_line_bg : Color = Color.palette(17)  # Slightly lighter
    property show_line_numbers : Bool = true
    property tab_size : Int32 = 4
    property word_wrap : Bool = false

    # Callbacks
    @on_change : Proc(Nil)?
    @on_save : Proc(Path, Nil)?

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    def on_change(&block : -> Nil) : Nil
      @on_change = block
    end

    def on_save(&block : Path -> Nil) : Nil
      @on_save = block
    end

    def title : String
      @modified ? "#{@title} *" : @title
    end

    def modified? : Bool
      @modified
    end

    def path : Path?
      @path
    end

    def lines : Array(String)
      @lines
    end

    def text : String
      @lines.join("\n")
    end

    def text=(content : String) : Nil
      @lines = content.lines
      @lines = [""] if @lines.empty?
      @cursor = Cursor.new
      @selection = nil
      @scroll_x = 0
      @scroll_y = 0
      @modified = true
      mark_dirty!
    end

    def load_file(path : Path) : Bool
      begin
        content = File.read(path.to_s)
        @lines = content.lines
        @lines = [""] if @lines.empty?
        @path = path
        @title = path.basename
        @cursor = Cursor.new
        @selection = nil
        @scroll_x = 0
        @scroll_y = 0
        @modified = false
        mark_dirty!
        true
      rescue ex
        @lines = ["Error loading file:", ex.message || "Unknown error"]
        @modified = false
        mark_dirty!
        false
      end
    end

    def save : Bool
      return false unless path = @path
      save_as(path)
    end

    def save_as(path : Path) : Bool
      begin
        File.write(path.to_s, text)
        @path = path
        @title = path.basename
        @modified = false
        @on_save.try &.call(path)
        mark_dirty!
        true
      rescue
        false
      end
    end

    # Editing operations
    def insert_char(char : Char) : Nil
      delete_selection if @selection
      line = @lines[@cursor.line]
      @lines[@cursor.line] = line[0, @cursor.col] + char + line[@cursor.col..]
      @cursor.col += 1
      text_changed
    end

    def insert_text(text : String) : Nil
      delete_selection if @selection
      text.each_char { |c| insert_char(c) }
    end

    def insert_newline : Nil
      delete_selection if @selection
      line = @lines[@cursor.line]
      @lines[@cursor.line] = line[0, @cursor.col]
      @lines.insert(@cursor.line + 1, line[@cursor.col..])
      @cursor.line += 1
      @cursor.col = 0
      text_changed
    end

    def backspace : Nil
      if @selection && !@selection.not_nil!.empty?
        delete_selection
        return
      end

      if @cursor.col > 0
        line = @lines[@cursor.line]
        @lines[@cursor.line] = line[0, @cursor.col - 1] + line[@cursor.col..]
        @cursor.col -= 1
        text_changed
      elsif @cursor.line > 0
        # Join with previous line
        prev_len = @lines[@cursor.line - 1].size
        @lines[@cursor.line - 1] += @lines[@cursor.line]
        @lines.delete_at(@cursor.line)
        @cursor.line -= 1
        @cursor.col = prev_len
        text_changed
      end
    end

    def delete : Nil
      if @selection && !@selection.not_nil!.empty?
        delete_selection
        return
      end

      line = @lines[@cursor.line]
      if @cursor.col < line.size
        @lines[@cursor.line] = line[0, @cursor.col] + line[@cursor.col + 1..]
        text_changed
      elsif @cursor.line < @lines.size - 1
        # Join with next line
        @lines[@cursor.line] += @lines[@cursor.line + 1]
        @lines.delete_at(@cursor.line + 1)
        text_changed
      end
    end

    def delete_selection : Nil
      sel = @selection
      return unless sel

      sel = sel.normalize
      if sel.start_line == sel.end_line
        line = @lines[sel.start_line]
        @lines[sel.start_line] = line[0, sel.start_col] + line[sel.end_col..]
      else
        # Delete across lines
        first_part = @lines[sel.start_line][0, sel.start_col]
        last_part = @lines[sel.end_line][sel.end_col..]
        @lines[sel.start_line] = first_part + last_part
        (sel.end_line - sel.start_line).times do
          @lines.delete_at(sel.start_line + 1)
        end
      end

      @cursor.line = sel.start_line
      @cursor.col = sel.start_col
      @selection = nil
      text_changed
    end

    def select_all : Nil
      @selection = Selection.new(0, 0, @lines.size - 1, @lines.last.size)
      mark_dirty!
    end

    def copy : String?
      sel = @selection
      return nil unless sel

      sel = sel.normalize
      if sel.start_line == sel.end_line
        @lines[sel.start_line][sel.start_col...sel.end_col]
      else
        result = @lines[sel.start_line][sel.start_col..]
        (sel.start_line + 1...sel.end_line).each do |i|
          result += "\n" + @lines[i]
        end
        result += "\n" + @lines[sel.end_line][0, sel.end_col]
        result
      end
    end

    def cut : String?
      result = copy
      delete_selection if result
      result
    end

    def paste(text : String) : Nil
      delete_selection if @selection
      lines = text.lines
      if lines.size == 1
        insert_text(lines.first)
      else
        # Multi-line paste
        current_line = @lines[@cursor.line]
        before = current_line[0, @cursor.col]
        after = current_line[@cursor.col..]

        @lines[@cursor.line] = before + lines.first
        lines[1...-1].each_with_index do |line, i|
          @lines.insert(@cursor.line + 1 + i, line)
        end
        @lines.insert(@cursor.line + lines.size - 1, lines.last + after)

        @cursor.line += lines.size - 1
        @cursor.col = lines.last.size
        text_changed
      end
    end

    # Cursor movement
    def move_left(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      if @cursor.col > 0
        @cursor.col -= 1
      elsif @cursor.line > 0
        @cursor.line -= 1
        @cursor.col = @lines[@cursor.line].size
      end

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_right(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      if @cursor.col < @lines[@cursor.line].size
        @cursor.col += 1
      elsif @cursor.line < @lines.size - 1
        @cursor.line += 1
        @cursor.col = 0
      end

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_up(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      if @cursor.line > 0
        @cursor.line -= 1
        @cursor.col = @cursor.col.clamp(0, @lines[@cursor.line].size)
      end

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_down(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      if @cursor.line < @lines.size - 1
        @cursor.line += 1
        @cursor.col = @cursor.col.clamp(0, @lines[@cursor.line].size)
      end

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_word_left(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      if @cursor.col == 0 && @cursor.line > 0
        @cursor.line -= 1
        @cursor.col = @lines[@cursor.line].size
      else
        line = @lines[@cursor.line]
        # Skip whitespace
        while @cursor.col > 0 && line[@cursor.col - 1].whitespace?
          @cursor.col -= 1
        end
        # Skip word chars
        while @cursor.col > 0 && !line[@cursor.col - 1].whitespace?
          @cursor.col -= 1
        end
      end

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_word_right(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      line = @lines[@cursor.line]
      if @cursor.col >= line.size && @cursor.line < @lines.size - 1
        @cursor.line += 1
        @cursor.col = 0
      else
        # Skip word chars
        while @cursor.col < line.size && !line[@cursor.col].whitespace?
          @cursor.col += 1
        end
        # Skip whitespace
        while @cursor.col < line.size && line[@cursor.col].whitespace?
          @cursor.col += 1
        end
      end

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_home(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      @cursor.col = 0

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_end(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      @cursor.col = @lines[@cursor.line].size

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_to_start : Nil
      @cursor = Cursor.new
      @selection = nil
      @scroll_x = 0
      @scroll_y = 0
      mark_dirty!
    end

    def move_to_end : Nil
      @cursor.line = @lines.size - 1
      @cursor.col = @lines.last.size
      @selection = nil
      ensure_cursor_visible
      mark_dirty!
    end

    def page_up : Nil
      visible_lines = content_height
      @cursor.line = (@cursor.line - visible_lines).clamp(0, @lines.size - 1)
      @cursor.col = @cursor.col.clamp(0, @lines[@cursor.line].size)
      @selection = nil
      ensure_cursor_visible
      mark_dirty!
    end

    def page_down : Nil
      visible_lines = content_height
      @cursor.line = (@cursor.line + visible_lines).clamp(0, @lines.size - 1)
      @cursor.col = @cursor.col.clamp(0, @lines[@cursor.line].size)
      @selection = nil
      ensure_cursor_visible
      mark_dirty!
    end

    def goto_line(line : Int32) : Nil
      @cursor.line = (line - 1).clamp(0, @lines.size - 1)
      @cursor.col = 0
      @selection = nil
      ensure_cursor_visible
      mark_dirty!
    end

    private def text_changed : Nil
      @modified = true
      @on_change.try &.call
      ensure_cursor_visible
      mark_dirty!
    end

    private def update_selection_start : Nil
      @selection = Selection.new(@cursor.line, @cursor.col, @cursor.line, @cursor.col)
    end

    private def update_selection_end : Nil
      if sel = @selection
        @selection = Selection.new(sel.start_line, sel.start_col, @cursor.line, @cursor.col)
      end
    end

    private def clear_selection : Nil
      @selection = nil
    end

    private def line_number_width : Int32
      @show_line_numbers ? (@lines.size.to_s.size + 1) : 0
    end

    private def content_width : Int32
      @rect.width - line_number_width
    end

    private def content_height : Int32
      @rect.height
    end

    private def ensure_cursor_visible : Nil
      # Vertical scrolling
      if @cursor.line < @scroll_y
        @scroll_y = @cursor.line
      elsif @cursor.line >= @scroll_y + content_height
        @scroll_y = @cursor.line - content_height + 1
      end

      # Horizontal scrolling
      visible_col = @cursor.col - @scroll_x
      if visible_col < 0
        @scroll_x = @cursor.col
      elsif visible_col >= content_width - 1
        @scroll_x = @cursor.col - content_width + 2
      end
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      text_style = Style.new(fg: @text_fg, bg: @text_bg)
      line_num_style = Style.new(fg: @line_number_fg, bg: @line_number_bg)
      cursor_style = Style.new(fg: @cursor_fg, bg: @cursor_bg)
      selection_style = Style.new(fg: @selection_fg, bg: @selection_bg)
      current_line_style = Style.new(fg: @text_fg, bg: @current_line_bg)

      ln_width = line_number_width
      visible_lines = content_height

      visible_lines.times do |i|
        line_idx = @scroll_y + i
        y = @rect.y + i

        if line_idx >= @lines.size
          # Clear empty lines
          @rect.width.times do |x|
            buffer.set(@rect.x + x, y, ' ', text_style) if clip.contains?(@rect.x + x, y)
          end
          next
        end

        is_current_line = line_idx == @cursor.line
        base_style = is_current_line && focused? ? current_line_style : text_style

        # Draw line number
        if @show_line_numbers
          num_str = (line_idx + 1).to_s.rjust(ln_width - 1)
          num_str.each_char_with_index do |char, ci|
            buffer.set(@rect.x + ci, y, char, line_num_style) if clip.contains?(@rect.x + ci, y)
          end
        end

        # Draw line content
        line = @lines[line_idx]
        content_x = @rect.x + ln_width

        (content_width).times do |col|
          text_col = @scroll_x + col
          x = content_x + col

          char = if text_col < line.size
                   c = line[text_col]
                   c == '\t' ? ' ' : c
                 else
                   ' '
                 end

          # Determine style
          style = if is_cursor_at?(line_idx, text_col) && focused?
                    cursor_style
                  elsif in_selection?(line_idx, text_col)
                    selection_style
                  else
                    base_style
                  end

          buffer.set(x, y, char, style) if clip.contains?(x, y)
        end
      end
    end

    private def is_cursor_at?(line : Int32, col : Int32) : Bool
      line == @cursor.line && col == @cursor.col
    end

    private def in_selection?(line : Int32, col : Int32) : Bool
      sel = @selection
      return false unless sel

      sel = sel.normalize
      return false if line < sel.start_line || line > sel.end_line

      if line == sel.start_line && line == sel.end_line
        col >= sel.start_col && col < sel.end_col
      elsif line == sel.start_line
        col >= sel.start_col
      elsif line == sel.end_line
        col < sel.end_col
      else
        true
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
        if handle_mouse(event)
          event.stop!
          return true
        end
      end

      false
    end

    private def handle_key(event : KeyEvent) : Bool
      shift = event.modifiers.shift?
      ctrl = event.modifiers.ctrl?

      case event.key
      when .left?
        if ctrl
          move_word_left(shift)
        else
          move_left(shift)
        end
        true
      when .right?
        if ctrl
          move_word_right(shift)
        else
          move_right(shift)
        end
        true
      when .up?
        move_up(shift)
        true
      when .down?
        move_down(shift)
        true
      when .home?
        move_home(shift)
        true
      when .end?
        move_end(shift)
        true
      when .page_up?
        page_up
        true
      when .page_down?
        page_down
        true
      when .backspace?
        backspace
        true
      when .delete?
        delete
        true
      when .enter?
        insert_newline
        true
      when .tab?
        insert_text("  ")  # 2 spaces for tab
        true
      else
        if ctrl
          case event.char
          when 'a'
            select_all
            return true
          when 's'
            save
            return true
          when 'c'
            copy
            return true
          when 'x'
            cut
            return true
          when 'v'
            # Paste would need clipboard access
            return true
          when 'g'
            # Goto line - would need dialog
            return true
          end
        end

        # Regular character input
        if char = event.char
          if char.printable?
            insert_char(char)
            return true
          end
        end

        false
      end
    end

    private def handle_mouse(event : MouseEvent) : Bool
      return false unless event.in_rect?(@rect)

      case event.action
      when MouseAction::Press
        # Click to position cursor
        rel_x, rel_y = event.relative_to(@rect)
        text_x = rel_x - line_number_width + @scroll_x
        text_y = rel_y + @scroll_y

        if text_y < @lines.size
          @cursor.line = text_y
          @cursor.col = text_x.clamp(0, @lines[text_y].size)
          @selection = nil
          mark_dirty!
        end
        true
      when MouseAction::Drag
        # Selection
        rel_x, rel_y = event.relative_to(@rect)
        text_x = rel_x - line_number_width + @scroll_x
        text_y = (rel_y + @scroll_y).clamp(0, @lines.size - 1)

        unless @selection
          @selection = Selection.new(@cursor.line, @cursor.col, @cursor.line, @cursor.col)
        end

        @cursor.line = text_y
        @cursor.col = text_x.clamp(0, @lines[text_y].size)
        update_selection_end

        mark_dirty!
        true
      else
        false
      end
    end
  end
end
