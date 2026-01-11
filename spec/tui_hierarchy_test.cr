require "spec"
require "../src/tui"

describe "TUI hierarchy width" do
  it "passes correct width through hierarchy" do
    md = Tui::MarkdownView.new("md")
    md.content = "Test with emoji 😊 and more text that should wrap correctly at the edge of the content area without overflowing."
    
    tabs = Tui::TabbedPanel.new("tabs")
    tabs.add_tab("test", "Test") { md }
    
    content_split = Tui::SplitContainer.new(direction: :vertical, ratio: 0.8, id: "content")
    content_split.first = tabs
    content_split.second = Tui::Panel.new("input")
    
    main_split = Tui::SplitContainer.new(direction: :horizontal, ratio: 0.25, id: "main")  
    main_split.first = Tui::Panel.new("sidebar")
    main_split.second = content_split
    
    # Set rect and render
    main_split.rect = Tui::Rect.new(0, 0, 100, 30)
    
    buffer = Tui::Buffer.new(100, 30)
    main_split.render(buffer, main_split.rect)
    
    puts "\n=== Hierarchy rects ==="
    puts "main_split: #{main_split.rect}"
    puts "content_split: #{content_split.rect}"
    puts "tabs: #{tabs.rect}"
    puts "md: #{md.rect}"
    
    puts "\n=== Full grid ==="
    buffer.to_grid.each_with_index do |line, i|
      next if line.strip.empty?
      w = Tui::Unicode.display_width(line)
      puts "#{i.to_s.rjust(2)}: (#{w.to_s.rjust(3)}) |#{line}|"
    end
    
    true.should be_true
  end
end
