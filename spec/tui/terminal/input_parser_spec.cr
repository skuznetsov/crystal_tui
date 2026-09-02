require "../../spec_helper"

private def new_parser : Tui::InputParser
  Tui::InputParser.new(Tui::MockInputProvider.new)
end

describe Tui::InputParser do
  it "decodes Option/Alt+F from an ESC prefix" do
    events = new_parser.feed("\ef")
    raise "expected one event, got #{events.size}" unless events.size == 1
    event = events[0]
    raise "expected key event" unless event.is_a?(Tui::KeyEvent)
    raise "expected alt+f, got key=#{event.key} char=#{event.char.inspect} mods=#{event.modifiers}" unless event.matches?("alt+f")
    raise "option+f alias should match" unless event.matches?("option+f")
  end

  it "keeps double-escape as a single Escape with a leftover ESC" do
    events = new_parser.feed("\e\e")
    raise "first of ESC ESC should emit one Escape, got #{events.size}" unless events.size == 1
    event = events[0]
    raise "expected Escape" unless event.is_a?(Tui::KeyEvent) && event.key == Tui::Key::Escape
    raise "double-escape must not become Alt+Escape" if event.modifiers.alt?
  end

  it "decodes kitty CSI u Option+F" do
    events = new_parser.feed("\e[102;3u")
    raise "expected one event, got #{events.inspect}" unless events.size == 1
    event = events[0]
    raise "CSI u Option+F should match alt+f, got #{event.inspect}" unless event.is_a?(Tui::KeyEvent) && event.matches?("alt+f")
  end

  it "decodes kitty CSI u Shift+Enter" do
    events = new_parser.feed("\e[13;2u")
    raise "expected one event, got #{events.inspect}" unless events.size == 1
    event = events[0]
    raise "Shift+Enter CSI u should match shift+enter, got #{event.inspect}" unless event.is_a?(Tui::KeyEvent) && event.matches?("shift+enter")
  end

  it "decodes xterm modifyOtherKeys Shift+Enter" do
    events = new_parser.feed("\e[27;2;13~")
    raise "expected one event, got #{events.inspect}" unless events.size == 1
    event = events[0]
    raise "modifyOtherKeys Shift+Enter should match, got #{event.inspect}" unless event.is_a?(Tui::KeyEvent) && event.matches?("shift+enter")
  end

  it "decodes CSI 13;2~ as Shift+Enter" do
    events = new_parser.feed("\e[13;2~")
    raise "expected one event, got #{events.inspect}" unless events.size == 1
    event = events[0]
    raise "CSI 13;2~ should be Shift+Enter, got #{event.inspect}" unless event.is_a?(Tui::KeyEvent) && event.matches?("shift+enter")
  end

  it "decodes CSI Z as Shift+Tab" do
    events = new_parser.feed("\e[Z")
    raise "expected one event, got #{events.inspect}" unless events.size == 1
    event = events[0]
    raise "CSI Z should be Shift+Tab, got #{event.inspect}" unless event.is_a?(Tui::KeyEvent) && event.matches?("shift+tab")
  end

  it "still treats a bare CR as unmodified Enter" do
    events = new_parser.feed("\r")
    raise "expected one event, got #{events.inspect}" unless events.size == 1
    event = events[0]
    raise "bare CR should be Enter without shift" unless event.is_a?(Tui::KeyEvent) && event.matches?("enter")
    raise "bare CR must not match shift+enter" if event.is_a?(Tui::KeyEvent) && event.matches?("shift+enter")
  end

  it "treats macOS Option+F (ƒ) as alt+f" do
    event = Tui::KeyEvent.new('ƒ')
    raise "ƒ should match alt+f" unless event.matches?("alt+f")
    raise "ƒ should match option+f" unless event.matches?("option+f")
    raise "plain f must not match alt+f" if Tui::KeyEvent.new('f').matches?("alt+f")

    events = new_parser.feed("ƒ")
    raise "expected one event for ƒ, got #{events.inspect}" unless events.size == 1
    parsed = events[0]
    raise "ƒ should parse as alt+f, got #{parsed.inspect}" unless parsed.is_a?(Tui::KeyEvent) && parsed.matches?("alt+f")
  end

  it "decodes kitty CSI u Option+F with colon subfields" do
    events = new_parser.feed("\e[102:402;3u")
    raise "expected one event, got #{events.inspect}" unless events.size == 1
    event = events[0]
    raise "colon CSI u Option+F should match alt+f, got #{event.inspect}" unless event.is_a?(Tui::KeyEvent) && event.matches?("alt+f")
  end

  it "decodes kitty CSI u for the ƒ codepoint as alt+f" do
    events = new_parser.feed("\e[402u")
    raise "expected one event, got #{events.inspect}" unless events.size == 1
    event = events[0]
    raise "ƒ codepoint CSI u should match alt+f, got #{event.inspect}" unless event.is_a?(Tui::KeyEvent) && event.matches?("alt+f")
  end

  it "ignores kitty CSI u key-release events" do
    events = new_parser.feed("\e[102;3:3u")
    raise "key-release must not emit a key event, got #{events.inspect}" unless events.empty?
  end
end
