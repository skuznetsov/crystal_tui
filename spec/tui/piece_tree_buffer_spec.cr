require "../spec_helper"

private def utf8_boundaries(text : String) : Array(Int32)
  offsets = [0] of Int32
  offset = 0
  text.each_char do |char|
    offset += char.bytesize
    offsets << offset
  end
  offsets
end

private def editable_utf8_boundaries(text : String) : Array(Int32)
  bytes = text.to_slice
  utf8_boundaries(text).reject do |offset|
    offset > 0 && offset < bytes.size && bytes[offset - 1] == '\r'.ord && bytes[offset] == '\n'.ord
  end
end

private def reference_lines(text : String) : Array(String)
  text.split(/\r\n|\r|\n/, remove_empty: false)
end

private def reference_line_starts(text : String) : Array(Int32)
  starts = [0] of Int32
  bytes = text.to_slice
  offset = 0
  while offset < bytes.size
    if bytes[offset] == '\r'.ord && offset + 1 < bytes.size && bytes[offset + 1] == '\n'.ord
      offset += 2
      starts << offset
    elsif bytes[offset] == '\r'.ord || bytes[offset] == '\n'.ord
      offset += 1
      starts << offset
    else
      offset += 1
    end
  end
  starts
end

private def splice_reference(text : String, offset : Int32, length : Int32, replacement : String) : String
  prefix = text.byte_slice(0, offset) || ""
  suffix_offset = offset + length
  suffix = text.byte_slice(suffix_offset, text.bytesize - suffix_offset) || ""
  prefix + replacement + suffix
end

private def assert_piece_tree_matches(buffer : Tui::PieceTreeBuffer, reference : String) : Nil
  lines = reference_lines(reference)
  buffer.text.should eq reference
  buffer.byte_length.should eq reference.bytesize
  buffer.line_count.should eq lines.size
  lines.each_with_index do |expected, index|
    buffer.line(index).should eq expected
  end

  utf8_boundaries(reference).each do |offset|
    next if offset > 0 && offset < reference.bytesize && reference.to_slice[offset - 1] == '\r'.ord && reference.to_slice[offset] == '\n'.ord
    expected_line = reference_line_starts(reference).count { |start| start <= offset } - 1
    buffer.line_index_at_offset(offset).should eq expected_line
  end

  reference_line_starts(reference).each_with_index do |expected_offset, index|
    buffer.line_start_offset(index).should eq expected_offset
  end

  buffer.validate!
end

describe Tui::PieceTreeBuffer do
  it "initializes from UTF-8 text and exposes logical lines" do
    buffer = Tui::PieceTreeBuffer.new("alpha\nβeta\n")

    buffer.byte_length.should eq "alpha\nβeta\n".bytesize
    buffer.line_count.should eq 3
    buffer.line(0).should eq "alpha"
    buffer.line(1).should eq "βeta"
    buffer.line(2).should eq ""
    buffer.storage_bytesize.should eq buffer.byte_length
  end

  it "keeps insert and delete byte-oriented" do
    buffer = Tui::PieceTreeBuffer.new("hello\nworld")
    buffer.insert("hello".bytesize, ", 世界\n")

    buffer.text.should eq "hello, 世界\n\nworld"
    buffer.line_count.should eq 3
    buffer.line(0).should eq "hello, 世界"
    buffer.line(1).should eq ""
    buffer.line(2).should eq "world"

    deleted_offset = "hello, ".bytesize
    buffer.delete(deleted_offset, "世界".bytesize).should eq "世界"
    buffer.text.should eq "hello, \n\nworld"
    buffer.validate!
  end

  it "converts between line indexes and UTF-8 byte offsets" do
    text = "a\nβb\nlast"
    buffer = Tui::PieceTreeBuffer.new(text)

    buffer.line_start_offset(0).should eq 0
    buffer.line_start_offset(1).should eq "a\n".bytesize
    buffer.line_start_offset(2).should eq "a\nβb\n".bytesize

    buffer.line_index_at_offset(0).should eq 0
    buffer.line_index_at_offset(1).should eq 0
    buffer.line_index_at_offset("a\n".bytesize).should eq 1
    buffer.line_index_at_offset("a\nβ".bytesize).should eq 1
    buffer.line_index_at_offset(text.bytesize).should eq 2

    trailing_newline = Tui::PieceTreeBuffer.new("#{text}\n")
    trailing_newline.line_count.should eq 4
    trailing_newline.line(3).should eq ""
    trailing_newline.line_index_at_offset(trailing_newline.byte_length).should eq 3
  end

  it "converts codepoint coordinates without materializing a line" do
    text = "Aé🙂\n界é"
    buffer = Tui::PieceTreeBuffer.new(text)
    boundaries = utf8_boundaries(text)

    boundaries.each_with_index do |offset, codepoint|
      buffer.codepoint_index_at_offset(offset).should eq codepoint
      buffer.byte_offset_at_codepoint(codepoint).should eq offset
    end
    buffer.line_character_length(0).should eq 3
    buffer.line_character_length(1).should eq 3 # combining mark is a codepoint
    buffer.line_slice(0, 1, 2).should eq "é🙂"
    buffer.character_at(1, 0).should eq '界'
    buffer.character_at(1, 3).should be_nil
    expect_raises(ArgumentError) { buffer.byte_offset_at_codepoint(-1) }
    expect_raises(ArgumentError) { buffer.byte_offset_at_codepoint(boundaries.size) }

    crlf = Tui::PieceTreeBuffer.new("Aé🙂\r\n界é")
    crlf.line_character_length(0).should eq 3
    crlf.line_character_length(1).should eq 3
  end

  it "rejects invalid ranges without changing the buffer" do
    buffer = Tui::PieceTreeBuffer.new("Aé🙂B")
    before = buffer.text

    expect_raises(ArgumentError) { buffer.insert(2, "x") }
    expect_raises(ArgumentError) { buffer.delete(2, 1) }
    expect_raises(ArgumentError) { buffer.delete(1, 1) }
    expect_raises(ArgumentError) { buffer.insert(-1, "x") }
    expect_raises(ArgumentError) { buffer.insert(buffer.byte_length + 1, "x") }
    expect_raises(ArgumentError) { buffer.delete(0, -1) }
    expect_raises(ArgumentError) { buffer.delete(buffer.byte_length, 1) }
    expect_raises(ArgumentError) { buffer.delete(0, buffer.byte_length + 1) }
    expect_raises(ArgumentError) { buffer.line_index_at_offset(2) }
    expect_raises(IndexError) { buffer.line_start_offset(-1) }
    expect_raises(IndexError) { buffer.line_start_offset(buffer.line_count) }

    buffer.text.should eq before
  end

  it "restores persistent snapshots without copying document storage" do
    original = "line\n" * 10_000
    buffer = Tui::PieceTreeBuffer.new(original)
    snapshot = buffer.snapshot
    stored_before = buffer.storage_bytesize

    buffer.insert(original.bytesize // 2, "世界")
    changed = buffer.snapshot
    buffer.storage_bytesize.should eq stored_before + "世界".bytesize

    buffer.restore(snapshot)
    buffer.text.should eq original
    buffer.restore(changed)
    buffer.text.should eq splice_reference(original, original.bytesize // 2, 0, "世界")
  end

  it "chunks large sources, streams exact bytes, and stays balanced" do
    original = String.build do |io|
      8_000.times { |index| io << index << ": αβγ🙂\r\n" }
    end
    buffer = Tui::PieceTreeBuffer.new(original)

    buffer.piece_count.should be > 10
    buffer.tree_height.should be < 64
    output = IO::Memory.new
    buffer.write_to(output).should eq original.bytesize
    output.to_s.should eq original
    buffer.line(4_000).ends_with?('\r').should be_false

    crlf = original.index("\r\n").not_nil!
    expect_raises(ArgumentError) { buffer.insert(crlf + 1, "x") }
    buffer.validate!
  end

  it "preserves mixed line endings while indexing them as logical lines" do
    text = "a\rb\r\nc\nd\r\n"
    buffer = Tui::PieceTreeBuffer.new(text)

    buffer.text.should eq text
    buffer.line_count.should eq 5
    buffer.line(0).should eq "a"
    buffer.line(1).should eq "b"
    buffer.line(2).should eq "c"
    buffer.line(3).should eq "d"
    buffer.line(4).should eq ""
    buffer.line_start_offset(1).should eq 2
    buffer.line_start_offset(2).should eq 5
    buffer.line_start_offset(3).should eq 7
    buffer.line_start_offset(4).should eq 10
    buffer.validate!
  end

  it "normalizes LF and CRLF exactly once for CR-only streaming" do
    buffer = Tui::PieceTreeBuffer.new("a\r\nb\nc\r")
    output = IO::Memory.new

    buffer.write_to(output, lf_as_cr: true).should eq 6

    output.to_s.should eq "a\rb\rc\r"
  end

  it "finds word boundaries across many pieces without materializing the line" do
    prefix = "word " * 50_000
    buffer = Tui::PieceTreeBuffer.new(prefix + "tail")
    finish = buffer.line_character_length(0)

    buffer.previous_word_column(0, finish).should eq finish - 4
    buffer.next_word_column(0, 0).should eq 5
    buffer.next_word_column(0, finish - 4).should eq finish
    buffer.previous_word_column(0, 0).should eq 0
  end

  it "keeps multi-megabyte edit history structurally shared" do
    original = "source line 0123456789\n" * 350_000
    buffer = Tui::PieceTreeBuffer.new(original)
    initial = buffer.snapshot
    snapshots = [] of Tui::PieceTreeBuffer::Snapshot
    inserted_bytes = 0

    100.times do |index|
      offset = buffer.byte_length // 2
      inserted = "<#{index}>"
      inserted_bytes += inserted.bytesize
      buffer.insert(offset, inserted)
      snapshots << buffer.snapshot
    end

    buffer.storage_bytesize.should eq original.bytesize.to_i64 + inserted_bytes
    buffer.tree_height.should be < 128
    buffer.validate!

    buffer.restore(initial)
    buffer.byte_length.should eq original.bytesize
    buffer.slice(0, 11).should eq "source line"
    buffer.restore(snapshots.last)
    buffer.byte_length.should eq original.bytesize + inserted_bytes
  end

  it "coalesces consecutive typing in the append-only add store" do
    buffer = Tui::PieceTreeBuffer.new

    20_000.times { buffer.insert(buffer.byte_length, "x") }

    buffer.byte_length.should eq 20_000
    buffer.storage_bytesize.should eq 20_000
    buffer.piece_count.should be <= 3
    buffer.tree_height.should be <= 3
    buffer.validate!
  end

  it "matches a String model through deterministic randomized edits" do
    seed = 0x50494543
    random = Random.new(seed)
    chunks = ["", "a", "é", "🙂", "\n", "x\nβ", "世界", "\n\n"]
    reference = "α\nseed🙂\n"
    buffer = Tui::PieceTreeBuffer.new(reference)

    500.times do |step|
      boundaries = utf8_boundaries(reference)
      start_index = random.rand(boundaries.size)
      offset = boundaries[start_index]

      if random.rand(100) < 60
        inserted = chunks[random.rand(chunks.size)]
        buffer.insert(offset, inserted)
        reference = splice_reference(reference, offset, 0, inserted)
      else
        end_index = start_index + random.rand(boundaries.size - start_index)
        end_offset = boundaries[end_index]
        length = end_offset - offset
        expected_deleted = reference.byte_slice(offset, length) || ""
        buffer.delete(offset, length).should eq expected_deleted
        reference = splice_reference(reference, offset, length, "")
      end

      begin
        assert_piece_tree_matches(buffer, reference)
      rescue ex
        raise "seed #{seed}, edit #{step}, reference #{reference.inspect}: #{ex.message}"
      end
    end
  end

  it "matches a String model across randomized CRLF boundary edits" do
    chunks = ["a", "é", "🙂", "\r\n", "x\r\nβ", "世界", "\n", "\r"]

    [0x43524c46, 0x50494543, 0x54524545, 0x554e4943].each do |seed|
      random = Random.new(seed)
      reference = "α\r\nseed🙂\r\n"
      buffer = Tui::PieceTreeBuffer.new(reference)

      300.times do |step|
        boundaries = editable_utf8_boundaries(reference)
        start_index = random.rand(boundaries.size)
        offset = boundaries[start_index]

        if random.rand(100) < 60
          inserted = chunks[random.rand(chunks.size)]
          buffer.insert(offset, inserted)
          reference = splice_reference(reference, offset, 0, inserted)
        else
          end_index = start_index + random.rand(boundaries.size - start_index)
          end_offset = boundaries[end_index]
          length = end_offset - offset
          buffer.delete(offset, length).should eq(reference.byte_slice(offset, length) || "")
          reference = splice_reference(reference, offset, length, "")
        end

        begin
          assert_piece_tree_matches(buffer, reference)
        rescue ex
          raise "seed #{seed}, edit #{step}, reference #{reference.inspect}: #{ex.message}"
        end
      end
    end
  end
end
