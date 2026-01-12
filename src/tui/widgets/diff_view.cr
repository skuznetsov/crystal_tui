# DiffView - Rich diff viewer widget with syntax highlighting and collapse/expand
#
# Features:
# - Unified diff parsing
# - Green (+) / Red (-) line highlighting
# - Word-level diff within lines
# - Collapsible hunks and files
# - Line numbers (old/new)
# - File tree for multi-file diffs
# - Keyboard navigation

module Tui
  # Represents a single line in a diff
  struct DiffLine
    enum Type
      Context   # Unchanged line
      Addition  # Added line (+)
      Deletion  # Removed line (-)
      Header    # @@ hunk header
      FileHeader # diff --git, ---, +++
    end

    property type : Type
    property content : String
    property old_line : Int32?  # Line number in old file
    property new_line : Int32?  # Line number in new file
    # Word-level changes: array of {start, length, type} for inline highlighting
    property word_changes : Array(Tuple(Int32, Int32, Type)) = [] of Tuple(Int32, Int32, Type)

    def initialize(@type, @content, @old_line = nil, @new_line = nil)
    end
  end

  # Represents a hunk (section) in a diff
  class DiffHunk
    property header : String           # The @@ line
    property old_start : Int32         # Starting line in old file
    property old_count : Int32         # Number of lines in old file
    property new_start : Int32         # Starting line in new file
    property new_count : Int32         # Number of lines in new file
    property lines : Array(DiffLine) = [] of DiffLine
    property? collapsed : Bool = false

    def initialize(@header, @old_start = 0, @old_count = 0, @new_start = 0, @new_count = 0)
    end

    # Statistics
    def additions : Int32
      lines.count { |l| l.type.addition? }
    end

    def deletions : Int32
      lines.count { |l| l.type.deletion? }
    end
  end

  # Represents a file in a diff
  class DiffFile
    property old_path : String
    property new_path : String
    property hunks : Array(DiffHunk) = [] of DiffHunk
    property? collapsed : Bool = false
    property? binary : Bool = false
    property? new_file : Bool = false
    property? deleted_file : Bool = false
    property? renamed : Bool = false

    def initialize(@old_path = "", @new_path = "")
    end

    # Display path (prefer new path, handle renames)
    def display_path : String
      if renamed?
        "#{old_path} → #{new_path}"
      elsif deleted_file?
        old_path
      else
        new_path.empty? ? old_path : new_path
      end
    end

    # Statistics
    def additions : Int32
      hunks.sum(&.additions)
    end

    def deletions : Int32
      hunks.sum(&.deletions)
    end
  end

  # Parser for unified diff format
  class DiffParser
    # Parse unified diff text into array of DiffFile
    def self.parse(diff_text : String) : Array(DiffFile)
      files = [] of DiffFile
      current_file : DiffFile? = nil
      current_hunk : DiffHunk? = nil
      old_line = 0
      new_line = 0

      diff_text.each_line do |line|
        case line
        when /^diff --git a\/(.*) b\/(.*)/
          # New file starts
          current_file = DiffFile.new($1, $2)
          files << current_file
          current_hunk = nil

        when /^--- (.+)/
          if file = current_file
            path = $1.sub(/^a\//, "").sub(/^\/dev\/null$/, "")
            file.old_path = path if path != "/dev/null"
            file.new_file = true if $1 == "/dev/null"
          end

        when /^\+\+\+ (.+)/
          if file = current_file
            path = $1.sub(/^b\//, "").sub(/^\/dev\/null$/, "")
            file.new_path = path if path != "/dev/null"
            file.deleted_file = true if $1 == "/dev/null"
          end

        when /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)?/
          if file = current_file
            old_start = $1.to_i
            old_count = $2?.try(&.to_i) || 1
            new_start = $3.to_i
            new_count = $4?.try(&.to_i) || 1
            context = $5? || ""

            current_hunk = DiffHunk.new(
              line,
              old_start, old_count,
              new_start, new_count
            )
            file.hunks << current_hunk
            old_line = old_start
            new_line = new_start
          end

        when /^Binary files .* differ/
          if file = current_file
            file.binary = true
          end

        when /^rename from (.+)/
          if file = current_file
            file.old_path = $1
            file.renamed = true
          end

        when /^rename to (.+)/
          if file = current_file
            file.new_path = $1
            file.renamed = true
          end

        else
          if hunk = current_hunk
            if line.starts_with?('+') && !line.starts_with?("+++")
              hunk.lines << DiffLine.new(
                DiffLine::Type::Addition,
                line[1..]? || "",
                nil,
                new_line
              )
              new_line += 1
            elsif line.starts_with?('-') && !line.starts_with?("---")
              hunk.lines << DiffLine.new(
                DiffLine::Type::Deletion,
                line[1..]? || "",
                old_line,
                nil
              )
              old_line += 1
            elsif line.starts_with?(' ') || line.empty?
              content = line.empty? ? "" : (line[1..]? || "")
              hunk.lines << DiffLine.new(
                DiffLine::Type::Context,
                content,
                old_line,
                new_line
              )
              old_line += 1
              new_line += 1
            elsif line.starts_with?('\\')
              # "\ No newline at end of file" - skip
            end
          end
        end
      end

      # Calculate word-level diffs
      files.each do |file|
        file.hunks.each do |hunk|
          calculate_word_diffs(hunk)
        end
      end

      files
    end

    # Calculate word-level differences between adjacent +/- lines
    private def self.calculate_word_diffs(hunk : DiffHunk)
      i = 0
      while i < hunk.lines.size
        # Find consecutive deletion/addition pairs
        if hunk.lines[i].type.deletion?
          deletions = [] of DiffLine
          additions = [] of DiffLine

          # Collect consecutive deletions
          while i < hunk.lines.size && hunk.lines[i].type.deletion?
            deletions << hunk.lines[i]
            i += 1
          end

          # Collect consecutive additions
          while i < hunk.lines.size && hunk.lines[i].type.addition?
            additions << hunk.lines[i]
            i += 1
          end

          # If we have matching pairs, calculate word diffs
          if !deletions.empty? && !additions.empty?
            pairs = {deletions.size, additions.size}.min
            pairs.times do |j|
              compute_inline_diff(deletions[j], additions[j])
            end
          end
        else
          i += 1
        end
      end
    end

    # Compute inline (word-level) diff between two lines
    private def self.compute_inline_diff(old_line : DiffLine, new_line : DiffLine)
      old_words = tokenize(old_line.content)
      new_words = tokenize(new_line.content)

      # Simple LCS-based diff
      lcs = compute_lcs(old_words, new_words)

      # Mark deletions in old line
      old_pos = 0
      char_pos = 0
      old_words.each_with_index do |word, idx|
        unless lcs[:old].includes?(idx)
          old_line.word_changes << {char_pos, word.size, DiffLine::Type::Deletion}
        end
        char_pos += word.size
      end

      # Mark additions in new line
      char_pos = 0
      new_words.each_with_index do |word, idx|
        unless lcs[:new].includes?(idx)
          new_line.word_changes << {char_pos, word.size, DiffLine::Type::Addition}
        end
        char_pos += word.size
      end
    end

    # Tokenize line into words (preserving whitespace as separate tokens)
    private def self.tokenize(line : String) : Array(String)
      tokens = [] of String
      current = ""
      in_word = false

      line.each_char do |c|
        if c.whitespace?
          tokens << current unless current.empty?
          current = c.to_s
          in_word = false
        elsif c.alphanumeric? || c == '_'
          if in_word
            current += c
          else
            tokens << current unless current.empty?
            current = c.to_s
            in_word = true
          end
        else
          tokens << current unless current.empty?
          tokens << c.to_s
          current = ""
          in_word = false
        end
      end
      tokens << current unless current.empty?
      tokens
    end

    # Compute LCS indices for old and new word arrays
    private def self.compute_lcs(old_words : Array(String), new_words : Array(String)) : NamedTuple(old: Set(Int32), new: Set(Int32))
      m = old_words.size
      n = new_words.size

      # DP table
      dp = Array.new(m + 1) { Array.new(n + 1, 0) }
      (1..m).each do |i|
        (1..n).each do |j|
          if old_words[i - 1] == new_words[j - 1]
            dp[i][j] = dp[i - 1][j - 1] + 1
          else
            dp[i][j] = {dp[i - 1][j], dp[i][j - 1]}.max
          end
        end
      end

      # Backtrack to find LCS indices
      old_indices = Set(Int32).new
      new_indices = Set(Int32).new
      i, j = m, n
      while i > 0 && j > 0
        if old_words[i - 1] == new_words[j - 1]
          old_indices << (i - 1)
          new_indices << (j - 1)
          i -= 1
          j -= 1
        elsif dp[i - 1][j] > dp[i][j - 1]
          i -= 1
        else
          j -= 1
        end
      end

      {old: old_indices, new: new_indices}
    end
  end

  # DiffView widget - displays parsed diff with colors and interactivity
  class DiffView < Widget
    property files : Array(DiffFile) = [] of DiffFile
    property scroll_offset : Int32 = 0
    property selected_index : Int32 = 0  # Currently selected line/item

    # Colors
    property addition_bg : Color = Color.rgb(0, 60, 0)       # Dark green
    property addition_fg : Color = Color.rgb(80, 255, 80)    # Light green
    property deletion_bg : Color = Color.rgb(60, 0, 0)       # Dark red
    property deletion_fg : Color = Color.rgb(255, 80, 80)    # Light red
    property context_fg : Color = Color.white
    property header_bg : Color = Color.rgb(40, 40, 60)       # Dark blue
    property header_fg : Color = Color.rgb(150, 150, 255)    # Light blue
    property line_number_fg : Color = Color.palette(240)     # Gray
    property word_change_bg : Color = Color.rgb(80, 80, 0)   # Highlight changed words

    # UI settings
    property? show_line_numbers : Bool = true
    property line_number_width : Int32 = 4
    property? show_scrollbar : Bool = true

    # Callbacks
    @on_file_select : Proc(DiffFile, Nil)?

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    # Set diff content from raw diff text
    def content=(diff_text : String)
      @files = DiffParser.parse(diff_text)
      @scroll_offset = 0
      @selected_index = 0
      mark_dirty!
    end

    # Callback when file is selected
    def on_file_select(&block : DiffFile -> Nil)
      @on_file_select = block
    end

    # Collapse/expand all
    def collapse_all
      @files.each do |file|
        file.collapsed = true
        file.hunks.each(&.collapsed = true)
      end
      mark_dirty!
    end

    def expand_all
      @files.each do |file|
        file.collapsed = false
        file.hunks.each(&.collapsed = false)
      end
      mark_dirty!
    end

    # Toggle current item (file or hunk)
    def toggle_selected
      item = item_at_index(@selected_index)
      case item
      when DiffFile
        item.collapsed = !item.collapsed?
      when DiffHunk
        item.collapsed = !item.collapsed?
      end
      mark_dirty!
    end

    # Statistics
    def total_additions : Int32
      @files.sum(&.additions)
    end

    def total_deletions : Int32
      @files.sum(&.deletions)
    end

    # Calculate total visible lines
    def total_lines : Int32
      count = 0
      @files.each do |file|
        count += 1  # File header
        next if file.collapsed?

        file.hunks.each do |hunk|
          count += 1  # Hunk header
          next if hunk.collapsed?
          count += hunk.lines.size
        end
      end
      count
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      y = @rect.y
      line_idx = 0
      visible_height = @rect.height

      # Render header bar
      render_header(buffer, clip, y)
      y += 1
      visible_height -= 1

      # Skip to scroll offset
      current_line = 0

      @files.each do |file|
        break if y >= @rect.bottom

        # File header
        if current_line >= @scroll_offset
          render_file_header(buffer, clip, y, file, line_idx == @selected_index)
          y += 1
        end
        current_line += 1
        line_idx += 1

        next if file.collapsed?

        file.hunks.each do |hunk|
          break if y >= @rect.bottom

          # Hunk header
          if current_line >= @scroll_offset
            render_hunk_header(buffer, clip, y, hunk, line_idx == @selected_index)
            y += 1
          end
          current_line += 1
          line_idx += 1

          next if hunk.collapsed?

          hunk.lines.each do |line|
            break if y >= @rect.bottom

            if current_line >= @scroll_offset
              render_diff_line(buffer, clip, y, line, line_idx == @selected_index)
              y += 1
            end
            current_line += 1
            line_idx += 1
          end
        end
      end

      # Draw scrollbar
      if show_scrollbar?
        draw_scrollbar(buffer, clip, visible_height)
      end
    end

    private def draw_scrollbar(buffer : Buffer, clip : Rect, visible_height : Int32) : Nil
      return if @rect.width < 2

      total = total_lines
      return if total <= visible_height

      scrollbar_x = @rect.right - 1
      content_y = @rect.y + 1  # +1 for header bar
      content_height = visible_height

      # Calculate thumb position and size
      thumb_height = Math.max(1, (content_height * content_height / total).to_i)
      max_scroll = total - content_height
      thumb_pos = max_scroll > 0 ? (@scroll_offset * (content_height - thumb_height) / max_scroll).to_i : 0

      track_style = Style.new(fg: Color.palette(240))
      thumb_style = Style.new(fg: focused? ? Color.cyan : Color.white)

      content_height.times do |i|
        y = content_y + i
        next unless clip.contains?(scrollbar_x, y)

        if i >= thumb_pos && i < thumb_pos + thumb_height
          buffer.set(scrollbar_x, y, '█', thumb_style)
        else
          buffer.set(scrollbar_x, y, '│', track_style)
        end
      end
    end

    private def render_header(buffer : Buffer, clip : Rect, y : Int32)
      # Header bar with collapse/expand buttons and stats
      bg = focused? ? Color.rgb(50, 50, 70) : Color.rgb(30, 30, 40)
      style = Style.new(fg: Color.white, bg: bg)

      # Clear line
      @rect.width.times do |dx|
        buffer.set(@rect.x + dx, y, ' ', style) if clip.contains?(@rect.x + dx, y)
      end

      # Left side: collapse/expand hints
      hints = " [c]ollapse  [e]xpand "
      hints.each_char_with_index do |c, i|
        buffer.set(@rect.x + i, y, c, style) if clip.contains?(@rect.x + i, y)
      end

      # Right side: statistics
      stats = " #{@files.size} file#{"s" if @files.size != 1}  +#{total_additions} -#{total_deletions} "
      stats_x = @rect.right - stats.size
      add_style = Style.new(fg: addition_fg, bg: bg)
      del_style = Style.new(fg: deletion_fg, bg: bg)

      x = stats_x
      stats.each_char do |c|
        s = case c
            when '+' then add_style
            when '-' then del_style
            else          style
            end
        buffer.set(x, y, c, s) if clip.contains?(x, y)
        x += 1
      end
    end

    private def render_file_header(buffer : Buffer, clip : Rect, y : Int32, file : DiffFile, selected : Bool)
      bg = selected && focused? ? Color.blue : header_bg
      style = Style.new(fg: header_fg, bg: bg)

      # Clear line
      @rect.width.times do |dx|
        buffer.set(@rect.x + dx, y, ' ', style) if clip.contains?(@rect.x + dx, y)
      end

      # Collapse indicator
      indicator = file.collapsed? ? "▶ " : "▼ "
      x = @rect.x
      indicator.each_char do |c|
        buffer.set(x, y, c, style) if clip.contains?(x, y)
        x += 1
      end

      # File path
      path = file.display_path
      path.each_char do |c|
        break if x >= @rect.right - 15
        buffer.set(x, y, c, style) if clip.contains?(x, y)
        x += 1
      end

      # Stats on right
      stats = " +#{file.additions} -#{file.deletions}"
      stats_x = @rect.right - stats.size - 1
      stats.each_char_with_index do |c, i|
        s = case c
            when '+' then Style.new(fg: addition_fg, bg: bg)
            when '-' then Style.new(fg: deletion_fg, bg: bg)
            else          style
            end
        buffer.set(stats_x + i, y, c, s) if clip.contains?(stats_x + i, y)
      end
    end

    private def render_hunk_header(buffer : Buffer, clip : Rect, y : Int32, hunk : DiffHunk, selected : Bool)
      bg = selected && focused? ? Color.blue : Color.rgb(30, 30, 50)
      style = Style.new(fg: Color.palette(245), bg: bg)

      # Clear line
      @rect.width.times do |dx|
        buffer.set(@rect.x + dx, y, ' ', style) if clip.contains?(@rect.x + dx, y)
      end

      # Collapse indicator
      indicator = hunk.collapsed? ? "  ▶ " : "  ▼ "
      x = @rect.x
      indicator.each_char do |c|
        buffer.set(x, y, c, style) if clip.contains?(x, y)
        x += 1
      end

      # Hunk header text (truncated)
      header = hunk.header
      max_len = @rect.width - 6
      header = header[0, max_len] if header.size > max_len
      header.each_char do |c|
        buffer.set(x, y, c, style) if clip.contains?(x, y)
        x += 1
      end
    end

    private def render_diff_line(buffer : Buffer, clip : Rect, y : Int32, line : DiffLine, selected : Bool)
      # Determine colors based on line type
      bg, fg = case line.type
               when .addition? then {addition_bg, addition_fg}
               when .deletion? then {deletion_bg, deletion_fg}
               else                 {Color.default, context_fg}
               end

      bg = Color.blue if selected && focused?
      style = Style.new(fg: fg, bg: bg)

      # Clear line
      @rect.width.times do |dx|
        buffer.set(@rect.x + dx, y, ' ', style) if clip.contains?(@rect.x + dx, y)
      end

      x = @rect.x

      # Line numbers
      if show_line_numbers?
        old_num = line.old_line.try { |n| n.to_s.rjust(line_number_width) } || " " * line_number_width
        new_num = line.new_line.try { |n| n.to_s.rjust(line_number_width) } || " " * line_number_width
        num_style = Style.new(fg: line_number_fg, bg: bg)

        old_num.each_char do |c|
          buffer.set(x, y, c, num_style) if clip.contains?(x, y)
          x += 1
        end
        buffer.set(x, y, ' ', num_style) if clip.contains?(x, y)
        x += 1
        new_num.each_char do |c|
          buffer.set(x, y, c, num_style) if clip.contains?(x, y)
          x += 1
        end
        buffer.set(x, y, '│', num_style) if clip.contains?(x, y)
        x += 1
      end

      # Line prefix (+/-/ )
      prefix = case line.type
               when .addition? then '+'
               when .deletion? then '-'
               else                 ' '
               end
      buffer.set(x, y, prefix, style) if clip.contains?(x, y)
      x += 1

      # Line content with word-level highlighting
      content = line.content
      char_idx = 0
      content.each_char do |c|
        break if x >= @rect.right

        # Check if this char is in a word change region
        char_style = style
        line.word_changes.each do |(start, len, change_type)|
          if char_idx >= start && char_idx < start + len
            highlight_bg = change_type.addition? ? Color.rgb(0, 100, 0) : Color.rgb(100, 0, 0)
            char_style = Style.new(fg: fg, bg: selected && focused? ? Color.blue : highlight_bg)
            break
          end
        end

        buffer.set(x, y, c, char_style) if clip.contains?(x, y)
        x += 1
        char_idx += 1
      end
    end

    # Find item (DiffFile or DiffHunk) at given index
    private def item_at_index(index : Int32) : DiffFile | DiffHunk | DiffLine | Nil
      current = 0
      @files.each do |file|
        return file if current == index
        current += 1

        next if file.collapsed?

        file.hunks.each do |hunk|
          return hunk if current == index
          current += 1

          next if hunk.collapsed?

          hunk.lines.each do |line|
            return line if current == index
            current += 1
          end
        end
      end
      nil
    end

    def on_event(event : Event) : Bool
      case event
      when MouseEvent
        # Wheel scrolling works without focus (hover scroll)
        if event.in_rect?(@rect)
          visible_height = @rect.height - 1  # -1 for header
          max_scroll = (total_lines - visible_height).clamp(0, Int32::MAX)
          if event.button.wheel_up?
            @scroll_offset = (@scroll_offset - 3).clamp(0, max_scroll)
            mark_dirty!
            return true
          elsif event.button.wheel_down?
            @scroll_offset = (@scroll_offset + 3).clamp(0, max_scroll)
            mark_dirty!
            return true
          end
        end

        if event.action.press? && event.button.left?
          self.focused = true

          # Calculate which line was clicked
          clicked_line = @scroll_offset + (event.y - @rect.y - 1)  # -1 for header
          if clicked_line >= 0 && clicked_line < total_lines
            @selected_index = clicked_line
            toggle_selected
          end

          event.stop_propagation!
          return true
        end
        return false

      when KeyEvent
        return false unless focused?

        case event.key
        when .up?
          select_prev
          event.stop_propagation!
          return true
        when .down?
          select_next
          event.stop_propagation!
          return true
        when .enter?
          toggle_selected
          event.stop_propagation!
          return true
        when .page_up?
          page_up
          event.stop_propagation!
          return true
        when .page_down?
          page_down
          event.stop_propagation!
          return true
        when .home?
          scroll_to_top
          event.stop_propagation!
          return true
        when .end?
          scroll_to_bottom
          event.stop_propagation!
          return true
        end

        case event.char
        when 'j'
          select_next
          event.stop_propagation!
          return true
        when 'k'
          select_prev
          event.stop_propagation!
          return true
        when 'c'
          collapse_all
          event.stop_propagation!
          return true
        when 'e'
          expand_all
          event.stop_propagation!
          return true
        end
      end

      false
    end

    private def select_next
      max = total_lines - 1
      @selected_index = (@selected_index + 1).clamp(0, max)
      ensure_visible
      mark_dirty!
    end

    private def select_prev
      @selected_index = (@selected_index - 1).clamp(0, total_lines - 1)
      ensure_visible
      mark_dirty!
    end

    private def page_up
      @selected_index = (@selected_index - (@rect.height - 2)).clamp(0, total_lines - 1)
      ensure_visible
      mark_dirty!
    end

    private def page_down
      @selected_index = (@selected_index + (@rect.height - 2)).clamp(0, total_lines - 1)
      ensure_visible
      mark_dirty!
    end

    private def scroll_to_top
      @selected_index = 0
      @scroll_offset = 0
      mark_dirty!
    end

    private def scroll_to_bottom
      @selected_index = total_lines - 1
      ensure_visible
      mark_dirty!
    end

    private def ensure_visible
      visible_height = @rect.height - 1  # -1 for header
      if @selected_index < @scroll_offset
        @scroll_offset = @selected_index
      elsif @selected_index >= @scroll_offset + visible_height
        @scroll_offset = @selected_index - visible_height + 1
      end
    end
  end
end
