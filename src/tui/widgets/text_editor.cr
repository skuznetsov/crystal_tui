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

    struct EditState
      getter text : String
      getter line : Int32
      getter col : Int32

      def initialize(@text : String, @line : Int32, @col : Int32)
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
    @undo_stack : Array(EditState) = [] of EditState
    @redo_stack : Array(EditState) = [] of EditState
    @last_edit_kind : Symbol? = nil
    @recording_undo : Bool = true
    @saved_text : String = ""
    @line_ending : String = "\n"

    UNDO_LIMIT = 100

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
    property show_scrollbar : Bool = true
    property scroll_lines : Int32 = 3
    property tab_size : Int32 = 4
    property word_wrap : Bool = false

    # Callbacks
    @on_change : Proc(Nil)?
    @on_save : Proc(Path, Nil)?
    @on_cell_style : Proc(Int32, Int32, Char, Style, Style)?
    @on_hyperclick : Proc(Int32, Int32, Modifiers, Nil)?
    @v_scrollbar : ScrollBar

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
      @v_scrollbar = ScrollBar.new(id ? "#{id}:v-scroll" : "text-editor:v-scroll", ScrollBar::Orientation::Vertical)
      @v_scrollbar.show_arrows = false
      @v_scrollbar.on_scroll { |offset| apply_scrollbar_offset(offset) }
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

    def on_hyperclick(&block : Int32, Int32, Modifiers -> Nil) : Nil
      @on_hyperclick = block
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

    def scroll_y : Int32
      @scroll_y
    end

    def scroll_view_by(lines : Int32) : Nil
      return if lines == 0 || @lines.empty?

      offset = visible_index_of(@scroll_y) + lines
      apply_scrollbar_offset(offset)
    end

    def v_scrollbar : ScrollBar
      @v_scrollbar
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
      @lines.join(@line_ending)
    end

    def text=(content : String) : Nil
      load_content(content)
      @cursor = Cursor.new
      @selection = nil
      @scroll_x = 0
      @scroll_y = 0
      @modified = true
      clear_undo_history
      clear_folds
      mark_dirty!
    end

    def load_file(path : Path) : Bool
      begin
        content = File.read(path.to_s)
        load_content(content)
        @path = path
        @title = path.basename
        @cursor = Cursor.new
        @selection = nil
        @scroll_x = 0
        @scroll_y = 0
        @modified = false
        @saved_text = text
        clear_undo_history
        clear_folds
        mark_dirty!
        true
      rescue ex
        @lines = ["Error loading file:", ex.message || "Unknown error"]
        @modified = false
        @saved_text = text
        clear_undo_history
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
        @saved_text = text
        @on_save.try &.call(path)
        mark_dirty!
        true
      rescue
        false
      end
    end

    # Replace the complete document as a single undoable edit.
    # This is intended for transformations such as replace-all and formatting.
    def replace_text(content : String) : Bool
      return false if content == text

      begin_edit(nil)
      line = @cursor.line
      col = @cursor.col
      load_content(content)
      @cursor.line = line.clamp(0, @lines.size - 1)
      @cursor.col = col.clamp(0, @lines[@cursor.line].size)
      @selection = nil
      text_changed
      true
    end

    def can_undo? : Bool
      !@undo_stack.empty?
    end

    def can_redo? : Bool
      !@redo_stack.empty?
    end

    def undo : Bool
      return false if @undo_stack.empty?

      @redo_stack << current_edit_state
      state = @undo_stack.pop
      @last_edit_kind = nil
      restore_edit_state(state)
      true
    end

    def redo : Bool
      return false if @redo_stack.empty?

      @undo_stack << current_edit_state
      state = @redo_stack.pop
      @last_edit_kind = nil
      restore_edit_state(state)
      true
    end

    # Editing operations
    def insert_char(char : Char, record_undo : Bool = true) : Nil
      has_sel = selection_active?
      if record_undo
        begin_edit(has_sel ? nil : :insert)
        @last_edit_kind = :insert if has_sel
      end
      delete_selection(false) if @selection
      line = @lines[@cursor.line]
      @lines[@cursor.line] = line[0, @cursor.col] + char + line[@cursor.col..]
      @cursor.col += 1
      text_changed
    end

    def insert_text(text : String) : Nil
      return if text.empty? && @selection.nil?

      begin_edit(nil)
      delete_selection(false) if @selection
      text.each_char { |c| insert_char(c, false) }
    end

    def insert_newline : Nil
      begin_edit(selection_active? ? nil : :newline)
      delete_selection(false) if @selection
      line = @lines[@cursor.line]
      @lines[@cursor.line] = line[0, @cursor.col]
      @lines.insert(@cursor.line + 1, line[@cursor.col..])
      @cursor.line += 1
      @cursor.col = 0
      text_changed
    end

    def backspace : Nil
      if selection_active?
        delete_selection
        return
      end

      return if @cursor.line == 0 && @cursor.col == 0

      begin_edit(:backspace)
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
      if selection_active?
        delete_selection
        return
      end

      line = @lines[@cursor.line]
      return if @cursor.col >= line.size && @cursor.line >= @lines.size - 1

      begin_edit(:delete)
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

    def delete_selection(record_undo : Bool = true) : Nil
      sel = @selection
      return unless sel

      begin_edit(nil) if record_undo
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

    def select_range(start_line : Int32, start_col : Int32, end_line : Int32, end_col : Int32, *, cursor_at_end : Bool = true) : Nil
      return if @lines.empty?

      start_line = start_line.clamp(0, @lines.size - 1)
      end_line = end_line.clamp(0, @lines.size - 1)
      start_col = start_col.clamp(0, @lines[start_line].size)
      end_col = end_col.clamp(0, @lines[end_line].size)
      @selection = Selection.new(start_line, start_col, end_line, end_col)
      if cursor_at_end
        @cursor.line = end_line
        @cursor.col = end_col
      else
        @cursor.line = start_line
        @cursor.col = start_col
      end
      ensure_cursor_visible
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
      normalized = normalize_newlines(text)
      return if normalized.empty? && @selection.nil?

      begin_edit(nil)
      delete_selection(false) if @selection
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

    private def selection_active? : Bool
      if sel = @selection
        !sel.empty?
      else
        false
      end
    end

    private def current_edit_state : EditState
      EditState.new(text, @cursor.line, @cursor.col)
    end

    private def clear_undo_history : Nil
      @undo_stack.clear
      @redo_stack.clear
      @last_edit_kind = nil
    end

    private def begin_edit(kind : Symbol?) : Nil
      return unless @recording_undo
      if kind && kind == @last_edit_kind && !@undo_stack.empty?
        return
      end

      @undo_stack << current_edit_state
      @undo_stack.shift if @undo_stack.size > UNDO_LIMIT
      @redo_stack.clear
      @last_edit_kind = kind
    end

    private def restore_edit_state(state : EditState) : Nil
      @recording_undo = false
      load_content(state.text)
      @cursor.line = state.line.clamp(0, @lines.size - 1)
      @cursor.col = state.col.clamp(0, @lines[@cursor.line].size)
      @selection = nil
      @modified = text != @saved_text
      clear_folds if @fold_ranges.any?
      @on_change.try &.call
      ensure_cursor_visible
      mark_dirty!
    ensure
      @recording_undo = true
    end

    private def load_content(content : String) : Nil
      @line_ending = detect_line_ending(content)
      @lines = content.split(@line_ending, remove_empty: false)
      @lines = [""] if @lines.empty?
    end

    private def detect_line_ending(content : String) : String
      crlf = content.index("\r\n")
      lf = content.index('\n')
      cr = content.index('\r')

      candidates = [] of {Int32, String}
      candidates << {crlf, "\r\n"} if crlf
      candidates << {lf, "\n"} if lf && (crlf.nil? || lf != crlf)
      candidates << {cr, "\r"} if cr && (crlf.nil? || cr != crlf)
      candidates.min_by?(&.[0]).try(&.[1]) || @line_ending
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

    private def scrollbar_width : Int32
      (@show_scrollbar && needs_scrollbar?) ? 1 : 0
    end

    private def needs_scrollbar? : Bool
      return false if @rect.height <= 0
      visible_line_count > @rect.height
    end

    private def gutter_width : Int32
      fold_gutter_width + line_number_width
    end

    private def content_width : Int32
      (@rect.width - gutter_width - scrollbar_width).clamp(0, Int32::MAX)
    end

    private def content_height : Int32
      @rect.height
    end

    private def visible_line_count : Int32
      count = 0
      @lines.size.times do |line|
        count += 1 unless line_hidden?(line)
      end
      count
    end

    private def visible_index_of(doc_line : Int32) : Int32
      index = 0
      limit = doc_line.clamp(0, @lines.size)
      limit.times do |line|
        index += 1 unless line_hidden?(line)
      end
      index
    end

    private def document_line_at_visible_index(visible_index : Int32) : Int32
      return 0 if @lines.empty?
      index = 0
      last_visible = 0
      @lines.size.times do |line|
        next if line_hidden?(line)
        last_visible = line
        return line if index == visible_index
        index += 1
      end
      last_visible
    end

    private def max_scrollbar_offset : Int32
      (visible_line_count - content_height).clamp(0, Int32::MAX)
    end

    private def apply_scrollbar_offset(offset : Int32) : Nil
      clamped = offset.clamp(0, max_scrollbar_offset)
      @scroll_y = document_line_at_visible_index(clamped)
      mark_dirty!
    end

    private def sync_scrollbar! : Nil
      @v_scrollbar.thumb_active_color = focused? ? Color.cyan : @v_scrollbar.thumb_color
      @v_scrollbar.rect = Rect.new(@rect.right - 1, @rect.y, 1, @rect.height)
      @v_scrollbar.update(visible_line_count, content_height, visible_index_of(@scroll_y))
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
      return if @lines.empty?

      # Vertical scrolling in document-line space, skipping hidden lines for height.
      if @cursor.line < @scroll_y || line_hidden?(@scroll_y)
        @scroll_y = first_visible_from(@cursor.line)
      elsif !cursor_in_viewport?
        # Put the cursor on the last visible row.
        @scroll_y = @cursor.line
        remaining = Math.max(content_height - 1, 0)
        while remaining > 0
          previous = previous_visible_line(@scroll_y)
          break unless previous
          @scroll_y = previous
          remaining -= 1
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

    private def cursor_in_viewport? : Bool
      return false if content_height <= 0

      line = first_visible_from(@scroll_y)
      content_height.times do
        return true if line == @cursor.line
        following = next_visible_line(line)
        return false unless following
        line = following
      end
      false
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

      if @show_scrollbar && needs_scrollbar?
        sync_scrollbar!
        @v_scrollbar.render(buffer, clip)
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
      case event
      when MouseEvent
        if handle_mouse(event)
          event.stop!
          return true
        end
      when PasteEvent
        return false unless focused?
        paste(event.text)
        event.stop!
        return true
      when KeyEvent
        return false unless focused?
        if handle_key(event)
          event.stop!
          return true
        end
      end

      false
    end

    private def handle_key(event : KeyEvent) : Bool
      if event.matches?("ctrl+shift+z") || event.matches?("ctrl+y")
        redo
        return true
      end
      if event.matches?("ctrl+z")
        undo
        return true
      end

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

        # Regular character input. Alt/Ctrl/Meta chords are shortcuts, not text.
        if char = event.char
          if char.printable? && !ctrl && !alt && !event.meta?
            insert_char(char)
            return true
          end
        end

        false
      end
    end

    private def handle_mouse(event : MouseEvent) : Bool
      return false unless event.in_rect?(@rect) || @v_scrollbar.dragging?

      if @show_scrollbar && needs_scrollbar?
        sync_scrollbar!
        if @v_scrollbar.hit_test?(event.x, event.y) || @v_scrollbar.dragging?
          focus unless focused?
          return @v_scrollbar.on_event(event)
        end
      end

      if event.button.wheel_up?
        scroll_view_by(-@scroll_lines)
        return true
      elsif event.button.wheel_down?
        scroll_view_by(@scroll_lines)
        return true
      end

      case event.action
      when MouseAction::Press
        focus unless focused?

        rel_x, rel_y = event.relative_to(@rect)
        doc_line = document_line_at_visual_row(rel_y)

        if fold_gutter_width > 0 && rel_x < fold_gutter_width
          toggle_fold_at(doc_line)
          return true
        end

        text_x = rel_x - gutter_width + @scroll_x
        if doc_line < @lines.size
          # iTerm2 SGR mouse reliably reports Shift; Ctrl is intercepted and
          # Option often does not set the Alt bit. Middle-click has no modifier.
          if hyperclick_mouse?(event)
            col = text_x.clamp(0, @lines[doc_line].size)
            @cursor.line = doc_line
            @cursor.col = col
            @selection = nil
            mark_dirty!
            @on_hyperclick.try(&.call(doc_line, col, event.modifiers))
            return true
          end

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
        focus unless focused?
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

    private def hyperclick_mouse?(event : MouseEvent) : Bool
      return true if event.button.middle?
      return false unless event.button.left?
      event.shift? || event.alt? || event.ctrl?
    end
  end
end
