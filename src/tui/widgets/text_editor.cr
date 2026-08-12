# Text Editor widget - Full-featured text editing
require "set"

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

    # LSP-style fold: start_line stays visible; start_line+1..end_line hide when collapsed.
    struct FoldRange
      property start_line : Int32
      property end_line : Int32

      def initialize(@start_line : Int32, @end_line : Int32)
      end

      def valid? : Bool
        @end_line > @start_line && @start_line >= 0
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
    @fold_ranges : Array(FoldRange) = [] of FoldRange
    @collapsed_folds : Set(Int32) = Set(Int32).new
    @hidden_lines : Array(Bool) = [false]
    @fold_starts : Hash(Int32, FoldRange) = {} of Int32 => FoldRange

    # Style
    property text_fg : Color = Color.white
    property text_bg : Color = Color.blue
    property cursor_fg : Color = Color.black
    property cursor_bg : Color = Color.white
    property selection_fg : Color = Color.white
    property selection_bg : Color = Color.cyan
    property line_number_fg : Color = Color.yellow
    property line_number_bg : Color = Color.blue
    property fold_gutter_fg : Color = Color.rgb(120, 120, 120)
    property fold_placeholder_fg : Color = Color.rgb(128, 128, 160)
    property current_line_bg : Color = Color.palette(17) # Slightly lighter
    property show_line_numbers : Bool = true
    property show_fold_gutter : Bool = true
    property tab_size : Int32 = 4
    property word_wrap : Bool = false

    # Callbacks
    @on_change : Proc(Nil)?
    @on_save : Proc(Path, Nil)?
    @on_cell_style : Proc(Int32, Int32, Char, Style, Style)?

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

    def on_cell_style(&block : Int32, Int32, Char, Style -> Style) : Nil
      @on_cell_style = block
    end

    def fold_ranges : Array(FoldRange)
      @fold_ranges
    end

    def set_fold_ranges(ranges : Array(FoldRange)) : Nil
      previous_collapsed = @collapsed_folds.dup
      @fold_ranges = ranges.select(&.valid?).sort_by { |range| {range.start_line, -range.end_line} }
      @fold_starts = {} of Int32 => FoldRange
      @fold_ranges.each do |range|
        existing = @fold_starts[range.start_line]?
        if existing.nil? || range.end_line > existing.end_line
          @fold_starts[range.start_line] = range
        end
      end
      @collapsed_folds = previous_collapsed.select { |line| @fold_starts.has_key?(line) }.to_set
      rebuild_hidden_lines!
      reveal_cursor_line!
      ensure_cursor_visible
      mark_dirty!
    end

    def clear_folds : Nil
      return if @fold_ranges.empty? && @collapsed_folds.empty?
      @fold_ranges = [] of FoldRange
      @fold_starts = {} of Int32 => FoldRange
      @collapsed_folds.clear
      rebuild_hidden_lines!
      mark_dirty!
    end

    def toggle_fold_at(line : Int32) : Bool
      range = @fold_starts[line]?
      return false unless range

      if @collapsed_folds.includes?(line)
        @collapsed_folds.delete(line)
      else
        @collapsed_folds.add(line)
      end
      rebuild_hidden_lines!
      reveal_cursor_line!
      ensure_cursor_visible
      mark_dirty!
      true
    end

    def toggle_fold_at_cursor : Bool
      toggle_fold_at(@cursor.line)
    end

    def fold_marker_at(line : Int32) : Char?
      return nil unless @fold_starts.has_key?(line)
      @collapsed_folds.includes?(line) ? '+' : '-'
    end

    FOLD_PLACEHOLDER = " {...}"

    def fold_placeholder_at(line : Int32) : String?
      return nil unless @collapsed_folds.includes?(line)
      FOLD_PLACEHOLDER
    end

    # True when `col` lands on the `{...}` after a collapsed header; expands the fold.
    def expand_fold_at_placeholder?(line : Int32, col : Int32) : Bool
      return false unless fold_placeholder_at(line)
      return false if line < 0 || line >= @lines.size
      start = @lines[line].size
      return false unless col >= start && col < start + FOLD_PLACEHOLDER.size
      toggle_fold_at(line)
    end

    def line_hidden?(line : Int32) : Bool
      return false if line < 0 || line >= @hidden_lines.size
      @hidden_lines[line]
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

    def cursor : Cursor
      @cursor
    end

    def cursor_line : Int32
      @cursor.line
    end

    def cursor_col : Int32
      @cursor.col
    end

    def set_cursor(line : Int32, col : Int32) : Nil
      return if @lines.empty?

      @cursor.line = line.clamp(0, @lines.size - 1)
      @cursor.col = col.clamp(0, @lines[@cursor.line].size)
      @selection = nil
      ensure_cursor_visible
      mark_dirty!
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
      clear_folds
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
        clear_folds
        mark_dirty!
        true
      rescue ex
        @lines = ["Error loading file:", ex.message || "Unknown error"]
        @modified = false
        clear_folds
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

      normalized = normalize_newlines(text)
      return if normalized.empty?

      normalized.each_char do |char|
        if char == '\n'
          line = @lines[@cursor.line]
          @lines[@cursor.line] = line[0, @cursor.col]
          @lines.insert(@cursor.line + 1, line[@cursor.col..])
          @cursor.line += 1
          @cursor.col = 0
        else
          line = @lines[@cursor.line]
          @lines[@cursor.line] = line[0, @cursor.col] + char + line[@cursor.col..]
          @cursor.col += 1
        end
      end

      text_changed
    end

    private def normalize_newlines(text : String) : String
      text.gsub("\r\n", "\n").gsub("\r", "\n")
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

      target = previous_visible_line(@cursor.line)
      if target
        @cursor.line = target
        @cursor.col = @cursor.col.clamp(0, @lines[@cursor.line].size)
      end

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_down(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      target = next_visible_line(@cursor.line)
      if target
        @cursor.line = target
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
      steps = content_height
      line = @cursor.line
      steps.times do
        previous = previous_visible_line(line)
        break unless previous
        line = previous
      end
      @cursor.line = line
      @cursor.col = @cursor.col.clamp(0, @lines[@cursor.line].size)
      @selection = nil
      ensure_cursor_visible
      mark_dirty!
    end

    def page_down : Nil
      steps = content_height
      line = @cursor.line
      steps.times do
        following = next_visible_line(line)
        break unless following
        line = following
      end
      @cursor.line = line
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
      clear_folds if @fold_ranges.any?
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

    private def fold_gutter_width : Int32
      (@show_fold_gutter && !@fold_ranges.empty?) ? 1 : 0
    end

    private def gutter_width : Int32
      fold_gutter_width + line_number_width
    end

    private def content_width : Int32
      @rect.width - gutter_width
    end

    private def content_height : Int32
      @rect.height
    end

    private def rebuild_hidden_lines! : Nil
      @hidden_lines = Array.new(@lines.size, false)
      @collapsed_folds.each do |start_line|
        range = @fold_starts[start_line]?
        next unless range
        line = range.start_line + 1
        while line <= range.end_line && line < @hidden_lines.size
          @hidden_lines[line] = true
          line += 1
        end
      end
    end

    private def reveal_cursor_line! : Nil
      return unless line_hidden?(@cursor.line)

      changed = false
      @fold_ranges.each do |range|
        next unless @collapsed_folds.includes?(range.start_line)
        next unless @cursor.line > range.start_line && @cursor.line <= range.end_line
        @collapsed_folds.delete(range.start_line)
        changed = true
      end
      rebuild_hidden_lines! if changed
    end

    private def next_visible_line(from : Int32) : Int32?
      line = from + 1
      while line < @lines.size
        return line unless line_hidden?(line)
        line += 1
      end
      nil
    end

    private def previous_visible_line(from : Int32) : Int32?
      line = from - 1
      while line >= 0
        return line unless line_hidden?(line)
        line -= 1
      end
      nil
    end

    private def first_visible_from(from : Int32) : Int32
      line = from.clamp(0, Math.max(@lines.size - 1, 0))
      return line unless line_hidden?(line)
      next_visible_line(line - 1) || previous_visible_line(line + 1) || 0
    end

    private def document_line_at_visual_row(visual_row : Int32) : Int32
      line = first_visible_from(@scroll_y)
      row = 0
      while row < visual_row
        following = next_visible_line(line)
        break unless following
        line = following
        row += 1
      end
      line
    end

    private def ensure_cursor_visible : Nil
      reveal_cursor_line!

      # Vertical scrolling in document-line space, skipping hidden lines for height.
      if @cursor.line < @scroll_y || line_hidden?(@scroll_y)
        @scroll_y = first_visible_from(@cursor.line)
      else
        visible_count = 0
        line = first_visible_from(@scroll_y)
        while visible_count < content_height && line <= @cursor.line
          visible_count += 1
          break if line == @cursor.line
          following = next_visible_line(line)
          break unless following
          line = following
        end
        if visible_count >= content_height && line != @cursor.line
          # Scroll forward until cursor fits in the last row.
          @scroll_y = @cursor.line
          remaining = content_height - 1
          while remaining > 0
            previous = previous_visible_line(@scroll_y)
            break unless previous
            @scroll_y = previous
            remaining -= 1
          end
        end
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
      fold_style = Style.new(fg: @fold_gutter_fg, bg: @line_number_bg)
      placeholder_style = Style.new(fg: @fold_placeholder_fg, bg: @text_bg)
      cursor_style = Style.new(fg: @cursor_fg, bg: @cursor_bg)
      selection_style = Style.new(fg: @selection_fg, bg: @selection_bg)
      current_line_style = Style.new(fg: @text_fg, bg: @current_line_bg)

      fold_width = fold_gutter_width
      ln_width = line_number_width
      visible_rows = content_height
      doc_line = first_visible_from(@scroll_y)

      visible_rows.times do |row|
        y = @rect.y + row

        if doc_line >= @lines.size
          @rect.width.times do |x|
            buffer.set(@rect.x + x, y, ' ', text_style) if clip.contains?(@rect.x + x, y)
          end
          next
        end

        is_current_line = doc_line == @cursor.line
        base_style = is_current_line && focused? ? current_line_style : text_style
        x_offset = 0

        if fold_width > 0
          marker = fold_marker_at(doc_line) || ' '
          buffer.set(@rect.x, y, marker, fold_style) if clip.contains?(@rect.x, y)
          x_offset = 1
        end

        if @show_line_numbers
          num_str = (doc_line + 1).to_s.rjust(ln_width - 1)
          num_str.each_char_with_index do |char, ci|
            buffer.set(@rect.x + x_offset + ci, y, char, line_num_style) if clip.contains?(@rect.x + x_offset + ci, y)
          end
        end

        line = @lines[doc_line]
        content_x = @rect.x + gutter_width
        placeholder = fold_placeholder_at(doc_line)
        placeholder_start = line.size
        line_placeholder_style = is_current_line && focused? ? Style.new(fg: @fold_placeholder_fg, bg: @current_line_bg) : placeholder_style

        content_width.times do |col|
          text_col = @scroll_x + col
          x = content_x + col

          placeholder_index = text_col - placeholder_start
          in_placeholder = false
          placeholder_char = ' '
          if ph = placeholder
            if placeholder_index >= 0 && placeholder_index < ph.size
              in_placeholder = true
              placeholder_char = ph[placeholder_index]
            end
          end

          char = if in_placeholder
                   placeholder_char
                 elsif text_col < line.size
                   c = line[text_col]
                   c == '\t' ? ' ' : c
                 else
                   ' '
                 end

          style = if is_cursor_at?(doc_line, text_col) && focused? && !in_placeholder
                    cursor_style
                  elsif in_placeholder
                    line_placeholder_style
                  elsif in_selection?(doc_line, text_col)
                    selection_style
                  elsif style_callback = @on_cell_style
                    style_callback.call(doc_line, text_col, char, base_style)
                  else
                    base_style
                  end

          buffer.set(x, y, char, style) if clip.contains?(x, y)
        end

        following = next_visible_line(doc_line)
        break unless following
        doc_line = following
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

    def on_event(event : Event) : Bool
      return false unless focused?

      case event
      when PasteEvent
        paste(event.text)
        event.stop!
        return true
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
      alt = event.modifiers.alt?

      case event.key
      when .left?
        if ctrl || alt
          move_word_left(shift)
        else
          move_left(shift)
        end
        true
      when .right?
        if ctrl || alt
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
        insert_text("  ") # 2 spaces for tab
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
        rel_x, rel_y = event.relative_to(@rect)
        doc_line = document_line_at_visual_row(rel_y)

        if fold_gutter_width > 0 && rel_x < fold_gutter_width
          toggle_fold_at(doc_line)
          return true
        end

        text_x = rel_x - gutter_width + @scroll_x
        if doc_line < @lines.size
          if expand_fold_at_placeholder?(doc_line, text_x)
            return true
          end
          @cursor.line = doc_line
          @cursor.col = text_x.clamp(0, @lines[doc_line].size)
          @selection = nil
          mark_dirty!
        end
        true
      when MouseAction::Drag
        rel_x, rel_y = event.relative_to(@rect)
        text_x = rel_x - gutter_width + @scroll_x
        text_y = document_line_at_visual_row(rel_y).clamp(0, @lines.size - 1)

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
