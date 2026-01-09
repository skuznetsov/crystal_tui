# Footer widget - MC-style function key bar
module Tui
  class Footer < Widget
    struct Binding
      property key : Int32      # F1-F10
      property label : String
      property action : Symbol?

      def initialize(@key, @label, @action = nil)
      end
    end

    property bindings : Array(Binding) = [] of Binding
    property key_color : Color = Color.black
    property key_bg : Color = Color.cyan
    property label_color : Color = Color.black
    property label_bg : Color = Color.white

    # Callback for when a binding is clicked
    @on_click : Proc(Binding, Nil)?

    def on_click(&block : Binding -> Nil) : Nil
      @on_click = block
    end

    def initialize(id : String? = nil)
      super(id)
    end

    # Quick setup with standard MC-like bindings
    def self.mc_style : Footer
      footer = Footer.new
      footer.bindings = [
        Binding.new(1, "Help"),
        Binding.new(2, "Menu"),
        Binding.new(3, "View"),
        Binding.new(4, "Edit"),
        Binding.new(5, "Copy", :copy),
        Binding.new(6, "Move", :move),
        Binding.new(7, "Mkdir", :mkdir),
        Binding.new(8, "Del", :delete),
        Binding.new(9, ""),
        Binding.new(10, "Quit", :quit),
      ]
      footer
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty? || @rect.height < 1

      y = @rect.y
      x = @rect.x

      key_style = Style.new(fg: @key_color, bg: @key_bg)
      label_style = Style.new(fg: @label_color, bg: @label_bg)

      # First, fill entire width with background to avoid gaps
      @rect.width.times do |col|
        px = @rect.x + col
        buffer.set(px, y, ' ', label_style) if clip.contains?(px, y)
      end

      # Calculate width per binding (10 F-keys)
      num_keys = 10
      width_per_key = @rect.width // num_keys

      num_keys.times do |i|
        binding = @bindings.find { |b| b.key == i + 1 }
        key_num = (i + 1).to_s
        key_num = "10" if i == 9

        label = binding.try(&.label) || ""

        # Draw key number
        key_num.each_char do |char|
          draw_char(buffer, clip, x, y, char, key_style)
          x += 1
        end

        # Draw label (fill remaining width)
        remaining = width_per_key - key_num.size
        label_chars = label.size > remaining ? label[0, remaining] : label

        label_chars.each_char do |char|
          draw_char(buffer, clip, x, y, char, label_style)
          x += 1
        end

        # Pad with spaces
        (remaining - label_chars.size).times do
          draw_char(buffer, clip, x, y, ' ', label_style)
          x += 1
        end
      end

      # Background already filled at the start, no need to fill remaining
    end

    private def draw_char(buffer : Buffer, clip : Rect, x : Int32, y : Int32, char : Char, style : Style) : Nil
      buffer.set(x, y, char, style) if clip.contains?(x, y)
    end

    def handle_event(event : Event) : Bool
      case event
      when MouseEvent
        if event.action.press? && event.button.left? && event.in_rect?(@rect)
          # Calculate which binding was clicked
          width_per_key = @rect.width // 10
          clicked_x = event.x - @rect.x
          key_index = clicked_x // width_per_key
          key_num = key_index + 1

          if binding = @bindings.find { |b| b.key == key_num }
            @on_click.try &.call(binding)
            event.stop!
            return true
          end
        end
      end
      false
    end
  end
end
