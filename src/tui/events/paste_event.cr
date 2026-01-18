# Clipboard paste event (bracketed paste)
module Tui
  class PasteEvent < Event
    getter text : String

    def initialize(@text : String)
    end
  end
end
