require "../../spec_helper"

# Debug test to trace MarkdownView rendering issue
describe "MarkdownView Debug" do
  it "traces render_to_lines output" do
    view = Tui::MarkdownView.new("test")

    # Set rect FIRST before setting content
    view.rect = Tui::Rect.new(0, 0, 80, 24)

    view.content = "# Hello"

    # Check document was parsed
    puts "\n=== DEBUG: Document parsed ==="
    puts "Raw markdown: #{view.content.inspect}"
    puts "View visible?: #{view.visible?}"
    puts "View rect: #{view.rect.inspect}"
    puts "View rect empty?: #{view.rect.empty?}"

    # Now render to buffer
    buffer = Tui::Buffer.new(80, 24)
    clip = Tui::Rect.new(0, 0, 80, 24)
    puts "Clip: #{clip.inspect}"
    view.render(buffer, clip)

    # Print buffer contents
    puts "\n=== DEBUG: Buffer contents (first 5 rows) ==="
    5.times do |y|
      row = String.build do |s|
        80.times do |x|
          cell = buffer.get(x, y)
          s << cell.char
        end
      end
      puts "Row #{y}: |#{row.rstrip}|"
    end

    # Check what's in the buffer
    non_space_cells = 0
    24.times do |y|
      80.times do |x|
        cell = buffer.get(x, y)
        if cell.char != ' ' && cell.char != '\0'
          non_space_cells += 1
          puts "Found char '#{cell.char}' at (#{x}, #{y})"
        end
      end
    end

    puts "\nTotal non-space cells: #{non_space_cells}"
    non_space_cells.should be > 0
  end

  it "checks rect is properly set" do
    view = Tui::MarkdownView.new("test")
    view.content = "# Test"
    view.rect = Tui::Rect.new(10, 5, 60, 15)

    puts "\n=== DEBUG: Rect check ==="
    puts "Rect: x=#{view.rect.x}, y=#{view.rect.y}, w=#{view.rect.width}, h=#{view.rect.height}"
    puts "Rect empty?: #{view.rect.empty?}"

    view.rect.empty?.should be_false
    view.rect.width.should eq 60
    view.rect.height.should eq 15
  end

  it "traces issue: rect set AFTER content" do
    view = Tui::MarkdownView.new("test")

    puts "\n=== DEBUG: Before content set ==="
    puts "Default rect: #{view.rect.inspect}"
    puts "Default rect.width: #{view.rect.width}"
    puts "Default rect empty?: #{view.rect.empty?}"

    # Content is set when rect is still zero
    view.content = "# Hello"

    puts "\n=== DEBUG: After content set, before rect set ==="
    puts "Rect: #{view.rect.inspect}"

    # Now set rect
    view.rect = Tui::Rect.new(0, 0, 80, 24)

    puts "\n=== DEBUG: After rect set ==="
    puts "Rect: #{view.rect.inspect}"
    puts "visible?: #{view.visible?}"
    puts "rect.empty?: #{view.rect.empty?}"

    # Force re-render by calling render twice
    puts "\n=== DEBUG: First render ==="
    buffer = Tui::Buffer.new(80, 24)
    clip = Tui::Rect.new(0, 0, 80, 24)
    view.render(buffer, clip)

    # Count after first render
    first_count = 0
    24.times do |y|
      80.times do |x|
        cell = buffer.get(x, y)
        if cell.char != ' ' && cell.char != '\0'
          first_count += 1
        end
      end
    end
    puts "First render non-space cells: #{first_count}"

    # Try second render
    puts "\n=== DEBUG: Second render ==="
    buffer2 = Tui::Buffer.new(80, 24)
    view.render(buffer2, clip)

    # Check buffer2 (second render)
    second_count = 0
    24.times do |y|
      80.times do |x|
        cell = buffer2.get(x, y)
        if cell.char != ' ' && cell.char != '\0'
          second_count += 1
        end
      end
    end
    puts "Second render non-space cells: #{second_count}"

    # Print first few rows from buffer2
    puts "\n=== Buffer2 rows ==="
    3.times do |y|
      row = String.build do |s|
        80.times do |x|
          s << buffer2.get(x, y).char
        end
      end
      puts "Row #{y}: |#{row.rstrip}|"
    end

    # Use first_count for assertion since that's what matters
    first_count.should be > 0
  end

  it "checks markdown document parsing" do
    doc = Tui::Markdown.parse("# Hello World")

    puts "\n=== DEBUG: Markdown parsing ==="
    puts "Document size: #{doc.size}"
    doc.each_with_index do |block, i|
      puts "Block #{i}: type=#{block.type}, elements=#{block.elements.size}"
      block.elements.each_with_index do |elem, j|
        puts "  Element #{j}: type=#{elem.type}, text=#{elem.text.inspect}"
      end
    end

    doc.size.should eq 1
    doc[0].type.should eq Tui::Markdown::BlockType::Heading1
  end
end
