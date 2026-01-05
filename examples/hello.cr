# Hello World example for crystal_tui
require "../src/tui"

class HelloApp < Tui::App
  def compose : Array(Tui::Widget)
    [
      Tui::Label.new(
        "Hello, TUI!",
        fg: Tui::Color.green,
        bold: true,
        align: Tui::Label::Align::Center
      ),
      Tui::Label.new(
        "Press 'q' to quit",
        fg: Tui::Color.white,
        align: Tui::Label::Align::Center
      ),
    ] of Tui::Widget
  end
end

HelloApp.new.run
