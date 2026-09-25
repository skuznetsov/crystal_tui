# Text Editor widget - Full-featured text editing
require "set"

module Tui
  class TextEditor < Widget
    UNDO_LIMIT = 100

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

    # A position in both the editor's public character coordinates and UTF-16
    # coordinates suitable for protocol boundaries such as LSP.
    struct TextPosition
      getter line : Int32
      getter column : Int32
      getter utf16_column : Int32

      def initialize(@line : Int32, @column : Int32, @utf16_column : Int32)
      end
    end

    # Describes one logical mutation. Incremental ranges refer to the document
    # before the mutation and +text+ is the exact replacement stored afterward.
    # Full changes deliberately omit text so consumers materialize it only when
    # their compatibility boundary requires a complete document.
    struct TextChange
      getter start : TextPosition?
      getter finish : TextPosition?
      getter text : String

      def initialize(@start : TextPosition, @finish : TextPosition, @text : String)
      end

      private def initialize(@start : Nil, @finish : Nil, @text : String)
      end

      def self.full : TextChange
        new(nil, nil, "")
      end

      def incremental? : Bool
        !@start.nil?
      end

      def full? : Bool
        !incremental?
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
      getter snapshot : PieceTreeBuffer::Snapshot?
      getter line : Int32
      getter col : Int32
      getter line_ending : String
      getter view_id : UInt64
      @legacy_text : String?

      def initialize(snapshot : PieceTreeBuffer::Snapshot, @line : Int32, @col : Int32, @line_ending : String, @view_id : UInt64 = 0_u64)
        @snapshot = snapshot
        @legacy_text = nil
      end

      # Compatibility constructor for callers that used EditState directly.
      # TextEditor-created history entries always use structural snapshots.
      def initialize(text : String, @line : Int32, @col : Int32)
        @snapshot = nil
        @line_ending = "\n"
        @view_id = 0_u64
        @legacy_text = text
      end

      # Preserve the historical EditState API without retaining a duplicate
      # document string in each undo entry.
      def text : String
        @legacy_text || @snapshot.not_nil!.text
      end
    end

    # Shared text and file state for one logical document. Each TextEditor
    # keeps its own cursor, selection, viewport, folds, and render callbacks.
    class Document
      getter buffer : PieceTreeBuffer
      property saved_snapshot : PieceTreeBuffer::Snapshot
      property saved_line_ending : String
      property modified : Bool
      property path : Path?
      property title : String
      property undo_stack : Array(EditState)
      property redo_stack : Array(EditState)
      property last_edit_kind : Symbol?
      property last_edit_view_id : UInt64?
      property recording_undo : Bool
      property line_ending : String

      @on_text_change : Proc(TextChange, Nil)?
      @on_save : Proc(Path, Nil)?
      @views : Hash(UInt64, TextEditor) = {} of UInt64 => TextEditor
      @next_view_id : UInt64 = 0_u64

      def initialize
        @buffer = PieceTreeBuffer.new
        @saved_snapshot = @buffer.snapshot
        @saved_line_ending = "\n"
        @modified = false
        @path = nil
        @title = "Untitled"
        @undo_stack = [] of EditState
        @redo_stack = [] of EditState
        @last_edit_kind = nil
        @last_edit_view_id = nil
        @recording_undo = true
        @line_ending = "\n"
      end

      def modified? : Bool
        @modified
      end

      def title_with_status : String
        @modified ? "#{@title} *" : @title
      end

      # There is one document-level publisher, regardless of how many views
      # are attached. Existing TextEditor callback methods delegate here.
      def on_text_change(&block : TextChange -> Nil) : Nil
        @on_text_change = block
      end

      def on_save(&block : Path -> Nil) : Nil
        @on_save = block
      end

      def publish_text_change(change : TextChange, origin_view_id : UInt64) : Nil
        begin
          @on_text_change.try &.call(change)
        ensure
          refresh_views(origin_view_id, change)
        end
      end

      def publish_save(path : Path) : Nil
        @on_save.try &.call(path)
      end

      def next_view_id : UInt64
        @next_view_id &+= 1_u64
        @next_view_id
      end

      def attach(view_id : UInt64, view : TextEditor) : Nil
        @views[view_id] = view
      end

      def detach(view_id : UInt64) : Nil
        @views.delete(view_id)
      end

      def view(view_id : UInt64) : TextEditor?
        @views[view_id]?
      end

      def refresh_views(origin_view_id : UInt64? = nil, change : TextChange? = nil) : Nil
        @views.to_a.each do |view_id, view|
          next unless @views[view_id]? == view
          view.document_refreshed(origin_view_id, change)
        end
      end
    end

    @buffer : PieceTreeBuffer
    @document : Document
    @view_id : UInt64
    # Kept as a non-nil inherited alias for existing TextEditor subclasses.
    # Shared policy is authoritative in Document; document_refreshed syncs it.
    @line_ending : String
    @cursor : Cursor = Cursor.new
    @selection : Selection?
    @scroll_x : Int32 = 0
    @scroll_y : Int32 = 0
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
    property show_scrollbar : Bool = true
    property scroll_lines : Int32 = 3
    property tab_size : Int32 = 4
    property word_wrap : Bool = false

    # Callbacks
    @on_change : Proc(Nil)?
    @on_cell_style : Proc(Int32, Int32, Char, Style, Style)?
    @on_hyperclick : Proc(Int32, Int32, Modifiers, Nil)?
    @v_scrollbar : ScrollBar

    def initialize(id : String? = nil, document : Document = Document.new)
      super(id)
      @document = document
      @buffer = @document.buffer
      @view_id = @document.next_view_id
      @line_ending = @document.line_ending
      @focusable = true
      @v_scrollbar = ScrollBar.new(id ? "#{id}:v-scroll" : "text-editor:v-scroll", ScrollBar::Orientation::Vertical)
      @v_scrollbar.show_arrows = false
      @v_scrollbar.on_scroll { |offset| apply_scrollbar_offset(offset) }
      @document.attach(@view_id, self)
    end

    getter document : Document

    def line_ending : String
      @document.line_ending
    end

    def line_ending=(value : String) : Nil
      @document.line_ending = value
      @line_ending = value
    end

    # Remove this view from document notifications and view-aware undo cursor
    # restoration. The shared document and its event publishers remain alive.
    def detach : Nil
      @document.detach(@view_id)
    end

    def on_change(&block : -> Nil) : Nil
      @on_change = block
    end

    def on_text_change(&block : TextChange -> Nil) : Nil
      @document.on_text_change(&block)
    end

    def on_save(&block : Path -> Nil) : Nil
      @document.on_save(&block)
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
      return false if line < 0 || line >= line_count
      start = line_length(line)
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
      return if lines == 0 || line_count == 0

      offset = visible_index_of(@scroll_y) + lines
      apply_scrollbar_offset(offset)
    end

    def v_scrollbar : ScrollBar
      @v_scrollbar
    end

    def title : String
      @document.title_with_status
    end

    def modified? : Bool
      @document.modified?
    end

    def path : Path?
      @document.path
    end

    # Returns a materialized snapshot. Mutate the editor through its edit API.
    def lines : Array(String)
      Array.new(line_count) { |index| line_at(index) }
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
      return if line_count == 0

      @cursor.line = line.clamp(0, line_count - 1)
      @cursor.col = col.clamp(0, line_length(@cursor.line))
      @selection = nil
      ensure_cursor_visible
      mark_dirty!
    end

    def text : String
      @buffer.text
    end

    # Stream the current document bytes directly from the piece tree.
    def write_to(io : IO) : Int32
      @buffer.write_to(io)
    end

    def text=(content : String) : Nil
      load_content(content)
      @cursor = Cursor.new
      @selection = nil
      @scroll_x = 0
      @scroll_y = 0
      @document.modified = true
      clear_undo_history
      clear_folds
      @document.refresh_views(nil, TextChange.full)
    end

    def load_file(path : Path) : Bool
      begin
        content = File.read(path.to_s)
        apply_content_as_saved(content, path, preserve_history: false, notify: false)
        true
      rescue ex
        load_content("Error loading file:\n#{ex.message || "Unknown error"}")
        @document.modified = false
        @document.saved_snapshot = @buffer.snapshot
        @document.saved_line_ending = @document.line_ending
        clear_undo_history
        clear_folds
        @document.refresh_views(nil, TextChange.full)
        false
      end
    end

    # Load exact content as the saved baseline. By default this is an initial
    # load and clears history; callers accepting an external revision should
    # use `reload_as_saved`, which preserves the current structural root.
    def load_content_as_saved(content : String, path : Path? = nil, *, preserve_history : Bool = false) : Bool
      apply_content_as_saved(content, path, preserve_history: preserve_history, notify: true)
    end

    # Accept externally reloaded content as the clean baseline while retaining
    # the current piece-tree root as one undoable history entry.
    def reload_as_saved(content : String, path : Path? = nil) : Bool
      load_content_as_saved(content, path, preserve_history: true)
    end

    # Accept the existing piece-tree root as the saved baseline. This is used
    # when an independently validated disk revision has identical bytes, so a
    # no-op reload does not create a dirty undo entry containing the same text.
    def accept_current_as_saved(path : Path? = nil) : Bool
      if path
        @document.path = path
        @document.title = path.basename
      end
      @document.modified = false
      @document.saved_snapshot = @buffer.snapshot
      @document.saved_line_ending = @document.line_ending
      @document.refresh_views
      true
    end

    def save : Bool
      return false unless path = @document.path
      save_as(path)
    end

    # Save the active path after the caller approves the resolved target just
    # before the temporary file is renamed into place.
    def save_checked(&guard : Path -> Bool) : Bool
      return false unless path = @document.path
      save_as_checked(path, &guard)
    end

    # Save the active path with validation immediately before and after the
    # atomic replacement. The editor becomes clean only after both predicates
    # accept the resolved physical target.
    def save_checked(before_rename : Proc(Path, Bool), after_rename : Proc(Path, Bool)) : Bool
      return false unless path = @document.path
      save_as_checked(path, before_rename, after_rename)
    end

    def save_as(path : Path) : Bool
      save_as_checked(path) { |_target| true }
    end

    # Save +path+ with a final, pre-rename predicate. A false predicate leaves
    # the target and editor state untouched.
    def save_as_checked(path : Path, &guard : Path -> Bool) : Bool
      save_as_checked(path, guard, ->(_target : Path) { true })
    end

    # Save +path+ with predicates around the atomic replacement. A failed
    # pre-rename predicate leaves the target untouched; a failed post-rename
    # predicate leaves the editor dirty and suppresses the save callback.
    def save_as_checked(path : Path, before_rename : Proc(Path, Bool), after_rename : Proc(Path, Bool)) : Bool
      # A retired widget may still be held by an asynchronous callback. It
      # must not write an obsolete document over the live file.
      return false unless @document.view(@view_id).try(&.same?(self))

      begin
        target = atomic_write(path, before_rename) { |io| @buffer.write_to(io) }
        return false unless target
        return false unless after_rename.call(target)
        @document.path = path
        @document.title = path.basename
        @document.modified = false
        @document.saved_snapshot = @buffer.snapshot
        @document.saved_line_ending = @document.line_ending
        @document.publish_save(path)
        @document.refresh_views
        true
      rescue
        false
      end
    end

    private def atomic_write(path : Path, guard : Proc(Path, Bool), & : IO ->) : Path?
      target = if File.info?(path, follow_symlinks: false).try(&.symlink?)
                 Path.new(File.realpath(path))
               else
                 path.expand
               end
      permissions = File.info?(target).try(&.permissions.to_i)
      parent = target.parent
      temporary = File.tempfile(".#{target.basename}.adamantine-", nil, dir: parent.to_s)
      temporary_path = Path.new(temporary.path)
      renamed = false

      begin
        yield temporary
        temporary.flush
        File.chmod(temporary_path, permissions) if permissions
        temporary.fsync
        temporary.close
        return nil unless guard.call(target)
        File.rename(temporary_path, target)
        renamed = true

        begin
          File.open(parent.to_s) { |directory| directory.fsync }
        rescue
          # Some platforms do not permit opening directories. The file itself
          # is already durable and atomically visible at this point.
        end
        target
      ensure
        temporary.close unless temporary.closed?
        File.delete(temporary_path) if !renamed && File.exists?(temporary_path)
      end
    end

    # Replace the complete document as a single undoable edit.
    # This is intended for transformations such as replace-all and formatting.
    def replace_text(content : String) : Bool
      return false if @buffer.same_text?(content)

      begin_edit(nil)
      line = @cursor.line
      col = @cursor.col
      @document.line_ending = detect_line_ending(content)
      @buffer.replace_all(content)
      @cursor.line = line.clamp(0, line_count - 1)
      @cursor.col = col.clamp(0, line_length(@cursor.line))
      @selection = nil
      text_changed(TextChange.full)
      true
    end

    def can_undo? : Bool
      !@document.undo_stack.empty?
    end

    def can_redo? : Bool
      !@document.redo_stack.empty?
    end

    def undo : Bool
      return false if @document.undo_stack.empty?

      @document.redo_stack << current_edit_state
      state = @document.undo_stack.pop
      @document.last_edit_kind = nil
      @document.last_edit_view_id = nil
      restore_edit_state(state)
      true
    end

    def redo : Bool
      return false if @document.redo_stack.empty?

      @document.undo_stack << current_edit_state
      state = @document.redo_stack.pop
      @document.last_edit_kind = nil
      @document.last_edit_view_id = nil
      restore_edit_state(state)
      true
    end

    # Editing operations
    def insert_char(char : Char, record_undo : Bool = true) : Nil
      has_sel = selection_active?
      if record_undo
        begin_edit(has_sel ? nil : :insert)
        if has_sel
          @document.last_edit_kind = :insert
          @document.last_edit_view_id = @view_id
        end
      end
      selection_change = delete_selection_content(false) if @selection
      start_position = selection_change.try(&.[0]) || current_text_position
      finish_position = selection_change.try(&.[1]) || start_position
      exact = selection_change.try(&.[2]) != false
      logical = normalize_newlines(char.to_s)
      offset = byte_offset(@cursor.line, @cursor.col)
      inserted = encode_newlines(logical, offset)
      @buffer.insert(offset, inserted)
      advance_cursor_by(logical)
      text_changed(exact ? TextChange.new(start_position, finish_position, inserted) : TextChange.full)
    end

    def insert_text(text : String) : Nil
      return if text.empty? && @selection.nil?

      begin_edit(nil)
      selection_change = delete_selection_content(false) if @selection
      start_position = selection_change.try(&.[0]) || current_text_position
      finish_position = selection_change.try(&.[1]) || start_position
      exact = selection_change.try(&.[2]) != false
      if text.empty?
        text_changed(exact ? TextChange.new(start_position, finish_position, "") : TextChange.full)
        return
      end

      normalized = normalize_newlines(text)
      offset = byte_offset(@cursor.line, @cursor.col)
      inserted = encode_newlines(normalized, offset)
      @buffer.insert(offset, inserted)
      advance_cursor_by(normalized)
      text_changed(exact ? TextChange.new(start_position, finish_position, inserted) : TextChange.full)
    end

    def insert_newline : Nil
      begin_edit(selection_active? ? nil : :newline)
      selection_change = delete_selection_content(false) if @selection
      start_position = selection_change.try(&.[0]) || current_text_position
      finish_position = selection_change.try(&.[1]) || start_position
      exact = selection_change.try(&.[2]) != false
      offset = byte_offset(@cursor.line, @cursor.col)
      inserted = encode_newlines("\n", offset)
      @buffer.insert(offset, inserted)
      @cursor.line += 1
      @cursor.col = 0
      text_changed(exact ? TextChange.new(start_position, finish_position, inserted) : TextChange.full)
    end

    def backspace : Nil
      if selection_active?
        delete_selection
        return
      end

      return if @cursor.line == 0 && @cursor.col == 0

      begin_edit(:backspace)
      if @cursor.col > 0
        finish_position = current_text_position
        start_position = text_position(@cursor.line, @cursor.col - 1)
        char = @buffer.character_at(@cursor.line, @cursor.col - 1).not_nil!
        length = char.bytesize
        offset = byte_offset(@cursor.line, @cursor.col) - length
        exact = delete_buffer_range(offset, length)
        @cursor.col -= 1
        text_changed(exact ? TextChange.new(start_position, finish_position, "") : TextChange.full)
      elsif @cursor.line > 0
        # Join with previous line
        finish_position = current_text_position
        prev_line = @cursor.line - 1
        prev_len = line_length(prev_line)
        start_position = text_position(prev_line, prev_len)
        offset = byte_offset(prev_line, prev_len)
        finish = @buffer.line_start_offset(@cursor.line)
        exact = delete_buffer_range(offset, finish - offset)
        @cursor.line -= 1
        @cursor.col = prev_len
        text_changed(exact ? TextChange.new(start_position, finish_position, "") : TextChange.full)
      end
    end

    def delete : Nil
      if selection_active?
        delete_selection
        return
      end

      length = line_length(@cursor.line)
      return if @cursor.col >= length && @cursor.line >= line_count - 1

      begin_edit(:delete)
      if @cursor.col < length
        start_position = current_text_position
        finish_position = text_position(@cursor.line, @cursor.col + 1)
        char = @buffer.character_at(@cursor.line, @cursor.col).not_nil!
        offset = byte_offset(@cursor.line, @cursor.col)
        exact = delete_buffer_range(offset, char.bytesize)
        text_changed(exact ? TextChange.new(start_position, finish_position, "") : TextChange.full)
      elsif @cursor.line < line_count - 1
        # Join with next line
        start_position = current_text_position
        finish_position = text_position(@cursor.line + 1, 0)
        offset = byte_offset(@cursor.line, length)
        finish = @buffer.line_start_offset(@cursor.line + 1)
        exact = delete_buffer_range(offset, finish - offset)
        text_changed(exact ? TextChange.new(start_position, finish_position, "") : TextChange.full)
      end
    end

    def delete_selection(record_undo : Bool = true) : Nil
      change = delete_selection_content(record_undo)
      return unless change

      text_changed(change[2] ? TextChange.new(change[0], change[1], "") : TextChange.full)
    end

    def select_all : Nil
      @selection = Selection.new(0, 0, line_count - 1, line_length(line_count - 1))
      mark_dirty!
    end

    def select_range(start_line : Int32, start_col : Int32, end_line : Int32, end_col : Int32, *, cursor_at_end : Bool = true) : Nil
      return if line_count == 0

      start_line = start_line.clamp(0, line_count - 1)
      end_line = end_line.clamp(0, line_count - 1)
      start_col = start_col.clamp(0, line_length(start_line))
      end_col = end_col.clamp(0, line_length(end_line))
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
      start_offset = byte_offset(sel.start_line, sel.start_col)
      end_offset = byte_offset(sel.end_line, sel.end_col)
      normalize_newlines(@buffer.slice(start_offset, end_offset - start_offset))
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
      selection_change = delete_selection_content(false) if @selection
      start_position = selection_change.try(&.[0]) || current_text_position
      finish_position = selection_change.try(&.[1]) || start_position
      exact = selection_change.try(&.[2]) != false
      if normalized.empty?
        text_changed(exact ? TextChange.new(start_position, finish_position, "") : TextChange.full)
        return
      end

      offset = byte_offset(@cursor.line, @cursor.col)
      inserted = encode_newlines(normalized, offset)
      @buffer.insert(offset, inserted)
      advance_cursor_by(normalized)

      text_changed(exact ? TextChange.new(start_position, finish_position, inserted) : TextChange.full)
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
        @cursor.col = line_length(@cursor.line)
      end

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_right(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      if @cursor.col < line_length(@cursor.line)
        @cursor.col += 1
      elsif @cursor.line < line_count - 1
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
        @cursor.col = @cursor.col.clamp(0, line_length(@cursor.line))
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
        @cursor.col = @cursor.col.clamp(0, line_length(@cursor.line))
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
        @cursor.col = line_length(@cursor.line)
      else
        @cursor.col = @buffer.previous_word_column(@cursor.line, @cursor.col)
      end

      update_selection_end if with_selection
      ensure_cursor_visible
      mark_dirty!
    end

    def move_word_right(with_selection : Bool = false) : Nil
      update_selection_start if with_selection && !@selection
      clear_selection unless with_selection

      length = line_length(@cursor.line)
      if @cursor.col >= length && @cursor.line < line_count - 1
        @cursor.line += 1
        @cursor.col = 0
      else
        @cursor.col = @buffer.next_word_column(@cursor.line, @cursor.col)
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

      @cursor.col = line_length(@cursor.line)

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
      @cursor.line = line_count - 1
      @cursor.col = line_length(@cursor.line)
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
      @cursor.col = @cursor.col.clamp(0, line_length(@cursor.line))
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
      @cursor.col = @cursor.col.clamp(0, line_length(@cursor.line))
      @selection = nil
      ensure_cursor_visible
      mark_dirty!
    end

    def goto_line(line : Int32) : Nil
      @cursor.line = (line - 1).clamp(0, line_count - 1)
      @cursor.col = 0
      @selection = nil
      ensure_cursor_visible
      mark_dirty!
    end

    private def text_changed(change : TextChange) : Nil
      @document.modified = true
      notify_text_change(change)
    end

    private def notify_text_change(change : TextChange) : Nil
      @document.publish_text_change(change, @view_id)
    end

    # Called by the shared document after any view mutates its text. Keep this
    # view's local position valid and repaint it without replacing its cursor
    # with the editing view's cursor.
    def document_refreshed(origin_view_id : UInt64? = nil, change : TextChange? = nil) : Nil
      @line_ending = @document.line_ending
      if origin_view_id != @view_id
        if update = change
          if update.incremental?
            rebase_view_state(update)
          else
            @selection = nil
            clear_folds
          end
        end
      end
      previous_cursor = {@cursor.line, @cursor.col}
      @cursor.line = @cursor.line.clamp(0, line_count - 1)
      @cursor.col = @cursor.col.clamp(0, line_length(@cursor.line))
      cursor_clamped = previous_cursor != {@cursor.line, @cursor.col}
      @scroll_y = @scroll_y.clamp(0, line_count - 1)
      if origin_view_id == @view_id
        clear_folds if @fold_ranges.any? || @collapsed_folds.any?
      elsif @fold_ranges.any? { |range| range.end_line >= line_count }
        set_fold_ranges(@fold_ranges.select { |range| range.end_line < line_count })
      end
      if selection = @selection
        @selection = nil unless valid_position?(selection.start_line, selection.start_col) &&
                                valid_position?(selection.end_line, selection.end_col)
      end
      @on_change.try &.call
      ensure_cursor_visible if origin_view_id == @view_id || cursor_clamped
      mark_dirty!
    end

    private def rebase_view_state(change : TextChange) : Nil
      return unless start = change.start
      return unless finish = change.finish

      change_start = {start.line, start.column}
      change_finish = {finish.line, finish.column}
      inserted_end = position_after_text(change_start, change.text)

      @cursor.line, @cursor.col = rebase_coordinate(
        {@cursor.line, @cursor.col}, change_start, change_finish, inserted_end, true
      )

      if selection = @selection
        rebase_selection(selection, change_start, change_finish, inserted_end)
      end

      rebase_fold_ranges(change_start, change_finish, inserted_end)
    end

    private def rebase_selection(selection : Selection, change_start : Tuple(Int32, Int32), change_finish : Tuple(Int32, Int32), inserted_end : Tuple(Int32, Int32)) : Nil
      normalized = selection.normalize
      selection_start = {normalized.start_line, normalized.start_col}
      selection_end = {normalized.end_line, normalized.end_col}
      insertion = change_start == change_finish

      overlaps = if insertion
                   compare_coordinates(change_start, selection_start) > 0 &&
                     compare_coordinates(change_start, selection_end) < 0
                 else
                   compare_coordinates(change_start, selection_end) < 0 &&
                     compare_coordinates(change_finish, selection_start) > 0
                 end
      if overlaps
        @selection = nil
        return
      end

      rebased_start = rebase_coordinate(selection_start, change_start, change_finish, inserted_end, true)
      end_right_bias = !(insertion && change_start == selection_end)
      rebased_end = rebase_coordinate(selection_end, change_start, change_finish, inserted_end, end_right_bias)

      if compare_coordinates({selection.start_line, selection.start_col}, {selection.end_line, selection.end_col}) > 0
        @selection = Selection.new(rebased_end[0], rebased_end[1], rebased_start[0], rebased_start[1])
      else
        @selection = Selection.new(rebased_start[0], rebased_start[1], rebased_end[0], rebased_end[1])
      end
    end

    private def rebase_fold_ranges(change_start : Tuple(Int32, Int32), change_finish : Tuple(Int32, Int32), inserted_end : Tuple(Int32, Int32)) : Nil
      return if @fold_ranges.empty?

      line_delta = inserted_end[0] - change_finish[0]
      changed = false
      ranges = [] of FoldRange
      collapsed = Set(Int32).new

      @fold_ranges.each do |range|
        if change_finish[0] < range.start_line
          start_line = range.start_line + line_delta
          end_line = range.end_line + line_delta
          next_range = FoldRange.new(start_line, end_line)
          ranges << next_range
          collapsed.add(start_line) if @collapsed_folds.includes?(range.start_line)
          changed ||= line_delta != 0
        elsif change_start[0] > range.end_line
          ranges << range
          collapsed.add(range.start_line) if @collapsed_folds.includes?(range.start_line)
        else
          changed = true
        end
      end

      return unless changed

      @fold_ranges = ranges
      @fold_starts = {} of Int32 => FoldRange
      @fold_ranges.each do |range|
        existing = @fold_starts[range.start_line]?
        if existing.nil? || range.end_line > existing.end_line
          @fold_starts[range.start_line] = range
        end
      end
      @collapsed_folds = collapsed
      rebuild_hidden_lines!
    end

    private def rebase_coordinate(position : Tuple(Int32, Int32), change_start : Tuple(Int32, Int32), change_finish : Tuple(Int32, Int32), inserted_end : Tuple(Int32, Int32), right_bias : Bool) : Tuple(Int32, Int32)
      return position if compare_coordinates(position, change_start) < 0

      if change_start == change_finish
        return position if position == change_start && !right_bias
        return position_after_change(position, change_finish, inserted_end)
      end

      return position if position == change_start
      return change_start if compare_coordinates(position, change_finish) < 0

      position_after_change(position, change_finish, inserted_end)
    end

    private def position_after_change(position : Tuple(Int32, Int32), old_end : Tuple(Int32, Int32), new_end : Tuple(Int32, Int32)) : Tuple(Int32, Int32)
      if position[0] == old_end[0]
        {new_end[0], new_end[1] + position[1] - old_end[1]}
      else
        {position[0] + new_end[0] - old_end[0], position[1]}
      end
    end

    private def position_after_text(start : Tuple(Int32, Int32), text : String) : Tuple(Int32, Int32)
      line = start[0]
      column = start[1]
      pending_carriage_return = false

      text.each_char do |char|
        if pending_carriage_return
          line += 1
          column = 0
          pending_carriage_return = false
          next if char == '\n'
        end

        if char == '\r'
          pending_carriage_return = true
        elsif char == '\n'
          line += 1
          column = 0
        else
          column += 1
        end
      end

      if pending_carriage_return
        line += 1
        column = 0
      end
      {line, column}
    end

    private def compare_coordinates(left : Tuple(Int32, Int32), right : Tuple(Int32, Int32)) : Int32
      return left[0] <=> right[0] unless left[0] == right[0]
      left[1] <=> right[1]
    end

    private def selection_active? : Bool
      if sel = @selection
        !sel.empty?
      else
        false
      end
    end

    private def valid_position?(line : Int32, col : Int32) : Bool
      line >= 0 && line < line_count && col >= 0 && col <= line_length(line)
    end

    private def current_edit_state : EditState
      EditState.new(@buffer.snapshot, @cursor.line, @cursor.col, @document.line_ending, @view_id)
    end

    private def clear_undo_history : Nil
      @document.undo_stack.clear
      @document.redo_stack.clear
      @document.last_edit_kind = nil
      @document.last_edit_view_id = nil
    end

    private def begin_edit(kind : Symbol?) : Nil
      return unless @document.recording_undo
      if kind && kind == @document.last_edit_kind && @view_id == @document.last_edit_view_id && !@document.undo_stack.empty?
        return
      end

      @document.undo_stack << current_edit_state
      @document.undo_stack.shift if @document.undo_stack.size > UNDO_LIMIT
      @document.redo_stack.clear
      @document.last_edit_kind = kind
      @document.last_edit_view_id = @view_id
    end

    private def restore_edit_state(state : EditState) : Nil
      @document.recording_undo = false
      if snapshot = state.snapshot
        @buffer.restore(snapshot)
        @document.line_ending = state.line_ending
      else
        load_content(state.text)
      end
      view = @document.view(state.view_id) || self
      view.set_cursor(state.line, state.col)
      @document.modified = !saved_state?
      notify_text_change(TextChange.full)
    ensure
      @document.recording_undo = true
    end

    private def load_content(content : String) : Nil
      @document.line_ending = detect_line_ending(content)
      @buffer.reset(content)
    end

    private def apply_content_as_saved(content : String, path : Path?, *, preserve_history : Bool, notify : Bool) : Bool
      raise ArgumentError.new("buffer text must be valid UTF-8") unless content.valid_encoding?

      if preserve_history
        old_line = @cursor.line
        old_col = @cursor.col
        # External revisions can contain megabytes of new source bytes. Keep
        # exactly the current editor root as OURS so repeated reloads cannot
        # retain an unbounded chain of complete external revisions.
        clear_undo_history
        begin_edit(nil)
        @document.line_ending = detect_line_ending(content)
        @buffer.replace_all(content)
        @cursor.line = old_line.clamp(0, line_count - 1)
        @cursor.col = old_col.clamp(0, line_length(@cursor.line))
        @selection = nil
      else
        load_content(content)
        @cursor = Cursor.new
        @selection = nil
        @scroll_x = 0
        @scroll_y = 0
        clear_undo_history
      end

      if path
        @document.path = path
        @document.title = path.basename
      end
      @document.modified = false
      @document.saved_snapshot = @buffer.snapshot
      @document.saved_line_ending = @document.line_ending
      clear_folds
      ensure_cursor_visible
      if notify
        notify_text_change(TextChange.full)
      else
        @document.refresh_views(nil, TextChange.full)
      end
      true
    end

    # TextEditor cursor columns are character indexes while PieceTreeBuffer
    # edit offsets are UTF-8 byte indexes. Keep that conversion in one place.
    private def line_count : Int32
      @buffer.line_count
    end

    private def line_at(index : Int32) : String
      @buffer.line(index)
    end

    private def line_length(index : Int32) : Int32
      @buffer.line_character_length(index)
    end

    private def byte_offset(line : Int32, col : Int32) : Int32
      start = @buffer.line_start_offset(line)
      @buffer.byte_offset_at_codepoint(@buffer.codepoint_index_at_offset(start) + col)
    end

    private def text_position(line : Int32, col : Int32) : TextPosition
      TextPosition.new(line, col, @buffer.line_utf16_column(line, col))
    end

    private def current_text_position : TextPosition
      text_position(@cursor.line, @cursor.col)
    end

    private def delete_selection_content(record_undo : Bool) : Tuple(TextPosition, TextPosition, Bool)?
      sel = @selection
      return nil unless sel

      begin_edit(nil) if record_undo
      sel = sel.normalize
      start_position = text_position(sel.start_line, sel.start_col)
      finish_position = text_position(sel.end_line, sel.end_col)
      start_offset = byte_offset(sel.start_line, sel.start_col)
      end_offset = byte_offset(sel.end_line, sel.end_col)
      exact = delete_buffer_range(start_offset, end_offset - start_offset)

      @cursor.line = sel.start_line
      @cursor.col = sel.start_col
      @selection = nil
      {start_position, finish_position, exact}
    end

    private def encode_newlines(content : String, offset : Int32) : String
      return content unless content.includes?('\n')

      ending = @document.line_ending
      previous_is_cr = offset > 0 && @buffer.byte_at_offset(offset - 1) == '\r'.ord
      next_is_lf = @buffer.byte_at_offset(offset) == '\n'.ord
      if (content.starts_with?("\n") && ending.starts_with?("\n") && previous_is_cr) ||
         (content.ends_with?("\n") && ending.ends_with?("\r") && next_is_lf)
        ending = "\r\n"
      end
      content.gsub("\n", ending)
    end

    # Deleting content between a lone CR and a lone LF must not silently merge
    # two untouched logical line endings into one CRLF sequence.
    private def delete_buffer_range(offset : Int32, length : Int32) : Bool
      finish = offset + length
      joins_crlf = offset > 0 && finish < @buffer.byte_length &&
                   @buffer.byte_at_offset(offset - 1) == '\r'.ord &&
                   @buffer.byte_at_offset(finish) == '\n'.ord
      if joins_crlf
        @buffer.delete(offset, length + 1)
        replacement = @document.line_ending == "\n" ? "\n\n" : "\r\n"
        @buffer.insert(offset, replacement)
        false
      else
        @buffer.delete(offset, length)
        true
      end
    end

    private def advance_cursor_by(content : String) : Nil
      content.each_char do |char|
        if char == '\n'
          @cursor.line += 1
          @cursor.col = 0
        else
          @cursor.col += 1
        end
      end
    end

    private def saved_state? : Bool
      @document.line_ending == @document.saved_line_ending && @buffer.same_state?(@document.saved_snapshot)
    end

    private def detect_line_ending(content : String) : String
      crlf = content.index("\r\n")
      lf = content.index('\n')
      cr = content.index('\r')

      candidates = [] of {Int32, String}
      candidates << {crlf, "\r\n"} if crlf
      candidates << {lf, "\n"} if lf && (crlf.nil? || lf != crlf)
      candidates << {cr, "\r"} if cr && (crlf.nil? || cr != crlf)
      candidates.min_by?(&.[0]).try(&.[1]) || @document.line_ending
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
      @show_line_numbers ? (line_count.to_s.size + 1) : 0
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
      return line_count if @collapsed_folds.empty?

      count = 0
      line_count.times do |line|
        count += 1 unless line_hidden?(line)
      end
      count
    end

    private def visible_index_of(doc_line : Int32) : Int32
      return doc_line.clamp(0, line_count) if @collapsed_folds.empty?

      index = 0
      limit = doc_line.clamp(0, line_count)
      limit.times do |line|
        index += 1 unless line_hidden?(line)
      end
      index
    end

    private def document_line_at_visible_index(visible_index : Int32) : Int32
      return 0 if line_count == 0
      return visible_index.clamp(0, line_count - 1) if @collapsed_folds.empty?

      index = 0
      last_visible = 0
      line_count.times do |line|
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
      @hidden_lines = Array.new(line_count, false)
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
      while line < line_count
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
      line = from.clamp(0, Math.max(line_count - 1, 0))
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
      return if line_count == 0

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

        if doc_line >= line_count
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

        full_length = line_length(doc_line)
        visible_line = if @scroll_x <= full_length
                         @buffer.line_slice(doc_line, @scroll_x, content_width)
                       else
                         ""
                       end
        content_x = @rect.x + gutter_width
        placeholder = fold_placeholder_at(doc_line)
        placeholder_start = full_length
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
                 elsif text_col < full_length
                   c = visible_line[col]
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
        if doc_line < line_count
          # iTerm2 SGR mouse reliably reports Shift; Ctrl is intercepted and
          # Option often does not set the Alt bit. Middle-click has no modifier.
          if hyperclick_mouse?(event)
            col = text_x.clamp(0, line_length(doc_line))
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
          @cursor.col = text_x.clamp(0, line_length(doc_line))
          @selection = nil
          mark_dirty!
        end
        true
      when MouseAction::Drag
        focus unless focused?
        rel_x, rel_y = event.relative_to(@rect)
        text_x = rel_x - gutter_width + @scroll_x
        text_y = document_line_at_visual_row(rel_y).clamp(0, line_count - 1)

        unless @selection
          @selection = Selection.new(@cursor.line, @cursor.col, @cursor.line, @cursor.col)
        end

        @cursor.line = text_y
        @cursor.col = text_x.clamp(0, line_length(text_y))
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
