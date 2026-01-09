# Test harness for automated TUI testing
# Allows rendering to buffer and injecting input events

module Tui
  module Testing
    # Test harness for running TUI apps in headless mode
    class Harness
      getter app : App
      getter buffer : Buffer
      getter width : Int32
      getter height : Int32
      getter mock_input : MockInputProvider
      getter screenshots : Array(String)

      def initialize(@app : App, @width : Int32 = 80, @height : Int32 = 24)
        @buffer = Buffer.new(@width, @height)
        @mock_input = MockInputProvider.new(blocking: false)
        @screenshots = [] of String

        # Initialize app for headless testing
        @app.mount_headless(@width, @height)
      end

      # Render current state to buffer
      def render : Buffer
        @buffer = Buffer.new(@width, @height)  # Fresh buffer
        clip = Rect.new(0, 0, @width, @height)
        @app.render(@buffer, clip)
        @buffer
      end

      # Render and return as grid of strings
      def render_grid : Array(String)
        render
        @buffer.to_grid
      end

      # Render and return as single string
      def render_text : String
        render_grid.join("\n")
      end

      # Take a screenshot (save current render to screenshots array)
      def screenshot(label : String = "") : String
        text = render_text
        @screenshots << "=== #{label} ===\n#{text}"
        text
      end

      # Save all screenshots to a file
      def save_screenshots(path : String) : Nil
        File.write(path, @screenshots.join("\n\n"))
      end

      # Save ANSI screenshot
      def save_ansi(path : String) : Nil
        render
        @buffer.save_ansi(path)
      end

      # Send a key press
      def press(key : Key, modifiers : Modifiers = Modifiers::None) : Nil
        event = KeyEvent.new(key, modifiers)
        @app.handle_event(event)
        @app.refresh  # Re-layout after event
      end

      # Send a character
      def type(char : Char, modifiers : Modifiers = Modifiers::None) : Nil
        event = KeyEvent.new(char, modifiers)
        @app.handle_event(event)
        @app.refresh  # Re-layout after event
      end

      # Send a string (multiple characters)
      def type_string(str : String) : Nil
        str.each_char do |char|
          type(char)
        end
      end

      # Send Ctrl+key
      def ctrl(char : Char) : Nil
        type(char, Modifiers::Ctrl)
      end

      # Send Alt+key
      def alt(char : Char) : Nil
        type(char, Modifiers::Alt)
      end

      # Send mouse click
      def click(x : Int32, y : Int32, button : MouseButton = MouseButton::Left) : Nil
        event = MouseEvent.new(x, y, button, MouseAction::Press)
        @app.handle_event(event)
        # Also send release
        release_event = MouseEvent.new(x, y, button, MouseAction::Release)
        @app.handle_event(release_event)
        @app.refresh  # Re-layout after event
      end

      # Send mouse wheel
      def scroll_up(x : Int32 = 0, y : Int32 = 0, amount : Int32 = 1) : Nil
        amount.times do
          event = MouseEvent.new(x, y, MouseButton::WheelUp, MouseAction::Press)
          @app.handle_event(event)
        end
      end

      def scroll_down(x : Int32 = 0, y : Int32 = 0, amount : Int32 = 1) : Nil
        amount.times do
          event = MouseEvent.new(x, y, MouseButton::WheelDown, MouseAction::Press)
          @app.handle_event(event)
        end
      end

      # Check if text is present on screen
      def has_text?(text : String) : Bool
        render_text.includes?(text)
      end

      # Find text position (returns first match or nil)
      def find_text(text : String) : Tuple(Int32, Int32)?
        grid = render_grid
        grid.each_with_index do |row, y|
          if idx = row.index(text)
            return {idx, y}
          end
        end
        nil
      end

      # Get content of a specific row
      def row(y : Int32) : String
        render_grid[y]? || ""
      end

      # Get content of specific cell
      def cell(x : Int32, y : Int32) : Cell
        render
        @buffer.get(x, y)
      end

      # Debug dump of current screen
      def debug_dump : String
        render
        @buffer.debug_dump
      end

      # Resize the test screen
      def resize(@width : Int32, @height : Int32) : Nil
        @buffer = Buffer.new(@width, @height)
        @app.rect = Rect.new(0, 0, @width, @height)
        @app.refresh
      end
    end
  end
end
