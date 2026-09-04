require "../../spec_helper"

private def piece_tree_editor(id : String, content : String = "") : Tui::TextEditor
  editor = Tui::TextEditor.new(id)
  editor.rect = Tui::Rect.new(0, 0, 80, 12)
  editor.text = content unless content.empty?
  editor.focus
  editor
end

describe Tui::TextEditor do
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
