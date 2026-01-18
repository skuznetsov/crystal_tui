# Wakeup event - internal event to trigger pending input flush
module Tui
  class WakeupEvent < Event
    # Empty event used to wake up event loop for timeout handling
  end
end
