require "../../spec_helper"

private def new_parser : Tui::InputParser
  Tui::InputParser.new(Tui::MockInputProvider.new)
end

private def flush_after_burst_timeout(parser : Tui::InputParser) : Tui::Event?
  sleep Tui::InputParser::BURST_CHAR_INTERVAL + 2.milliseconds
  parser.flush_paste_burst
end

private def burst_allocation_delta(chars : Int32) : UInt64
  GC.collect
  before = GC.stats.total_bytes
  parser = new_parser
  parser.feed("x" * chars)
  GC.stats.total_bytes - before
end

private def bracketed_paste_allocation_delta(bytes : Int32) : UInt64
  payload = "x" * bytes
  input = "\e[200~#{payload}\e[201~"
  parser = new_parser
  GC.collect
  before = GC.stats.total_bytes
  events = parser.feed(input)
  event = events.first?
  unless events.size == 1 && event.is_a?(Tui::PasteEvent) && event.text == payload
    raise "bracketed paste probe emitted incorrect events: #{events.inspect}"
  end
  GC.stats.total_bytes - before
end

private def ascii_burst_allocation_delta(bytes : Int32) : UInt64
  payload = "x" * bytes
  parser = new_parser
  GC.collect
  before = GC.stats.total_bytes
  parser.feed(payload)
  GC.stats.total_bytes - before
end

private def paste_text_before_up(parser : Tui::InputParser, data : String) : String
  events = parser.feed(data + "\e[A")
  unless events.size == 1 && events[0].is_a?(Tui::PasteEvent)
    raise "expected paste before Up, got #{events.inspect}"
  end
  events[0].as(Tui::PasteEvent).text
end

describe Tui::InputParser do
  it "keeps ASCII burst allocations below a fixed bound" do
    allocated = ascii_burst_allocation_delta(100_000)

    # The buffer itself grows geometrically to 128 KiB at this size. Leave
    # allocator headroom while rejecting per-character decoder or timer work.
    unless allocated < 1_000_000
      raise "ASCII burst allocation bound exceeded: #{allocated} bytes"
    end
  end

  it "decodes valid two-, three-, and four-byte UTF-8 sequences across feeds" do
    parser = new_parser

    two_byte = "\xC3\xA9"
    three_byte = "\xE4\xB8\xAD"
    four_byte = "\xF0\x9F\x99\x82"

    raise "2-byte prefix emitted early" unless parser.feed("\xC3").empty?
    raise "2-byte split decode changed" unless paste_text_before_up(parser, "\xA9#{two_byte}#{two_byte}") == "ééé"

    parser = new_parser
    raise "3-byte prefix emitted early" unless parser.feed("\xE4\xB8").empty?
    raise "3-byte split decode changed" unless paste_text_before_up(parser, "\xAD#{three_byte}#{three_byte}") == "中中中"

    parser = new_parser
    raise "4-byte prefix emitted early" unless parser.feed("\xF0\x9F\x99").empty?
    raise "4-byte split decode changed" unless paste_text_before_up(parser, "\x82#{four_byte}#{four_byte}") == "🙂🙂🙂"
  end

  it "preserves malformed UTF-8 replacement and declared-width consumption" do
    cases = [
      {"invalid start", "\x80"},
      {"invalid continuation", "\xC2\x41"},
      {"overlong two-byte", "\xC0\x80"},
      {"overlong three-byte", "\xE0\x80\x80"},
      {"surrogate", "\xED\xA0\x80"},
      {"out of range", "\xF4\x90\x80\x80"},
      {"invalid four-byte lead", "\xF5\x80\x80\x80"},
    ]

    cases.each do |name, malformed|
      parser = new_parser
      text = paste_text_before_up(parser, malformed + "abc")
      expected = "�abc"
      raise "#{name} changed: expected #{expected.inspect}, got #{text.inspect}" unless text == expected
    end
  end

  it "keeps incomplete declared sequences buffered until complete" do
    parser = new_parser
    raise "incomplete 3-byte prefix emitted early" unless parser.feed("\xE2").empty?
    raise "incomplete 3-byte prefix consumed too soon" unless parser.feed("\x82").empty?

    text = paste_text_before_up(parser, "\xACabc")
    raise "incomplete sequence recovery changed: #{text.inspect}" unless text == "€abc"
  end

  it "keeps long non-bracketed burst accumulation amortized-linear" do
    small = burst_allocation_delta(2_048)
    large = burst_allocation_delta(8_192)

    # A quadratic append path grows by roughly 16x for a 4x input increase.
    # Leave room for parser setup and GC noise while rejecting that shape.
    unless large < small * 6
      raise "burst allocation scaling is superlinear: 2K=#{small}, 8K=#{large}"
    end
  end

  it "keeps bracketed paste finalization within one payload materialization" do
    payload_bytes = 1_048_576
    allocated = bracketed_paste_allocation_delta(payload_bytes)

    # The old Array -> Slice -> String finalization allocated well over 4x
    # the payload at this size. Keep this as an allocation bound, not timing.
    unless allocated < payload_bytes.to_u64 * 4
      raise "bracketed paste allocation bound exceeded: #{allocated} for #{payload_bytes} bytes"
    end
  end

  it "flushes an ASCII non-bracketed burst as one paste and resets it" do
    parser = new_parser
    raise "burst input emitted before timeout" unless parser.feed("abcdef").empty?
    raise "burst should be pending" unless parser.has_pending_burst?

    event = flush_after_burst_timeout(parser)
    raise "expected timed-out burst paste, got #{event.inspect}" unless event.is_a?(Tui::PasteEvent) && event.text == "abcdef"
    raise "burst state should reset after flush" if parser.has_pending_burst?

    parser.feed("xyz")
    second = flush_after_burst_timeout(parser)
    raise "reset burst leaked previous text: #{second.inspect}" unless second.is_a?(Tui::PasteEvent) && second.text == "xyz"
  end

  it "wakes the input loop to flush an active burst" do
    provider = Tui::MockInputProvider.new
    provider.push_string("abc")
    parser = Tui::InputParser.new(provider)
    parser.start

    begin
      wakeup = parser.read_event(100.milliseconds)
      raise "expected burst wakeup, got #{wakeup.inspect}" unless wakeup.is_a?(Tui::WakeupEvent)

      event = parser.flush_paste_burst
      unless event.is_a?(Tui::PasteEvent) && event.text == "abc"
        raise "expected timed-out burst paste after wakeup, got #{event.inspect}"
      end
      raise "burst should be reset after wakeup flush" if parser.has_pending_burst?
    ensure
      parser.stop
    end
  end

  it "preserves UTF-8 characters in a non-bracketed burst" do
    parser = new_parser
    text = "a中🙂é"
    raise "unicode burst emitted before timeout" unless parser.feed(text).empty?

    event = flush_after_burst_timeout(parser)
    raise "expected UTF-8 burst #{text.inspect}, got #{event.inspect}" unless event.is_a?(Tui::PasteEvent) && event.text == text
  end

  it "keeps the timer threshold for short input" do
    parser = new_parser
    raise "short input emitted too early" unless parser.feed("ab").empty?

    first = flush_after_burst_timeout(parser)
    second = parser.flush_paste_burst
    unless first.is_a?(Tui::KeyEvent) && first.char == 'a' && second.is_a?(Tui::KeyEvent) && second.char == 'b'
      raise "short input should flush as key events, got #{first.inspect}, #{second.inspect}"
    end
    raise "short input should be fully flushed" if parser.has_pending_burst?
  end

  it "flushes an active burst before a following key event" do
    parser = new_parser
    raise "burst input emitted before key event" unless parser.feed("abc").empty?

    events = parser.feed("\e[A")
    first = events[0]?
    second = parser.flush_paste_burst
    unless events.size == 1 && first.is_a?(Tui::PasteEvent) && second.is_a?(Tui::KeyEvent)
      raise "burst/key ordering changed: #{events.inspect}"
    end
    raise "burst/key payload changed: #{events.inspect}" unless first.as(Tui::PasteEvent).text == "abc" && second.as(Tui::KeyEvent).key == Tui::Key::Up
    raise "event flush should reset burst state" if parser.has_pending_burst?
  end

  it "leaves bracketed paste parsing on its existing path" do
    parser = new_parser
    event = parser.feed("\e[200~a中\n\e[201~").first?
    raise "expected bracketed paste event, got #{event.inspect}" unless event.is_a?(Tui::PasteEvent) && event.text == "a中\n"
    raise "bracketed paste should not leave burst state" if parser.has_pending_burst?
  end

  it "preserves partial terminators inside bracketed paste payloads" do
    parser = new_parser
    text = "before\e[20x中\nafter"
    event = parser.feed("\e[200~#{text}\e[201~").first?

    raise "partial terminator changed paste payload: #{event.inspect}" unless event.is_a?(Tui::PasteEvent) && event.text == text
  end

  it "resets bracketed paste storage between empty and consecutive pastes" do
    parser = new_parser
    events = parser.feed("\e[200~\e[201~\e[200~next\e[201~\e[A")

    unless events.size == 3 &&
           events[0].is_a?(Tui::PasteEvent) && events[0].as(Tui::PasteEvent).text.empty? &&
           events[1].is_a?(Tui::PasteEvent) && events[1].as(Tui::PasteEvent).text == "next" &&
           events[2].is_a?(Tui::KeyEvent) && events[2].as(Tui::KeyEvent).key == Tui::Key::Up
      raise "consecutive paste ordering changed: #{events.inspect}"
    end
  end

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
