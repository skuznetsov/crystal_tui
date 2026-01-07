require "../src/tui"

# Streaming demo - simulates LLM response streaming
# Run with: crystal run examples/streaming_demo.cr

SIMULATED_RESPONSE = <<-MD
# Streaming Response Demo

This demonstrates **real-time markdown rendering** as tokens arrive from an LLM.

## Features

The MarkdownView widget supports:

- **Streaming mode** with blinking cursor
- **Auto-scroll** to follow new content
- Proper **markdown parsing** even with partial content
- `Inline code` rendering

## Code Example

Here's some Crystal code being streamed:

```crystal
class StreamingDemo
  def initialize
    @buffer = ""
  end

  def append(token : String)
    @buffer += token
    render
  end

  private def render
    puts @buffer
  end
end
```

## List Example

1. First item streaming in
2. Second item appears
3. Third item follows

## Blockquote

> "The future is already here — it's just not evenly distributed."
> — William Gibson

---

*Streaming complete!*
MD

class StreamingDemoApp < Tui::App
  @markdown : Tui::MarkdownView
  @tokens : Array(String)
  @token_index : Int32 = 0
  @streaming_fiber : Fiber?
  @status : Tui::Label

  def initialize
    super
    @markdown = Tui::MarkdownView.new("content")
    @status = Tui::Label.new("[Space] Start/Restart | [q] Quit", id: "status")
    @status.style = Tui::Style.new(fg: Tui::Color.black, bg: Tui::Color.cyan)
    @status.align = Tui::Label::Align::Center

    # Tokenize the response (simulate word-by-word streaming)
    @tokens = tokenize(SIMULATED_RESPONSE)
  end

  private def tokenize(text : String) : Array(String)
    tokens = [] of String
    current = ""

    text.each_char do |c|
      if c == ' ' || c == '\n'
        tokens << current + c.to_s unless current.empty?
        current = ""
        tokens << c.to_s if current.empty? && c == '\n'
      else
        current += c
      end
    end
    tokens << current unless current.empty?
    tokens
  end

  def compose : Array(Tui::Widget)
    # Use VBox for layout
    vbox = Tui::VBox.new("main")
    vbox.add_child(@markdown)
    vbox.add_child(@status)
    [vbox] of Tui::Widget
  end

  private def start_streaming : Nil
    # Reset
    @markdown.clear
    @token_index = 0
    @markdown.start_streaming

    # Start streaming fiber
    @streaming_fiber = spawn(name: "token-streamer") do
      stream_tokens
    end
  end

  private def stream_tokens : Nil
    while @token_index < @tokens.size
      token = @tokens[@token_index]
      @markdown.append(token)
      @token_index += 1

      # Variable delay for realistic effect
      delay = case token
              when /\n/     then 50.milliseconds   # Fast for newlines
              when /^```/   then 100.milliseconds  # Pause at code blocks
              when /^#/     then 80.milliseconds   # Slight pause at headings
              else               20.milliseconds   # Normal tokens
              end

      sleep delay
    end

    @markdown.stop_streaming
  end

  def handle_event(event : Tui::Event) : Bool
    if event.is_a?(Tui::KeyEvent)
      if event.matches?("ctrl+c") || event.matches?("ctrl+q") || event.matches?("q")
        quit
        return true
      end

      if event.matches?("space")
        start_streaming
        return true
      end
    end

    # Let markdown view handle scrolling
    if @markdown.handle_event(event)
      return true
    end

    super
  end
end

StreamingDemoApp.new.run
