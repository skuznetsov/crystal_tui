require "../../spec_helper"

describe Tui::MarkdownView do
  describe "#content=" do
    it "parses markdown and populates rendered_lines" do
      view = Tui::MarkdownView.new("test")
      view.content = "# Hello"

      # Set rect so render_to_lines uses proper width
      view.rect = Tui::Rect.new(0, 0, 80, 24)

      # Content should be set
      view.content.should eq "# Hello"
    end

    it "handles multi-line content" do
      view = Tui::MarkdownView.new("test")
      view.content = "# Title\n\nParagraph text here."
      view.content.should contain "Title"
      view.content.should contain "Paragraph"
    end
  end

  describe "#background" do
    it "defaults to nil" do
      view = Tui::MarkdownView.new("test")
      view.background.should be_nil
    end

    it "can be set to a color" do
      view = Tui::MarkdownView.new("test")
      view.background = Tui::Color.blue
      view.background.should eq Tui::Color.blue
    end
  end

  describe "#render" do
    it "renders content to buffer with background" do
      view = Tui::MarkdownView.new("test")
      view.background = Tui::Color.blue
      view.content = "# Hello World"

      # Set rect
      rect = Tui::Rect.new(0, 0, 80, 24)
      view.rect = rect

      # Create buffer and clip
      buffer = Tui::Buffer.new(80, 24)
      clip = Tui::Rect.new(0, 0, 80, 24)

      # Render
      view.render(buffer, clip)

      # Check that something was rendered
      # The heading should appear on line 1 (after blank line)
      # Check for 'H' from "Hello"
      found_content = false
      24.times do |y|
        80.times do |x|
          cell = buffer.get(x, y)
          if cell.char == 'H'
            found_content = true
            # Should have blue background
            cell.style.bg.should eq Tui::Color.blue
            break
          end
        end
        break if found_content
      end

      found_content.should be_true
    end

    it "renders with correct foreground colors" do
      view = Tui::MarkdownView.new("test")
      view.background = Tui::Color.blue
      view.content = "# Heading"
      view.rect = Tui::Rect.new(0, 0, 80, 24)

      buffer = Tui::Buffer.new(80, 24)
      clip = Tui::Rect.new(0, 0, 80, 24)
      view.render(buffer, clip)

      # Find the 'H' and check its style
      found = false
      24.times do |y|
        80.times do |x|
          cell = buffer.get(x, y)
          if cell.char == 'H'
            found = true
            # Heading1 should be white and bold
            cell.style.fg.should eq Tui::Color.white
            cell.style.bold?.should be_true
            break
          end
        end
        break if found
      end

      found.should be_true
    end

    it "does not render when rect is empty" do
      view = Tui::MarkdownView.new("test")
      view.content = "# Hello"
      # Don't set rect - it's empty by default

      buffer = Tui::Buffer.new(80, 24)
      clip = Tui::Rect.new(0, 0, 80, 24)
      view.render(buffer, clip)

      # Buffer should be empty (all spaces with default style)
      cell = buffer.get(0, 0)
      cell.char.should eq ' '
    end

    it "clears lines with background color" do
      view = Tui::MarkdownView.new("test")
      view.background = Tui::Color.green
      view.content = ""  # Empty content
      view.rect = Tui::Rect.new(5, 5, 20, 10)

      buffer = Tui::Buffer.new(80, 24)
      clip = Tui::Rect.new(0, 0, 80, 24)
      view.render(buffer, clip)

      # Cell at (5, 5) should have green background
      cell = buffer.get(5, 5)
      cell.style.bg.should eq Tui::Color.green
    end
  end

  describe "scrolling" do
    it "scrolls down" do
      view = Tui::MarkdownView.new("test")
      view.content = (1..50).map { |i| "Line #{i}" }.join("\n\n")
      view.rect = Tui::Rect.new(0, 0, 80, 10)

      view.scroll_down(5)
      # Can't easily check scroll position without exposing it
      # But this shouldn't crash
    end

    it "scrolls to bottom" do
      view = Tui::MarkdownView.new("test")
      view.content = (1..50).map { |i| "Line #{i}" }.join("\n\n")
      view.rect = Tui::Rect.new(0, 0, 80, 10)

      view.scroll_to_bottom
      view.at_bottom?.should be_true
    end
  end

  describe "with_background helper" do
    it "applies background to styles with default bg" do
      view = Tui::MarkdownView.new("test")
      view.background = Tui::Color.red
      view.content = "Test"
      view.rect = Tui::Rect.new(0, 0, 80, 24)

      buffer = Tui::Buffer.new(80, 24)
      clip = Tui::Rect.new(0, 0, 80, 24)
      view.render(buffer, clip)

      # Find 'T' and check background
      found = false
      24.times do |y|
        80.times do |x|
          cell = buffer.get(x, y)
          if cell.char == 'T'
            found = true
            cell.style.bg.should eq Tui::Color.red
            break
          end
        end
        break if found
      end

      found.should be_true
    end

    it "preserves explicit background in code blocks" do
      view = Tui::MarkdownView.new("test")
      view.background = Tui::Color.blue
      view.content = "```\ncode\n```"
      view.rect = Tui::Rect.new(0, 0, 80, 24)

      buffer = Tui::Buffer.new(80, 24)
      clip = Tui::Rect.new(0, 0, 80, 24)
      view.render(buffer, clip)

      # Code blocks have their own background (palette 235)
      # This should NOT be overridden by view.background
      found_code = false
      24.times do |y|
        80.times do |x|
          cell = buffer.get(x, y)
          if cell.char == 'c'  # from "code"
            found_code = true
            # Should have code block background, not blue
            cell.style.bg.should_not eq Tui::Color.blue
            break
          end
        end
        break if found_code
      end

      found_code.should be_true
    end
  end
end
