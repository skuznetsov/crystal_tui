# Key event debugging
require "../src/tui"

class KeyTestApp < Tui::App
  @log : Array(String) = [] of String

  def compose : Array(Tui::Widget)
    [] of Tui::Widget
  end

  def handle_event(event : Tui::Event) : Bool
    case event
    when Tui::KeyEvent
      key_info = "Key: #{event.key}, Char: #{event.char.inspect}, Mods: #{event.modifiers}"
      @log << key_info
      @log.shift if @log.size > 20

      # Draw log
      STDOUT.print "\e[2J\e[H"  # Clear screen
      puts "=== Key Test (press 'q' to quit) ==="
      puts "Press any key to see its event info:\n"
      @log.each { |line| puts line }

      if event.key.tab?
        puts "\n>>> TAB DETECTED! <<<"
      end
      if event.key.page_up?
        puts "\n>>> PAGE UP DETECTED! <<<"
      end
      if event.key.page_down?
        puts "\n>>> PAGE DOWN DETECTED! <<<"
      end
    end

    super
  end
end

KeyTestApp.new.run
