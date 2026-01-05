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

# Widgets
require "./tui/reactive"
require "./tui/widget"

# Containers
require "./tui/containers/vbox"
require "./tui/containers/hbox"

# Basic Widgets
require "./tui/widgets/label"
require "./tui/widgets/button"
require "./tui/widgets/input"
require "./tui/widgets/data_table"
require "./tui/widgets/panel"

# Application
require "./tui/app"

module Tui
  VERSION = "0.1.0"
end
