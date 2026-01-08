# TUI Editor - Visual TUML Editor built with Crystal TUI
require "../tui"
require "./widget_palette"
require "./canvas"
require "./property_inspector"
require "./code_preview"
require "./clipboard"

module TuiEditor
  class EditorApp < Tui::App
    @palette : WidgetPalette
    @canvas : Canvas
    @inspector : PropertyInspector
    @code_preview : CodePreview
    @header : Tui::Header
    @menu_bar : Tui::MenuBar
    @footer : Tui::Footer
    @main_split : Tui::SplitContainer
    @dialog : Tui::Dialog?
    @clipboard_picker : ClipboardPicker?

    # Drag & Drop state
    @dragging_widget : WidgetDef?
    @drag_x : Int32 = 0
    @drag_y : Int32 = 0

    # Focus highlighting color
    @focus_color : Tui::Color = Tui::Color.cyan

    def initialize
      super

      # Create components
      @palette = WidgetPalette.new
      @canvas = Canvas.new
      @inspector = PropertyInspector.new
      @code_preview = CodePreview.new

      # Focus highlighting is configured on SplitContainers below

      # Header with clock
      @header = Tui::Header.new(id: "header", title: "TUI Editor")
      @header.show_clock = true
      @header.start_clock  # Start clock update fiber

      # Menu bar (setup after footer initialized)
      @menu_bar = Tui::MenuBar.new(id: "menu")

      # Wire up events
      @palette.on_select do |widget_def|
        @canvas.add_widget(widget_def)
        @code_preview.update_code
      end

      @palette.on_drag_start do |widget_def, x, y|
        start_drag(widget_def, x, y)
      end

      @canvas.on_select do |node|
        @inspector.node = node
      end

      @inspector.on_change do |node, prop, value|
        @canvas.mark_dirty!
        @code_preview.update_code
      end

      @code_preview.canvas = @canvas

      # Footer with keybindings
      @footer = Tui::Footer.new(id: "footer")
      @footer.bindings = [
        Tui::Footer::Binding.new(1, "Help"),
        Tui::Footer::Binding.new(2, "Edit"),
        Tui::Footer::Binding.new(3, "Add"),
        Tui::Footer::Binding.new(4, "Cut"),
        Tui::Footer::Binding.new(5, "Del"),
        Tui::Footer::Binding.new(6, "Copy"),
        Tui::Footer::Binding.new(7, "Paste"),
        Tui::Footer::Binding.new(8, "Save"),
        Tui::Footer::Binding.new(9, "Menu"),
        Tui::Footer::Binding.new(10, "Quit"),
      ]

      # Handle footer mouse clicks
      @footer.on_click do |binding|
        handle_footer_click(binding.key)
      end

      # Build split layout - like split_demo
      # All nested splits: show_border=false (parent draws border)
      # Titles on splitters via second_title

      # Canvas / Code Preview (vertical split)
      center_vsplit = Tui::SplitContainer.new(
        direction: Tui::SplitContainer::Direction::Vertical,
        ratio: 0.65,
        id: "center-vsplit"
      )
      center_vsplit.first = @canvas
      center_vsplit.second = @code_preview
      center_vsplit.show_border = false
      center_vsplit.second_title = "Code"  # Title on horizontal splitter
      center_vsplit.min_first = 5
      center_vsplit.min_second = 5

      # Center | Properties (horizontal split)
      right_split = Tui::SplitContainer.new(
        direction: Tui::SplitContainer::Direction::Horizontal,
        ratio: 0.78,
        id: "right-split"
      )
      right_split.first = center_vsplit
      right_split.second = @inspector
      right_split.show_border = false
      right_split.second_title = "Props"  # Title won't show without border
      right_split.min_first = 20
      right_split.min_second = 14

      # Palette | (Canvas/Code | Properties) - OUTER split with border
      @main_split = Tui::SplitContainer.new(
        direction: Tui::SplitContainer::Direction::Horizontal,
        ratio: 0.16,
        id: "main-split"
      )
      @main_split.first = @palette
      @main_split.second = right_split
      @main_split.show_border = true  # Draws outer border
      @main_split.first_title = "Widgets"
      @main_split.second_title = "Editor"  # Canvas + Code area
      @main_split.min_first = 12
      @main_split.min_second = 40
      @main_split.focus_border_color = @focus_color

      # Inner splits also need focus colors for their titles
      center_vsplit.focus_border_color = @focus_color  # For "Code" title
      right_split.focus_border_color = @focus_color    # For "Props" title (if shown)

      # Setup menus (after all components initialized)
      setup_menus

      # Set initial focus
      @palette.focus
    end

    # Layout:
    # ┌─────────────────────────────────────────┐
    # │              Header (1 row)             │
    # ├─────────┬─────────────────┬─────────────┤
    # │ Palette │     Canvas      │  Properties │
    # │    ↔    ├────────↕────────┤     ↔       │
    # │         │   Code Preview  │             │
    # ├─────────┴─────────────────┴─────────────┤
    # │              Footer (1 row)             │
    # └─────────────────────────────────────────┘
    # ↔ = vertical splitter (drag left/right)
    # ↕ = horizontal splitter (drag up/down)

    def compose : Array(Tui::Widget)
      [@header, @menu_bar, @main_split, @footer] of Tui::Widget
    end

    private def layout_children : Nil
      return if @children.empty?

      header_height = 1
      menu_height = 1
      footer_height = 1
      main_height = @rect.height - header_height - menu_height - footer_height

      # Header
      @header.rect = Tui::Rect.new(@rect.x, @rect.y, @rect.width, header_height)

      # Menu bar
      @menu_bar.rect = Tui::Rect.new(@rect.x, @rect.y + header_height, @rect.width, menu_height)

      # Main split (takes all middle space)
      @main_split.rect = Tui::Rect.new(
        @rect.x,
        @rect.y + header_height + menu_height,
        @rect.width,
        main_height
      )

      # Footer
      @footer.rect = Tui::Rect.new(
        @rect.x,
        @rect.y + header_height + menu_height + main_height,
        @rect.width,
        footer_height
      )

      # Dialog (centered)
      if dialog = @dialog
        dialog_width = 40
        dialog_height = 12
        dialog.rect = Tui::Rect.new(
          @rect.x + (@rect.width - dialog_width) // 2,
          @rect.y + (@rect.height - dialog_height) // 2,
          dialog_width,
          dialog_height
        )
      end

      # Clipboard picker (centered popup)
      if picker = @clipboard_picker
        picker_width = 30
        picker_height = [@canvas.clipboard_history.size + 3, 15].min
        picker.rect = Tui::Rect.new(
          @rect.x + (@rect.width - picker_width) // 2,
          @rect.y + (@rect.height - picker_height) // 2,
          picker_width,
          picker_height
        )
      end
    end

    # Override handle_event to intercept BEFORE base App
    def handle_event(event : Tui::Event) : Bool
      return false if event.stopped?

      case event
      when Tui::KeyEvent
        # Quit keys - handle first, but Ctrl+C only when not in canvas/code
        case
        when event.matches?("ctrl+q"), event.matches?("f10")
          quit
          return true
        when event.matches?("ctrl+c")
          # Ctrl+C = copy in canvas, quit otherwise
          if @canvas.focused?
            @canvas.copy_selected
            @code_preview.update_code
            return true
          end
          quit
          return true
        when event.matches?("ctrl+x")
          # Cut in canvas
          if @canvas.focused?
            @canvas.cut_selected
            @code_preview.update_code
            return true
          end
        when event.matches?("ctrl+v")
          # Paste in canvas
          if @canvas.focused?
            @canvas.paste
            @code_preview.update_code
            return true
          end
        when event.matches?("ctrl+shift+v"), event.matches?("V")  # Shift+V for clipboard history
          # Show clipboard history
          if @canvas.focused? && !@canvas.clipboard_history.empty?
            show_clipboard_picker
            return true
          end
        when event.matches?("q")
          # q quits unless editing code
          if @code_preview.editing?
            return false  # Let code editor handle
          end
          quit
          return true
        when event.matches?("ctrl+s")
          save_file
          return true
        when event.matches?("ctrl+o")
          # TODO: open file dialog
          return true
        when event.matches?("tab")
          # Our custom tab handling (cycle through our panels)
          cycle_focus(forward: true)
          return true
        when event.matches?("shift+tab")
          # Reverse cycle
          cycle_focus(forward: false)
          return true
        when event.matches?("f1")
          show_help
          return true
        when event.matches?("escape")
          # Close clipboard picker first, then menu, then cancel drag
          if @clipboard_picker
            close_clipboard_picker
            return true
          end
          if @menu_bar.open?
            @menu_bar.close
            return true
          end
          if @dragging_widget
            @dragging_widget = nil
            mark_dirty!
            return true
          end
        end

        # Let clipboard picker handle events first
        if picker = @clipboard_picker
          if picker.handle_event(event)
            return true
          end
        end

        # Let MenuBar handle F9 and Alt+key
        if @menu_bar.handle_event(event)
          return true
        end

        # Route to focused widget
        if focused = Tui::Widget.focused_widget
          if focused.handle_event(event)
            return true
          end
        end

      when Tui::MouseEvent
        # Handle global drag events first
        if @dragging_widget
          case event.action
          when .drag?
            update_drag(event.x, event.y)
            return true
          when .release?
            end_drag(event.x, event.y)
            return true
          end
        end

        # Let MenuBar handle its mouse events
        if @menu_bar.handle_event(event)
          return true
        end

        # Route to children for mouse events
        @children.reverse_each do |child|
          next if child == @menu_bar  # Already handled
          if child.handle_event(event)
            return true
          end
        end
      end

      false
    end

    private def cycle_focus(forward : Bool = true)
      # Cycle focus between palette, canvas, inspector, code_preview
      widgets = [@palette, @canvas, @inspector, @code_preview]
      current = widgets.find(&.focused?)
      idx = current ? widgets.index(current) || 0 : -1

      next_idx = if forward
                   (idx + 1) % widgets.size
                 else
                   idx <= 0 ? widgets.size - 1 : idx - 1
                 end

      widgets.each(&.blur)
      widgets[next_idx].focus
      mark_dirty!
    end

    private def save_file
      # Save to file (TODO: file dialog)
      code = @code_preview.format.pug? ? @canvas.to_tuml(:pug) : @canvas.to_tuml(:yaml)

      filename = case @code_preview.format
                 when .pug?     then "ui.tui"
                 when .yaml?    then "ui.tui.yaml"
                 when .json?    then "ui.tui.json"
                 when .crystal? then "ui.cr"
                 else                "ui.tui"
                 end

      File.write(filename, code)

      # Show notification
      show_notification("Saved to #{filename}")
    end

    private def show_notification(message : String)
      # TODO: Use Toast widget when focus returns
      # For now, update footer temporarily
      @footer.bindings = [
        Tui::Footer::Binding.new(1, message),
      ]
      mark_dirty!

      # Restore after delay (simplified - in real app use timer)
      spawn do
        sleep 2.seconds
        restore_footer_bindings
        mark_dirty!
      end
    end

    private def restore_footer_bindings
      @footer.bindings = [
        Tui::Footer::Binding.new(1, "Help"),
        Tui::Footer::Binding.new(2, "Edit"),
        Tui::Footer::Binding.new(3, "Add"),
        Tui::Footer::Binding.new(4, "Cut"),
        Tui::Footer::Binding.new(5, "Del"),
        Tui::Footer::Binding.new(6, "Copy"),
        Tui::Footer::Binding.new(7, "Paste"),
        Tui::Footer::Binding.new(8, "Save"),
        Tui::Footer::Binding.new(9, "Menu"),
        Tui::Footer::Binding.new(10, "Quit"),
      ]
    end

    private def handle_footer_click(key : Int32) : Nil
      case key
      when 1  then show_help
      when 2  then @code_preview.start_editing  # Edit
      when 3  then @palette.focus               # Add
      when 4  then @canvas.cut_selected         # Cut
      when 5  then @canvas.delete_selected      # Del
      when 6  then @canvas.copy_selected        # Copy
      when 7  then @canvas.paste                # Paste
      when 8  then save_file                    # Save
      when 9  then @menu_bar.focus              # Menu
      when 10 then quit                         # Quit
      end
    end

    private def show_help
      help_text = <<-HELP
      Navigation:
        Tab         Cycle focus between panels
        Arrow keys  Navigate within panel
        Enter       Add widget / Edit property
        Delete      Remove selected widget

      File Operations:
        Ctrl+S      Save to file
        Ctrl+Q      Quit
      HELP

      dialog = Tui::Dialog.new("TUI Editor Help", help_text, id: "help-dialog")
      dialog.buttons = [Tui::Dialog::Button.new("[ OK ]", Tui::Dialog::Result::OK, 'o')]

      dialog.on_close do |result, input|
        close_dialog
      end

      @dialog = dialog
      add_child(dialog)
      dialog.show
      layout_children
      mark_dirty!
    end

    private def close_dialog
      if dialog = @dialog
        remove_child(dialog)
        @dialog = nil
        @canvas.focus
        mark_dirty!
      end
    end

    private def show_clipboard_picker
      picker = ClipboardPicker.new(@canvas.clipboard_history)

      picker.on_select do |node|
        @canvas.paste_node(node)
        @code_preview.update_code
        close_clipboard_picker
      end

      picker.on_close do
        close_clipboard_picker
      end

      @clipboard_picker = picker
      add_child(picker)
      picker.focus
      layout_children
      mark_dirty!
    end

    private def close_clipboard_picker
      if picker = @clipboard_picker
        remove_child(picker)
        @clipboard_picker = nil
        @canvas.focus
        mark_dirty!
      end
    end

    private def setup_menus
      # File menu
      @menu_bar.add_menu("File", 'f') do |items|
        items << Tui::MenuBar::MenuAction.new("New", 'n', ->{ new_file })
        items << Tui::MenuBar::MenuAction.new("Open...", 'o', ->{ open_file })
        items << Tui::MenuBar::MenuAction.new("Save", 's', ->{ save_file })
        items << Tui::MenuBar::MenuAction.new("Save As...", 'a', ->{ save_file_as })
        items << Tui::MenuBar::MenuAction.separator
        items << Tui::MenuBar::MenuAction.new("Quit", 'q', ->{ quit })
      end

      # Edit menu
      @menu_bar.add_menu("Edit", 'e') do |items|
        items << Tui::MenuBar::MenuAction.new("Undo", 'u', ->{ undo })
        items << Tui::MenuBar::MenuAction.new("Redo", 'r', ->{ redo_action })
        items << Tui::MenuBar::MenuAction.separator
        items << Tui::MenuBar::MenuAction.new("Delete", 'd', ->{ delete_selected })
      end

      # View menu
      @menu_bar.add_menu("View", 'v') do |items|
        items << Tui::MenuBar::MenuAction.new("Pug Format", 'p', ->{ set_format_pug })
        items << Tui::MenuBar::MenuAction.new("YAML Format", 'y', ->{ set_format_yaml })
        items << Tui::MenuBar::MenuAction.new("JSON Format", 'j', ->{ set_format_json })
        items << Tui::MenuBar::MenuAction.new("Crystal Format", 'c', ->{ set_format_crystal })
      end

      # Help menu
      @menu_bar.add_menu("Help", 'h') do |items|
        items << Tui::MenuBar::MenuAction.new("Help", 'h', ->{ show_help })
        items << Tui::MenuBar::MenuAction.new("About", 'a', ->{ show_about })
      end

      # Close menu returns focus to palette
      @menu_bar.on_close do
        @palette.focus
      end
    end

    # Menu actions
    private def new_file
      @canvas.root = nil
      @code_preview.update_code
      show_notification("New file created")
    end

    private def open_file
      # TODO: implement file dialog
      show_notification("Open not implemented yet")
    end

    private def save_file_as
      # TODO: implement file dialog
      show_notification("Save As not implemented yet")
    end

    private def undo
      # TODO: implement undo
      show_notification("Undo not implemented yet")
    end

    private def redo_action
      # TODO: implement redo
      show_notification("Redo not implemented yet")
    end

    private def delete_selected
      if @canvas.delete_selected
        @code_preview.update_code
        show_notification("Widget deleted")
      end
    end

    private def set_format_pug
      @code_preview.format = CodePreview::Format::Pug
    end

    private def set_format_yaml
      @code_preview.format = CodePreview::Format::YAML
    end

    private def set_format_json
      @code_preview.format = CodePreview::Format::JSON
    end

    private def set_format_crystal
      @code_preview.format = CodePreview::Format::Crystal
    end

    private def show_about
      about_text = <<-ABOUT
      TUI Editor v0.1

      A visual editor for creating
      TUI interfaces using TUML.

      Built with Crystal TUI
      ABOUT

      dialog = Tui::Dialog.new("About TUI Editor", about_text, id: "about-dialog")
      dialog.buttons = [Tui::Dialog::Button.new("[ OK ]", Tui::Dialog::Result::OK, 'o')]

      dialog.on_close do |result, input|
        close_dialog
      end

      @dialog = dialog
      add_child(dialog)
      dialog.show
      layout_children
      mark_dirty!
    end

    # Drag & Drop methods
    private def start_drag(widget_def : WidgetDef, x : Int32, y : Int32)
      @dragging_widget = widget_def
      @drag_x = x
      @drag_y = y
      mark_dirty!
    end

    private def update_drag(x : Int32, y : Int32)
      @drag_x = x
      @drag_y = y
      mark_dirty!
    end

    private def end_drag(x : Int32, y : Int32)
      if widget_def = @dragging_widget
        # Check if dropped on canvas
        if @canvas.rect.contains?(x, y)
          @canvas.add_widget(widget_def)
          @code_preview.update_code
        end
      end
      @dragging_widget = nil
      mark_dirty!
    end

    # Drag preview is rendered after normal render cycle
    # App.render_all handles z_index ordering for menu dropdown
  end
end

# Run the editor if executed directly
TuiEditor::EditorApp.new.run
