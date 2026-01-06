# MC-like dual-pane file manager
require "../src/tui"

class FileManagerApp < Tui::App
  @left_panel : Tui::FilePanel
  @right_panel : Tui::FilePanel
  @menu_bar : Tui::MenuBar
  @footer : Tui::Footer
  @viewer : Tui::TextViewer?
  @dialog : Tui::Dialog?
  @active_panel : Symbol = :left
  @last_mask : String = "*"

  def initialize
    super

    @left_panel = Tui::FilePanel.new(Path.home, id: "left")
    @left_panel.title_align = Tui::Label::Align::Center

    @right_panel = Tui::FilePanel.new(Path.home, id: "right")
    @right_panel.title_align = Tui::Label::Align::Center

    # Set initial focus
    @left_panel.focused = true
    @right_panel.focused = false
    @left_panel.focusable = true
    @right_panel.focusable = true

    # Menu bar
    @menu_bar = Tui::MenuBar.new(id: "menu")

    # Footer
    @footer = Tui::Footer.mc_style

    # Setup menus (after all instance vars initialized)
    setup_menus

    # File activation callback
    @left_panel.on_activate { |entry| view_file(@left_panel.path / entry.name) }
    @right_panel.on_activate { |entry| view_file(@right_panel.path / entry.name) }

    # Selection mask callbacks
    setup_mask_callbacks(@left_panel)
    setup_mask_callbacks(@right_panel)

    # Menu close callback
    @menu_bar.on_close { active.focus }
  end

  private def setup_menus : Nil
    # Left menu
    @menu_bar.add_menu("Left", 'l') do |items|
      items << Tui::MenuBar::MenuAction.new("Listing mode...", 'l')
      items << Tui::MenuBar::MenuAction.new("Sort order...", 's')
      items << Tui::MenuBar::MenuAction.separator
      items << Tui::MenuBar::MenuAction.new("Filter...", 'f')
    end

    # File menu
    @menu_bar.add_menu("File", 'f') do |items|
      items << Tui::MenuBar::MenuAction.new("View", 'v', ->{ view_current })
      items << Tui::MenuBar::MenuAction.new("Edit", 'e', ->{ edit_current })
      items << Tui::MenuBar::MenuAction.new("Copy", 'c', ->{ copy_files })
      items << Tui::MenuBar::MenuAction.new("Move", 'm', ->{ move_files })
      items << Tui::MenuBar::MenuAction.new("Mkdir", 'k', ->{ make_dir })
      items << Tui::MenuBar::MenuAction.new("Delete", 'd', ->{ delete_files })
      items << Tui::MenuBar::MenuAction.separator
      items << Tui::MenuBar::MenuAction.new("Quit", 'q', ->{ show_quit_dialog })
    end

    # Right menu
    @menu_bar.add_menu("Right", 'r') do |items|
      items << Tui::MenuBar::MenuAction.new("Listing mode...", 'l')
      items << Tui::MenuBar::MenuAction.new("Sort order...", 's')
      items << Tui::MenuBar::MenuAction.separator
      items << Tui::MenuBar::MenuAction.new("Filter...", 'f')
    end
  end

  private def setup_mask_callbacks(panel : Tui::FilePanel) : Nil
    panel.on_select_mask do |callback|
      show_mask_dialog("Select", callback)
    end
    panel.on_deselect_mask do |callback|
      show_mask_dialog("Deselect", callback)
    end
  end

  private def show_mask_dialog(title : String, callback : Proc(String, Nil)) : Nil
    dialog = Tui::Dialog.mask_dialog(title, @last_mask)
    dialog.on_close do |result, value|
      if result.ok? && value && !value.empty?
        @last_mask = value  # Remember for next time
        callback.call(value)
      end
      close_dialog
    end
    @dialog = dialog
    add_child(dialog)
    dialog.show
    layout_children
    mark_dirty!
  end

  private def close_dialog : Nil
    if dialog = @dialog
      remove_child(dialog)
      @dialog = nil
      active.focus
      mark_dirty!
    end
  end

  private def show_quit_dialog : Nil
    dialog = Tui::Dialog.confirm_dialog("Quit", "Do you want to quit?")
    dialog.on_close do |result, _|
      if result.ok?
        quit
      end
      close_dialog
    end
    @dialog = dialog
    add_child(dialog)
    dialog.show
    layout_children
    mark_dirty!
  end

  def compose : Array(Tui::Widget)
    [@menu_bar.as(Tui::Widget), @left_panel.as(Tui::Widget), @right_panel.as(Tui::Widget), @footer.as(Tui::Widget)]
  end

  # Custom layout: menu at top, panels side-by-side, footer at bottom
  private def layout_children : Nil
    return if @children.empty?

    menu_height = 1
    footer_height = 1
    panels_height = @rect.height - menu_height - footer_height
    panel_width = @rect.width // 2

    # Menu bar at top
    @menu_bar.rect = Tui::Rect.new(
      @rect.x,
      @rect.y,
      @rect.width,
      menu_height
    )

    # Left panel
    @left_panel.rect = Tui::Rect.new(
      @rect.x,
      @rect.y + menu_height,
      panel_width,
      panels_height
    )

    # Right panel
    @right_panel.rect = Tui::Rect.new(
      @rect.x + panel_width,
      @rect.y + menu_height,
      @rect.width - panel_width,
      panels_height
    )

    # Footer at bottom
    @footer.rect = Tui::Rect.new(
      @rect.x,
      @rect.y + menu_height + panels_height,
      @rect.width,
      footer_height
    )

    # Viewer overlay (full screen minus menu and footer)
    if viewer = @viewer
      viewer.rect = Tui::Rect.new(
        @rect.x,
        @rect.y + menu_height,
        @rect.width,
        panels_height
      )
    end

    # Dialog centered on screen (rect includes shadow space: +2 width, +1 height)
    if dialog = @dialog
      content_width = 30
      # Height: MC-style mask dialog = 3 (title + input + bottom border), with buttons = 7
      content_height = dialog.buttons.empty? ? 3 : 7
      total_width = content_width + 2   # +2 for shadow
      total_height = content_height + 1 # +1 for shadow
      dialog.rect = Tui::Rect.new(
        @rect.x + (@rect.width - total_width) // 2,
        @rect.y + menu_height + (panels_height - total_height) // 2,
        total_width,
        total_height
      )
    end
  end

  def handle_event(event : Tui::Event) : Bool
    # If dialog is open, route events to it
    if dialog = @dialog
      if dialog.handle_event(event)
        return true
      end
    end

    # If menu is open, route events to it
    if @menu_bar.open?
      if @menu_bar.handle_event(event)
        return true
      end
    end

    # If viewer is open, route events to it
    if viewer = @viewer
      if viewer.handle_event(event)
        return true
      end
    end

    # Skip global keys when dialog or viewer is open
    return super if @dialog

    case event
    when Tui::KeyEvent
      case event.key
      when .f9?
        @menu_bar.open(0) unless @viewer
        event.stop!
        return true
      when .tab?
        switch_panel unless @viewer && !@menu_bar.open?
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
          show_quit_dialog
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
