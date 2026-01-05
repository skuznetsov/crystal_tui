# DataTable demo for crystal_tui
require "../src/tui"

class TableApp < Tui::App
  @table : Tui::DataTable?
  @status : Tui::Label?

  def compose : Array(Tui::Widget)
    @status = Tui::Label.new(
      "Select a file with arrows, Enter to open, Space to select, q to quit",
      fg: Tui::Color.cyan,
      align: Tui::Label::Align::Center
    )

    @table = Tui::DataTable.new
    table = @table.not_nil!

    # Define columns
    table.add_column("name", "Name", width: 30)
    table.add_column("size", "Size", width: 10, align: Tui::Label::Align::Right)
    table.add_column("modified", "Modified", width: 20)
    table.add_column("type", "Type", width: 10)

    # Add sample data (simulating a file listing)
    table.add_row(name: "..", size: "<DIR>", modified: "", type: "dir")
    table.add_row(name: "Documents", size: "<DIR>", modified: "2024-01-15", type: "dir")
    table.add_row(name: "Downloads", size: "<DIR>", modified: "2024-01-14", type: "dir")
    table.add_row(name: "Pictures", size: "<DIR>", modified: "2024-01-10", type: "dir")
    table.add_row(name: "config.json", size: "2.4 KB", modified: "2024-01-15", type: "json")
    table.add_row(name: "readme.md", size: "5.1 KB", modified: "2024-01-12", type: "md")
    table.add_row(name: "main.cr", size: "12.8 KB", modified: "2024-01-15", type: "cr")
    table.add_row(name: "shard.yml", size: "0.5 KB", modified: "2024-01-01", type: "yml")
    table.add_row(name: "Makefile", size: "1.2 KB", modified: "2024-01-05", type: "make")
    table.add_row(name: "LICENSE", size: "1.1 KB", modified: "2023-12-01", type: "txt")
    table.add_row(name: ".gitignore", size: "0.2 KB", modified: "2023-12-01", type: "git")
    table.add_row(name: "spec_helper.cr", size: "0.8 KB", modified: "2024-01-08", type: "cr")
    table.add_row(name: "data.csv", size: "45.2 KB", modified: "2024-01-14", type: "csv")
    table.add_row(name: "report.pdf", size: "1.2 MB", modified: "2024-01-13", type: "pdf")
    table.add_row(name: "archive.tar.gz", size: "15.6 MB", modified: "2024-01-11", type: "tar")

    table.zebra_stripes = true
    table.focus!

    table.on_select do |idx, row|
      @status.try &.text = "Selected: #{row["name"]?} (#{row["size"]?})"
      mark_dirty!
    end

    table.on_activate do |idx, row|
      name = row["name"]? || ""
      if row["type"]? == "dir"
        @status.try &.text = "Opening directory: #{name}"
      else
        @status.try &.text = "Opening file: #{name}"
      end
      mark_dirty!
    end

    [
      Tui::Label.new(
        "═══ File Browser ═══",
        fg: Tui::Color.yellow,
        bold: true,
        align: Tui::Label::Align::Center
      ),
      table,
      @status.not_nil!,
    ] of Tui::Widget
  end
end

TableApp.new.run
