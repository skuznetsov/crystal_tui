# Top menu bar widget (MC-style)
module Tui
  class MenuBar < Widget
    struct MenuItem
      property label : String
      property hotkey : Char?      # Alt+letter
      property items : Array(MenuAction)

      def initialize(@label, @hotkey = nil, @items = [] of MenuAction)
      end
    end

    struct MenuAction
      property label : String
      property hotkey : Char?      # Letter in menu
      property action : Proc(Nil)?
      property separator : Bool

      def initialize(@label, @hotkey = nil, @action = nil, @separator = false)
      end

      def self.separator : MenuAction
        MenuAction.new("", separator: true)
      end
    end

    @menus : Array(MenuItem) = [] of MenuItem
    @active_menu : Int32 = -1    # -1 = no menu open
    @active_item : Int32 = 0     # Item in dropdown
    @dropdown_open : Bool = false

    # Style - MC colors
    property bg_color : Color = Color.cyan
    property fg_color : Color = Color.black
    property hotkey_color : Color = Color.yellow
    property active_bg : Color = Color.black
    property active_fg : Color = Color.cyan
    property dropdown_bg : Color = Color.cyan
    property dropdown_fg : Color = Color.black
    property dropdown_hotkey : Color = Color.yellow
    property dropdown_active_bg : Color = Color.black
    property dropdown_active_fg : Color = Color.cyan
    property shadow_fg : Color = Color.palette(8)
    property shadow_bg : Color = Color.black

    # Callbacks
    @on_close : Proc(Nil)?

    def initialize(id : String? = nil)
      super(id)
      @focusable = true
    end

    def on_close(&block : -> Nil) : Nil
      @on_close = block
    end

    def add_menu(label : String, hotkey : Char? = nil, &block : Array(MenuAction) ->) : Nil
      items = [] of MenuAction
      block.call(items)
      @menus << MenuItem.new(label, hotkey, items)
    end

    def add_menu(menu : MenuItem) : Nil
      @menus << menu
    end

    def menus : Array(MenuItem)
      @menus
    end

    def open? : Bool
      @dropdown_open
    end

    def open(menu_index : Int32 = 0) : Nil
      @active_menu = menu_index.clamp(0, @menus.size - 1)
      @active_item = 0
      @dropdown_open = true
      self.focused = true
      mark_dirty!
    end

    def close : Nil
      @dropdown_open = false
      @active_menu = -1
      @on_close.try &.call
      mark_dirty!
    end

    def render(buffer : Buffer, clip : Rect) : Nil
      return unless visible?
      return if @rect.empty?

      style = Style.new(fg: @fg_color, bg: @bg_color)
      hotkey_style = Style.new(fg: @hotkey_color, bg: @bg_color)
      active_style = Style.new(fg: @active_fg, bg: @active_bg)

      # Clear bar background
      @rect.width.times do |x|
        buffer.set(@rect.x + x, @rect.y, ' ', style) if clip.contains?(@rect.x + x, @rect.y)
      end

      # Draw menu items
      x = @rect.x + 1
      @menus.each_with_index do |menu, i|
        is_active = i == @active_menu && @dropdown_open
        item_style = is_active ? active_style : style
        hk_style = is_active ? active_style : hotkey_style

        # Space before
        buffer.set(x, @rect.y, ' ', item_style) if clip.contains?(x, @rect.y)
        x += 1

        # Draw label with hotkey highlighting
        menu.label.each_char_with_index do |char, ci|
          char_style = (menu.hotkey && char.downcase == menu.hotkey.not_nil!.downcase && ci == find_hotkey_pos(menu.label, menu.hotkey.not_nil!)) ? hk_style : item_style
          buffer.set(x, @rect.y, char, char_style) if clip.contains?(x, @rect.y)
          x += 1
        end

        # Space after
        buffer.set(x, @rect.y, ' ', item_style) if clip.contains?(x, @rect.y)
        x += 1
      end

      # Draw dropdown if open
      if @dropdown_open && @active_menu >= 0 && @active_menu < @menus.size
        draw_dropdown(buffer, clip)
      end
    end

    private def find_hotkey_pos(label : String, hotkey : Char) : Int32
      label.each_char_with_index do |c, i|
        return i if c.downcase == hotkey.downcase
      end
      -1
    end

    private def draw_dropdown(buffer : Buffer, clip : Rect) : Nil
      menu = @menus[@active_menu]
      return if menu.items.empty?

      # Calculate dropdown position
      x = @rect.x + 1
      @active_menu.times do |i|
        x += @menus[i].label.size + 2
      end

      y = @rect.y + 1
      width = menu.items.max_of { |item| item.separator ? 1 : item.label.size } + 4
      height = menu.items.size

      # Draw shadow
      draw_shadow(buffer, clip, x, y, width, height)

      # Draw dropdown background
      dropdown_style = Style.new(fg: @dropdown_fg, bg: @dropdown_bg)
      active_item_style = Style.new(fg: @dropdown_active_fg, bg: @dropdown_active_bg)
      hotkey_item_style = Style.new(fg: @dropdown_hotkey, bg: @dropdown_bg)

      menu.items.each_with_index do |item, i|
        is_active = i == @active_item
        row_y = y + i

        if item.separator
          # Draw separator line
          width.times do |dx|
            char = dx == 0 ? '├' : (dx == width - 1 ? '┤' : '─')
            buffer.set(x + dx, row_y, char, dropdown_style) if clip.contains?(x + dx, row_y)
          end
        else
          # Draw menu item
          item_style = is_active ? active_item_style : dropdown_style
          hk_style = is_active ? active_item_style : hotkey_item_style

          # Left border
          buffer.set(x, row_y, '│', dropdown_style) if clip.contains?(x, row_y)

          # Item text with hotkey
          label_x = x + 2
          item.label.each_char_with_index do |char, ci|
            char_style = (item.hotkey && char.downcase == item.hotkey.not_nil!.downcase && ci == find_hotkey_pos(item.label, item.hotkey.not_nil!)) ? hk_style : item_style
            buffer.set(label_x + ci, row_y, char, char_style) if clip.contains?(label_x + ci, row_y)
          end

          # Fill remaining space
          (item.label.size...width - 3).each do |dx|
            buffer.set(x + 2 + dx, row_y, ' ', item_style) if clip.contains?(x + 2 + dx, row_y)
          end

          # Right border
          buffer.set(x + width - 1, row_y, '│', dropdown_style) if clip.contains?(x + width - 1, row_y)
        end
      end

      # Draw bottom border
      bottom_y = y + height
      width.times do |dx|
        char = dx == 0 ? '└' : (dx == width - 1 ? '┘' : '─')
        buffer.set(x + dx, bottom_y, char, dropdown_style) if clip.contains?(x + dx, bottom_y)
      end
    end

    private def draw_shadow(buffer : Buffer, clip : Rect, x : Int32, y : Int32, width : Int32, height : Int32) : Nil
      shadow_style = Style.new(fg: @shadow_fg, bg: @shadow_bg)

      # Right shadow (2 chars)
      (y + 1).upto(y + height + 1) do |sy|
        [x + width, x + width + 1].each do |sx|
          next unless clip.contains?(sx, sy)
          existing = buffer.get(sx, sy)
          char = existing.char.printable? ? existing.char : ' '
          buffer.set(sx, sy, char, shadow_style)
        end
      end

      # Bottom shadow
      (x + 2).upto(x + width + 1) do |sx|
        sy = y + height + 1
        next unless clip.contains?(sx, sy)
        existing = buffer.get(sx, sy)
        char = existing.char.printable? ? existing.char : ' '
        buffer.set(sx, sy, char, shadow_style)
      end
    end

    def handle_event(event : Event) : Bool
      return false if event.stopped?

      case event
      when KeyEvent
        # F9 opens menu (MC convention)
        if event.key.f9?
          if @dropdown_open
            close
          else
            open(0)
          end
          event.stop!
          return true
        end

        # Alt+letter for menu hotkeys (when not open)
        if event.modifiers.alt? && !@dropdown_open
          if char = event.char
            @menus.each_with_index do |menu, i|
              if menu.hotkey && menu.hotkey.not_nil!.downcase == char.downcase
                open(i)
                event.stop!
                return true
              end
            end
          end
        end

        # Only handle navigation when open
        return false unless @dropdown_open

        case event.key
        when .escape?
          close
          event.stop!
          return true
        when .left?
          prev_menu
          event.stop!
          return true
        when .right?
          next_menu
          event.stop!
          return true
        when .up?
          prev_item
          event.stop!
          return true
        when .down?
          next_item
          event.stop!
          return true
        when .enter?
          execute_current
          event.stop!
          return true
        else
          # Check item hotkeys
          if char = event.char
            if select_by_hotkey(char)
              event.stop!
              return true
            end
          end
        end
      end

      false
    end

    private def next_menu : Nil
      @active_menu = (@active_menu + 1) % @menus.size
      @active_item = 0
      mark_dirty!
    end

    private def prev_menu : Nil
      @active_menu = (@active_menu - 1) % @menus.size
      @active_menu = @menus.size - 1 if @active_menu < 0
      @active_item = 0
      mark_dirty!
    end

    private def next_item : Nil
      return if @active_menu < 0 || @menus[@active_menu].items.empty?
      items = @menus[@active_menu].items
      loop do
        @active_item = (@active_item + 1) % items.size
        break unless items[@active_item].separator
      end
      mark_dirty!
    end

    private def prev_item : Nil
      return if @active_menu < 0 || @menus[@active_menu].items.empty?
      items = @menus[@active_menu].items
      loop do
        @active_item = (@active_item - 1) % items.size
        @active_item = items.size - 1 if @active_item < 0
        break unless items[@active_item].separator
      end
      mark_dirty!
    end

    private def execute_current : Nil
      return if @active_menu < 0
      items = @menus[@active_menu].items
      return if @active_item < 0 || @active_item >= items.size

      item = items[@active_item]
      return if item.separator

      close
      item.action.try &.call
    end

    private def select_by_hotkey(char : Char) : Bool
      return false if @active_menu < 0
      items = @menus[@active_menu].items

      items.each_with_index do |item, i|
        next if item.separator
        if item.hotkey && item.hotkey.not_nil!.downcase == char.downcase
          @active_item = i
          execute_current
          return true
        end
      end

      false
    end
  end
end
