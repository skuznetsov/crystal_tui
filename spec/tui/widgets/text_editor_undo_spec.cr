require "../../spec_helper"
require "file_utils"

def focused_editor(id : String, content : String = "") : Tui::TextEditor
  editor = Tui::TextEditor.new(id)
  editor.rect = Tui::Rect.new(0, 0, 40, 10)
  editor.text = content unless content.empty?
  editor.focus
  editor
end

describe Tui::TextEditor do
  it "undoes and redoes typed text and cursor" do
    editor = focused_editor("undo-type", "ab")
    editor.set_cursor(0, 2)
    editor.insert_char('x')
    editor.insert_char('y')
    editor.text.should eq "abxy"
    editor.cursor_col.should eq 4
    editor.can_undo?.should be_true
    editor.can_redo?.should be_false

    editor.undo.should be_true
    editor.text.should eq "ab"
    editor.cursor_line.should eq 0
    editor.cursor_col.should eq 2
    editor.can_redo?.should be_true

    editor.redo.should be_true
    editor.text.should eq "abxy"
    editor.cursor_col.should eq 4
  end

  it "coalesces consecutive inserts into one undo group" do
    editor = focused_editor("undo-coalesce")
    "hello".each_char { |ch| editor.insert_char(ch) }
    editor.text.should eq "hello"
    editor.undo.should be_true
    editor.text.should eq ""
    editor.can_undo?.should be_false
  end

  it "keeps backspace groups separate from insert groups" do
    editor = focused_editor("undo-backspace")
    "ab".each_char { |ch| editor.insert_char(ch) }
    editor.backspace
    editor.backspace
    editor.text.should eq ""

    editor.undo.should be_true
    editor.text.should eq "ab"
    editor.undo.should be_true
    editor.text.should eq ""
  end

  it "is a no-op when undo and redo stacks are empty" do
    editor = focused_editor("undo-empty", "keep")
    editor.undo.should be_false
    editor.redo.should be_false
    editor.text.should eq "keep"
    editor.cursor_line.should eq 0
    editor.cursor_col.should eq 0
  end

  it "clears history on text= and load_file" do
    editor = focused_editor("undo-clear")
    editor.insert_char('x')
    editor.can_undo?.should be_true

    editor.text = "replaced"
    editor.can_undo?.should be_false
    editor.can_redo?.should be_false
    editor.undo.should be_false
    editor.text.should eq "replaced"

    tmp = Path.new(Dir.tempdir, "text-editor-undo-#{Random::Secure.hex(8)}.txt")
    File.write(tmp.to_s, "from-disk")
    begin
      editor.insert_char('z')
      editor.load_file(tmp).should be_true
      editor.text.should eq "from-disk"
      editor.can_undo?.should be_false
      editor.modified?.should be_false
    ensure
      FileUtils.rm_rf(tmp.to_s)
    end
  end

  it "clears modified when undo returns to the saved file contents" do
    tmp = Path.new(Dir.tempdir, "text-editor-undo-saved-#{Random::Secure.hex(8)}.txt")
    File.write(tmp.to_s, "saved")
    editor = focused_editor("undo-modified")
    begin
      editor.load_file(tmp).should be_true
      editor.insert_char('!')
      editor.modified?.should be_true
      editor.undo.should be_true
      editor.text.should eq "saved"
      editor.modified?.should be_false
    ensure
      FileUtils.rm_rf(tmp.to_s)
    end
  end

  it "handles Ctrl+Z as C0 and as ctrl+z without inserting z" do
    editor = focused_editor("undo-ctrl-z")
    editor.insert_char('q')
    editor.handle_event(Tui::KeyEvent.new('\u001A')).should be_true
    editor.text.should eq ""

    editor.insert_char('q')
    editor.handle_event(Tui::KeyEvent.new('z', Tui::Modifiers::Ctrl)).should be_true
    editor.text.should eq ""
    editor.text.should_not eq "z"
    editor.text.should_not eq "qz"
  end

  it "redoes with Ctrl+Y and Ctrl+Shift+Z" do
    editor = focused_editor("undo-redo-keys")
    editor.insert_char('q')
    editor.undo.should be_true

    editor.handle_event(Tui::KeyEvent.new('y', Tui::Modifiers::Ctrl)).should be_true
    editor.text.should eq "q"

    editor.undo.should be_true
    editor.handle_event(Tui::KeyEvent.new('z', Tui::Modifiers::Ctrl | Tui::Modifiers::Shift)).should be_true
    editor.text.should eq "q"
  end

  it "undoes a selection replace as one group with later typing" do
    editor = focused_editor("undo-selection", "old")
    editor.select_all
    editor.insert_char('n')
    editor.insert_char('e')
    editor.insert_char('w')
    editor.text.should eq "new"
    editor.undo.should be_true
    editor.text.should eq "old"
    editor.can_undo?.should be_false
  end

  it "undoes paste as one snapshot" do
    editor = focused_editor("undo-paste", "pre")
    editor.set_cursor(0, 3)
    editor.paste("X\nY")
    editor.text.should eq "preX\nY"
    editor.undo.should be_true
    editor.text.should eq "pre"
  end

  it "does not change the buffer when undoing at the start" do
    editor = focused_editor("undo-negative", "same")
    before = editor.text
    editor.undo.should be_false
    editor.text.should eq before
  end
end
