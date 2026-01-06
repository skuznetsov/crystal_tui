# Crystal TUI - Modern Terminal UI Framework
#
# Inspired by:
# - Textual (Python) - reactive state, TCSS styling
# - TurboVision (Borland) - widget hierarchy, event bubbling
#
# Unique features:
# - Overlay transparency
# - Macro-based reactive properties
# - Fiber-based async
# - Compile-time type safety

# Core
require "./tui/terminal/ansi"
require "./tui/terminal/cell"
require "./tui/terminal/buffer"
require "./tui/terminal/terminal"
require "./tui/terminal/input"

# Events
require "./tui/events/event"
require "./tui/events/key_event"
require "./tui/events/mouse_event"
require "./tui/events/resize_event"

# Layout
require "./tui/layout/rect"
require "./tui/layout/dimension"
require "./tui/layout/flex"

# CSS
require "./tui/css/parser"

# Unicode
require "./tui/unicode"

# Widgets
require "./tui/reactive"
require "./tui/widget"

# Containers
require "./tui/containers/vbox"
require "./tui/containers/hbox"
require "./tui/containers/split_container"

# Basic Widgets
require "./tui/widgets/label"
require "./tui/widgets/button"
require "./tui/widgets/input"
require "./tui/widgets/data_table"
require "./tui/widgets/panel"
require "./tui/widgets/file_panel"
require "./tui/widgets/footer"
require "./tui/widgets/text_viewer"
require "./tui/widgets/dialog"
require "./tui/widgets/menu_bar"
require "./tui/widgets/tabbed_panel"
require "./tui/widgets/collapsible"
require "./tui/widgets/rich_text"
require "./tui/widgets/window_manager"
require "./tui/widgets/text_editor"
require "./tui/widgets/progress_bar"
require "./tui/widgets/checkbox"
require "./tui/widgets/radio_group"
require "./tui/widgets/combo_box"
require "./tui/widgets/draggable_window"

# Application
require "./tui/app"

module Tui
  VERSION = "0.1.0"
end
