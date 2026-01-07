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

    # A block of content
    struct Block
      property type : BlockType
      property elements : Array(InlineElement)  # For paragraph, heading
      property language : String?               # For code blocks
      property code : String?                   # For code blocks (raw code)
      property items : Array(ListItem)?         # For lists

      def initialize(
        @type : BlockType,
        @elements : Array(InlineElement) = [] of InlineElement,
        @language : String? = nil,
        @code : String? = nil,
        @items : Array(ListItem)? = nil
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

        # Paragraph (default)
        parse_paragraph
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

          # Bold+Italic: ***text*** or ___text___
          if m = remaining.match(/^\*\*\*(.+?)\*\*\*/) || remaining.match(/^___(.+?)___/)
            flush_text(elements, current_text)
            current_text = ""
            elements << InlineElement.new(InlineType::BoldItalic, m[1])
            pos += m[0].size
            next
          end

          # Bold: **text** or __text__
          if m = remaining.match(/^\*\*(.+?)\*\*/) || remaining.match(/^__(.+?)__/)
            flush_text(elements, current_text)
            current_text = ""
            elements << InlineElement.new(InlineType::Bold, m[1])
            pos += m[0].size
            next
          end

          # Italic: *text* or _text_
          if m = remaining.match(/^\*([^*]+?)\*/) || remaining.match(/^_([^_]+?)_/)
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

          # Inline code: `text`
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
  end
end
