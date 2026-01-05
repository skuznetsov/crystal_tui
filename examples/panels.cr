# Panel demo for crystal_tui - shows different border styles
require "../src/tui"

class PanelApp < Tui::App
  def compose : Array(Tui::Widget)
    # Create panels with different border styles
    panels = [] of Tui::Widget

    panels << create_panel("Light Border", Tui::Panel::BorderStyle::Light, Tui::Color.white)
    panels << create_panel("Heavy Border", Tui::Panel::BorderStyle::Heavy, Tui::Color.cyan)
    panels << create_panel("Double Border", Tui::Panel::BorderStyle::Double, Tui::Color.yellow)
    panels << create_panel("Round Border", Tui::Panel::BorderStyle::Round, Tui::Color.green)
    panels << create_panel("ASCII Border", Tui::Panel::BorderStyle::Ascii, Tui::Color.magenta)

    panels << Tui::Label.new(
      "Press 'q' to quit",
      fg: Tui::Color.white,
      align: Tui::Label::Align::Center
    )

    panels
  end

  private def create_panel(title : String, style : Tui::Panel::BorderStyle, color : Tui::Color) : Tui::Panel
    panel = Tui::Panel.new(
      title: title,
      border_style: style,
      border_color: color
    )

    # Set content
    label = Tui::Label.new(
      "Content inside #{title.downcase}",
      fg: color,
      align: Tui::Label::Align::Center
    )
    panel.content = label

    panel
  end
end

PanelApp.new.run
