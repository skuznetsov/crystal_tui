# MarkdownView - renders markdown with streaming support
module Tui
  class MarkdownView < Widget
    # Background color for the view (nil = transparent/inherit from parent)
    # Set this to match parent container's background for proper rendering
    property background : Color? = nil

    # Styles for different elements
    property heading1_style : Style = Style.new(fg: Color.white, attrs: Attributes::Bold)
    property heading2_style : Style = Style.new(fg: Color.cyan, attrs: Attributes::Bold)
    property heading3_style : Style = Style.new(fg: Color.green, attrs: Attributes::Bold)
    property heading4_style : Style = Style.new(fg: Color.yellow)
    property text_style : Style = Style.new(fg: Color.white)
    property bold_style : Style = Style.new(fg: Color.white, attrs: Attributes::Bold)
    property italic_style : Style = Style.new(fg: Color.white, attrs: Attributes::Italic)
    property code_style : Style = Style.new(fg: Color.yellow, bg: Color.palette(236))
    property code_block_style : Style = Style.new(fg: Color.green, bg: Color.palette(235))
    property code_block_border : Style = Style.new(fg: Color.palette(240))
    property link_style : Style = Style.new(fg: Color.cyan, attrs: Attributes::Underline)
    property list_bullet_style : Style = Style.new(fg: Color.cyan)
    property blockquote_style : Style = Style.new(fg: Color.palette(250), attrs: Attributes::Italic)
    property blockquote_bar : Style = Style.new(fg: Color.palette(240))
    property hr_style : Style = Style.new(fg: Color.palette(240))
    property strikethrough_style : Style = Style.new(fg: Color.palette(245), attrs: Attributes::Strikethrough)
    property table_border_style : Style = Style.new(fg: Color.palette(240))
    property table_header_style : Style = Style.new(fg: Color.cyan, attrs: Attributes::Bold)
    property table_cell_style : Style = Style.new(fg: Color.white)

    # Streaming cursor
    property cursor_char : Char = '▌'
    property cursor_style : Style = Style.new(fg: Color.cyan, attrs: Attributes::Blink)
    property? streaming : Bool = false

    # Details (collapsible) styles
    property details_header_style : Style = Style.new(fg: Color.cyan)
    property details_content_style : Style = Style.new(fg: Color.palette(250))
    property details_collapsed_char : Char = '▶'
    property details_expanded_char : Char = '▼'

    # Track expanded state of details blocks by id
    @expanded_details : Set(String) = Set(String).new

    # Track clickable regions for details headers
    @details_regions : Array(Tuple(Rect, String)) = [] of Tuple(Rect, String)

    # Scroll
    @scroll_y : Int32 = 0
    @content_height : Int32 = 0

    # Parsed content
    @document : Markdown::Document = [] of Markdown::Block
    @raw_markdown : String = ""

    # Rendered lines cache
    @rendered_lines : Array(Array(Tuple(Char, Style))) = [] of Array(Tuple(Char, Style))
    @last_render_width : Int32 = 0
    @rendered_with_default_width : Bool = false

    # Callbacks
    @on_link_click : Proc(String, Nil)?
    @on_code_copy : Proc(String, Nil)?

    # Text selection state
    struct SelectionPos
      property line : Int32
      property col : Int32

      def initialize(@line = 0, @col = 0)
      end

      def ==(other : SelectionPos) : Bool
        @line == other.line && @col == other.col
      end

      def <(other : SelectionPos) : Bool
        @line < other.line || (@line == other.line && @col < other.col)
      end

      def <=(other : SelectionPos) : Bool
        self < other || self == other
      end

      def >=(other : SelectionPos) : Bool
        !(self < other)
      end

      def >(other : SelectionPos) : Bool
        other < self
      end
    end

    @selection_start : SelectionPos = SelectionPos.new
    @selection_end : SelectionPos = SelectionPos.new
    @selecting : Bool = false
    @has_selection : Bool = false
    property selection_bg : Color = Color.rgb(60, 90, 150)  # Blue highlight

    # Scrollbar drag state
    @scrollbar_dragging : Bool = false
    @scrollbar_drag_start_y : Int32 = 0
    @scrollbar_drag_start_scroll : Int32 = 0

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    # Convert screen coordinates to content position
    private def screen_to_content_pos(screen_x : Int32, screen_y : Int32) : SelectionPos
      # Convert screen Y to content line
      content_line = @scroll_y + (screen_y - @rect.y)
      content_line = content_line.clamp(0, (@rendered_lines.size - 1).clamp(0, Int32::MAX))

      # Convert screen X to content column
      content_col = screen_x - @rect.x
      if line = @rendered_lines[content_line]?
        content_col = content_col.clamp(0, line.size)
      else
        content_col = 0
      end

      SelectionPos.new(content_line, content_col)
    end

    # Get ordered selection bounds (start < end)
    private def selection_bounds : Tuple(SelectionPos, SelectionPos)
      if @selection_start < @selection_end
        {@selection_start, @selection_end}
      else
        {@selection_end, @selection_start}
      end
    end

    # Check if position is within selection
    private def in_selection?(line : Int32, col : Int32) : Bool
      return false unless @has_selection

      start_pos, end_pos = selection_bounds
      pos = SelectionPos.new(line, col)

      pos >= start_pos && pos < end_pos
    end

    # Get selected text as plain text
    def selected_text : String
      return "" unless @has_selection

      start_pos, end_pos = selection_bounds
      result = String.build do |s|
        (start_pos.line..end_pos.line).each do |line_idx|
          next unless line = @rendered_lines[line_idx]?

          start_col = (line_idx == start_pos.line) ? start_pos.col : 0
          end_col = (line_idx == end_pos.line) ? end_pos.col : line.size

          (start_col...end_col).each do |col_idx|
            if cell = line[col_idx]?
              s << cell[0]  # The character
            end
          end

          # Add newline between lines (but not after last line)
          s << '\n' if line_idx < end_pos.line
        end
      end
      result
    end

    # Copy selection to clipboard (cross-platform: macOS, Linux)
    def copy_selection_to_clipboard : Bool
      text = selected_text
      return false if text.empty?

      {% if flag?(:darwin) %}
        copy_to_clipboard_macos(text)
      {% elsif flag?(:linux) %}
        copy_to_clipboard_linux(text)
      {% else %}
        false
      {% end %}
    end

    # macOS clipboard copy
    private def copy_to_clipboard_macos(text : String) : Bool
      begin
        process = Process.new("pbcopy", shell: false, input: Process::Redirect::Pipe)
        process.input.print(text)
        process.input.close
        process.wait
        true
      rescue
        false
      end
    end

    # Linux clipboard copy (tries xclip, then xsel)
    private def copy_to_clipboard_linux(text : String) : Bool
      # Try xclip first
      begin
        process = Process.new("xclip", ["-selection", "clipboard"], shell: false, input: Process::Redirect::Pipe)
        process.input.print(text)
        process.input.close
        process.wait
        return true
      rescue
        # xclip failed, try xsel
      end

      # Fallback to xsel
      begin
        process = Process.new("xsel", ["--clipboard", "--input"], shell: false, input: Process::Redirect::Pipe)
        process.input.print(text)
        process.input.close
        process.wait
        true
      rescue
        false
      end
    end

    # Clear selection
    def clear_selection : Nil
      @has_selection = false
      @selecting = false
      mark_dirty!
    end

    # Check if there's an active selection
    def has_selection? : Bool
      @has_selection
    end

    # Apply view's background color to a style if bg is default
    private def with_background(style : Style) : Style
      if bg = @background
        # Only override if style has default background
        if style.bg.default?
          Style.new(fg: style.fg, bg: bg, attrs: style.attrs)
        else
          style
        end
      else
        style
      end
    end

    # Set markdown content (full replace)
    def content=(markdown : String) : Nil
      # Check if we're at bottom before changing content
      # Only auto-scroll if rect is valid (height > 0), otherwise scroll calculation is meaningless
      was_at_bottom = @rect.height > 0 && at_bottom?

      @raw_markdown = markdown
      @document = Markdown.parse(markdown)
      render_to_lines

      # Auto-scroll to bottom if we were already at bottom
      if was_at_bottom
        scroll_to_bottom
      end

      mark_dirty!
    end

    # Check if scrolled to bottom (or within 2 lines of bottom)
    def at_bottom? : Bool
      @scroll_y >= max_scroll - 2
    end

    def content : String
      @raw_markdown
    end

    # Append text (for streaming)
    def append(text : String) : Nil
      @raw_markdown += text
      @document = Markdown.parse(@raw_markdown)
      render_to_lines
      # Auto-scroll to bottom when streaming
      if @streaming
        scroll_to_bottom
      end
      mark_dirty!
    end

    # Clear content
    def clear : Nil
      @raw_markdown = ""
      @document.clear
      @rendered_lines.clear
      @scroll_y = 0
      @content_height = 0
      mark_dirty!
    end

    # Start streaming mode
    def start_streaming : Nil
      @streaming = true
      mark_dirty!
    end

    # End streaming mode
    def stop_streaming : Nil
      @streaming = false
      mark_dirty!
    end

    # Callbacks
    def on_link_click(&block : String -> Nil) : Nil
      @on_link_click = block
    end

    def on_code_copy(&block : String -> Nil) : Nil
      @on_code_copy = block
    end

    # Scrolling
    def scroll_up(lines : Int32 = 1) : Nil
      @scroll_y = (@scroll_y - lines).clamp(0, max_scroll)
      mark_dirty!
    end

    def scroll_down(lines : Int32 = 1) : Nil
      @scroll_y = (@scroll_y + lines).clamp(0, max_scroll)
      mark_dirty!
    end

    def scroll_to_top : Nil
      @scroll_y = 0
      mark_dirty!
    end

    def scroll_to_bottom : Nil
      @scroll_y = max_scroll
      mark_dirty!
    end

    def page_up : Nil
      scroll_up(@rect.height)
    end

    def page_down : Nil
      scroll_down(@rect.height)
    end

    private def max_scroll : Int32
      (@content_height - @rect.height).clamp(0, Int32::MAX)
    end

    # Pre-render to line buffer
    private def render_to_lines : Nil
      @rendered_lines.clear
      @details_regions.clear
      @rendered_with_default_width = @rect.width == 0

      # Use width minus 1 to leave room for scrollbar
      # We always render at scrollbar-aware width for consistency
      # (better to have slightly narrower content than missing chars when scrollbar appears)
      full_width = @rect.width > 0 ? @rect.width : 80  # Default width
      width = full_width > 1 ? full_width - 1 : full_width  # Reserve scrollbar column
      @last_render_width = full_width  # Track full width for change detection

      @document.each do |block|
        case block.type
        when .heading1?
          add_blank_line
          render_inline_to_lines(block.elements, @heading1_style, width)
          add_blank_line
        when .heading2?
          add_blank_line
          render_inline_to_lines(block.elements, @heading2_style, width)
          add_blank_line
        when .heading3?
          render_inline_to_lines(block.elements, @heading3_style, width)
        when .heading4?
          render_inline_to_lines(block.elements, @heading4_style, width)
        when .paragraph?
          render_inline_to_lines(block.elements, @text_style, width)
          add_blank_line
        when .code_block?
          render_code_block(block.code || "", block.language, width)
          add_blank_line
        when .unordered_list?
          block.items.try &.each_with_index do |item, i|
            render_list_item("•", item, width)
          end
          add_blank_line
        when .ordered_list?
          block.items.try &.each_with_index do |item, i|
            render_list_item("#{i + 1}.", item, width)
          end
          add_blank_line
        when .blockquote?
          render_blockquote(block.elements, width)
          add_blank_line
        when .horizontal_rule?
          render_hr(width)
          add_blank_line
        when .table?
          render_table(block, width)
          add_blank_line
        when .details?
          render_details(block, width)
          add_blank_line
        end
      end

      @content_height = @rendered_lines.size
    end

    private def add_blank_line : Nil
      @rendered_lines << [] of Tuple(Char, Style)
    end

    private def render_inline_to_lines(
      elements : Array(Markdown::InlineElement),
      base_style : Style,
      width : Int32,
      prefix : String = "",
      prefix_style : Style? = nil
    ) : Nil
      line = [] of Tuple(Char, Style)
      display_width = 0  # Track display width, not character count

      # Add prefix
      prefix.each_char do |c|
        line << {c, prefix_style || base_style}
        display_width += Unicode.char_width(c)
      end

      prefix_display_width = display_width  # Remember prefix width for wrapped lines

      elements.each do |elem|
        style = case elem.type
                when .text?          then base_style
                when .bold?          then @bold_style
                when .italic?        then @italic_style
                when .bold_italic?   then Style.new(fg: Color.white, attrs: Attributes::Bold | Attributes::Italic)
                when .code?          then @code_style
                when .link?          then @link_style
                when .strikethrough? then @strikethrough_style
                else                      base_style
                end

        elem.text.each_char do |c|
          char_w = Unicode.char_width(c)

          if c == '\n' || display_width + char_w > width
            @rendered_lines << line
            line = [] of Tuple(Char, Style)
            display_width = 0
            # Continue with same indent for wrapped lines
            prefix_display_width.times do
              line << {' ', base_style}
              display_width += 1
            end
          end

          unless c == '\n'
            line << {c, style}
            display_width += char_w
          end
        end
      end

      @rendered_lines << line unless line.empty?
    end

    private def render_code_block(code : String, language : String?, width : Int32) : Nil
      # Top border with language
      top_line = [] of Tuple(Char, Style)
      top_line << {'┌', @code_block_border}
      if lang = language
        top_line << {'─', @code_block_border}
        top_line << {' ', @code_block_border}
        lang.each_char { |c| top_line << {c, @code_block_border} }
        top_line << {' ', @code_block_border}
      end
      remaining = width - top_line.size - 1
      remaining.times { top_line << {'─', @code_block_border} }
      top_line << {'┐', @code_block_border}
      @rendered_lines << top_line

      # Code lines
      code.lines.each do |code_line|
        line = [] of Tuple(Char, Style)
        line << {'│', @code_block_border}
        line << {' ', @code_block_style}

        # Track display width (not character count) for proper alignment
        display_width = 2  # │ + space
        code_line.each_char do |c|
          char_w = Unicode.char_width(c)
          break if display_width + char_w > width - 2  # Leave room for space + │
          line << {c, @code_block_style}
          display_width += char_w
        end

        # Pad to width using display width
        while display_width < width - 1
          line << {' ', @code_block_style}
          display_width += 1
        end
        line << {'│', @code_block_border}
        @rendered_lines << line
      end

      # Bottom border
      bottom_line = [] of Tuple(Char, Style)
      bottom_line << {'└', @code_block_border}
      (width - 2).times { bottom_line << {'─', @code_block_border} }
      bottom_line << {'┘', @code_block_border}
      @rendered_lines << bottom_line
    end

    private def render_list_item(bullet : String, item : Markdown::ListItem, width : Int32) : Nil
      indent = "  " * item.indent
      prefix = "#{indent}#{bullet} "
      render_inline_to_lines(item.elements, @text_style, width, prefix, @list_bullet_style)
    end

    private def render_blockquote(elements : Array(Markdown::InlineElement), width : Int32) : Nil
      render_inline_to_lines(elements, @blockquote_style, width - 2, "│ ", @blockquote_bar)
    end

    private def render_hr(width : Int32) : Nil
      line = [] of Tuple(Char, Style)
      width.times { line << {'─', @hr_style} }
      @rendered_lines << line
    end

    private def render_details(block : Markdown::Block, width : Int32) : Nil
      details_id = block.details_id || "details-unknown"
      summary = block.summary || "Details"
      is_expanded = @expanded_details.includes?(details_id)

      # Record the line index for click detection
      header_line_idx = @rendered_lines.size

      # Render header: ▶ Summary (or ▼ Summary if expanded)
      header_line = [] of Tuple(Char, Style)
      toggle_char = is_expanded ? @details_expanded_char : @details_collapsed_char
      header_line << {toggle_char, @details_header_style}
      header_line << {' ', @details_header_style}
      summary.each_char do |c|
        break if header_line.size >= width
        header_line << {c, @details_header_style}
      end
      @rendered_lines << header_line

      # Store clickable region (will be adjusted in render based on scroll)
      # Store line index and id for click detection
      @details_regions << {Rect.new(0, header_line_idx, width, 1), details_id}

      # If expanded, render content
      if is_expanded && (content = block.details_content)
        # Parse and render content as sub-document
        content.lines.each do |content_line|
          line = [] of Tuple(Char, Style)
          line << {' ', @details_content_style}
          line << {' ', @details_content_style}
          line << {'│', Style.new(fg: Color.palette(240))}
          line << {' ', @details_content_style}
          content_line.each_char do |c|
            break if line.size >= width
            line << {c, @details_content_style}
          end
          @rendered_lines << line
        end
      end
    end

    # Toggle details expanded/collapsed state
    def toggle_details(details_id : String) : Nil
      if @expanded_details.includes?(details_id)
        @expanded_details.delete(details_id)
      else
        @expanded_details << details_id
      end
      render_to_lines
      mark_dirty!
    end

    # Expand all details
    def expand_all_details : Nil
      @document.each do |block|
        if block.type.details? && (id = block.details_id)
          @expanded_details << id
        end
      end
      render_to_lines
      mark_dirty!
    end

    # Collapse all details
    def collapse_all_details : Nil
      @expanded_details.clear
      render_to_lines
      mark_dirty!
    end

    private def render_table(block : Markdown::Block, max_width : Int32) : Nil
      rows = block.rows || return
      col_widths = block.col_widths || return
      return if rows.empty? || col_widths.empty?

      # Calculate total table width
      # │ cell │ cell │ = 1 + (col_width + 3) * cols
      total_width = 1 + col_widths.sum { |w| w + 3 }

      # Scale down if too wide
      if total_width > max_width && col_widths.size > 0
        scale = (max_width - 1).to_f / (total_width - 1)
        col_widths = col_widths.map { |w| (w * scale).to_i.clamp(3, w) }
      end

      # Top border: ┌───┬───┐
      render_table_border(col_widths, '┌', '┬', '┐', '─')

      rows.each_with_index do |row, row_idx|
        # Content row
        line = [] of Tuple(Char, Style)
        line << {'│', @table_border_style}

        row.cells.each_with_index do |cell, col_idx|
          col_w = col_widths[col_idx]? || 10
          style = row.header? ? @table_header_style : @table_cell_style

          # Render cell content
          text = cell.elements.map(&.text).join
          text = text[0, col_w] if text.size > col_w

          # Apply alignment
          padded = case cell.align
                   when :center
                     pad_left = (col_w - text.size) // 2
                     pad_right = col_w - text.size - pad_left
                     " " * pad_left + text + " " * pad_right
                   when :right
                     text.rjust(col_w)
                   else
                     text.ljust(col_w)
                   end

          line << {' ', style}
          padded.each_char { |c| line << {c, style} }
          line << {' ', style}
          line << {'│', @table_border_style}
        end

        @rendered_lines << line

        # After header, draw separator: ├───┼───┤
        if row.header? && row_idx == 0
          render_table_border(col_widths, '├', '┼', '┤', '─')
        end
      end

      # Bottom border: └───┴───┘
      render_table_border(col_widths, '└', '┴', '┘', '─')
    end

    private def render_table_border(col_widths : Array(Int32), left : Char, mid : Char, right : Char, fill : Char) : Nil
      line = [] of Tuple(Char, Style)
      line << {left, @table_border_style}

      col_widths.each_with_index do |w, i|
        (w + 2).times { line << {fill, @table_border_style} }
        line << {(i < col_widths.size - 1 ? mid : right), @table_border_style}
      end

      @rendered_lines << line
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      # Re-render if width changed
      if @rect.width > 0 && (@rendered_lines.empty? || need_rerender?)
        render_to_lines
      end

      # CRITICAL: Invalidate the entire region to force terminal update
      # This ensures ghost characters from previous frames are always cleared
      buffer.invalidate_region(@rect.x, @rect.y, @rect.width, @rect.height)

      # Determine background: explicit @background > @text_style.bg > nil (parent controls)
      clear_bg = @background || @text_style.bg

      # Render visible lines with proper clearing
      visible_lines = @rect.height
      has_scrollbar = @content_height > @rect.height

      visible_lines.times do |screen_row|
        line_idx = @scroll_y + screen_row
        y = @rect.y + screen_row

        # Clear line to space characters
        clear_style = if clear_bg && !clear_bg.default?
                        Style.new(fg: @text_style.fg, bg: clear_bg)
                      else
                        Style.default
                      end
        # Always clear full width including scrollbar column
        @rect.width.times do |col|
          px = @rect.x + col
          buffer.set(px, y, ' ', clear_style)
        end

        # Skip if past content
        next if line_idx >= @rendered_lines.size

        line = @rendered_lines[line_idx]

        # Content is pre-rendered at correct width (minus scrollbar space)
        # Just need to render characters tracking display width for wide chars
        # content_width excludes scrollbar column when scrollbar present
        content_width = has_scrollbar ? @rect.width - 1 : @rect.width
        display_col = 0
        char_idx = 0
        line.each do |(char, style)|
          char_w = Unicode.char_width(char)

          # Stop if we've reached the content edge (before scrollbar)
          # Also check if a wide character would overflow into scrollbar column
          break if display_col >= content_width
          break if display_col + char_w > content_width && char_w > 1

          x = @rect.x + display_col
          if clip.contains?(x, y)
            # Apply view's background to style if needed
            final_style = with_background(style)

            # Apply selection highlight if position is in selection
            if in_selection?(line_idx, char_idx)
              final_style = Style.new(fg: final_style.fg, bg: @selection_bg, attrs: final_style.attrs)
            end

            # Use set_wide to properly handle wide characters (emoji, CJK)
            # This sets both the main cell and continuation cell for width-2 chars
            char_width = buffer.set_wide(x, y, char, final_style)
            display_col += char_width
          else
            # Still advance display_col even if not clipped
            display_col += char_w
          end
          char_idx += 1
        end
      end

      # Draw streaming cursor
      if @streaming && !@rendered_lines.empty?
        last_line_idx = @content_height - 1
        if last_line_idx >= @scroll_y && last_line_idx < @scroll_y + @rect.height
          screen_row = last_line_idx - @scroll_y
          last_line = @rendered_lines[last_line_idx]
          # Calculate actual display width (not character count)
          display_width = last_line.sum { |(char, _)| Unicode.char_width(char) }
          cursor_x = @rect.x + display_width
          cursor_y = @rect.y + screen_row
          # Respect scrollbar area
          max_cursor_x = has_scrollbar ? @rect.right - 1 : @rect.right
          if cursor_x < max_cursor_x
            buffer.set(cursor_x, cursor_y, @cursor_char, @cursor_style)
          end
        end
      end

      # Register scrollbar to be drawn AFTER all widgets render
      # This guarantees the scrollbar won't be overwritten by any content
      if @content_height > @rect.height
        register_scrollbar_overlay(buffer)
      end
    end

    # Register scrollbar drawing as a post-render overlay
    private def register_scrollbar_overlay(buffer : Buffer) : Nil
      # Capture the rect and scroll state for the overlay
      rect = @rect
      scroll_y = @scroll_y
      content_height = @content_height
      max_scroll_val = max_scroll

      Tui.register_scrollbar do |buf, clip|
        draw_scrollbar_overlay(buf, rect, scroll_y, content_height, max_scroll_val)
      end
    end

    # Draw scrollbar (called from overlay system, after all widgets render)
    private def draw_scrollbar_overlay(buffer : Buffer, rect : Rect, scroll_y : Int32, content_height : Int32, max_scroll_val : Int32) : Nil
      return if rect.height <= 0 || content_height <= 0
      return if rect.width <= 1

      sx = rect.right - 1
      track_height = rect.height

      return if sx < rect.x || sx >= rect.x + rect.width

      # CRITICAL: Force terminal update for scrollbar column
      # This ensures no artifacts from previous renders
      buffer.invalidate_region(sx, rect.y, 1, track_height)

      # Calculate thumb position and size
      thumb_height = (track_height.to_f * rect.height / content_height).clamp(1, track_height).to_i
      thumb_pos = if max_scroll_val > 0
                    (scroll_y.to_f / max_scroll_val * (track_height - thumb_height)).to_i
                  else
                    0
                  end

      track_style = Style.new(fg: Color.palette(238))
      thumb_style = Style.new(fg: Color.palette(244))

      track_height.times do |i|
        y = rect.y + i
        is_thumb = i >= thumb_pos && i < thumb_pos + thumb_height
        char = is_thumb ? '█' : '░'
        style = is_thumb ? thumb_style : track_style
        buffer.set(sx, y, char, style)
      end
    end

    private def need_rerender? : Bool
      # Re-render if width changed since last render, or if last render used default width
      @rendered_with_default_width || @rect.width != @last_render_width
    end

    # Check if scrollbar is visible
    private def has_scrollbar? : Bool
      @content_height > @rect.height
    end

    # Get scrollbar X position
    private def scrollbar_x : Int32
      @rect.right - 1
    end

    # Check if coordinates are on the scrollbar
    # Allow ±1 tolerance to handle terminal coordinate system differences
    private def on_scrollbar?(x : Int32, y : Int32) : Bool
      return false unless has_scrollbar?
      return false unless y >= @rect.y && y < @rect.bottom
      sx = scrollbar_x
      x >= sx && x <= sx + 1  # Check scrollbar position and one to the right
    end

    # Get scrollbar thumb position and height
    private def scrollbar_thumb_info : {pos: Int32, height: Int32}
      track_height = @rect.height
      thumb_height = (track_height.to_f * @rect.height / @content_height).clamp(1, track_height).to_i
      thumb_pos = if max_scroll > 0
                    (@scroll_y.to_f / max_scroll * (track_height - thumb_height)).to_i
                  else
                    0
                  end
      {pos: thumb_pos, height: thumb_height}
    end

    # Handle scrollbar click - returns true if handled
    private def handle_scrollbar_click(screen_y : Int32) : Bool
      return false unless has_scrollbar?

      rel_y = screen_y - @rect.y
      thumb = scrollbar_thumb_info

      if rel_y < thumb[:pos]
        # Click above thumb - page up
        page_up
      elsif rel_y >= thumb[:pos] + thumb[:height]
        # Click below thumb - page down
        page_down
      else
        # Click on thumb - start drag
        @scrollbar_dragging = true
        @scrollbar_drag_start_y = screen_y
        @scrollbar_drag_start_scroll = @scroll_y
      end

      mark_dirty!
      true
    end

    # Handle scrollbar drag
    private def handle_scrollbar_drag(screen_y : Int32) : Bool
      return false unless @scrollbar_dragging

      track_height = @rect.height
      thumb = scrollbar_thumb_info

      # Calculate scroll delta based on mouse movement
      delta_y = screen_y - @scrollbar_drag_start_y

      # Map pixel delta to scroll delta
      scrollable_track = track_height - thumb[:height]
      if scrollable_track > 0
        scroll_per_pixel = max_scroll.to_f / scrollable_track
        new_scroll = (@scrollbar_drag_start_scroll + delta_y * scroll_per_pixel).to_i
        @scroll_y = new_scroll.clamp(0, max_scroll)
        mark_dirty!
      end

      true
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when KeyEvent
        case event.key
        when .up?
          scroll_up
          event.stop!
          return true
        when .down?
          scroll_down
          event.stop!
          return true
        when .page_up?
          page_up
          event.stop!
          return true
        when .page_down?
          page_down
          event.stop!
          return true
        when .home?
          scroll_to_top
          event.stop!
          return true
        when .end?
          scroll_to_bottom
          event.stop!
          return true
        end

        # j/k vim-style scrolling
        if event.char == 'j'
          scroll_down
          event.stop!
          return true
        elsif event.char == 'k'
          scroll_up
          event.stop!
          return true
        end

        # Ctrl+C / Cmd+C to copy selection
        if event.matches?("ctrl+c") && @has_selection
          copy_selection_to_clipboard
          event.stop!
          return true
        end

        # Escape to clear selection
        if event.key.escape? && @has_selection
          clear_selection
          event.stop!
          return true
        end

      when MouseEvent
        if event.button.wheel_up?
          scroll_up(3)
          event.stop!
          return true
        elsif event.button.wheel_down?
          scroll_down(3)
          event.stop!
          return true
        elsif event.action.press? && event.button.left?
          # Check for scrollbar click first (classic TUI behavior)
          if on_scrollbar?(event.x, event.y)
            handle_scrollbar_click(event.y)
            event.stop!
            return true
          end

          if event.in_rect?(@rect)
            # Check for click on details header first
            screen_y = event.y - @rect.y
            content_line = @scroll_y + screen_y

            header_clicked = false
            @details_regions.each do |(region, details_id)|
              if region.y == content_line
                toggle_details(details_id)
                event.stop!
                header_clicked = true
                break
              end
            end
            return true if header_clicked

            # Start text selection
            @selection_start = screen_to_content_pos(event.x, event.y)
            @selection_end = @selection_start
            @selecting = true
            @has_selection = false  # No selection until drag
            mark_dirty!
            event.stop!
            return true
          end
        elsif event.action.drag? && event.button.left?
          # Handle scrollbar drag first
          if @scrollbar_dragging
            handle_scrollbar_drag(event.y)
            event.stop!
            return true
          end

          # Continue text selection
          if @selecting && event.in_rect?(@rect)
            @selection_end = screen_to_content_pos(event.x, event.y)
            @has_selection = !(@selection_start == @selection_end)
            mark_dirty!
            event.stop!
            return true
          end
        elsif event.action.release? && event.button.left?
          # End scrollbar drag
          if @scrollbar_dragging
            @scrollbar_dragging = false
            event.stop!
            return true
          end

          # Finish text selection
          if @selecting
            @selecting = false
            if @has_selection
              # Auto-copy to clipboard on selection complete
              copy_selection_to_clipboard
            end
            event.stop!
            return true
          end
        end
      end

      false
    end
  end
end
