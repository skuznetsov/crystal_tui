# Progress Bar widget
module Tui
  class ProgressBar < Widget
    enum BarStyle
      Bar        # [████████░░░░]
      Blocks     # [▓▓▓▓▓▓░░░░░]
      Dots       # [●●●●●○○○○○]
      Percentage # 75%
      Spinner    # ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏
    end

    SPINNER_FRAMES = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']

    @value : Float64 = 0.0
    @max : Float64 = 100.0
    @min : Float64 = 0.0
    @indeterminate : Bool = false
    @spinner_frame : Int32 = 0
    @center_text : String = ""

    property bar_style : BarStyle = BarStyle::Bar
    property fg_color : Color = Color.green
    property bg_color : Color = Color.default
    property filled_bg : Color = Color.green      # Background of filled portion
    property empty_bg : Color = Color.palette(8)  # Background of empty portion
    property text_fg : Color = Color.white        # Text on filled
    property text_empty_fg : Color = Color.white  # Text on empty
    property empty_color : Color = Color.palette(8)  # Dark gray (for chars)
    property show_percentage : Bool = true
    property show_center_text : Bool = false      # Show text centered in bar
    property label : String = ""

    def initialize(id : String? = nil)
      super(id)
    end

    def value : Float64
      @value
    end

    def value=(val : Float64) : Nil
      @value = val.clamp(@min, @max)
      mark_dirty!
    end

    def min : Float64
      @min
    end

    def min=(val : Float64) : Nil
      @min = val
      mark_dirty!
    end

    def max : Float64
      @max
    end

    def max=(val : Float64) : Nil
      @max = val
      mark_dirty!
    end

    def percentage : Float64
      return 0.0 if @max == @min
      ((@value - @min) / (@max - @min) * 100).clamp(0.0, 100.0)
    end

    def indeterminate? : Bool
      @indeterminate
    end

    def indeterminate=(val : Bool) : Nil
      @indeterminate = val
      mark_dirty!
    end

    def advance(delta : Float64 = 1.0) : Nil
      self.value = @value + delta
    end

    def tick : Nil
      if @indeterminate
        @spinner_frame = (@spinner_frame + 1) % SPINNER_FRAMES.size
        mark_dirty!
      end
    end

    def complete? : Bool
      @value >= @max
    end

    def reset : Nil
      @value = @min
      @spinner_frame = 0
      mark_dirty!
    end

    def center_text : String
      @center_text
    end

    def center_text=(text : String) : Nil
      @center_text = text
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      if @indeterminate
        render_indeterminate(buffer, clip)
      else
        render_determinate(buffer, clip)
      end
    end

    private def render_determinate(buffer : Buffer, clip : Rect) : Nil
      style = Style.new(fg: @fg_color, bg: @bg_color)
      empty_style = Style.new(fg: @empty_color, bg: @bg_color)

      y = @rect.y
      pct = percentage

      # Calculate bar width
      label_width = @label.empty? ? 0 : @label.size + 1
      pct_width = @show_percentage && !@show_center_text ? 5 : 0  # " 100%" (not shown if center text mode)
      bar_width = @rect.width - label_width - pct_width - 2  # -2 for brackets
      filled = ((bar_width * pct) / 100).to_i

      x = @rect.x

      # Draw label
      unless @label.empty?
        @label.each_char do |char|
          buffer.set(x, y, char, style) if clip.contains?(x, y)
          x += 1
        end
        buffer.set(x, y, ' ', style) if clip.contains?(x, y)
        x += 1
      end

      # Draw left bracket
      buffer.set(x, y, '[', style) if clip.contains?(x, y)
      x += 1

      # Prepare center text if enabled
      display_text = ""
      text_start = 0
      text_width = 0
      if @show_center_text
        # Use center_text or fall back to percentage
        display_text = @center_text.empty? ? "#{pct.to_i}%" : @center_text
        text_width = Unicode.display_width(display_text)
        # Center the text in the bar
        text_start = (bar_width - text_width) // 2
        text_start = 0 if text_start < 0
      end

      # Build character array with positions for Unicode-aware rendering
      # For simple ASCII text, we can use simple approach; for Unicode, track positions
      text_chars = display_text.chars if @show_center_text

      # Draw bar
      bar_width.times do |i|
        is_filled = i < filled

        # Determine character
        char = if @show_center_text
                 # Show text character or space with bg color
                 text_pos = i - text_start
                 if text_pos >= 0 && text_pos < text_width && text_chars
                   # Find character at display position
                   char_at_pos = find_char_at_display_pos(text_chars, text_pos)
                   char_at_pos || ' '
                 else
                   ' '
                 end
               else
                 # Normal character-based progress
                 case @bar_style
                 when .bar?
                   is_filled ? '█' : '░'
                 when .blocks?
                   is_filled ? '▓' : '░'
                 when .dots?
                   is_filled ? '●' : '○'
                 else
                   is_filled ? '█' : '░'
                 end
               end

        # Determine style based on filled/empty and mode
        char_style = if @show_center_text
                       # Use bg colors for progress, text colors for fg
                       if is_filled
                         Style.new(fg: @text_fg, bg: @filled_bg)
                       else
                         Style.new(fg: @text_empty_fg, bg: @empty_bg)
                       end
                     else
                       # Normal mode
                       is_filled ? style : empty_style
                     end

        buffer.set(x, y, char, char_style) if clip.contains?(x, y)
        x += 1
      end

      # Draw right bracket
      buffer.set(x, y, ']', style) if clip.contains?(x, y)
      x += 1

      # Draw percentage (only if not using center text mode)
      if @show_percentage && !@show_center_text
        pct_str = " #{pct.to_i.to_s.rjust(3)}%"
        pct_str.each_char do |char|
          buffer.set(x, y, char, style) if clip.contains?(x, y)
          x += 1
        end
      end
    end

    private def render_indeterminate(buffer : Buffer, clip : Rect) : Nil
      style = Style.new(fg: @fg_color, bg: @bg_color)

      y = @rect.y
      x = @rect.x

      # Draw label
      unless @label.empty?
        @label.each_char do |char|
          buffer.set(x, y, char, style) if clip.contains?(x, y)
          x += 1
        end
        buffer.set(x, y, ' ', style) if clip.contains?(x, y)
        x += 1
      end

      # Draw spinner
      spinner = SPINNER_FRAMES[@spinner_frame]
      buffer.set(x, y, spinner, style) if clip.contains?(x, y)
    end

    # Find character at a given display position (accounting for wide chars)
    private def find_char_at_display_pos(chars : Array(Char), display_pos : Int32) : Char?
      current_pos = 0
      chars.each do |c|
        char_width = Unicode.char_width(c)
        if display_pos >= current_pos && display_pos < current_pos + char_width
          return c
        end
        current_pos += char_width
      end
      nil
    end
  end
end
