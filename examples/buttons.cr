# Button demo for crystal_tui
require "../src/tui"

class ButtonApp < Tui::App
  @counter : Int32 = 0
  @counter_label : Tui::Label?

  def compose : Array(Tui::Widget)
    @counter_label = Tui::Label.new(
      "Counter: 0",
      fg: Tui::Color.yellow,
      bold: true,
      align: Tui::Label::Align::Center
    )

    increment_btn = Tui::Button.new(
      "Increment [+]",
      style: Tui::Style.new(fg: Tui::Color.white, bg: Tui::Color.green)
    )
    increment_btn.on_press { increment }

    decrement_btn = Tui::Button.new(
      "Decrement [-]",
      style: Tui::Style.new(fg: Tui::Color.white, bg: Tui::Color.red)
    )
    decrement_btn.on_press { decrement }

    reset_btn = Tui::Button.new(
      "Reset [0]",
      style: Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.yellow)
    )
    reset_btn.on_press { reset }

    [
      Tui::Label.new(
        "Button Demo - Click or press Enter on focused button",
        fg: Tui::Color.cyan,
        align: Tui::Label::Align::Center
      ),
      Tui::Label.new(""),  # Spacer
      @counter_label.not_nil!,
      Tui::Label.new(""),  # Spacer
      increment_btn,
      decrement_btn,
      reset_btn,
      Tui::Label.new(""),  # Spacer
      Tui::Label.new(
        "Tab: next button | Enter/Space: press | q: quit",
        fg: Tui::Color.white,
        align: Tui::Label::Align::Center
      ),
    ] of Tui::Widget
  end

  def increment
    @counter += 1
    update_label
  end

  def decrement
    @counter -= 1
    update_label
  end

  def reset
    @counter = 0
    update_label
  end

  private def update_label
    @counter_label.try &.text = "Counter: #{@counter}"
  end

  def handle_event(event : Tui::Event) : Bool
    if event.is_a?(Tui::KeyEvent)
      case
      when event.matches?("tab")
        focus_next
        event.stop!
        return true
      when event.matches?("shift+tab")
        focus_prev
        event.stop!
        return true
      end
    end
    super
  end

  private def focus_next
    focusable = @children.select(&.focusable?)
    return if focusable.empty?

    current_idx = focusable.index { |w| w.focused? } || -1
    focusable.each(&.blur)

    next_idx = (current_idx + 1) % focusable.size
    focusable[next_idx].focus!
    mark_dirty!
  end

  private def focus_prev
    focusable = @children.select(&.focusable?)
    return if focusable.empty?

    current_idx = focusable.index { |w| w.focused? } || focusable.size
    focusable.each(&.blur)

    prev_idx = (current_idx - 1) % focusable.size
    focusable[prev_idx].focus!
    mark_dirty!
  end
end

ButtonApp.new.run
