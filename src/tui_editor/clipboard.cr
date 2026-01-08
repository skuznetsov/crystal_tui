# Clipboard with history for TUI Editor
require "./canvas"

module TuiEditor
  # Single clipboard entry
  struct ClipboardEntry
    property node : CanvasNode
    property cut : Bool
    property timestamp : Time

    def initialize(@node, @cut = false)
      @timestamp = Time.utc
    end

    def label : String
      mode = @cut ? "✂" : "📋"
      "#{mode} #{@node.widget_def.icon} #{@node.widget_def.name}"
    end
  end

  # Clipboard history manager
  class ClipboardHistory
    MAX_HISTORY = 20

    @entries : Array(ClipboardEntry) = [] of ClipboardEntry

    def initialize
    end

    def push(node : CanvasNode, cut : Bool = false) : Nil
      entry = ClipboardEntry.new(node, cut)
      @entries.unshift(entry)  # Add to front (most recent first)

      # Limit history size
      if @entries.size > MAX_HISTORY
        @entries.pop
      end
    end

    def latest : ClipboardEntry?
      @entries.first?
    end

    def get(index : Int32) : ClipboardEntry?
      @entries[index]?
    end

    def entries : Array(ClipboardEntry)
      @entries
    end

    def size : Int32
      @entries.size
    end

    def empty? : Bool
      @entries.empty?
    end

    def clear : Nil
      @entries.clear
    end

    def remove(index : Int32) : ClipboardEntry?
      return nil if index < 0 || index >= @entries.size
      @entries.delete_at(index)
    end
  end

  # Clipboard picker panel (shown in a dialog or sidebar)
  class ClipboardPicker < Tui::Panel
    @history : ClipboardHistory
    @selected_index : Int32 = 0
    @on_select : Proc(CanvasNode, Nil)?
    @on_close : Proc(Nil)?

    def initialize(@history : ClipboardHistory)
      super("Clipboard", id: "clipboard-picker")
      @focusable = true
    end

    def on_select(&block : CanvasNode -> Nil)
      @on_select = block
    end

    def on_close(&block : -> Nil)
      @on_close = block
    end

    def render(buffer : Tui::Buffer, clip : Tui::Rect) : Nil
      super

      inner = inner_rect
      return if inner.empty?

      if @history.empty?
        msg = "Clipboard empty"
        style = Tui::Style.new(fg: Tui::Color.rgb(100, 100, 100))
        msg.each_char_with_index do |c, i|
          buffer.set(inner.x + i, inner.y, c, style) if clip.contains?(inner.x + i, inner.y)
        end
        return
      end

      # Draw entries
      @history.entries.each_with_index do |entry, i|
        break if i >= inner.height - 1

        y = inner.y + i
        is_selected = i == @selected_index

        style = if is_selected && focused?
                  Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.cyan)
                elsif is_selected
                  Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.white)
                else
                  Tui::Style.new(fg: Tui::Color.white)
                end

        text = entry.label.ljust(inner.width)
        text.each_char_with_index do |c, ci|
          break if ci >= inner.width
          buffer.set(inner.x + ci, y, c, style) if clip.contains?(inner.x + ci, y)
        end
      end

      # Hints at bottom
      hint = "Enter=Paste  d=Delete  Esc=Close"
      hint_style = Tui::Style.new(fg: Tui::Color.rgb(100, 100, 100))
      hint_y = inner.y + inner.height - 1
      hint.each_char_with_index do |c, i|
        buffer.set(inner.x + i, hint_y, c, hint_style) if clip.contains?(inner.x + i, hint_y)
      end
    end

    def handle_event(event : Tui::Event) : Bool
      return false if event.stopped?

      case event
      when Tui::KeyEvent
        return false unless focused?

        case
        when event.matches?("up"), event.matches?("k")
          if @selected_index > 0
            @selected_index -= 1
            mark_dirty!
          end
          return true
        when event.matches?("down"), event.matches?("j")
          if @selected_index < @history.size - 1
            @selected_index += 1
            mark_dirty!
          end
          return true
        when event.matches?("enter"), event.matches?("space")
          if entry = @history.get(@selected_index)
            @on_select.try &.call(entry.node)
          end
          return true
        when event.matches?("d"), event.matches?("delete")
          @history.remove(@selected_index)
          @selected_index = @selected_index.clamp(0, (@history.size - 1).clamp(0, Int32::MAX))
          mark_dirty!
          return true
        when event.matches?("escape")
          @on_close.try &.call
          return true
        end
      when Tui::MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          focus unless focused?
          # Click to select
          inner = inner_rect
          clicked = event.y - inner.y
          if clicked >= 0 && clicked < @history.size
            @selected_index = clicked
            mark_dirty!
          end
          return true
        end
      end

      super
    end
  end
end
