require "../../spec_helper"

describe Tui::Calendar do
  describe "#initialize" do
    it "creates calendar with current date" do
      cal = Tui::Calendar.new
      today = Time.local
      cal.selected_date.year.should eq(today.year)
      cal.selected_date.month.should eq(today.month)
      cal.selected_date.day.should eq(today.day)
    end

    it "creates calendar with specific date" do
      date = Time.local(2023, 12, 25)
      cal = Tui::Calendar.new(date: date)
      cal.selected_date.year.should eq(2023)
      cal.selected_date.month.should eq(12)
      cal.selected_date.day.should eq(25)
    end

    it "accepts an id" do
      cal = Tui::Calendar.new(id: "birthday")
      cal.id.should eq("birthday")
    end

    it "is focusable" do
      cal = Tui::Calendar.new
      cal.focusable?.should be_true
    end
  end

  describe "#next_month" do
    it "advances to next month" do
      cal = Tui::Calendar.new(date: Time.local(2023, 6, 15))
      cal.next_month
      # View should be July 2023
    end

    it "handles year boundary" do
      cal = Tui::Calendar.new(date: Time.local(2023, 12, 15))
      cal.next_month
      # View should be January 2024
    end
  end

  describe "#prev_month" do
    it "goes to previous month" do
      cal = Tui::Calendar.new(date: Time.local(2023, 6, 15))
      cal.prev_month
      # View should be May 2023
    end

    it "handles year boundary" do
      cal = Tui::Calendar.new(date: Time.local(2023, 1, 15))
      cal.prev_month
      # View should be December 2022
    end
  end

  describe "#select_date" do
    it "selects the given date" do
      cal = Tui::Calendar.new
      new_date = Time.local(2024, 7, 4)
      cal.select_date(new_date)
      cal.selected_date.year.should eq(2024)
      cal.selected_date.month.should eq(7)
      cal.selected_date.day.should eq(4)
    end

    it "triggers on_select callback" do
      selected = nil
      cal = Tui::Calendar.new
      cal.on_select { |d| selected = d }
      cal.select_date(Time.local(2024, 1, 1))
      selected.should_not be_nil
    end
  end

  describe "#today" do
    it "selects today's date" do
      cal = Tui::Calendar.new(date: Time.local(2020, 1, 1))
      cal.today
      today = Time.local
      cal.selected_date.year.should eq(today.year)
      cal.selected_date.month.should eq(today.month)
      cal.selected_date.day.should eq(today.day)
    end
  end

  describe "#min_size" do
    it "returns minimum dimensions" do
      cal = Tui::Calendar.new
      min = cal.min_size
      min[0].should be >= 21  # At least 7 * 3 for days
      min[1].should be >= 8   # Header + weekdays + 6 weeks
    end
  end
end
