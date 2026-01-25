# Markdown parser for TUI rendering
module Tui
  module Markdown
    # Block types
    enum BlockType
      Paragraph
      Heading1
      Heading2
      Heading3
      Heading4
      CodeBlock
      UnorderedList
      OrderedList
      HorizontalRule
      Blockquote
      Table
      Details  # Collapsible section
    end

    # Inline element types
    enum InlineType
      Text
      Bold
      Italic
      BoldItalic
      Code
      Link
      Strikethrough
    end

    # Inline element within a block
    struct InlineElement
      property type : InlineType
      property text : String
      property url : String?

      def initialize(@type : InlineType, @text : String, @url : String? = nil)
      end
    end

    # List item (can have nested inline elements)
    struct ListItem
      property elements : Array(InlineElement)
      property indent : Int32

      def initialize(@elements : Array(InlineElement) = [] of InlineElement, @indent : Int32 = 0)
      end
    end

    # Table cell
    struct TableCell
      property elements : Array(InlineElement)
      property align : Symbol  # :left, :center, :right

      def initialize(@elements : Array(InlineElement) = [] of InlineElement, @align : Symbol = :left)
      end
    end

    # Table row
    struct TableRow
      property cells : Array(TableCell)
      property? header : Bool

      def initialize(@cells : Array(TableCell) = [] of TableCell, @header : Bool = false)
      end
    end

    # A block of content
    struct Block
      property type : BlockType
      property elements : Array(InlineElement)  # For paragraph, heading
      property language : String?               # For code blocks
      property code : String?                   # For code blocks (raw code)
      property items : Array(ListItem)?         # For lists
      property rows : Array(TableRow)?          # For tables
      property col_widths : Array(Int32)?       # For tables
      property summary : String?                # For details (collapsible)
      property details_content : String?        # For details (inner content)
      property details_id : String?             # For details (unique id for state)

      def initialize(
        @type : BlockType,
        @elements : Array(InlineElement) = [] of InlineElement,
        @language : String? = nil,
        @code : String? = nil,
        @items : Array(ListItem)? = nil,
        @rows : Array(TableRow)? = nil,
        @col_widths : Array(Int32)? = nil,
        @summary : String? = nil,
        @details_content : String? = nil,
        @details_id : String? = nil
      )
      end
    end

    # Document is array of blocks
    alias Document = Array(Block)

    # Main parser class
    class Parser
      @lines : Array(String)
      @pos : Int32 = 0

      def initialize(markdown : String)
        @lines = markdown.lines
      end

      def parse : Document
        blocks = [] of Block
        while @pos < @lines.size
          block = parse_block
          blocks << block if block
        end
        blocks
      end

      private def current_line : String?
        @lines[@pos]?
      end

      private def advance : Nil
        @pos += 1
      end

      private def parse_block : Block?
        line = current_line
        return nil unless line

        # Empty line - skip
        if line.strip.empty?
          advance
          return nil
        end

        # Horizontal rule: ---, ***, ___
        if line =~ /^(\s*[-*_]){3,}\s*$/
          advance
          return Block.new(BlockType::HorizontalRule)
        end

        # Headings: # ## ### ####
        if m = line.match(/^(\#{1,4})\s+(.+)$/)
          advance
          level = m[1].size
          content = m[2]
          type = case level
                 when 1 then BlockType::Heading1
                 when 2 then BlockType::Heading2
                 when 3 then BlockType::Heading3
                 else        BlockType::Heading4
                 end
          return Block.new(type, parse_inline(content))
        end

        # Code block: ```language
        if line.starts_with?("```")
          return parse_code_block
        end

        # Details block: <details>
        if line.strip.starts_with?("<details")
          return parse_details
        end

        # Blockquote: >
        if line.starts_with?(">")
          return parse_blockquote
        end

        # Unordered list: - * +
        if line =~ /^(\s*)[-*+]\s+/
          return parse_unordered_list
        end

        # Ordered list: 1. 2.
        if line =~ /^(\s*)\d+\.\s+/
          return parse_ordered_list
        end

        # Table: | col1 | col2 |
        if line.starts_with?("|") || (line.includes?("|") && next_line_is_table_separator?)
          return parse_table
        end

        # Paragraph (default)
        parse_paragraph
      end

      private def next_line_is_table_separator? : Bool
        next_line = @lines[@pos + 1]?
        return false unless next_line
        next_line =~ /^\|?[\s\-:|]+\|[\s\-:|]*$/ ? true : false
      end

      private def parse_code_block : Block
        first_line = current_line.not_nil!
        language = first_line[3..].strip
        language = nil if language.empty?
        advance

        code_lines = [] of String
        while (line = current_line) && !line.starts_with?("```")
          code_lines << line
          advance
        end
        advance if current_line  # Skip closing ```

        Block.new(
          BlockType::CodeBlock,
          language: language,
          code: code_lines.join("\n")
        )
      end

      # Parse <details><summary>...</summary>...</details>
      private def parse_details : Block
        advance  # Skip <details> line

        summary = "Details"
        content_lines = [] of String

        # Look for <summary>...</summary>
        while (line = current_line)
          stripped = line.strip

          # Check for summary tag
          if m = stripped.match(/<summary>(.+)<\/summary>/)
            summary = m[1]
            advance
            next
          end

          # End of details
          if stripped.starts_with?("</details")
            advance
            break
          end

          content_lines << line
          advance
        end

        # Generate stable ID based on a content preview
        # Use first non-empty, non-fence lines to reduce collisions for tool outputs.
        preview_lines = [] of String
        content_lines.each do |line|
          stripped = line.strip
          next if stripped.empty?
          next if stripped.starts_with?("```")
          preview_lines << stripped
          break if preview_lines.size >= 5
        end
        content_preview = preview_lines.join(" ")[0, 200]
        stable_key = "#{summary}:#{content_preview}"
        details_id = "details-#{stable_key.hash.abs}"

        Block.new(
          BlockType::Details,
          summary: summary,
          details_content: content_lines.join("\n"),
          details_id: details_id
        )
      end

      private def parse_blockquote : Block
        lines = [] of String
        while (line = current_line) && line.starts_with?(">")
          # Remove > and optional space
          content = line.lchop(">").lstrip
          lines << content
          advance
        end

        Block.new(BlockType::Blockquote, parse_inline(lines.join(" ")))
      end

      private def parse_unordered_list : Block
        items = [] of ListItem
        while (line = current_line)
          if m = line.match(/^(\s*)[-*+]\s+(.+)$/)
            indent = m[1].size // 2
            content = m[2]
            items << ListItem.new(parse_inline(content), indent)
            advance
          else
            break
          end
        end
        Block.new(BlockType::UnorderedList, items: items)
      end

      private def parse_ordered_list : Block
        items = [] of ListItem
        while (line = current_line)
          if m = line.match(/^(\s*)\d+\.\s+(.+)$/)
            indent = m[1].size // 2
            content = m[2]
            items << ListItem.new(parse_inline(content), indent)
            advance
          else
            break
          end
        end
        Block.new(BlockType::OrderedList, items: items)
      end

      private def parse_table : Block
        rows = [] of TableRow
        alignments = [] of Symbol
        col_widths = [] of Int32

        # Parse header row
        header_line = current_line.not_nil!
        header_cells = parse_table_row(header_line)
        rows << TableRow.new(header_cells, header: true)
        col_widths = header_cells.map { |c| cell_text_width(c) }
        advance

        # Parse separator row (|---|---|)
        if (sep_line = current_line) && sep_line =~ /^\|?[\s\-:|]+\|/
          alignments = parse_alignments(sep_line)
          advance
        else
          alignments = header_cells.map { :left }
        end

        # Apply alignments to header
        rows[0] = TableRow.new(
          header_cells.map_with_index { |cell, i|
            TableCell.new(cell.elements, alignments[i]? || :left)
          },
          header: true
        )

        # Parse data rows
        while (line = current_line)
          break unless line.includes?("|")
          break if line.strip.empty?

          cells = parse_table_row(line)
          # Apply alignments
          cells = cells.map_with_index { |cell, i|
            TableCell.new(cell.elements, alignments[i]? || :left)
          }
          rows << TableRow.new(cells, header: false)

          # Update column widths
          cells.each_with_index do |cell, i|
            w = cell_text_width(cell)
            if i < col_widths.size
              col_widths[i] = Math.max(col_widths[i], w)
            else
              col_widths << w
            end
          end

          advance
        end

        Block.new(BlockType::Table, rows: rows, col_widths: col_widths)
      end

      private def parse_table_row(line : String) : Array(TableCell)
        # Remove leading/trailing pipes and split
        content = line.strip
        content = content[1..] if content.starts_with?("|")
        content = content[..-2] if content.ends_with?("|")

        content.split("|").map do |cell_text|
          TableCell.new(parse_inline(cell_text.strip))
        end
      end

      private def parse_alignments(sep_line : String) : Array(Symbol)
        content = sep_line.strip
        content = content[1..] if content.starts_with?("|")
        content = content[..-2] if content.ends_with?("|")

        content.split("|").map do |col|
          col = col.strip
          if col.starts_with?(":") && col.ends_with?(":")
            :center
          elsif col.ends_with?(":")
            :right
          else
            :left
          end
        end
      end

      private def cell_text_width(cell : TableCell) : Int32
        cell.elements.sum { |e| Unicode.display_width(e.text) }
      end

      private def parse_paragraph : Block
        lines = [] of String
        while (line = current_line)
          # Stop at empty line or special syntax
          break if line.strip.empty?
          break if line =~ /^\#{1,4}\s/
          break if line.starts_with?("```")
          break if line.starts_with?(">")
          break if line =~ /^[-*+]\s/
          break if line =~ /^\d+\.\s/
          break if line =~ /^(\s*[-*_]){3,}\s*$/
          break if line.starts_with?("|")  # Table
          break if line.strip.starts_with?("<details")   # Details block
          break if line.strip.starts_with?("</details")  # End of details

          lines << line.strip
          advance
        end

        Block.new(BlockType::Paragraph, parse_inline(lines.join(" ")))
      end

      # Parse inline elements (bold, italic, code, links)
      private def parse_inline(text : String) : Array(InlineElement)
        elements = [] of InlineElement
        pos = 0
        current_text = ""

        while pos < text.size
          # Check for patterns at current position
          remaining = text[pos..]

          # Bold+Italic: ***text*** only
          # Note: ___ style disabled to protect variable_names_with_underscores
          if m = remaining.match(/^\*\*\*(.+?)\*\*\*/)
            flush_text(elements, current_text)
            current_text = ""
            elements << InlineElement.new(InlineType::BoldItalic, m[1])
            pos += m[0].size
            next
          end

          # Bold: **text** only
          # Note: __ style disabled to protect variable_names_with_underscores
          if m = remaining.match(/^\*\*(.+?)\*\*/)
            flush_text(elements, current_text)
            current_text = ""
            elements << InlineElement.new(InlineType::Bold, m[1])
            pos += m[0].size
            next
          end

          # Italic: *text* only
          # Note: _ style disabled to protect variable_names_with_underscores
          # Using only asterisks for emphasis avoids breaking code identifiers
          if m = remaining.match(/^\*([^*]+?)\*/)
            flush_text(elements, current_text)
            current_text = ""
            elements << InlineElement.new(InlineType::Italic, m[1])
            pos += m[0].size
            next
          end

          # Strikethrough: ~~text~~
          if m = remaining.match(/^~~(.+?)~~/)
            flush_text(elements, current_text)
            current_text = ""
            elements << InlineElement.new(InlineType::Strikethrough, m[1])
            pos += m[0].size
            next
          end

          # Inline code: ``text`` (double backticks) - check first
          if m = remaining.match(/^``([^`]|`[^`])+``/)
            flush_text(elements, current_text)
            current_text = ""
            # Extract content between double backticks, trim leading/trailing space
            code_content = m[0][2..-3].strip
            elements << InlineElement.new(InlineType::Code, code_content)
            pos += m[0].size
            next
          end

          # Inline code: `text` (single backticks)
          if m = remaining.match(/^`([^`]+)`/)
            flush_text(elements, current_text)
            current_text = ""
            elements << InlineElement.new(InlineType::Code, m[1])
            pos += m[0].size
            next
          end

          # Link: [text](url)
          if m = remaining.match(/^\[([^\]]+)\]\(([^)]+)\)/)
            flush_text(elements, current_text)
            current_text = ""
            elements << InlineElement.new(InlineType::Link, m[1], m[2])
            pos += m[0].size
            next
          end

          # Regular character
          current_text += text[pos]
          pos += 1
        end

        flush_text(elements, current_text)
        elements
      end

      private def flush_text(elements : Array(InlineElement), text : String) : Nil
        return if text.empty?
        elements << InlineElement.new(InlineType::Text, text)
      end
    end

    # Convenience method
    def self.parse(markdown : String) : Document
      Parser.new(markdown).parse
    end

    # Sanitize unclosed inline formatting markers
    # Call this on each message/block BEFORE concatenating to prevent
    # unclosed markers from affecting subsequent content
    def self.sanitize_unclosed(text : String) : String
      result = text
      chars = text.chars
      in_fence = false
      in_inline = false
      inline_ticks = 0
      outside = String.build do |io|
        i = 0
        while i < chars.size
          if !in_inline && i + 2 < chars.size &&
             chars[i] == '`' && chars[i + 1] == '`' && chars[i + 2] == '`'
            in_fence = !in_fence
            i += 3
            next
          end

          if !in_fence && chars[i] == '`'
            inline_ticks += 1
            in_inline = !in_inline
            i += 1
            next
          end

          io << chars[i] unless in_fence || in_inline
          i += 1
        end
      end

      # Close unclosed fenced code block if needed
      result += "\n```" if in_fence

      # Track markers that need closing (in order of specificity)
      # Check *** before ** before *

      # Count unmatched *** (bold+italic) outside code
      if outside.scan(/(?<!\*)\*\*\*(?!\*)/).size.odd?
        result += "***"
      end

      # Count unmatched ** (bold) - exclude *** patterns
      temp = outside.gsub(/\*\*\*/, "XXX")
      if temp.scan(/(?<!\*)\*\*(?!\*)/).size.odd?
        result += "**"
      end

      # Count unmatched * (italic) - exclude ** and *** patterns
      temp = outside.gsub(/\*\*\*/, "XXX").gsub(/\*\*/, "XX")
      if temp.scan(/(?<!\*)\*(?!\*)/).size.odd?
        result += "*"
      end

      # Count unmatched ~~ (strikethrough)
      if outside.scan(/~~/).size.odd?
        result += "~~"
      end

      # Count unmatched ` (inline code) outside fenced blocks
      result += "`" if inline_ticks.odd?

      result
    end
  end
end
