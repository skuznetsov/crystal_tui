# LoadingIndicator - Animated spinner/loading animation
module Tui
  class LoadingIndicator < Widget
    enum Style
      Spinner    # ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏
      Dots       # ⣾⣽⣻⢿⡿⣟⣯⣷
      Line       # -\|/
      Pulse      # ◐◓◑◒
      Bar        # ▏▎▍▌▋▊▉█
      Bounce     # ⠁⠂⠄⠂
    end

    FRAMES = {
      Style::Spinner => ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'],
      Style::Dots    => ['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'],
      Style::Line    => ['-', '\\', '|', '/'],
      Style::Pulse   => ['◐', '◓', '◑', '◒'],
      Style::Bar     => ['▏', '▎', '▍', '▌', '▋', '▊', '▉', '█', '▉', '▊', '▋', '▌', '▍', '▎', '▏'],
      Style::Bounce  => ['⠁', '⠂', '⠄', '⠂'],
    }

    property style : Style = Style::Spinner
    property color : Color = Color.cyan
    property text : String = ""
    property interval : Time::Span = 100.milliseconds

    @frame : Int32 = 0
    @running : Bool = false
    @fiber : Fiber?

    def initialize(id : String? = nil, @style : Style = Style::Spinner)
      super(id)
    end

    def start : Nil
      return if @running
      @running = true
      @fiber = spawn(name: "loading-indicator") do
        while @running
          sleep @interval
          @frame = (@frame + 1) % frames.size
          mark_dirty!
        end
      end
    end

    def stop : Nil
      @running = false
      @fiber = nil
    end

    def running? : Bool
      @running
    end

    private def frames : Array(Char)
      FRAMES[@style]
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      x, y = @rect.x, @rect.y

      # Draw spinner
      spinner_style = Tui::Style.new(fg: @color)
      char = frames[@frame % frames.size]
      buffer.set(x, y, char, spinner_style) if clip.contains?(x, y)

      # Draw text after spinner
      unless @text.empty?
        text_style = Tui::Style.new(fg: Color.white)
        @text.each_char_with_index do |c, i|
          buffer.set(x + 2 + i, y, c, text_style) if clip.contains?(x + 2 + i, y)
        end
      end
    end

    def min_size : {Int32, Int32}
      {2 + @text.size, 1}
    end

    def finalize
      stop
    end
  end
end
