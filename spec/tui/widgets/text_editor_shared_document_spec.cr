require "../../spec_helper"
require "file_utils"

describe Tui::TextEditor::Document do
  it "shares content and document events while keeping each view cursor independent" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("shared-left", document)
    right = Tui::TextEditor.new("shared-right", document)
    left.load_content_as_saved("ab\ncd").should be_true

    changes = [] of Tui::TextEditor::TextChange
    left_redraws = 0
    right_redraws = 0
    document.on_text_change { |change| changes << change }
    left.on_change { left_redraws += 1 }
    right.on_change { right_redraws += 1 }

    left.set_cursor(0, 1)
    right.set_cursor(1, 1)
    left.insert_char('X')
    left.text.should eq "aXb\ncd"
    right.text.should eq "aXb\ncd"
    right.cursor.line.should eq 1
    right.cursor.col.should eq 1

    right.insert_char('Y')
    left.text.should eq "aXb\ncYd"
    left.cursor.line.should eq 0
    left.cursor.col.should eq 2
    changes.size.should eq 2
    left_redraws.should eq 2
    right_redraws.should eq 2
  end

  it "orders undo and redo globally without restoring another view cursor" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("history-left", document)
    right = Tui::TextEditor.new("history-right", document)
    left.load_content_as_saved("ab\ncd").should be_true
    changes = [] of Tui::TextEditor::TextChange
    document.on_text_change { |change| changes << change }

    left.set_cursor(0, 1)
    left.insert_char('X')
    right.set_cursor(1, 1)
    right.insert_char('Y')
    left.text.should eq "aXb\ncYd"

    right.undo.should be_true
    left.text.should eq "aXb\ncd"
    left.cursor.line.should eq 0
    left.cursor.col.should eq 2
    left.undo.should be_true
    right.text.should eq "ab\ncd"
    right.cursor.line.should eq 1
    right.cursor.col.should eq 1

    left.redo.should be_true
    right.redo.should be_true
    left.text.should eq "aXb\ncYd"
    changes.size.should eq 6
  end

  it "publishes save state once and keeps the no-op replace guard" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("save-left", document)
    right = Tui::TextEditor.new("save-right", document)
    left.load_content_as_saved("same").should be_true
    changes = [] of Tui::TextEditor::TextChange
    saved_paths = [] of Path
    document.on_text_change { |change| changes << change }
    document.on_save { |path| saved_paths << path }

    left.replace_text("same").should be_false
    changes.should be_empty
    left.replace_text("updated").should be_true
    right.text.should eq "updated"

    path = Path.new(Dir.tempdir, "text-editor-shared-#{Random::Secure.hex(8)}.txt")
    begin
      right.save_as(path).should be_true
      File.read(path.to_s).should eq "updated"
      left.path.should eq path
      left.modified?.should be_false
      right.modified?.should be_false
      saved_paths.should eq [path]
    ensure
      FileUtils.rm_rf(path.to_s)
    end
    changes.size.should eq 1
  end

  it "shares line-ending policy and saved state across views and history" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("ending-left", document)
    right = Tui::TextEditor.new("ending-right", document)
    left.load_content_as_saved("a\r\nb").should be_true
    right.line_ending.should eq "\r\n"

    right.set_cursor(1, 1)
    right.insert_newline
    left.text.should eq "a\r\nb\r\n"
    left.modified?.should be_true
    left.undo.should be_true
    right.text.should eq "a\r\nb"
    right.line_ending.should eq "\r\n"
    right.modified?.should be_false
  end

  it "detaches a closed view from redraws without splitting shared history" do
    document = Tui::TextEditor::Document.new
    open_view = Tui::TextEditor.new("detach-open", document)
    closed_view = Tui::TextEditor.new("detach-closed", document)
    open_view.load_content_as_saved("base").should be_true
    closed_redraws = 0
    closed_view.on_change { closed_redraws += 1 }
    closed_view.detach

    open_view.set_cursor(0, 4)
    open_view.insert_char('!')
    closed_view.text.should eq "base!"
    closed_redraws.should eq 0
    closed_view.undo.should be_true
    open_view.text.should eq "base"
    closed_redraws.should eq 0
  end

  it "refuses a save from a detached view" do
    document = Tui::TextEditor::Document.new
    live_view = Tui::TextEditor.new("save-live", document)
    retired_view = Tui::TextEditor.new("save-retired", document)
    live_view.load_content_as_saved("new content").should be_true
    path = Path.new(Dir.tempdir, "text-editor-retired-#{Random::Secure.hex(8)}.txt")
    File.write(path, "existing content")
    begin
      retired_view.detach
      retired_view.save_as(path).should be_false
      File.read(path).should eq "existing content"
      live_view.save_as(path).should be_true
      File.read(path).should eq "new content"
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "skips a view detached during another view's redraw callback" do
    document = Tui::TextEditor::Document.new
    open_view = Tui::TextEditor.new("reentrant-open", document)
    closing_view = Tui::TextEditor.new("reentrant-closing", document)
    open_view.load_content_as_saved("base").should be_true
    closing_redraws = 0
    open_view.on_change { closing_view.detach }
    closing_view.on_change { closing_redraws += 1 }

    open_view.set_cursor(0, 4)
    open_view.insert_char('!')

    closing_redraws.should eq 0
  end

  it "refreshes sibling views even when the document change publisher raises" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("publisher-error-left", document)
    right = Tui::TextEditor.new("publisher-error-right", document)
    left.load_content_as_saved("base").should be_true
    right_redraws = 0
    right.on_change { right_redraws += 1 }
    document.on_text_change { |_change| raise "publisher failed" }

    left.set_cursor(0, 4)
    expect_raises(Exception, "publisher failed") { left.insert_char('!') }

    right.text.should eq "base!"
    right_redraws.should eq 1
  end

  it "preserves another view's selection and folds during an unrelated edit" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("selection-left", document)
    right = Tui::TextEditor.new("selection-right", document)
    left.load_content_as_saved("head\nbody\nend").should be_true

    right.set_cursor(0, 0)
    right.move_right(with_selection: true)
    right.set_fold_ranges([Tui::TextEditor::FoldRange.new(0, 1)])
    right.toggle_fold_at(0).should be_true

    left.set_cursor(2, 3)
    left.insert_char('!')
    right.fold_ranges.should eq [Tui::TextEditor::FoldRange.new(0, 1)]
    right.line_hidden?(1).should be_true

    right.insert_char('Z')
    left.text.should eq "Zead\nbody\nend!"
  end

  it "does not snap another view's scrolled viewport back to its cursor" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("scroll-left", document)
    right = Tui::TextEditor.new("scroll-right", document)
    left.load_content_as_saved((0..11).map { |line| "line #{line}" }.join("\n")).should be_true
    right.rect = Tui::Rect.new(0, 0, 40, 3)
    right.scroll_view_by(5)
    right.scroll_y.should eq 5

    left.set_cursor(0, 0)
    left.insert_text("intro\n")

    right.cursor.should eq Tui::TextEditor::Cursor.new(1, 0)
    right.scroll_y.should eq 5
  end

  it "rebases sibling cursor and selection after a multiline insertion before them" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("rebase-insert-left", document)
    right = Tui::TextEditor.new("rebase-insert-right", document)
    left.load_content_as_saved("first\r\nsecond\r\nthird\r\nfourth").should be_true
    right.select_range(2, 1, 2, 4)
    right.copy.should eq "hir"

    left.set_cursor(0, 0)
    left.insert_text("intro\nchapter\n")

    left.text.should eq "intro\r\nchapter\r\nfirst\r\nsecond\r\nthird\r\nfourth"
    right.cursor.should eq Tui::TextEditor::Cursor.new(4, 4)
    right.copy.should eq "hir"
  end

  it "rebases sibling cursor and selection across same-line insertions and deletions" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("same-line-rebase-left", document)
    right = Tui::TextEditor.new("same-line-rebase-right", document)
    left.load_content_as_saved("abcdef").should be_true
    right.select_range(0, 3, 0, 5)
    right.copy.should eq "de"

    left.set_cursor(0, 0)
    left.insert_text("XY")
    right.cursor.should eq Tui::TextEditor::Cursor.new(0, 7)
    right.copy.should eq "de"

    left.select_range(0, 0, 0, 2)
    left.delete_selection
    right.cursor.should eq Tui::TextEditor::Cursor.new(0, 5)
    right.copy.should eq "de"
  end

  it "rebases a sibling selection across a CRLF multiline selection replacement" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("selection-replace-left", document)
    right = Tui::TextEditor.new("selection-replace-right", document)
    left.load_content_as_saved("alpha\r\nbeta\r\ngamma").should be_true
    right.select_range(2, 1, 2, 4)
    right.copy.should eq "amm"

    left.select_range(0, 0, 0, 1)
    left.insert_text("intro\nchapter\n")

    left.text.should eq "intro\r\nchapter\r\nlpha\r\nbeta\r\ngamma"
    right.cursor.should eq Tui::TextEditor::Cursor.new(4, 4)
    right.copy.should eq "amm"
  end

  it "rebases sibling cursor and selection after a multiline deletion before them" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("rebase-delete-left", document)
    right = Tui::TextEditor.new("rebase-delete-right", document)
    left.load_content_as_saved("head\nfirst\nsecond\nthird\ntail").should be_true
    right.select_range(3, 1, 3, 4)
    right.copy.should eq "hir"

    left.select_range(0, 0, 2, 0)
    left.delete_selection

    right.cursor.should eq Tui::TextEditor::Cursor.new(1, 4)
    right.copy.should eq "hir"
  end

  it "clears selections and folds invalidated by another view shrinking the document" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("shrink-left", document)
    right = Tui::TextEditor.new("shrink-right", document)
    left.load_content_as_saved("alpha\nbeta\ngamma").should be_true
    right.rect = Tui::Rect.new(0, 0, 40, 5)
    right.select_range(2, 4, 2, 5)
    right.set_fold_ranges([Tui::TextEditor::FoldRange.new(1, 2)])
    right.toggle_fold_at(1).should be_true

    left.replace_text("x").should be_true

    right.copy.should be_nil
    right.fold_ranges.should be_empty
    right.delete_selection
    right.insert_char('!')
    buffer = Tui::Buffer.new(40, 5)
    right.render(buffer, right.rect)
    right.text.should eq "x!"
  end

  it "shifts untouched folds and drops folds touched by a sibling incremental edit" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("fold-rebase-left", document)
    right = Tui::TextEditor.new("fold-rebase-right", document)
    left.load_content_as_saved("zero\none\ntwo\nthree\nfour").should be_true
    right.set_fold_ranges([Tui::TextEditor::FoldRange.new(3, 4)])
    right.toggle_fold_at(3).should be_true

    left.set_cursor(0, 0)
    left.insert_text("intro\n")

    right.fold_ranges.should eq [Tui::TextEditor::FoldRange.new(4, 5)]
    right.line_hidden?(5).should be_true

    left.set_cursor(5, 0)
    left.insert_char('X')
    right.fold_ranges.should be_empty
    right.line_hidden?(5).should be_false
  end

  it "clears sibling selections and folds across full replace, undo, and redo changes" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("full-history-left", document)
    right = Tui::TextEditor.new("full-history-right", document)
    left.load_content_as_saved("alpha\nbeta\ngamma").should be_true
    right.select_range(0, 0, 0, 5)
    right.set_fold_ranges([Tui::TextEditor::FoldRange.new(1, 2)])
    right.toggle_fold_at(1).should be_true

    left.replace_text("unrelated\nreplacement\ncontent").should be_true
    right.cursor.should eq Tui::TextEditor::Cursor.new(0, 5)
    right.copy.should be_nil
    right.fold_ranges.should be_empty

    left.undo.should be_true
    right.cursor.should eq Tui::TextEditor::Cursor.new(0, 5)
    right.text.should eq "alpha\nbeta\ngamma"
    right.copy.should be_nil
    right.fold_ranges.should be_empty

    left.redo.should be_true
    right.cursor.should eq Tui::TextEditor::Cursor.new(0, 5)
    right.text.should eq "unrelated\nreplacement\ncontent"
    right.copy.should be_nil
    right.fold_ranges.should be_empty
  end

  it "clears sibling selection and folds when the text setter replaces all content" do
    document = Tui::TextEditor::Document.new
    left = Tui::TextEditor.new("setter-full-left", document)
    right = Tui::TextEditor.new("setter-full-right", document)
    left.load_content_as_saved("alpha\nbeta\ngamma").should be_true
    right.select_range(0, 0, 0, 5)
    right.set_fold_ranges([Tui::TextEditor::FoldRange.new(1, 2)])
    right.toggle_fold_at(1).should be_true

    left.text = "unrelated\nreplacement\ncontent"

    right.text.should eq "unrelated\nreplacement\ncontent"
    right.copy.should be_nil
    right.fold_ranges.should be_empty
  end
end
