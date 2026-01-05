# TCSS Parser test
require "../src/tui"

# Test TCSS parsing
css = <<-TCSS
  /* Variables */
  $primary: cyan;
  $bg-dark: rgb(30, 30, 40);

  /* Type selector */
  Button {
    background: blue;
    color: white;
  }

  /* Pseudo-class */
  Button:focus {
    background: $primary;
  }

  /* ID selector */
  #my-button {
    color: yellow;
  }

  /* Class selector */
  .active {
    border-color: green;
  }

  /* Compound selector */
  Button.primary {
    background: $primary;
  }
TCSS

puts "Parsing TCSS..."
stylesheet = Tui::CSS.parse(css)

puts "\n=== Variables ==="
stylesheet.variables.each do |name, value|
  puts "  $#{name}: #{value}"
end

puts "\n=== Rules ==="
stylesheet.rules.each do |rule|
  selector_str = case rule.selector
                 when Tui::CSS::Selector::Type   then rule.selector.as(Tui::CSS::Selector::Type).name
                 when Tui::CSS::Selector::Id     then "##{rule.selector.as(Tui::CSS::Selector::Id).id}"
                 when Tui::CSS::Selector::Class  then ".#{rule.selector.as(Tui::CSS::Selector::Class).class_name}"
                 when Tui::CSS::Selector::Pseudo then "#{rule.selector.as(Tui::CSS::Selector::Pseudo).base}:#{rule.selector.as(Tui::CSS::Selector::Pseudo).pseudo}"
                 else                                 rule.selector.class.name
                 end

  puts "\n  #{selector_str} (specificity: #{rule.selector.specificity})"
  rule.properties.each do |prop, value|
    puts "    #{prop}: #{value}"
  end
end

puts "\n=== Test Complete ==="
