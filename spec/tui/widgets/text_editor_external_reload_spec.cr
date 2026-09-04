require "../../spec_helper"
require "file_utils"

private def external_reload_editor(id : String, content : String = "") : Tui::TextEditor
  editor = Tui::TextEditor.new(id)
  editor.rect = Tui::Rect.new(0, 0, 40, 10)
  editor.text = content unless content.empty?
  editor.focus
  editor
end

private def with_external_reload_file(content : String, &)
  root = Path.new(Dir.tempdir, "text-editor-external-reload-#{Random::Secure.hex(8)}")
  Dir.mkdir_p(root)
  path = root / "sample.txt"
  File.write(path.to_s, content)
  begin
    yield root, path
  ensure
    FileUtils.rm_rf(root.to_s)
  end
end

describe Tui::TextEditor do
  it "reloads external content as clean while retaining OURS as one undo entry" do
    with_external_reload_file("base\nline\n") do |_root, path|
      editor = external_reload_editor("external-reload-history")
      editor.load_file(path).should be_true
      editor.set_cursor(1, 2)
      editor.insert_char('!')
      editor.insert_text("?")
      editor.undo.should be_true
      editor.text.should eq "base\nli!ne\n"
      editor.set_fold_ranges([Tui::TextEditor::FoldRange.new(0, 1)])
      editor.toggle_fold_at(0).should be_true
      editor.can_redo?.should be_true

      changes = [] of Tui::TextEditor::TextChange
      editor.on_text_change { |change| changes << change }

      editor.reload_as_saved("external\nchanged").should be_true

      editor.text.should eq "external\nchanged"
      editor.modified?.should be_false
      editor.path.should eq path
      editor.title.should eq path.basename
      editor.cursor.should eq Tui::TextEditor::Cursor.new(1, 3)
      editor.fold_ranges.should be_empty
      editor.can_undo?.should be_true
      editor.can_redo?.should be_false
      changes.size.should eq 1
      changes.first.full?.should be_true

      editor.undo.should be_true
      editor.text.should eq "base\nli!ne\n"
      editor.modified?.should be_true
      changes.size.should eq 2
      changes.last.full?.should be_true

      editor.redo.should be_true
      editor.text.should eq "external\nchanged"
      editor.modified?.should be_false
      changes.size.should eq 3
      changes.last.full?.should be_true
    end
  end

  it "loads exact content as a clean baseline and reuses the optional path" do
    path = Path.new(Dir.tempdir, "text-editor-content-as-saved-#{Random::Secure.hex(8)}.txt")
    editor = external_reload_editor("content-as-saved")

    editor.load_content_as_saved("first\r\nsecond", path).should be_true
    editor.text.should eq "first\r\nsecond"
    editor.modified?.should be_false
    editor.path.should eq path
    editor.title.should eq path.basename
    editor.cursor.should eq Tui::TextEditor::Cursor.new(0, 0)
    editor.can_undo?.should be_false

    editor.set_cursor(1, 4)
    editor.reload_as_saved("new\ncontent").should be_true
    editor.path.should eq path
    editor.title.should eq path.basename
    editor.cursor.should eq Tui::TextEditor::Cursor.new(1, 4)
    editor.modified?.should be_false
  end

  it "accepts identical current bytes without creating a duplicate undo state" do
    editor = external_reload_editor("accept-current")
    editor.load_content_as_saved("same\n", Path.new("same.txt")).should be_true

    editor.accept_current_as_saved.should be_true

    editor.text.should eq "same\n"
    editor.modified?.should be_false
    editor.can_undo?.should be_false
  end

  it "streams exact piece-tree bytes with the detected line ending" do
    editor = external_reload_editor("streaming")
    editor.load_content_as_saved("first\r\nsecond", Path.new("streaming.txt")).should be_true
    editor.set_cursor(0, 5)
    editor.insert_newline

    output = IO::Memory.new
    editor.write_to(output).should eq output.to_s.bytesize
    output.to_s.should eq "first\r\n\r\nsecond"
  end

  it "retains only the immediately previous root across repeated external reloads" do
    editor = external_reload_editor("reload-ours")

    101.times do |index|
      editor.reload_as_saved("reload-#{index}").should be_true
    end

    editor.undo.should be_true
    editor.text.should eq "reload-99"
    editor.undo.should be_false
  end

  it "rejects a checked save before rename and reports the resolved target" do
    with_external_reload_file("disk") do |root, path|
      target = root / "target.txt"
      link = root / "link.txt"
      File.rename(path, target)
      File.symlink(target.basename.to_s, link)

      editor = external_reload_editor("checked-save-reject")
      editor.load_file(link).should be_true
      editor.insert_text("ours")
      before_path = editor.path
      before_text = editor.text
      before_title = editor.title
      save_callbacks = [] of Path
      editor.on_save { |saved_path| save_callbacks << saved_path }
      guard_paths = [] of Path
      observed_disk = ""

      editor.save_as_checked(link) do |resolved_path|
        guard_paths << resolved_path
        observed_disk = File.read(resolved_path.to_s)
        false
      end.should be_false

      guard_paths.should eq [Path.new(File.realpath(link))]
      observed_disk.should eq "disk"
      File.read(target.to_s).should eq "disk"
      editor.text.should eq before_text
      editor.path.should eq before_path
      editor.title.should eq before_title
      editor.modified?.should be_true
      save_callbacks.should be_empty
    end
  end

  it "preserves the logical path in on_save after a checked save" do
    with_external_reload_file("disk") do |root, path|
      target = root / "target.txt"
      link = root / "link.txt"
      File.rename(path, target)
      File.symlink(target.basename.to_s, link)

      editor = external_reload_editor("checked-save-success")
      editor.load_file(link).should be_true
      editor.insert_text("ours")
      saved_paths = [] of Path
      editor.on_save { |saved_path| saved_paths << saved_path }

      editor.save_checked { |resolved_path| resolved_path == Path.new(File.realpath(link)) }.should be_true

      File.read(target.to_s).should eq editor.text
      editor.path.should eq link
      saved_paths.should eq [link]
      editor.modified?.should be_false
    end
  end

  it "stays dirty and suppresses callbacks when post-rename validation fails" do
    with_external_reload_file("disk") do |_root, path|
      editor = external_reload_editor("checked-save-post-reject")
      editor.load_file(path).should be_true
      editor.insert_text("ours")
      saved_paths = [] of Path
      editor.on_save { |saved_path| saved_paths << saved_path }
      before_paths = [] of Path
      after_paths = [] of Path

      before_rename = ->(resolved_path : Path) do
        before_paths << resolved_path
        true
      end
      after_rename = ->(resolved_path : Path) do
        after_paths << resolved_path
        File.write(resolved_path.to_s, "external-after-rename")
        false
      end

      editor.save_checked(before_rename, after_rename).should be_false

      resolved = path.expand
      before_paths.should eq [resolved]
      after_paths.should eq [resolved]
      File.read(path.to_s).should eq "external-after-rename"
      editor.modified?.should be_true
      saved_paths.should be_empty
    end
  end
end
