# Sparkline - Mini chart for displaying data trends
module Tui
  class Sparkline < Widget
    # Block characters for different heights (8 levels)
    BLOCKS = [' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']

    property data : Array(Float64) = [] of Float64
    property max_value : Float64? = nil  # Auto-detect if nil
    property min_value : Float64? = nil  # Auto-detect if nil
    property color : Color = Color.green
    property summary : Bool = true  # Show min/max/current values

    def initialize(id : String? = nil, @data : Array(Float64) = [] of Float64)
      super(id)
    end

    # Add a data point
    def push(value : Float64) : Nil
      @data << value
      mark_dirty!
    end

    # Add multiple data points
    def push(*values : Float64) : Nil
      values.each { |v| @data << v }
      mark_dirty!
    end

    # Set data from array
    def data=(values : Array(Float64)) : Nil
      @data = values
      mark_dirty!
    end

    # Clear all data
    def clear : Nil
      @data.clear
      mark_dirty!
    end

    # Get effective min/max
    private def effective_range : {Float64, Float64}
      return {0.0, 1.0} if @data.empty?

      actual_min = @data.min
      actual_max = @data.max

      min = @min_value || actual_min
      max = @max_value || actual_max

      # Ensure valid range
      if min >= max
        max = min + 1.0
      end

      {min, max}
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      style = Style.new(fg: @color)
      dim_style = Style.new(fg: Color.palette(240))

      # Clear background
      @rect.each_cell do |x, y|
        buffer.set(x, y, ' ', Style.default) if clip.contains?(x, y)
      end

      return if @data.empty?

      min, max = effective_range
      range = max - min

      # Calculate how many data points to show
      chart_width = @rect.width
      chart_width -= 12 if @summary && @rect.width > 20  # Reserve space for summary

      # Sample or interpolate data to fit width
      visible_data = sample_data(chart_width)

      # Draw sparkline
      visible_data.each_with_index do |value, i|
        x = @rect.x + i
        y = @rect.y

        next unless clip.contains?(x, y)

        # Normalize value to 0-8 range
        normalized = ((value - min) / range * 8).clamp(0.0, 8.0).to_i
        char = BLOCKS[normalized]

        buffer.set(x, y, char, style)
      end

      # Draw summary if enabled and space available
      if @summary && @rect.width > 20
        draw_summary(buffer, clip, chart_width, min, max, dim_style)
      end
    end

    private def sample_data(target_width : Int32) : Array(Float64)
      return [] of Float64 if @data.empty? || target_width <= 0

      if @data.size <= target_width
        # Pad with empty space or return as-is
        @data
      else
        # Sample data at regular intervals (show most recent)
        start_idx = @data.size - target_width
        @data[start_idx..]
      end
    end

    private def draw_summary(buffer : Buffer, clip : Rect, chart_width : Int32, min : Float64, max : Float64, style : Style) : Nil
      x = @rect.x + chart_width + 1
      y = @rect.y

      return unless clip.contains?(x, y)

      # Current value
      current = @data.last? || 0.0

      # Format summary
      summary_text = format_number(current)

      # Draw separator
      buffer.set(x, y, '│', style) if clip.contains?(x, y)
      x += 1

      # Draw current value
      summary_text.each_char do |char|
        break if x >= @rect.x + @rect.width
        buffer.set(x, y, char, Style.new(fg: @color)) if clip.contains?(x, y)
        x += 1
      end
    end

    private def format_number(value : Float64) : String
      if value.abs >= 1_000_000
        "#{(value / 1_000_000).round(1)}M"
      elsif value.abs >= 1_000
        "#{(value / 1_000).round(1)}K"
      elsif value == value.to_i
        value.to_i.to_s
      else
        value.round(2).to_s
      end
    end

    def min_size : {Int32, Int32}
      {5, 1}
    end
  end
end
