require "../../spec_helper"

describe Tui::TabbedPanel do
  it "allows a caller to veto a tab close before state is removed" do
    tabs = Tui::TabbedPanel.new("tabs")
    tabs.add_tab("dirty", "dirty") { Tui::Label.new("content", "dirty") }
    close_events = 0
    tabs.on_before_tab_close { |id| id != "dirty" }
    tabs.on_tab_close { |_id| close_events += 1 }

    tabs.close_tab("dirty").should be_false
    tabs.tabs.map(&.id).should eq ["dirty"]
    tabs.active_tab_id.should eq "dirty"
    close_events.should eq 0
  end
end
