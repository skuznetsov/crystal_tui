# Code Preview - Live TUML/Crystal code output for TUI Editor
# Bidirectional: view code AND edit to update Canvas
require "./canvas"
require "./tuml_parser"

module TuiEditor
  class CodePreview < Tui::Panel
    enum Format
      Pug
      YAML
      JSON
      Crystal
    end

    @canvas : Canvas?
    @format : Format = Format::Pug
    @scroll_offset : Int32 = 0
    @lines : Array(String) = [] of String

    # Edit mode state
    @editing : Bool = false
    @edit_lines : Array(String) = [] of String
    @cursor_line : Int32 = 0
    @cursor_col : Int32 = 0
    @parse_error : TumlParser::ParseError?
    @last_valid_lines : Array(String) = [] of String

    # Selection state (MCEdit-style block selection)
    @selecting : Bool = false
    @sel_start_line : Int32 = 0
    @sel_start_col : Int32 = 0
    @sel_end_line : Int32 = 0
    @sel_end_col : Int32 = 0
    @clipboard : String = ""

    def initialize
      super("Code Preview", id: "code-preview")
      @focusable = true
      @border_style = BorderStyle::None  # SplitContainer draws border
    end

    def editing? : Bool
      @editing
    end

    def parse_error : TumlParser::ParseError?
      @parse_error
    end

    def has_selection? : Bool
      @selecting && (@sel_start_line != @sel_end_line || @sel_start_col != @sel_end_col)
    end

    # Get normalized selection bounds (start always before end)
    private def selection_bounds : {Int32, Int32, Int32, Int32}
      if @sel_start_line < @sel_end_line || (@sel_start_line == @sel_end_line && @sel_start_col <= @sel_end_col)
        {@sel_start_line, @sel_start_col, @sel_end_line, @sel_end_col}
      else
        {@sel_end_line, @sel_end_col, @sel_start_line, @sel_start_col}
      end
    end

    # Check if position is within selection
    private def in_selection?(line : Int32, col : Int32) : Bool
      return false unless has_selection?

      start_line, start_col, end_line, end_col = selection_bounds

      if line < start_line || line > end_line
        false
      elsif line == start_line && line == end_line
        col >= start_col && col < end_col
      elsif line == start_line
        col >= start_col
      elsif line == end_line
        col < end_col
      else
        true
      end
    end

    # Get selected text
    private def selected_text : String
      return "" unless has_selection?

      start_line, start_col, end_line, end_col = selection_bounds
      lines = @edit_lines

      if start_line == end_line
        line = lines[start_line]? || ""
        line[start_col...end_col]? || ""
      else
        result = String.build do |str|
          (start_line..end_line).each do |i|
            line = lines[i]? || ""
            if i == start_line
              str << (line[start_col..]? || "")
              str << '\n'
            elsif i == end_line
              str << (line[...end_col]? || "")
            else
              str << line
              str << '\n'
            end
          end
        end
        result
      end
    end

    # Delete selected text
    private def delete_selection : Nil
      return unless has_selection?

      start_line, start_col, end_line, end_col = selection_bounds

      if start_line == end_line
        line = @edit_lines[start_line]
        @edit_lines[start_line] = line[...start_col] + line[end_col..]
      else
        first_part = @edit_lines[start_line][...start_col]? || ""
        last_part = @edit_lines[end_line][end_col..]? || ""
        @edit_lines[start_line] = first_part + last_part

        # Remove lines between
        (end_line - start_line).times { @edit_lines.delete_at(start_line + 1) }
      end

      @cursor_line = start_line
      @cursor_col = start_col
      clear_selection
    end

    private def clear_selection : Nil
      @selecting = false
    end

    private def start_selection : Nil
      unless @selecting
        @selecting = true
        @sel_start_line = @cursor_line
        @sel_start_col = @cursor_col
      end
      @sel_end_line = @cursor_line
      @sel_end_col = @cursor_col
    end

    private def update_selection : Nil
      if @selecting
        @sel_end_line = @cursor_line
        @sel_end_col = @cursor_col
      end
    end

    def canvas=(canvas : Canvas) : Nil
      @canvas = canvas
      update_code
    end

    def format : Format
      @format
    end

    def format=(f : Format) : Nil
      @format = f
      update_title
      update_code
      mark_dirty!
    end

    def cycle_format : Nil
      @format = case @format
                when .pug?     then Format::YAML
                when .yaml?    then Format::JSON
                when .json?    then Format::Crystal
                when .crystal? then Format::Pug
                else                Format::Pug
                end
      update_title
      update_code
      mark_dirty!
    end

    private def update_title
      @title = @editing ? "Code - #{@format} [EDIT]" : "Code - #{@format}"
    end

    def update_code : Nil
      canvas = @canvas
      return unless canvas

      code = case @format
             when .pug?
               canvas.to_tuml(:pug)
             when .yaml?
               canvas.to_tuml(:yaml)
             when .json?
               # Pretty print JSON
               json = canvas.to_tuml(:json)
               pretty_json(json)
             when .crystal?
               to_crystal(canvas)
             else
               ""
             end

      @lines = code.split('\n')
      @last_valid_lines = @lines.dup
      @scroll_offset = 0
      @parse_error = nil
      mark_dirty!
    end

    # Enter edit mode
    def start_editing : Nil
      return if @format.crystal? || @format.json?  # Read-only formats

      @editing = true
      @edit_lines = @lines.dup
      @cursor_line = 0
      @cursor_col = 0
      @parse_error = nil
      update_title
      mark_dirty!
    end

    # Exit edit mode, parse and apply changes
    def stop_editing(apply : Bool = true) : Nil
      @editing = false

      if apply && @format.pug? || @format.yaml?
        source = @edit_lines.join('\n')
        result = TumlParser.parse(source)

        case result
        when TumlParser::ParseError
          @parse_error = result
          # Keep showing edit lines but mark error
          @lines = @edit_lines.dup
        when CanvasNode
          @parse_error = nil
          # Update canvas with new tree
          if canvas = @canvas
            canvas.root = result
          end
          @lines = @edit_lines.dup
          @last_valid_lines = @lines.dup
        end
      else
        # Cancelled - restore last valid
        @lines = @last_valid_lines.dup
        @parse_error = nil
      end

      update_title
      mark_dirty!
    end

    # Try to parse current edit buffer (live validation)
    private def try_parse : Nil
      return unless @editing

      source = @edit_lines.join('\n')
      result = TumlParser.parse(source)

      case result
      when TumlParser::ParseError
        @parse_error = result
      when CanvasNode
        @parse_error = nil
        # Live update canvas
        if canvas = @canvas
          canvas.root = result
        end
      end
      mark_dirty!
    end

    private def pretty_json(json : String, indent : Int32 = 0) : String
      # Simple JSON prettifier
      result = String.build do |str|
        level = 0
        in_string = false
        json.each_char do |char|
          case char
          when '"'
            in_string = !in_string
            str << char
          when '{', '['
            str << char
            unless in_string
              level += 1
              str << '\n'
              str << "  " * level
            end
          when '}', ']'
            unless in_string
              level -= 1
              str << '\n'
              str << "  " * level
            end
            str << char
          when ','
            str << char
            unless in_string
              str << '\n'
              str << "  " * level
            end
          when ':'
            str << char
            str << ' ' unless in_string
          else
            str << char
          end
        end
      end
      result
    end

    private def to_crystal(canvas : Canvas) : String
      return "" unless root = canvas.root
      String.build do |str|
        str << "require \"tui\"\n\n"
        str << "class MyApp < Tui::App\n"
        str << "  def compose : Array(Tui::Widget)\n"
        str << "    [\n"
        generate_crystal_widget(str, root, 3)
        str << "    ]\n"
        str << "  end\n"
        str << "end\n\n"
        str << "MyApp.new.run\n"
      end
    end

    private def generate_crystal_widget(str : String::Builder, node : CanvasNode, indent : Int32) : Nil
      prefix = "  " * indent
      widget_class = "Tui::#{node.widget_def.name}"

      # Build constructor args
      args = [] of String
      args << %("#{node.attrs["title"]}") if node.attrs["title"]?
      args << %("#{node.attrs["text"]}") if node.attrs["text"]? && !node.attrs["title"]?
      args << "id: \"#{node.id}\"" unless node.id.empty?

      # Other common attrs
      node.attrs.each do |k, v|
        next if k.in?("title", "text", "label")
        args << "#{k}: #{v.inspect}"
      end

      if node.container? && node.children.any?
        str << "#{prefix}#{widget_class}.new(#{args.join(", ")}) do |w|\n"
        node.children.each do |child|
          str << "#{prefix}  w.add_child "
          generate_crystal_widget_inline(str, child, indent + 1)
        end
        str << "#{prefix}end,\n"
      else
        str << "#{prefix}#{widget_class}.new(#{args.join(", ")}),\n"
      end
    end

    private def generate_crystal_widget_inline(str : String::Builder, node : CanvasNode, indent : Int32) : Nil
      widget_class = "Tui::#{node.widget_def.name}"

      args = [] of String
      args << %("#{node.attrs["title"]}") if node.attrs["title"]?
      args << %("#{node.attrs["text"]}") if node.attrs["text"]? && !node.attrs["title"]?
      args << %("#{node.attrs["label"]}") if node.attrs["label"]? && !node.attrs["title"]? && !node.attrs["text"]?
      args << "id: \"#{node.id}\"" unless node.id.empty?

      if node.container? && node.children.any?
        str << "#{widget_class}.new(#{args.join(", ")}) { |w|\n"
        prefix = "  " * (indent + 1)
        node.children.each do |child|
          str << "#{prefix}w.add_child "
          generate_crystal_widget_inline(str, child, indent + 1)
        end
        str << "#{" " * (indent * 2)}}\n"
      else
        str << "#{widget_class}.new(#{args.join(", ")})\n"
      end
    end

    def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
      super

      inner = inner_rect
      return if inner.empty?

      lines_to_render = @editing ? @edit_lines : @lines

      if lines_to_render.empty?
        msg = "No widgets yet"
        style = Tui::Style.new(fg: Tui::Color.rgb(100, 100, 100))
        draw_text(buffer, clip, inner.x, inner.y, msg, style, inner.width)
        return
      end

      # Syntax highlighting styles
      comment_style = Tui::Style.new(fg: Tui::Color.rgb(100, 100, 100))
      error_style = Tui::Style.new(fg: Tui::Color.red, attrs: Tui::Attributes::Bold)
      cursor_style = Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.white)

      visible_lines = inner.height - 1  # Reserve 1 line for status
      lines_to_render.each_with_index do |line, i|
        next if i < @scroll_offset
        break if i - @scroll_offset >= visible_lines

        y = inner.y + (i - @scroll_offset)
        x = inner.x

        # Error indicator for parse error line
        is_error_line = @parse_error && @parse_error.not_nil!.line == i

        # Line number
        line_num_str = "#{i + 1}".rjust(3)
        num_style = is_error_line ? error_style : comment_style
        line_num_str.each_char_with_index do |char, ci|
          buffer.set(x + ci, y, char, num_style) if clip.contains?(x + ci, y)
        end
        x += 4

        # Line content with syntax highlighting
        if @editing
          # Render with cursor and selection
          highlight_line_with_cursor(buffer, clip, line, x, y, inner.width - 4, @cursor_col, i)
        else
          highlight_line(buffer, clip, line, x, y, inner.width - 4)
        end

        # Error underline
        if is_error_line
          err_col = @parse_error.not_nil!.column
          if err_col < inner.width - 4
            buffer.set(x + err_col, y, '▲', error_style) if clip.contains?(x + err_col, y)
          end
        end
      end

      # Status line at bottom
      status_y = inner.y + inner.height - 1
      if @editing
        if err = @parse_error
          status = "ERROR: #{err.message}"
          status_style = error_style
        elsif has_selection?
          status = "SEL: Shift+←→↑↓  Ctrl+C=Copy  Ctrl+X=Cut  Ctrl+V=Paste"
          status_style = Tui::Style.new(fg: Tui::Color.cyan)
        else
          status = "EDIT: Shift+Arrows=Select  Ctrl+S=Apply  Esc=Cancel"
          status_style = Tui::Style.new(fg: Tui::Color.yellow)
        end
      else
        if err = @parse_error
          status = "Parse error: #{err.message}"
          status_style = error_style
        elsif lines_to_render.size > visible_lines
          status = "#{@format} | e=Edit  f=Format  ↑↓=Scroll"
          status_style = comment_style
        else
          status = "#{@format} | e=Edit  f=Format"
          status_style = comment_style
        end
      end
      draw_text(buffer, clip, inner.x, status_y, status.ljust(inner.width), status_style, inner.width)
    end

    private def highlight_line_with_cursor(buffer : Tui::Buffer, clip : Tui::Rect,
                                           line : String, x : Int32, y : Int32,
                                           max_width : Int32, cursor_col : Int32,
                                           line_idx : Int32 = 0) : Nil
      cursor_style = Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.white)
      selection_style = Tui::Style.new(fg: Tui::Color.white, bg: Tui::Color.blue)

      # Render line with cursor and selection
      col = 0
      in_string = false
      string_char = '"'

      # Ensure line has at least cursor_col characters for cursor visibility
      display_line = line.size <= cursor_col ? line + " " : line

      display_line.each_char_with_index do |char, i|
        break if col >= max_width

        style = get_char_style(line, i, in_string, string_char)

        # Update string state
        if !in_string && (char == '"' || char == '\'')
          in_string = true
          string_char = char
        elsif in_string && char == string_char && (i == 0 || line[i - 1]? != '\\')
          in_string = false
        end

        # Apply selection style
        if in_selection?(line_idx, i)
          style = selection_style
        end

        # Apply cursor style at cursor position (overrides selection)
        if i == cursor_col && line_idx == @cursor_line
          style = cursor_style
        end

        buffer.set(x + col, y, char, style) if clip.contains?(x + col, y)
        col += 1
      end

      # Draw cursor at end of line if needed
      if cursor_col >= line.size && col < max_width && line_idx == @cursor_line
        buffer.set(x + col, y, ' ', cursor_style) if clip.contains?(x + col, y)
      end
    end

    private def get_char_style(line : String, idx : Int32, in_string : Bool, string_char : Char) : Tui::Style
      char = line[idx]?
      return Tui::Style.new(fg: Tui::Color.white) unless char

      if in_string
        Tui::Style.new(fg: Tui::Color.green)
      elsif char == '"' || char == '\''
        Tui::Style.new(fg: Tui::Color.green)
      elsif char == '#'
        Tui::Style.new(fg: Tui::Color.cyan)
      elsif char.number?
        Tui::Style.new(fg: Tui::Color.cyan)
      elsif char.in?('(', ')', '{', '}', '[', ']', ':', ',', '.')
        Tui::Style.new(fg: Tui::Color.yellow)
      else
        Tui::Style.new(fg: Tui::Color.white)
      end
    end

    private def highlight_line(buffer : Tui::Buffer, clip : Tui::Rect,
                               line : String, x : Int32, y : Int32, max_width : Int32) : Nil
      # Keywords for Crystal
      keywords = %w[require class def end do if else elsif unless case when while until return yield
                    property getter setter include extend module struct enum alias]
      # Types
      types = %w[String Int32 Int64 Float64 Bool Nil Array Hash Tui Widget Panel Button Label]

      col = 0
      in_string = false
      string_char = '"'

      line.each_char_with_index do |char, i|
        break if col >= max_width

        style = Tui::Style.new(fg: Tui::Color.white)

        if in_string
          style = Tui::Style.new(fg: Tui::Color.green)
          in_string = false if char == string_char && (i == 0 || line[i - 1] != '\\')
        elsif char == '"' || char == '\''
          in_string = true
          string_char = char
          style = Tui::Style.new(fg: Tui::Color.green)
        elsif char == '#' && !in_string
          # Comment or ID - check context
          if @format.pug? || @format.yaml?
            # In Pug/YAML, # at start or after whitespace is comment
            if i == 0 || line[i - 1].whitespace?
              # Rest of line is comment
              (i...line.size).each do |j|
                break if col >= max_width
                buffer.set(x + col, y, line[j], Tui::Style.new(fg: Tui::Color.rgb(100, 100, 100))) if clip.contains?(x + col, y)
                col += 1
              end
              return
            end
          end
          style = Tui::Style.new(fg: Tui::Color.cyan)
        elsif char.number?
          style = Tui::Style.new(fg: Tui::Color.cyan)
        elsif char.in?('(', ')', '{', '}', '[', ']', ':', ',', '.')
          style = Tui::Style.new(fg: Tui::Color.yellow)
        else
          # Check for keywords
          if i == 0 || !line[i - 1].alphanumeric?
            word_end = i
            while word_end < line.size && (line[word_end].alphanumeric? || line[word_end] == '_')
              word_end += 1
            end
            word = line[i...word_end]

            if keywords.includes?(word)
              style = Tui::Style.new(fg: Tui::Color.magenta)
            elsif types.any? { |t| word.starts_with?(t) }
              style = Tui::Style.new(fg: Tui::Color.cyan, attrs: Tui::Attributes::Bold)
            end
          end
        end

        buffer.set(x + col, y, char, style) if clip.contains?(x + col, y)
        col += 1
      end
    end

    private def draw_text(buffer : Tui::Buffer, clip : Tui::Rect, x : Int32, y : Int32,
                          text : String, style : Tui::Style, max_width : Int32) : Nil
      text.each_char_with_index do |char, i|
        break if i >= max_width
        buffer.set(x + i, y, char, style) if clip.contains?(x + i, y)
      end
    end

    def handle_event(event : Tui::Event) : Bool
      return false if event.stopped?

      case event
      when Tui::KeyEvent
        return false unless focused?

        if @editing
          return handle_edit_key(event)
        else
          return handle_view_key(event)
        end
      when Tui::MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          focus unless focused?

          # Click to position cursor in edit mode
          if @editing
            inner = inner_rect
            clicked_line = event.y - inner.y + @scroll_offset
            clicked_col = event.x - inner.x - 4  # Account for line numbers

            if clicked_line >= 0 && clicked_line < @edit_lines.size
              @cursor_line = clicked_line
              line = @edit_lines[@cursor_line]
              @cursor_col = clicked_col.clamp(0, line.size)
              mark_dirty!
            end
          end
          return true
        end
      end

      super
    end

    private def handle_view_key(event : Tui::KeyEvent) : Bool
      case
      when event.matches?("up"), event.matches?("k")
        if @scroll_offset > 0
          @scroll_offset -= 1
          mark_dirty!
        end
        return true
      when event.matches?("down"), event.matches?("j")
        inner = inner_rect
        max_scroll = (@lines.size - inner.height + 1).clamp(0, @lines.size)
        if @scroll_offset < max_scroll
          @scroll_offset += 1
          mark_dirty!
        end
        return true
      when event.matches?("page_up")
        @scroll_offset = (@scroll_offset - 10).clamp(0, @lines.size)
        mark_dirty!
        return true
      when event.matches?("page_down")
        inner = inner_rect
        max_scroll = (@lines.size - inner.height + 1).clamp(0, @lines.size)
        @scroll_offset = (@scroll_offset + 10).clamp(0, max_scroll)
        mark_dirty!
        return true
      when event.matches?("f")  # Format change
        cycle_format
        return true
      when event.matches?("e"), event.matches?("enter")  # Enter edit mode
        start_editing
        return true
      end
      false
    end

    private def handle_edit_key(event : Tui::KeyEvent) : Bool
      case
      when event.matches?("escape")
        if has_selection?
          clear_selection
          mark_dirty!
        else
          stop_editing(apply: false)
        end
        return true
      when event.matches?("ctrl+s")
        stop_editing(apply: true)
        return true

      # Selection with Shift+arrows
      when event.matches?("shift+up")
        start_selection
        if @cursor_line > 0
          @cursor_line -= 1
          @cursor_col = @cursor_col.clamp(0, current_line.size)
          update_selection
          ensure_cursor_visible
        end
        mark_dirty!
        return true
      when event.matches?("shift+down")
        start_selection
        if @cursor_line < @edit_lines.size - 1
          @cursor_line += 1
          @cursor_col = @cursor_col.clamp(0, current_line.size)
          update_selection
          ensure_cursor_visible
        end
        mark_dirty!
        return true
      when event.matches?("shift+left")
        start_selection
        if @cursor_col > 0
          @cursor_col -= 1
        elsif @cursor_line > 0
          @cursor_line -= 1
          @cursor_col = current_line.size
        end
        update_selection
        mark_dirty!
        return true
      when event.matches?("shift+right")
        start_selection
        if @cursor_col < current_line.size
          @cursor_col += 1
        elsif @cursor_line < @edit_lines.size - 1
          @cursor_line += 1
          @cursor_col = 0
        end
        update_selection
        mark_dirty!
        return true
      when event.matches?("shift+home")
        start_selection
        @cursor_col = 0
        update_selection
        mark_dirty!
        return true
      when event.matches?("shift+end")
        start_selection
        @cursor_col = current_line.size
        update_selection
        mark_dirty!
        return true

      # Clipboard operations
      when event.matches?("ctrl+c")
        if has_selection?
          @clipboard = selected_text
        end
        return true
      when event.matches?("ctrl+x")
        if has_selection?
          @clipboard = selected_text
          delete_selection
          try_parse
          mark_dirty!
        end
        return true
      when event.matches?("ctrl+v")
        if has_selection?
          delete_selection
        end
        if !@clipboard.empty?
          paste_text(@clipboard)
          try_parse
          mark_dirty!
        end
        return true
      when event.matches?("ctrl+a")
        # Select all
        @selecting = true
        @sel_start_line = 0
        @sel_start_col = 0
        @sel_end_line = @edit_lines.size - 1
        @sel_end_col = (@edit_lines.last? || "").size
        @cursor_line = @sel_end_line
        @cursor_col = @sel_end_col
        mark_dirty!
        return true

      # Normal navigation (clears selection)
      when event.matches?("up")
        clear_selection
        if @cursor_line > 0
          @cursor_line -= 1
          @cursor_col = @cursor_col.clamp(0, current_line.size)
          ensure_cursor_visible
          mark_dirty!
        end
        return true
      when event.matches?("down")
        clear_selection
        if @cursor_line < @edit_lines.size - 1
          @cursor_line += 1
          @cursor_col = @cursor_col.clamp(0, current_line.size)
          ensure_cursor_visible
          mark_dirty!
        end
        return true
      when event.matches?("left")
        clear_selection
        if @cursor_col > 0
          @cursor_col -= 1
        elsif @cursor_line > 0
          @cursor_line -= 1
          @cursor_col = current_line.size
        end
        mark_dirty!
        return true
      when event.matches?("right")
        clear_selection
        if @cursor_col < current_line.size
          @cursor_col += 1
        elsif @cursor_line < @edit_lines.size - 1
          @cursor_line += 1
          @cursor_col = 0
        end
        mark_dirty!
        return true
      when event.matches?("home")
        clear_selection
        @cursor_col = 0
        mark_dirty!
        return true
      when event.matches?("end")
        clear_selection
        @cursor_col = current_line.size
        mark_dirty!
        return true
      when event.matches?("enter")
        if has_selection?
          delete_selection
        end
        # Split line at cursor
        line = current_line
        before = line[0...@cursor_col]
        after = line[@cursor_col..]
        @edit_lines[@cursor_line] = before
        @edit_lines.insert(@cursor_line + 1, after)
        @cursor_line += 1
        @cursor_col = 0
        ensure_cursor_visible
        try_parse
        return true
      when event.matches?("backspace")
        if has_selection?
          delete_selection
          try_parse
          mark_dirty!
        elsif @cursor_col > 0
          line = current_line
          @edit_lines[@cursor_line] = line[0...(@cursor_col - 1)] + line[@cursor_col..]
          @cursor_col -= 1
          try_parse
          mark_dirty!
        elsif @cursor_line > 0
          # Join with previous line
          prev_line = @edit_lines[@cursor_line - 1]
          @cursor_col = prev_line.size
          @edit_lines[@cursor_line - 1] = prev_line + current_line
          @edit_lines.delete_at(@cursor_line)
          @cursor_line -= 1
          try_parse
          mark_dirty!
        end
        return true
      when event.matches?("delete")
        line = current_line
        if @cursor_col < line.size
          @edit_lines[@cursor_line] = line[0...@cursor_col] + line[(@cursor_col + 1)..]
          try_parse
        elsif @cursor_line < @edit_lines.size - 1
          # Join with next line
          @edit_lines[@cursor_line] = line + @edit_lines[@cursor_line + 1]
          @edit_lines.delete_at(@cursor_line + 1)
          try_parse
        end
        mark_dirty!
        return true
      when event.matches?("tab")
        # Insert 2 spaces for indent
        insert_char(' ')
        insert_char(' ')
        return true
      else
        # Regular character input
        if event.char && event.char.not_nil!.printable?
          insert_char(event.char.not_nil!)
          return true
        end
      end
      false
    end

    private def current_line : String
      @edit_lines[@cursor_line]? || ""
    end

    private def insert_char(char : Char) : Nil
      clear_selection
      line = current_line
      @edit_lines[@cursor_line] = line[0...@cursor_col] + char.to_s + line[@cursor_col..]
      @cursor_col += 1
      try_parse
      mark_dirty!
    end

    private def paste_text(text : String) : Nil
      return if text.empty?

      lines = text.split('\n')
      if lines.size == 1
        # Single line paste
        line = current_line
        @edit_lines[@cursor_line] = line[0...@cursor_col] + text + line[@cursor_col..]
        @cursor_col += text.size
      else
        # Multi-line paste
        line = current_line
        first_part = line[0...@cursor_col]
        last_part = line[@cursor_col..]

        # Update first line
        @edit_lines[@cursor_line] = first_part + lines.first

        # Insert middle lines
        lines[1...-1].each_with_index do |mid_line, i|
          @edit_lines.insert(@cursor_line + 1 + i, mid_line)
        end

        # Insert last line with remainder
        last_idx = @cursor_line + lines.size - 1
        @edit_lines.insert(last_idx, lines.last + last_part)

        @cursor_line = last_idx
        @cursor_col = lines.last.size
      end
      clear_selection
    end

    private def ensure_cursor_visible : Nil
      inner = inner_rect
      visible_lines = inner.height - 1

      if @cursor_line < @scroll_offset
        @scroll_offset = @cursor_line
      elsif @cursor_line >= @scroll_offset + visible_lines
        @scroll_offset = @cursor_line - visible_lines + 1
      end
    end
  end
end
