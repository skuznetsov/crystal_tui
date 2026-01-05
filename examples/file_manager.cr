# MC-like dual-pane file manager
require "../src/tui"

class FileManagerApp < Tui::App
  @left_panel : Tui::FilePanel
  @right_panel : Tui::FilePanel
  @active_panel : Symbol = :left

  def initialize
    super

    @left_panel = Tui::FilePanel.new(Path.home, id: "left")
    @left_panel.border_style = Tui::Panel::BorderStyle::Round
    @left_panel.title_align = Tui::Label::Align::Center

    @right_panel = Tui::FilePanel.new(Path.home, id: "right")
    @right_panel.border_style = Tui::Panel::BorderStyle::Round
    @right_panel.title_align = Tui::Label::Align::Center

    # Set initial focus (use direct property for init, focus/blur for runtime changes)
    @left_panel.focused = true
    @right_panel.focused = false
    @left_panel.focusable = true
    @right_panel.focusable = true

    # File activation callback
    @left_panel.on_activate { |entry| view_file(@left_panel.path / entry.name) }
    @right_panel.on_activate { |entry| view_file(@right_panel.path / entry.name) }
  end

  def compose : Array(Tui::Widget)
    hbox = Tui::HBox.new(id: "panels") {
      [@left_panel.as(Tui::Widget), @right_panel.as(Tui::Widget)]
    }
    [hbox.as(Tui::Widget)]
  end

  def handle_event(event : Tui::Event) : Bool
    case event
    when Tui::KeyEvent
      case event.key
      when .tab?
        switch_panel
        event.stop!
        return true
      when .f5?
        copy_files
        event.stop!
        return true
      when .f6?
        move_files
        event.stop!
        return true
      when .f7?
        make_dir
        event.stop!
        return true
      when .f8?
        delete_files
        event.stop!
        return true
      end
    end

    super
  end

  private def switch_panel : Nil
    if @active_panel == :left
      @active_panel = :right
      @left_panel.blur
      @right_panel.focus
    else
      @active_panel = :left
      @left_panel.focus
      @right_panel.blur
    end
  end

  private def active : Tui::FilePanel
    @active_panel == :left ? @left_panel : @right_panel
  end

  private def inactive : Tui::FilePanel
    @active_panel == :left ? @right_panel : @left_panel
  end

  private def view_file(path : Path) : Nil
    # TODO: Open file viewer
  end

  private def copy_files : Nil
    # TODO: Copy selected files to other panel
  end

  private def move_files : Nil
    # TODO: Move selected files to other panel
  end

  private def make_dir : Nil
    # TODO: Create new directory
  end

  private def delete_files : Nil
    # TODO: Delete selected files
  end
end

FileManagerApp.new.run
