# Split Container Demo - IDE-like layout with draggable splitters
require "../src/tui"

class SplitDemo < Tui::App
  @main_split : Tui::SplitContainer
  @right_split : Tui::SplitContainer
  @status_label : Tui::Label

  def initialize
    super

    # Create content labels (no borders - SplitContainer handles borders)
    explorer_content = Tui::Label.new("File tree\n  src/\n    main.cr\n    app.cr\n  spec/\n    spec_helper.cr", fg: Tui::Color.cyan)

    editor_content = Tui::Label.new("require \"./app\"\n\nmodule MyApp\n  VERSION = \"0.1.0\"\nend\n\nMyApp.run", fg: Tui::Color.green)

    terminal_content = Tui::Label.new("$ crystal build src/main.cr\nCompiling...\nDone!", fg: Tui::Color.white)

    # Nested split: editor / terminal (vertical - top/bottom)
    @right_split = Tui::SplitContainer.new(
      direction: Tui::SplitContainer::Direction::Vertical,
      ratio: 0.7,
      id: "right_split"
    )
    @right_split.show_border = false  # No border - parent handles it
    @right_split.first = editor_content
    @right_split.second = terminal_content
    @right_split.second_title = "Terminal"  # Title on horizontal splitter
    @right_split.on_resize do |ratio|
      update_status("Right split: #{(ratio * 100).to_i}%")
    end

    # Main split: sidebar | right_split (horizontal - left/right)
    @main_split = Tui::SplitContainer.new(
      direction: Tui::SplitContainer::Direction::Horizontal,
      ratio: 0.25,
      id: "main_split"
    )
    @main_split.first = explorer_content
    @main_split.second = @right_split
    @main_split.first_title = "Explorer"
    @main_split.second_title = "Editor - main.cr"
    @main_split.on_resize do |ratio|
      update_status("Main split: #{(ratio * 100).to_i}%")
    end

    # Status bar
    @status_label = Tui::Label.new(
      "Drag splitters to resize | F10/q to quit",
      fg: Tui::Color.yellow
    )
  end

  def compose : Array(Tui::Widget)
    [@main_split, @status_label]
  end

  private def layout_children : Nil
    @main_split.rect = Tui::Rect.new(0, 0, @rect.width, @rect.height - 1)
    @status_label.rect = Tui::Rect.new(0, @rect.height - 1, @rect.width, 1)
  end

  private def update_status(msg : String)
    @status_label.text = msg
    @status_label.mark_dirty!
    mark_dirty!
  end

  def handle_event(event : Tui::Event) : Bool
    case event
    when Tui::KeyEvent
      case event.key
      when .f10?
        quit
        event.stop!
        return true
      end
    end

    super
  end
end

SplitDemo.new.run
