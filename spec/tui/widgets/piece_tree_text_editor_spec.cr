require "../../spec_helper"

private def piece_tree_editor(id : String, content : String = "") : Tui::TextEditor
  editor = Tui::TextEditor.new(id)
  editor.rect = Tui::Rect.new(0, 0, 80, 12)
  editor.text = content unless content.empty?
  editor.focus
  editor
end

describe Tui::TextEditor do
  it "emits a bounded structured change with UTF-16 coordinates" do
    editor = piece_tree_editor("piece-tree-change-unicode", "a🙂界\r\nnext")
    changes = [] of Tui::TextEditor::TextChange
    legacy_calls = 0
    editor.on_text_change { |change| changes << change }
    editor.on_change { legacy_calls += 1 }
    editor.set_cursor(0, 2)

    editor.insert_char('🚀')

    changes.size.should eq 1
    change = changes.first
    change.incremental?.should be_true
    change.start.should eq Tui::TextEditor::TextPosition.new(0, 2, 3)
    change.finish.should eq Tui::TextEditor::TextPosition.new(0, 2, 3)
    change.text.should eq "🚀"
    legacy_calls.should eq 1
  end

  it "emits one replacement event for a multi-line selection" do
    editor = piece_tree_editor("piece-tree-change-selection", "a🙂x\r\nnext")
    changes = [] of Tui::TextEditor::TextChange
    legacy_calls = 0
    editor.on_text_change { |change| changes << change }
    editor.on_change { legacy_calls += 1 }
    editor.select_range(0, 1, 1, 2)

    editor.insert_text("β\n")

    editor.text.should eq "aβ\r\nxt"
    changes.size.should eq 1
    change = changes.first
    change.start.should eq Tui::TextEditor::TextPosition.new(0, 1, 1)
    change.finish.should eq Tui::TextEditor::TextPosition.new(1, 2, 2)
    change.text.should eq "β\r\n"
    legacy_calls.should eq 1
  end

  it "describes a CRLF line join using pre-edit coordinates" do
    editor = piece_tree_editor("piece-tree-change-crlf", "a🙂\r\nb")
    changes = [] of Tui::TextEditor::TextChange
    editor.on_text_change { |change| changes << change }
    editor.set_cursor(1, 0)

    editor.backspace

    editor.text.should eq "a🙂b"
    change = changes.first
    change.start.should eq Tui::TextEditor::TextPosition.new(0, 2, 3)
    change.finish.should eq Tui::TextEditor::TextPosition.new(1, 0, 0)
    change.text.should eq ""
  end

  it "describes delete, newline, and paste operations exactly" do
    delete_editor = piece_tree_editor("piece-tree-change-delete", "a🙂b\r\nnext")
    delete_changes = [] of Tui::TextEditor::TextChange
    callback_text = ""
    delete_editor.on_text_change do |change|
      delete_changes << change
      callback_text = delete_editor.text
    end
    delete_editor.set_cursor(0, 1)

    delete_editor.delete

    delete_changes.last.start.should eq Tui::TextEditor::TextPosition.new(0, 1, 1)
    delete_changes.last.finish.should eq Tui::TextEditor::TextPosition.new(0, 2, 3)
    delete_changes.last.text.should eq ""
    callback_text.should eq "ab\r\nnext" # callback runs after mutation

    newline_editor = piece_tree_editor("piece-tree-change-newline", "ab\rc")
    newline_changes = [] of Tui::TextEditor::TextChange
    newline_editor.on_text_change { |change| newline_changes << change }
    newline_editor.set_cursor(0, 1)

    newline_editor.insert_newline

    newline_changes.last.start.should eq Tui::TextEditor::TextPosition.new(0, 1, 1)
    newline_changes.last.finish.should eq Tui::TextEditor::TextPosition.new(0, 1, 1)
    newline_changes.last.text.should eq "\r"
    newline_editor.text.should eq "a\rb\rc"

    paste_editor = piece_tree_editor("piece-tree-change-paste", "a\r\nb")
    paste_changes = [] of Tui::TextEditor::TextChange
    paste_editor.on_text_change { |change| paste_changes << change }
    paste_editor.set_cursor(1, 1)

    paste_editor.paste("x\ny")

    paste_changes.last.start.should eq Tui::TextEditor::TextPosition.new(1, 1, 1)
    paste_changes.last.finish.should eq Tui::TextEditor::TextPosition.new(1, 1, 1)
    paste_changes.last.text.should eq "x\r\ny"
    paste_editor.text.should eq "a\r\nbx\r\ny"
  end

  it "describes forward newline deletion as a cross-line range" do
    editor = piece_tree_editor("piece-tree-change-delete-newline", "a\r\nb")
    changes = [] of Tui::TextEditor::TextChange
    editor.on_text_change { |change| changes << change }
    editor.set_cursor(0, 1)

    editor.delete

    changes.last.start.should eq Tui::TextEditor::TextPosition.new(0, 1, 1)
    changes.last.finish.should eq Tui::TextEditor::TextPosition.new(1, 0, 0)
    changes.last.text.should eq ""
    editor.text.should eq "ab"
  end

  it "uses full-change events when a precise local edit is unavailable" do
    editor = piece_tree_editor("piece-tree-change-full", "a\rX\nb")
    changes = [] of Tui::TextEditor::TextChange
    editor.on_text_change { |change| changes << change }
    editor.set_cursor(1, 1)

    editor.backspace

    editor.text.should eq "a\r\r\nb"
    changes.last.full?.should be_true

    editor.undo.should be_true
    changes.last.full?.should be_true

    editor.redo.should be_true
    changes.last.full?.should be_true

    editor.replace_text("replacement").should be_true
    changes.last.full?.should be_true
  end

  it "keeps cursor columns character-indexed across Unicode edits and undo" do
    editor = piece_tree_editor("piece-tree-unicode", "a🙂界\n終")
    editor.set_cursor(0, 2)

    editor.insert_char('🚀')
    editor.cursor.should eq Tui::TextEditor::Cursor.new(0, 3)
    editor.text.should eq "a🙂🚀界\n終"

    editor.backspace
    editor.cursor.should eq Tui::TextEditor::Cursor.new(0, 2)
    editor.text.should eq "a🙂界\n終"

    editor.select_range(0, 1, 0, 3)
    editor.copy.should eq "🙂界"
    editor.delete_selection
    editor.text.should eq "a\n終"
    editor.undo.should be_true
    editor.text.should eq "a🙂界\n終"
    editor.cursor.should eq Tui::TextEditor::Cursor.new(0, 3)

    editor.undo.should be_true
    editor.text.should eq "a🙂🚀界\n終"
    editor.cursor.should eq Tui::TextEditor::Cursor.new(0, 3)

    editor.undo.should be_true
    editor.text.should eq "a🙂界\n終"
    editor.cursor.should eq Tui::TextEditor::Cursor.new(0, 2)
  end

  it "edits and undoes homogeneous LF, CRLF, and CR documents" do
    ["\n", "\r\n", "\r"].each do |ending|
      editor = piece_tree_editor("piece-tree-ending-#{ending.bytesize}", "left#{ending}right")
      editor.set_cursor(0, 4)
      editor.insert_newline
      editor.text.should eq "left#{ending}#{ending}right"
      editor.cursor.should eq Tui::TextEditor::Cursor.new(1, 0)

      editor.backspace
      editor.text.should eq "left#{ending}right"
      editor.undo.should be_true
      editor.text.should eq "left#{ending}#{ending}right"
      editor.redo.should be_true
      editor.text.should eq "left#{ending}right"
    end
  end

  it "preserves mixed line endings and uses the first style for new lines" do
    editor = piece_tree_editor("piece-tree-mixed-ending", "a\rb\r\nc\nd")

    editor.text.should eq "a\rb\r\nc\nd"
    editor.set_cursor(2, 1)
    editor.insert_newline
    editor.text.should eq "a\rb\r\nc\r\n\nd"
    editor.lines.should eq ["a", "b", "c", "", "d"]
    editor.undo.should be_true
    editor.text.should eq "a\rb\r\nc\nd"
  end

  it "does not merge untouched CR and LF separators when deleting line content" do
    editor = piece_tree_editor("piece-tree-mixed-delete", "a\rX\nb")
    editor.set_cursor(1, 1)

    editor.backspace

    editor.lines.should eq ["a", "", "b"]
    editor.text.should eq "a\r\r\nb"
    editor.undo.should be_true
    editor.text.should eq "a\rX\nb"
  end

  it "round-trips a large document through many structural undo states" do
    original = String.build do |io|
      12_000.times do |index|
        io << "line-" << index << ": αβγ🙂" << "\n"
      end
    end
    editor = piece_tree_editor("piece-tree-large", original)
    editor.set_cursor(0, 0)

    100.times { editor.insert_text("x") }
    changed = "x" * 100 + original
    editor.text.should eq changed

    100.times { editor.undo.should be_true }
    editor.text.should eq original
    editor.cursor.should eq Tui::TextEditor::Cursor.new(0, 0)

    100.times { editor.redo.should be_true }
    editor.text.should eq changed
    editor.cursor.should eq Tui::TextEditor::Cursor.new(0, 100)
  end

  it "renders a viewport from a multi-megabyte single line" do
    editor = piece_tree_editor("piece-tree-wide-line", "prefix-" + "x" * 8_000_000 + "-suffix")
    editor.set_cursor(0, 8_000_007)
    buffer = Tui::Buffer.new(80, 12)

    editor.render(buffer, editor.rect)

    buffer.get(7, 0).glyph.should eq "x"
    buffer.get(77, 0).glyph.should eq "x"
  end
end
