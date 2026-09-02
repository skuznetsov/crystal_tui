require "../../spec_helper"
require "file_utils"

private def with_editor_file(content : String, &)
  root = Path.new(Dir.tempdir, "text-editor-file-#{Random::Secure.hex(8)}")
  Dir.mkdir_p(root)
  path = root / "sample.txt"
  File.write(path, content)
  begin
    yield Tui::TextEditor.new("file-round-trip"), path
  ensure
    FileUtils.rm_rf(root)
  end
end

describe Tui::TextEditor do
  it "round-trips final newlines and line-ending style" do
    ["alpha", "alpha\n", "alpha\n\n", "alpha\r\nbeta\r\n"].each do |content|
      with_editor_file(content) do |editor, path|
        editor.load_file(path).should be_true
        editor.text.should eq content
        editor.save.should be_true
        File.read(path).should eq content
      end
    end
  end

  it "replaces the complete document as one undoable edit" do
    editor = Tui::TextEditor.new("replace-all")
    editor.text = "old old\n"
    editor.set_cursor(0, 3)

    editor.replace_text("new new\n").should be_true
    editor.text.should eq "new new\n"
    editor.cursor.should eq Tui::TextEditor::Cursor.new(0, 3)

    editor.undo.should be_true
    editor.text.should eq "old old\n"
    editor.redo.should be_true
    editor.text.should eq "new new\n"
  end
end
