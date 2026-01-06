# Tabbed panel demo
require "../src/tui"

class TabsDemo < Tui::App
  @tabbed : Tui::TabbedPanel

  def initialize
    super

    @tabbed = Tui::TabbedPanel.new(id: "tabs")
    @tabbed.focused = true

    # Add tabs with different positions
    @tabbed.add_tab("files", "Files", "File browser") { nil }
    @tabbed.add_tab("edit", "Edit", "Text editor") { nil }
    @tabbed.add_tab("view", "View", "Viewer options") { nil }
    @tabbed.add_tab("help", "Help", "Help and docs") { nil }

    # Try different positions - uncomment to test:
    # @tabbed.positions = Set{Tui::TabbedPanel::TabPosition::Top}           # Top only (default)
    # @tabbed.positions = Set{Tui::TabbedPanel::TabPosition::Left}          # Left only (vertical)
    # @tabbed.positions = Set{Tui::TabbedPanel::TabPosition::Top, Tui::TabbedPanel::TabPosition::Left}  # Both
    # @tabbed.add_position(Tui::TabbedPanel::TabPosition::Right)            # Add right tabs too
  end

  def compose : Array(Tui::Widget)
    [@tabbed.as(Tui::Widget)]
  end

  private def layout_children : Nil
    @tabbed.rect = @rect
  end

  def handle_event(event : Tui::Event) : Bool
    case event
    when Tui::KeyEvent
      case event.key
      when .escape?, .f10?
        quit
        event.stop!
        return true
      end
    end

    # Let tabbed panel handle navigation
    if @tabbed.handle_event(event)
      return true
    end

    super
  end
end

TabsDemo.new.run
