require "../../spec_helper"

describe Tui::Markdown::Parser do
  describe "headings" do
    it "parses H1" do
      doc = Tui::Markdown.parse("# Hello World")
      doc.size.should eq 1
      doc[0].type.should eq Tui::Markdown::BlockType::Heading1
      doc[0].elements.size.should eq 1
      doc[0].elements[0].text.should eq "Hello World"
    end

    it "parses H2" do
      doc = Tui::Markdown.parse("## Section")
      doc[0].type.should eq Tui::Markdown::BlockType::Heading2
    end

    it "parses H3" do
      doc = Tui::Markdown.parse("### Subsection")
      doc[0].type.should eq Tui::Markdown::BlockType::Heading3
    end

    it "parses H4" do
      doc = Tui::Markdown.parse("#### Minor")
      doc[0].type.should eq Tui::Markdown::BlockType::Heading4
    end

    it "handles inline formatting in headings" do
      doc = Tui::Markdown.parse("# Hello **World**")
      doc[0].elements.size.should eq 2
      doc[0].elements[0].text.should eq "Hello "
      doc[0].elements[1].type.should eq Tui::Markdown::InlineType::Bold
      doc[0].elements[1].text.should eq "World"
    end
  end

  describe "paragraphs" do
    it "parses simple paragraph" do
      doc = Tui::Markdown.parse("This is a paragraph.")
      doc.size.should eq 1
      doc[0].type.should eq Tui::Markdown::BlockType::Paragraph
      doc[0].elements[0].text.should eq "This is a paragraph."
    end

    it "joins multiple lines into one paragraph" do
      doc = Tui::Markdown.parse("Line one\nLine two")
      doc.size.should eq 1
      doc[0].elements[0].text.should eq "Line one Line two"
    end

    it "separates paragraphs by blank line" do
      doc = Tui::Markdown.parse("Para one\n\nPara two")
      doc.size.should eq 2
      doc[0].elements[0].text.should eq "Para one"
      doc[1].elements[0].text.should eq "Para two"
    end
  end

  describe "code blocks" do
    it "parses code block" do
      doc = Tui::Markdown.parse("```\ncode here\n```")
      doc.size.should eq 1
      doc[0].type.should eq Tui::Markdown::BlockType::CodeBlock
      doc[0].code.should eq "code here"
      doc[0].language.should be_nil
    end

    it "parses code block with language" do
      doc = Tui::Markdown.parse("```crystal\ndef foo\n  bar\nend\n```")
      doc[0].type.should eq Tui::Markdown::BlockType::CodeBlock
      doc[0].language.should eq "crystal"
      doc[0].code.should eq "def foo\n  bar\nend"
    end

    it "parses multiple code blocks" do
      md = "```ruby\nputs 1\n```\n\nText\n\n```python\nprint(2)\n```"
      doc = Tui::Markdown.parse(md)
      doc.size.should eq 3
      doc[0].type.should eq Tui::Markdown::BlockType::CodeBlock
      doc[0].language.should eq "ruby"
      doc[1].type.should eq Tui::Markdown::BlockType::Paragraph
      doc[2].type.should eq Tui::Markdown::BlockType::CodeBlock
      doc[2].language.should eq "python"
    end
  end

  describe "inline formatting" do
    it "parses bold with **" do
      doc = Tui::Markdown.parse("This is **bold** text")
      doc[0].elements.size.should eq 3
      doc[0].elements[1].type.should eq Tui::Markdown::InlineType::Bold
      doc[0].elements[1].text.should eq "bold"
    end

    it "parses bold with __" do
      doc = Tui::Markdown.parse("This is __bold__ text")
      doc[0].elements[1].type.should eq Tui::Markdown::InlineType::Bold
    end

    it "parses italic with *" do
      doc = Tui::Markdown.parse("This is *italic* text")
      doc[0].elements[1].type.should eq Tui::Markdown::InlineType::Italic
      doc[0].elements[1].text.should eq "italic"
    end

    it "parses italic with _" do
      doc = Tui::Markdown.parse("This is _italic_ text")
      doc[0].elements[1].type.should eq Tui::Markdown::InlineType::Italic
    end

    it "parses bold+italic with ***" do
      doc = Tui::Markdown.parse("This is ***bolditalic*** text")
      doc[0].elements[1].type.should eq Tui::Markdown::InlineType::BoldItalic
      doc[0].elements[1].text.should eq "bolditalic"
    end

    it "parses inline code" do
      doc = Tui::Markdown.parse("Use `foo()` function")
      doc[0].elements[1].type.should eq Tui::Markdown::InlineType::Code
      doc[0].elements[1].text.should eq "foo()"
    end

    it "parses strikethrough" do
      doc = Tui::Markdown.parse("This is ~~deleted~~ text")
      doc[0].elements[1].type.should eq Tui::Markdown::InlineType::Strikethrough
      doc[0].elements[1].text.should eq "deleted"
    end

    it "parses links" do
      doc = Tui::Markdown.parse("Check [this link](https://example.com)")
      doc[0].elements[1].type.should eq Tui::Markdown::InlineType::Link
      doc[0].elements[1].text.should eq "this link"
      doc[0].elements[1].url.should eq "https://example.com"
    end

    it "handles multiple inline elements" do
      doc = Tui::Markdown.parse("**bold** and *italic* and `code`")
      doc[0].elements.size.should eq 5  # bold, " and ", italic, " and ", code
      doc[0].elements[0].type.should eq Tui::Markdown::InlineType::Bold
      doc[0].elements[2].type.should eq Tui::Markdown::InlineType::Italic
      doc[0].elements[4].type.should eq Tui::Markdown::InlineType::Code
    end
  end

  describe "lists" do
    it "parses unordered list with -" do
      doc = Tui::Markdown.parse("- Item 1\n- Item 2\n- Item 3")
      doc.size.should eq 1
      doc[0].type.should eq Tui::Markdown::BlockType::UnorderedList
      items = doc[0].items.not_nil!
      items.size.should eq 3
      items[0].elements[0].text.should eq "Item 1"
      items[1].elements[0].text.should eq "Item 2"
      items[2].elements[0].text.should eq "Item 3"
    end

    it "parses unordered list with *" do
      doc = Tui::Markdown.parse("* One\n* Two")
      doc[0].type.should eq Tui::Markdown::BlockType::UnorderedList
    end

    it "parses ordered list" do
      doc = Tui::Markdown.parse("1. First\n2. Second\n3. Third")
      doc.size.should eq 1
      doc[0].type.should eq Tui::Markdown::BlockType::OrderedList
      items = doc[0].items.not_nil!
      items.size.should eq 3
      items[0].elements[0].text.should eq "First"
    end

    it "handles inline formatting in list items" do
      doc = Tui::Markdown.parse("- This is **bold** item")
      items = doc[0].items.not_nil!
      items[0].elements.size.should eq 3
      items[0].elements[1].type.should eq Tui::Markdown::InlineType::Bold
    end

    it "handles nested list indentation" do
      doc = Tui::Markdown.parse("- Item 1\n  - Nested\n- Item 2")
      items = doc[0].items.not_nil!
      items.size.should eq 3
      items[1].indent.should eq 1
    end
  end

  describe "blockquotes" do
    it "parses single line blockquote" do
      doc = Tui::Markdown.parse("> Quote here")
      doc.size.should eq 1
      doc[0].type.should eq Tui::Markdown::BlockType::Blockquote
      doc[0].elements[0].text.should eq "Quote here"
    end

    it "parses multi-line blockquote" do
      doc = Tui::Markdown.parse("> Line 1\n> Line 2")
      doc[0].elements[0].text.should eq "Line 1 Line 2"
    end
  end

  describe "horizontal rule" do
    it "parses ---" do
      doc = Tui::Markdown.parse("---")
      doc.size.should eq 1
      doc[0].type.should eq Tui::Markdown::BlockType::HorizontalRule
    end

    it "parses ***" do
      doc = Tui::Markdown.parse("***")
      doc[0].type.should eq Tui::Markdown::BlockType::HorizontalRule
    end

    it "parses ___" do
      doc = Tui::Markdown.parse("___")
      doc[0].type.should eq Tui::Markdown::BlockType::HorizontalRule
    end

    it "parses with extra dashes" do
      doc = Tui::Markdown.parse("----------")
      doc[0].type.should eq Tui::Markdown::BlockType::HorizontalRule
    end
  end

  describe "tables" do
    it "parses simple table" do
      md = "| A | B |\n|---|---|\n| 1 | 2 |"
      doc = Tui::Markdown.parse(md)
      doc.size.should eq 1
      doc[0].type.should eq Tui::Markdown::BlockType::Table
      rows = doc[0].rows.not_nil!
      rows.size.should eq 2  # header + 1 data row
      rows[0].header?.should be_true
      rows[0].cells.size.should eq 2
      rows[0].cells[0].elements[0].text.should eq "A"
      rows[1].cells[0].elements[0].text.should eq "1"
    end

    it "parses table with multiple rows" do
      md = "| Name | Age |\n|------|-----|\n| Alice | 30 |\n| Bob | 25 |"
      doc = Tui::Markdown.parse(md)
      rows = doc[0].rows.not_nil!
      rows.size.should eq 3
      rows[2].cells[0].elements[0].text.should eq "Bob"
    end

    it "parses table alignment" do
      md = "| Left | Center | Right |\n|:-----|:------:|------:|\n| a | b | c |"
      doc = Tui::Markdown.parse(md)
      rows = doc[0].rows.not_nil!
      rows[0].cells[0].align.should eq :left
      rows[0].cells[1].align.should eq :center
      rows[0].cells[2].align.should eq :right
    end

    it "handles table without leading pipe" do
      md = "A | B\n---|---\n1 | 2"
      doc = Tui::Markdown.parse(md)
      doc[0].type.should eq Tui::Markdown::BlockType::Table
    end

    it "calculates column widths" do
      md = "| Short | Longer text |\n|-------|-------------|\n| a | b |"
      doc = Tui::Markdown.parse(md)
      widths = doc[0].col_widths.not_nil!
      widths[0].should eq 5  # "Short"
      widths[1].should eq 11 # "Longer text"
    end
  end

  describe "complex document" do
    it "parses mixed content" do
      md = <<-MD
      # Welcome

      This is a **test** document.

      ## Features

      - Feature one
      - Feature two

      ```crystal
      puts "hello"
      ```

      > A quote

      ---

      [Link](https://example.com)
      MD

      doc = Tui::Markdown.parse(md)
      doc.size.should be > 5
      doc[0].type.should eq Tui::Markdown::BlockType::Heading1
    end
  end
end
