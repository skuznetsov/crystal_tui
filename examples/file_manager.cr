# MC-like dual-pane file manager
require "../src/tui"

class FileManagerApp < Tui::App
  @left_panel : Tui::FilePanel
  @right_panel : Tui::FilePanel
  @footer : Tui::Footer
  @viewer : Tui::TextViewer?
  @active_panel : Symbol = :left

  def initialize
    super

    @left_panel = Tui::FilePanel.new(Path.home, id: "left")
    @left_panel.border_style = Tui::Panel::BorderStyle::Round
    @left_panel.title_align = Tui::Label::Align::Center

    @right_panel = Tui::FilePanel.new(Path.home, id: "right")
    @right_panel.border_style = Tui::Panel::BorderStyle::Round
    @right_panel.title_align = Tui::Label::Align::Center

    # Set initial focus
    @left_panel.focused = true
    @right_panel.focused = false
    @left_panel.focusable = true
    @right_panel.focusable = true

    # File activation callback
    @left_panel.on_activate { |entry| view_file(@left_panel.path / entry.name) }
    @right_panel.on_activate { |entry| view_file(@right_panel.path / entry.name) }

    # Footer
    @footer = Tui::Footer.mc_style
  end

  def compose : Array(Tui::Widget)
    [@left_panel.as(Tui::Widget), @right_panel.as(Tui::Widget), @footer.as(Tui::Widget)]
  end

  # Custom layout: panels side-by-side, footer at bottom
  private def layout_children : Nil
    return if @children.empty?

    footer_height = 1
    panels_height = @rect.height - footer_height
    panel_width = @rect.width // 2

    # Left panel
    @left_panel.rect = Tui::Rect.new(
      @rect.x,
      @rect.y,
      panel_width,
      panels_height
    )

    # Right panel
    @right_panel.rect = Tui::Rect.new(
      @rect.x + panel_width,
      @rect.y,
      @rect.width - panel_width,
      panels_height
    )

    # Footer at bottom
    @footer.rect = Tui::Rect.new(
      @rect.x,
      @rect.y + panels_height,
      @rect.width,
      footer_height
    )

    # Viewer overlay (full screen minus footer)
    if viewer = @viewer
      viewer.rect = Tui::Rect.new(
        @rect.x,
        @rect.y,
        @rect.width,
        panels_height
      )
    end
  end

  def handle_event(event : Tui::Event) : Bool
    # If viewer is open, route events to it
    if viewer = @viewer
      if viewer.handle_event(event)
        return true
      end
    end

    case event
    when Tui::KeyEvent
      case event.key
      when .tab?
        switch_panel unless @viewer
        event.stop!
        return true
      when .f3?
        view_current unless @viewer
        event.stop!
        return true
      when .f4?
        edit_current unless @viewer
        event.stop!
        return true
      when .f5?
        copy_files unless @viewer
        event.stop!
        return true
      when .f6?
        move_files unless @viewer
        event.stop!
        return true
      when .f7?
        make_dir unless @viewer
        event.stop!
        return true
      when .f8?
        delete_files unless @viewer
        event.stop!
        return true
      when .f10?
        if @viewer
          close_viewer
        else
          quit
        end
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
    viewer = Tui::TextViewer.new(id: "viewer")
    viewer.border_style = Tui::Panel::BorderStyle::Light
    viewer.border_color = Tui::Color.cyan
    viewer.focused = true
    viewer.load_file(path)
    viewer.on_close { close_viewer }

    @viewer = viewer
    add_child(viewer)
    layout_children
    mark_dirty!
  end

  private def close_viewer : Nil
    if viewer = @viewer
      remove_child(viewer)
      @viewer = nil
      mark_dirty!
    end
  end

  private def view_current : Nil
    if entry = active.current_entry
      unless entry.is_dir
        view_file(active.path / entry.name)
      end
    end
  end

  private def edit_current : Nil
    # TODO: Open editor
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
