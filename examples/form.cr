# Form demo for crystal_tui
require "../src/tui"

class FormApp < Tui::App
  @name_input : Tui::Input?
  @email_input : Tui::Input?
  @password_input : Tui::Input?
  @status_label : Tui::Label?

  def compose : Array(Tui::Widget)
    @status_label = Tui::Label.new(
      "Fill in the form and press Submit",
      fg: Tui::Color.cyan,
      align: Tui::Label::Align::Center
    )

    @name_input = Tui::Input.new(placeholder: "Enter your name")
    @email_input = Tui::Input.new(placeholder: "Enter your email")
    @password_input = Tui::Input.new(placeholder: "Enter password", password: true)

    submit_btn = Tui::Button.new(
      "Submit",
      style: Tui::Style.new(fg: Tui::Color.white, bg: Tui::Color.green)
    )
    submit_btn.on_press { submit_form }

    clear_btn = Tui::Button.new(
      "Clear",
      style: Tui::Style.new(fg: Tui::Color.white, bg: Tui::Color.red)
    )
    clear_btn.on_press { clear_form }

    [
      Tui::Label.new(
        "=== Registration Form ===",
        fg: Tui::Color.yellow,
        bold: true,
        align: Tui::Label::Align::Center
      ),
      Tui::Label.new(""),
      Tui::Label.new("Name:", fg: Tui::Color.white),
      @name_input.not_nil!,
      Tui::Label.new(""),
      Tui::Label.new("Email:", fg: Tui::Color.white),
      @email_input.not_nil!,
      Tui::Label.new(""),
      Tui::Label.new("Password:", fg: Tui::Color.white),
      @password_input.not_nil!,
      Tui::Label.new(""),
      submit_btn,
      clear_btn,
      Tui::Label.new(""),
      @status_label.not_nil!,
      Tui::Label.new(
        "Tab: next field | Shift+Tab: prev | Enter: submit | q: quit",
        fg: Tui::Color.rgb(128, 128, 128),
        align: Tui::Label::Align::Center
      ),
    ] of Tui::Widget
  end

  def submit_form
    name = @name_input.try(&.value) || ""
    email = @email_input.try(&.value) || ""
    password = @password_input.try(&.value) || ""

    if name.empty? || email.empty? || password.empty?
      @status_label.try &.text = "Error: All fields are required!"
      @status_label.try &.style = Tui::Style.new(fg: Tui::Color.red)
    else
      @status_label.try &.text = "Success! Welcome, #{name} (#{email})"
      @status_label.try &.style = Tui::Style.new(fg: Tui::Color.green)
    end
    mark_dirty!
  end

  def clear_form
    @name_input.try &.value = ""
    @email_input.try &.value = ""
    @password_input.try &.value = ""
    @status_label.try &.text = "Form cleared"
    @status_label.try &.style = Tui::Style.new(fg: Tui::Color.cyan)
    mark_dirty!
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

FormApp.new.run
