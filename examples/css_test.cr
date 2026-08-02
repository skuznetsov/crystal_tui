# TCSS parser test using properties consumed by Label and Panel widgets.
require "../src/tui"

# Test TCSS parsing
css = <<-TCSS
  /* Variables */
  $primary: cyan;
  $bg-dark: rgb(30, 30, 40);

  /* Type selector */
  Label {
    background: blue;
    color: white;
  }

  /* Pseudo-class */
  Label:focus {
    background: $primary;
    text-style: bold;
  }

  /* ID selector */
  #my-label {
    color: yellow;
  }

  /* Class selector */
  .active {
    text-align: center;
  }

  /* Panel-specific properties */
  Panel {
    border: light green;
    title-align: center;
  }

  /* Compound selector */
  Label.primary {
    color: $primary;
  }
TCSS

puts "Parsing TCSS..."
stylesheet = Tui::CSS.parse(css)

# Verify both selector matching and widget-side property application.
label_probe = Tui::Label.new("Probe", id: "my-label")
label_probe.add_class("active")
label_style = stylesheet.style_for(label_probe)
raise "CSS probe failed: Label selectors did not match" unless label_style["color"]? == "yellow" && label_style["text-align"]? == "center"
label_probe.apply_css_style(label_style)
raise "CSS probe failed: Label properties were not applied" unless label_probe.style.fg == Tui::Color.yellow && label_probe.align.center?

panel_probe = Tui::Panel.new("Probe", id: "probe-panel")
panel_style = stylesheet.style_for(panel_probe)
raise "CSS probe failed: Panel selector did not match" unless panel_style["border"]? == "light green"
panel_probe.apply_css_style(panel_style)
raise "CSS probe failed: Panel properties were not applied" unless panel_probe.border_color == Tui::Color.green && panel_probe.title_align.center?

compound_probe = Tui::Label.new("Compound", id: "compound-label")
compound_probe.add_class("primary")
compound_style = stylesheet.style_for(compound_probe)
raise "CSS probe failed: compound selector did not match" unless compound_style["color"]? == "cyan"

def selector_name(selector : Tui::CSS::Selector) : String
  case selector
  when Tui::CSS::Selector::Type
    selector.name
  when Tui::CSS::Selector::Id
    "##{selector.id}"
  when Tui::CSS::Selector::Class
    ".#{selector.class_name}"
  when Tui::CSS::Selector::Pseudo
    "#{selector_name(selector.base)}:#{selector.pseudo}"
  when Tui::CSS::Selector::Compound
    selector.selectors.map { |part| selector_name(part) }.join
  when Tui::CSS::Selector::Universal
    "*"
  when Tui::CSS::Selector::Descendant
    "#{selector_name(selector.ancestor)} #{selector_name(selector.descendant)}"
  when Tui::CSS::Selector::Child
    "#{selector_name(selector.parent_sel)} > #{selector_name(selector.child_sel)}"
  else
    selector.class.name
  end
end

puts "\n=== Variables ==="
stylesheet.variables.each do |name, value|
  puts "  $#{name}: #{value}"
end

puts "\n=== Rules ==="
stylesheet.rules.each do |rule|
  selector_str = selector_name(rule.selector)

  puts "\n  #{selector_str} (specificity: #{rule.selector.specificity})"
  rule.properties.each do |prop, value|
    puts "    #{prop}: #{value}"
  end
end

puts "\n=== Test Complete ==="
