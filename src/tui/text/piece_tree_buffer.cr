require "set"

module Tui
  # UTF-8 text storage for editors. The document is represented as a persistent
  # implicit treap of pieces into immutable source strings. Edits path-copy only
  # the affected tree nodes, so snapshots used by undo share document storage.
  class PieceTreeBuffer
    TARGET_PIECE_BYTES = 4 * 1024
    MIN_PIECE_BYTES    = 2 * 1024
    MAX_PIECE_BYTES    = 8 * 1024
    MAX_TREE_HEIGHT    = 64

    private alias Source = String | IO::Memory

    private struct Piece
      getter source : Source
      getter start : Int32
      getter length : Int32
      getter newlines : Int32
      getter codepoints : Int32
      getter utf16_units : Int32
      getter starts_with_lf : Bool
      getter ends_with_cr : Bool

      def initialize(
        @source : Source,
        @start : Int32,
        @length : Int32,
        @newlines : Int32,
        @codepoints : Int32,
        @utf16_units : Int32,
        @starts_with_lf : Bool,
        @ends_with_cr : Bool,
      )
      end
    end

    private struct SourceRange
      getter source : Source
      getter start : Int32
      getter length : Int32

      def initialize(@source : Source, @start : Int32, @length : Int32)
      end
    end

    private class Node
      getter piece : Piece
      getter left : Node?
      getter right : Node?
      getter priority : UInt64
      getter byte_length : Int32
      getter newline_count : Int32
      getter codepoint_count : Int32
      getter utf16_unit_count : Int32
      getter piece_count : Int32
      getter height : Int32
      getter starts_with_lf : Bool
      getter ends_with_cr : Bool

      def initialize(@piece : Piece, @priority : UInt64, @left : Node? = nil, @right : Node? = nil)
        @byte_length = PieceTreeBuffer.node_bytes(@left) + @piece.length + PieceTreeBuffer.node_bytes(@right)
        @newline_count = PieceTreeBuffer.node_newlines(@left) + @piece.newlines + PieceTreeBuffer.node_newlines(@right)
        @newline_count -= 1 if @left.try(&.ends_with_cr) && @piece.starts_with_lf
        @newline_count -= 1 if @piece.ends_with_cr && @right.try(&.starts_with_lf)
        @codepoint_count = PieceTreeBuffer.node_codepoints(@left) + @piece.codepoints + PieceTreeBuffer.node_codepoints(@right)
        @utf16_unit_count = PieceTreeBuffer.node_utf16_units(@left) + @piece.utf16_units + PieceTreeBuffer.node_utf16_units(@right)
        @piece_count = PieceTreeBuffer.node_count(@left) + 1 + PieceTreeBuffer.node_count(@right)
        @height = 1 + Math.max(PieceTreeBuffer.node_height(@left), PieceTreeBuffer.node_height(@right))
        @starts_with_lf = @left ? @left.not_nil!.starts_with_lf : @piece.starts_with_lf
        @ends_with_cr = @right ? @right.not_nil!.ends_with_cr : @piece.ends_with_cr
      end
    end

    private class SnapshotToken
    end

    # An immutable, O(1) handle to a structurally shared document root.
    class Snapshot
      protected getter token : SnapshotToken
      protected getter root : Node?

      protected def initialize(@token : SnapshotToken, @root : Node?)
      end

      def byte_length : Int32
        PieceTreeBuffer.node_bytes(@root)
      end

      def text : String
        String.build(byte_length) { |io| write_node(io, @root) }
      end

      def write_to(io : IO) : Int32
        write_node(io, @root)
        byte_length
      end

      private def write_node(io : IO, node : Node?) : Nil
        return unless node
        write_node(io, node.left)
        source = node.piece.source
        io.write(source.to_slice[node.piece.start, node.piece.length])
        write_node(io, node.right)
      end
    end

    @root : Node?
    @add_page = IO::Memory.new
    @priority_state : UInt64 = 0x9e3779b97f4a7c15_u64
    @snapshot_token = SnapshotToken.new

    def initialize(text : String = "")
      @root = nil
      reset(text)
    end

    def byte_length : Int32
      self.class.node_bytes(@root)
    end

    def byte_at_offset(offset : Int32) : UInt8?
      raise ArgumentError.new("offset outside buffer") unless offset >= 0 && offset <= byte_length
      return nil if offset == byte_length
      byte_at(@root, offset)
    end

    def line_count : Int32
      self.class.node_newlines(@root) + 1
    end

    # Source bytes reachable from the active root plus the current append page.
    # Sources reachable only from older snapshots are intentionally not
    # discoverable from the active buffer.
    def storage_bytesize : Int64
      seen = Set(UInt64).new
      total = source_bytes(@root, seen)
      unless seen.includes?(@add_page.object_id)
        total += @add_page.to_slice.size
      end
      total
    end

    def text : String
      slice(0, byte_length)
    end

    def line(index : Int32) : String
      start, finish = line_content_range(index)
      slice(start, finish - start)
    end

    def each_line(& : String ->) : Nil
      line_count.times { |index| yield line(index) }
    end

    def line_start_offset(index : Int32) : Int32
      raise IndexError.new("line index #{index} outside 0...#{line_count}") unless index >= 0 && index < line_count
      return 0 if index == 0
      newline_offset(@root, index, 0, false) + 1
    end

    def line_character_length(index : Int32) : Int32
      start, finish = line_content_range(index)
      codepoint_index_at_offset(finish) - codepoint_index_at_offset(start)
    end

    # Converts a character-indexed editor column to the UTF-16 code-unit
    # coordinate used by LSP without materializing or scanning the line.
    def line_utf16_column(index : Int32, column : Int32) : Int32
      start, finish = line_content_range(index)
      first_codepoint = codepoint_index_at_offset(start)
      available = codepoint_index_at_offset(finish) - first_codepoint
      raise ArgumentError.new("column outside line") unless column >= 0 && column <= available

      target = byte_offset_at_codepoint(first_codepoint + column)
      utf16_units_before_offset(target) - utf16_units_before_offset(start)
    end

    def line_slice(index : Int32, start_column : Int32, count : Int32) : String
      raise ArgumentError.new("column and count must not be negative") if start_column < 0 || count < 0
      start, finish = line_content_range(index)
      first_codepoint = codepoint_index_at_offset(start)
      available = codepoint_index_at_offset(finish) - first_codepoint
      raise ArgumentError.new("column outside line") if start_column > available
      take = Math.min(count, available - start_column)
      from = byte_offset_at_codepoint(first_codepoint + start_column)
      to = byte_offset_at_codepoint(first_codepoint + start_column + take)
      slice(from, to - from)
    end

    def character_at(line : Int32, column : Int32) : Char?
      return nil if column < 0 || column >= line_character_length(line)
      start, _finish = line_content_range(line)
      first_codepoint = codepoint_index_at_offset(start)
      offset = byte_offset_at_codepoint(first_codepoint + column)
      character_at_offset(offset)
    end

    # Returns the word-motion destination without materializing the line and
    # without doing a tree lookup for every character crossed.
    def previous_word_column(line : Int32, column : Int32) : Int32
      start, finish = line_content_range(line)
      length = codepoint_index_at_offset(finish) - codepoint_index_at_offset(start)
      raise ArgumentError.new("column outside line") unless column >= 0 && column <= length
      return 0 if column == 0

      first_codepoint = codepoint_index_at_offset(start)
      offset = byte_offset_at_codepoint(first_codepoint + column)
      result = column
      skipping_whitespace = true
      each_character_reverse(start, offset) do |char|
        if skipping_whitespace
          if char.whitespace?
            result -= 1
            true
          else
            skipping_whitespace = false
            result -= 1
            true
          end
        elsif char.whitespace?
          false
        else
          result -= 1
          true
        end
      end
      result
    end

    # Returns the word-motion destination without materializing the line and
    # without doing a tree lookup for every character crossed.
    def next_word_column(line : Int32, column : Int32) : Int32
      start, finish = line_content_range(line)
      first_codepoint = codepoint_index_at_offset(start)
      length = codepoint_index_at_offset(finish) - first_codepoint
      raise ArgumentError.new("column outside line") unless column >= 0 && column <= length
      return length if column == length

      offset = byte_offset_at_codepoint(first_codepoint + column)
      result = column
      skipping_word = true
      each_character_forward(offset, finish) do |char|
        if skipping_word
          if char.whitespace?
            skipping_word = false
            result += 1
            true
          else
            result += 1
            true
          end
        elsif char.whitespace?
          result += 1
          true
        else
          false
        end
      end
      result
    end

    def codepoint_index_at_offset(offset : Int32) : Int32
      validate_boundary(offset)
      count_codepoints_before(@root, offset)
    end

    def byte_offset_at_codepoint(index : Int32) : Int32
      total = self.class.node_codepoints(@root)
      raise ArgumentError.new("codepoint index outside buffer") unless index >= 0 && index <= total
      codepoint_offset(@root, index, 0)
    end

    # Returns the zero-based logical line containing +offset+. A newline byte
    # belongs to the line before it; EOF after a final newline is the empty
    # trailing line.
    def line_index_at_offset(offset : Int32) : Int32
      validate_boundary(offset)
      low = 1
      high = self.class.node_newlines(@root)
      found = 0
      while low <= high
        middle = low + (high - low) // 2
        if newline_offset(@root, middle, 0, false) < offset
          found = middle
          low = middle + 1
        else
          high = middle - 1
        end
      end
      found
    end

    def insert(offset : Int32, value : String) : Nil
      validate_boundary(offset)
      raise ArgumentError.new("inserted text must be valid UTF-8") unless value.valid_encoding?
      return if value.empty?

      inserted = tree_for_insert(value)
      left, right = split(@root, offset)
      @root = concatenate(concatenate(left, inserted), right)
      ensure_height_bound!
    end

    def delete(offset : Int32, length : Int32) : String
      validate_range(offset, length)
      return "" if length == 0

      deleted = slice(offset, length)
      left, suffix = split(@root, offset)
      _removed, right = split(suffix, length)
      @root = concatenate(left, right)
      ensure_height_bound!
      deleted
    end

    # Replaces the active root while keeping previous source storage valid for
    # existing snapshots. This is used for undoable whole-document operations.
    def replace_all(value : String) : Nil
      raise ArgumentError.new("replacement text must be valid UTF-8") unless value.valid_encoding?
      @root = if value.empty?
                nil
              else
                tree_for_source(value)
              end
      ensure_height_bound!
    end

    # Resets storage and invalidates snapshots. Callers must clear history first.
    def reset(value : String = "") : Nil
      raise ArgumentError.new("buffer text must be valid UTF-8") unless value.valid_encoding?
      @add_page = IO::Memory.new
      @snapshot_token = SnapshotToken.new
      @root = if value.empty?
                nil
              else
                tree_for_source(value)
              end
      ensure_height_bound!
    end

    def snapshot : Snapshot
      Snapshot.new(@snapshot_token, @root)
    end

    def restore(snapshot : Snapshot) : Nil
      unless snapshot.token.same?(@snapshot_token)
        raise ArgumentError.new("snapshot belongs to stale or different buffer storage")
      end
      @root = snapshot.root
    end

    def same_state?(snapshot : Snapshot) : Bool
      return false unless snapshot.token.same?(@snapshot_token)
      roots_same?(@root, snapshot.root)
    end

    # Checks source ranges, UTF-8 boundaries, heap ordering, and cached metrics.
    # Intended for tests and diagnostics rather than ordinary edit paths.
    def validate! : Nil
      validate_node!(@root)
    end

    def write_to(io : IO, *, lf_as_cr : Bool = false) : Int32
      if lf_as_cr
        _previous_was_cr, written = write_node_as_cr(io, @root, false)
        written
      else
        write_node(io, @root)
        byte_length
      end
    end

    # These diagnostics make balancing and fragmentation observable in tests.
    def piece_count : Int32
      self.class.node_count(@root)
    end

    def tree_height : Int32
      self.class.node_height(@root)
    end

    protected def self.node_bytes(node : Node?) : Int32
      node.try(&.byte_length) || 0
    end

    protected def self.node_newlines(node : Node?) : Int32
      node.try(&.newline_count) || 0
    end

    protected def self.node_codepoints(node : Node?) : Int32
      node.try(&.codepoint_count) || 0
    end

    protected def self.node_utf16_units(node : Node?) : Int32
      node.try(&.utf16_unit_count) || 0
    end

    protected def self.node_count(node : Node?) : Int32
      node.try(&.piece_count) || 0
    end

    protected def self.node_height(node : Node?) : Int32
      node.try(&.height) || 0
    end

    private def tree_for_source(value : String) : Node?
      tree_for_source(value, value, 0)
    end

    private def tree_for_insert(value : String) : Node?
      root = nil.as(Node?)
      value_start = 0
      while value_start < value.bytesize
        page_start = @add_page.to_slice.size
        available = MAX_PIECE_BYTES - page_start
        if available == 0
          @add_page = IO::Memory.new
          next
        end

        length = Math.min(next_piece_length(value, value_start), available)
        while length > 0 && value_start + length < value.bytesize && value.to_unsafe[value_start + length] & 0xc0 == 0x80
          length -= 1
        end
        if length > 0 && value_start + length < value.bytesize &&
           value.to_unsafe[value_start + length - 1] == '\r'.ord && value.to_unsafe[value_start + length] == '\n'.ord
          length -= 1
        end
        if length == 0
          @add_page = IO::Memory.new
          next
        end

        @add_page.write(value.to_slice[value_start, length])
        root = concatenate(root, new_node(piece(@add_page, page_start, length)))
        value_start += length
      end
      root
    end

    private def tree_for_source(source : Source, value : String, source_start : Int32) : Node?
      root = nil.as(Node?)
      start = 0
      while start < value.bytesize
        length = next_piece_length(value, start)
        root = merge(root, new_node(piece(source, source_start + start, length)))
        start += length
      end
      root
    end

    private def next_piece_length(value : String, start : Int32) : Int32
      remaining = value.bytesize - start
      return remaining if remaining <= MAX_PIECE_BYTES

      minimum = start + MIN_PIECE_BYTES
      cut = start + TARGET_PIECE_BYTES

      # Prefer ending just after a nearby LF so line lookup scans less text.
      probe = cut
      while probe > minimum
        if value.to_unsafe[probe - 1] == '\n'.ord
          cut = probe
          break
        end
        probe -= 1
      end

      # Move off UTF-8 continuation bytes and never split a CRLF pair.
      while cut > start && value.to_unsafe[cut] & 0xc0 == 0x80
        cut -= 1
      end
      cut -= 1 if cut > start && value.to_unsafe[cut - 1] == '\r'.ord && value.to_unsafe[cut] == '\n'.ord

      # The target is far beyond the longest UTF-8 scalar, but keep a bounded
      # forward fallback for defensive completeness.
      if cut == start
        cut = start + TARGET_PIECE_BYTES
        while cut < start + MAX_PIECE_BYTES && value.to_unsafe[cut] & 0xc0 == 0x80
          cut += 1
        end
        cut += 1 if value.to_unsafe[cut - 1] == '\r'.ord && value.to_unsafe[cut] == '\n'.ord
      end

      cut - start
    end

    private def piece(source : Source, start : Int32, length : Int32) : Piece
      bytes = source.to_slice
      Piece.new(
        source,
        start,
        length,
        count_newlines(source, start, length),
        count_codepoints(source, start, length),
        count_utf16_units(source, start, length),
        bytes[start] == '\n'.ord,
        bytes[start + length - 1] == '\r'.ord
      )
    end

    private def new_node(piece : Piece, left : Node? = nil, right : Node? = nil, priority : UInt64 = next_priority) : Node
      Node.new(piece, priority, left, right)
    end

    private def rebuild(node : Node, left : Node?, right : Node?) : Node
      Node.new(node.piece, node.priority, left, right)
    end

    private def next_priority : UInt64
      state = @priority_state
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
      @priority_state = state
      state
    end

    private def split(node : Node?, offset : Int32) : Tuple(Node?, Node?)
      return {nil, nil} unless node

      left_bytes = self.class.node_bytes(node.left)
      piece_end = left_bytes + node.piece.length
      if offset < left_bytes
        before, after = split(node.left, offset)
        {before, rebuild(node, after, node.right)}
      elsif offset > piece_end
        before, after = split(node.right, offset - piece_end)
        {rebuild(node, node.left, before), after}
      elsif offset == left_bytes
        {node.left, rebuild(node, nil, node.right)}
      elsif offset == piece_end
        {rebuild(node, node.left, nil), node.right}
      else
        local = offset - left_bytes
        left_piece = piece(node.piece.source, node.piece.start, local)
        right_piece = piece(node.piece.source, node.piece.start + local, node.piece.length - local)
        # Both fragments inherit the original node's priority. This preserves
        # the heap bound promised to ancestors on both sides of the split.
        {merge(node.left, new_node(left_piece, priority: node.priority)), merge(new_node(right_piece, priority: node.priority), node.right)}
      end
    end

    private def merge(left : Node?, right : Node?) : Node?
      return right unless left
      return left unless right

      if left.priority >= right.priority
        rebuild(left, left.left, merge(left.right, right))
      else
        rebuild(right, merge(left, right.left), right.right)
      end
    end

    private def concatenate(left : Node?, right : Node?) : Node?
      return right unless left
      return left unless right

      left_rest, left_piece = pop_rightmost(left)
      right_piece, right_rest = pop_leftmost(right)
      if left_piece.source.object_id == right_piece.source.object_id &&
         left_piece.start + left_piece.length == right_piece.start &&
         left_piece.length + right_piece.length <= MAX_PIECE_BYTES
        combined = Piece.new(
          left_piece.source,
          left_piece.start,
          left_piece.length + right_piece.length,
          left_piece.newlines + right_piece.newlines - (left_piece.ends_with_cr && right_piece.starts_with_lf ? 1 : 0),
          left_piece.codepoints + right_piece.codepoints,
          left_piece.utf16_units + right_piece.utf16_units,
          left_piece.starts_with_lf,
          right_piece.ends_with_cr
        )
        merge(merge(left_rest, new_node(combined)), right_rest)
      else
        merge(left, right)
      end
    end

    private def pop_rightmost(node : Node) : Tuple(Node?, Piece)
      if right = node.right
        rest, piece = pop_rightmost(right)
        {rebuild(node, node.left, rest), piece}
      else
        {node.left, node.piece}
      end
    end

    private def pop_leftmost(node : Node) : Tuple(Piece, Node?)
      if left = node.left
        piece, rest = pop_leftmost(left)
        {piece, rebuild(node, rest, node.right)}
      else
        {node.piece, node.right}
      end
    end

    def slice(offset : Int32, length : Int32) : String
      validate_range(offset, length)
      return "" if length == 0

      String.build(length) do |io|
        append_range(io, @root, offset, length)
      end
    end

    private def write_node(io : IO, node : Node?) : Nil
      return unless node
      write_node(io, node.left)
      source = node.piece.source
      io.write(source.to_slice[node.piece.start, node.piece.length])
      write_node(io, node.right)
    end

    # Compatibility encoder for CR-only consumers. CRLF is collapsed to one
    # CR even when the pair crosses a piece boundary.
    private def write_node_as_cr(io : IO, node : Node?, previous_was_cr : Bool) : Tuple(Bool, Int32)
      return {previous_was_cr, 0} unless node

      previous_was_cr, written = write_node_as_cr(io, node.left, previous_was_cr)
      bytes = node.piece.source.to_slice[node.piece.start, node.piece.length]
      bytes.each do |byte|
        if byte == '\n'.ord
          unless previous_was_cr
            io.write_byte('\r'.ord.to_u8)
            written += 1
          end
        else
          io.write_byte(byte)
          written += 1
        end
        previous_was_cr = byte == '\r'.ord
      end
      previous_was_cr, right_written = write_node_as_cr(io, node.right, previous_was_cr)
      {previous_was_cr, written + right_written}
    end

    private def source_bytes(node : Node?, seen : Set(UInt64)) : Int64
      return 0_i64 unless node
      total = source_bytes(node.left, seen) + source_bytes(node.right, seen)
      id = node.piece.source.object_id
      unless seen.includes?(id)
        seen.add(id)
        total += node.piece.source.to_slice.size
      end
      total
    end

    private def ensure_height_bound! : Nil
      return if self.class.node_height(@root) <= MAX_TREE_HEIGHT

      pieces = [] of Piece
      collect_pieces(@root, pieces)
      @root = build_balanced(pieces, 0, pieces.size, 0)
    end

    private def collect_pieces(node : Node?, pieces : Array(Piece)) : Nil
      return unless node
      collect_pieces(node.left, pieces)
      pieces << node.piece
      collect_pieces(node.right, pieces)
    end

    private def build_balanced(pieces : Array(Piece), start : Int32, finish : Int32, depth : Int32) : Node?
      return nil if start >= finish
      middle = start + (finish - start) // 2
      left = build_balanced(pieces, start, middle, depth + 1)
      right = build_balanced(pieces, middle + 1, finish, depth + 1)
      Node.new(pieces[middle], UInt64::MAX - depth.to_u64, left, right)
    end

    private def append_range(io : IO, node : Node?, offset : Int32, length : Int32) : Nil
      return unless node
      return if length <= 0

      left_bytes = self.class.node_bytes(node.left)
      if offset < left_bytes
        take = Math.min(length, left_bytes - offset)
        append_range(io, node.left, offset, take)
        length -= take
        offset = left_bytes
      end
      return if length <= 0

      local = offset - left_bytes
      if local < node.piece.length
        take = Math.min(length, node.piece.length - local)
        source = node.piece.source
        io.write(source.to_slice[node.piece.start + local, take])
        length -= take
        local += take
      end
      return if length <= 0

      append_range(io, node.right, local - node.piece.length, length)
    end

    private def character_at_offset(offset : Int32) : Char
      first_byte = byte_at(@root, offset)
      width = if first_byte < 0x80
                1
              elsif first_byte < 0xe0
                2
              elsif first_byte < 0xf0
                3
              else
                4
              end
      Char::Reader.new(slice(offset, width)).current_char
    end

    private def each_character_forward(start : Int32, finish : Int32, &block : Char -> Bool) : Nil
      ranges = [] of SourceRange
      collect_source_ranges(@root, start, finish, 0, ranges)
      ranges.each do |range|
        chunk = String.new(range.source.to_slice[range.start, range.length])
        reader = Char::Reader.new(chunk)
        while reader.has_next?
          return unless yield reader.current_char
          reader.next_char
        end
      end
    end

    private def each_character_reverse(start : Int32, finish : Int32, &block : Char -> Bool) : Nil
      ranges = [] of SourceRange
      collect_source_ranges(@root, start, finish, 0, ranges)
      ranges.reverse_each do |range|
        chunk = String.new(range.source.to_slice[range.start, range.length])
        reader = Char::Reader.new(at_end: chunk)
        loop do
          return unless yield reader.current_char
          break unless reader.has_previous?
          reader.previous_char
        end
      end
    end

    private def collect_source_ranges(node : Node?, start : Int32, finish : Int32, base : Int32, ranges : Array(SourceRange)) : Nil
      return unless node
      return if start >= finish || finish <= base || start >= base + node.byte_length

      piece_start = base + self.class.node_bytes(node.left)
      piece_finish = piece_start + node.piece.length
      collect_source_ranges(node.left, start, finish, base, ranges)

      if start < piece_finish && finish > piece_start
        local_start = Math.max(start, piece_start) - piece_start
        local_finish = Math.min(finish, piece_finish) - piece_start
        ranges << SourceRange.new(node.piece.source, node.piece.start + local_start, local_finish - local_start)
      end

      collect_source_ranges(node.right, start, finish, piece_finish, ranges)
    end

    private def line_content_range(index : Int32) : Tuple(Int32, Int32)
      start = line_start_offset(index)
      terminated = index + 1 < line_count
      finish = terminated ? line_start_offset(index + 1) - 1 : byte_length
      finish -= 1 if terminated && finish > start && byte_at(@root, finish - 1) == '\r'.ord
      {start, finish}
    end

    private def newline_offset(node : Node?, ordinal : Int32, base : Int32, next_starts_lf : Bool) : Int32
      raise IndexError.new("newline ordinal outside buffer") unless node

      left_bytes = self.class.node_bytes(node.left)
      left_newlines = effective_newlines(node.left, node.piece.starts_with_lf)
      if ordinal <= left_newlines
        return newline_offset(node.left, ordinal, base, node.piece.starts_with_lf)
      end

      within_piece = ordinal - left_newlines
      following_starts_lf = node.right ? node.right.not_nil!.starts_with_lf : next_starts_lf
      piece_newlines = node.piece.newlines
      piece_newlines -= 1 if node.piece.ends_with_cr && following_starts_lf
      if within_piece <= piece_newlines
        source = node.piece.source
        bytes = source.to_slice
        seen = 0
        node.piece.length.times do |index|
          byte = bytes[node.piece.start + index]
          next_byte_is_lf = if index + 1 < node.piece.length
                              bytes[node.piece.start + index + 1] == '\n'.ord
                            else
                              following_starts_lf
                            end
          if byte == '\n'.ord || (byte == '\r'.ord && !next_byte_is_lf)
            seen += 1
            return base + left_bytes + index if seen == within_piece
          end
        end
      end

      newline_offset(
        node.right,
        within_piece - piece_newlines,
        base + left_bytes + node.piece.length,
        next_starts_lf
      )
    end

    private def effective_newlines(node : Node?, next_starts_lf : Bool) : Int32
      return 0 unless node
      count = node.newline_count
      count -= 1 if node.ends_with_cr && next_starts_lf
      count
    end

    private def count_codepoints_before(node : Node?, offset : Int32) : Int32
      return 0 unless node

      left_bytes = self.class.node_bytes(node.left)
      if offset <= left_bytes
        return count_codepoints_before(node.left, offset)
      end

      count = self.class.node_codepoints(node.left)
      local = offset - left_bytes
      take = Math.min(local, node.piece.length)
      count += count_codepoints(node.piece.source, node.piece.start, take)
      return count if local <= node.piece.length

      count + count_codepoints_before(node.right, local - node.piece.length)
    end

    private def utf16_units_before_offset(offset : Int32) : Int32
      validate_boundary(offset)
      count_utf16_units_before(@root, offset)
    end

    private def count_utf16_units_before(node : Node?, offset : Int32) : Int32
      return 0 unless node

      left_bytes = self.class.node_bytes(node.left)
      if offset <= left_bytes
        return count_utf16_units_before(node.left, offset)
      end

      count = self.class.node_utf16_units(node.left)
      local = offset - left_bytes
      take = Math.min(local, node.piece.length)
      count += count_utf16_units(node.piece.source, node.piece.start, take)
      return count if local <= node.piece.length

      count + count_utf16_units_before(node.right, local - node.piece.length)
    end

    private def codepoint_offset(node : Node?, ordinal : Int32, base : Int32) : Int32
      return base unless node

      left_codepoints = self.class.node_codepoints(node.left)
      left_bytes = self.class.node_bytes(node.left)
      if ordinal < left_codepoints
        return codepoint_offset(node.left, ordinal, base)
      end

      within_piece = ordinal - left_codepoints
      if within_piece < node.piece.codepoints
        bytes = node.piece.source.to_slice
        seen = 0
        node.piece.length.times do |index|
          next if bytes[node.piece.start + index] & 0xc0 == 0x80
          return base + left_bytes + index if seen == within_piece
          seen += 1
        end
      end

      codepoint_offset(
        node.right,
        within_piece - node.piece.codepoints,
        base + left_bytes + node.piece.length
      )
    end

    private def count_newlines(source : Source, start : Int32, length : Int32) : Int32
      count = 0
      bytes = source.to_slice
      length.times do |index|
        byte = bytes[start + index]
        next_byte_is_lf = index + 1 < length && bytes[start + index + 1] == '\n'.ord
        count += 1 if byte == '\n'.ord || (byte == '\r'.ord && !next_byte_is_lf)
      end
      count
    end

    private def count_codepoints(source : Source, start : Int32, length : Int32) : Int32
      count = 0
      bytes = source.to_slice
      length.times do |index|
        count += 1 unless bytes[start + index] & 0xc0 == 0x80
      end
      count
    end

    private def count_utf16_units(source : Source, start : Int32, length : Int32) : Int32
      count = 0
      bytes = source.to_slice
      length.times do |index|
        byte = bytes[start + index]
        next if byte & 0xc0 == 0x80

        count += byte & 0xf8 == 0xf0 ? 2 : 1
      end
      count
    end

    private def validate_range(offset : Int32, length : Int32) : Nil
      raise ArgumentError.new("length must not be negative") if length < 0
      validate_boundary(offset)
      finish = offset.to_i64 + length
      raise ArgumentError.new("range outside buffer") if finish > byte_length
      validate_boundary(finish.to_i32)
    end

    private def validate_boundary(offset : Int32) : Nil
      raise ArgumentError.new("offset outside buffer") unless offset >= 0 && offset <= byte_length
      return if offset == 0 || offset == byte_length

      byte = byte_at(@root, offset)
      raise ArgumentError.new("offset splits a UTF-8 codepoint") if byte & 0xc0 == 0x80
      if byte == '\n'.ord && byte_at(@root, offset - 1) == '\r'.ord
        raise ArgumentError.new("offset splits a CRLF line ending")
      end
    end

    private def byte_at(node : Node?, offset : Int32) : UInt8
      raise ArgumentError.new("offset outside buffer") unless node
      left_bytes = self.class.node_bytes(node.left)
      if offset < left_bytes
        byte_at(node.left, offset)
      elsif offset < left_bytes + node.piece.length
        node.piece.source.to_slice[node.piece.start + offset - left_bytes]
      else
        byte_at(node.right, offset - left_bytes - node.piece.length)
      end
    end

    private def validate_node!(node : Node?) : Tuple(Int32, Int32, Int32, Int32)
      return {0, 0, 0, 0} unless node
      source = node.piece.source
      raise "empty piece persisted" if node.piece.length <= 0
      finish = node.piece.start.to_i64 + node.piece.length
      raise "piece range outside source" if node.piece.start < 0 || finish > source.to_slice.size
      validate_source_boundary!(source, node.piece.start)
      validate_source_boundary!(source, finish.to_i32)
      expected_piece_newlines = count_newlines(source, node.piece.start, node.piece.length)
      expected_piece_codepoints = count_codepoints(source, node.piece.start, node.piece.length)
      expected_piece_utf16_units = count_utf16_units(source, node.piece.start, node.piece.length)
      raise "piece newline metric mismatch" unless expected_piece_newlines == node.piece.newlines
      raise "piece codepoint metric mismatch" unless expected_piece_codepoints == node.piece.codepoints
      raise "piece UTF-16 metric mismatch" unless expected_piece_utf16_units == node.piece.utf16_units
      raise "treap heap invariant violated" if node.left && node.left.not_nil!.priority > node.priority
      raise "treap heap invariant violated" if node.right && node.right.not_nil!.priority > node.priority

      left_bytes, left_newlines, left_count, left_height = validate_node!(node.left)
      right_bytes, right_newlines, right_count, right_height = validate_node!(node.right)
      expected_bytes = left_bytes + node.piece.length + right_bytes
      expected_newlines = left_newlines + node.piece.newlines + right_newlines
      expected_newlines -= 1 if node.left.try(&.ends_with_cr) && node.piece.starts_with_lf
      expected_newlines -= 1 if node.piece.ends_with_cr && node.right.try(&.starts_with_lf)
      expected_codepoints = self.class.node_codepoints(node.left) + node.piece.codepoints + self.class.node_codepoints(node.right)
      expected_utf16_units = self.class.node_utf16_units(node.left) + node.piece.utf16_units + self.class.node_utf16_units(node.right)
      expected_count = left_count + 1 + right_count
      expected_height = 1 + Math.max(left_height, right_height)
      expected_starts_with_lf = node.left ? node.left.not_nil!.starts_with_lf : node.piece.starts_with_lf
      expected_ends_with_cr = node.right ? node.right.not_nil!.ends_with_cr : node.piece.ends_with_cr
      raise "subtree byte metric mismatch" unless expected_bytes == node.byte_length
      raise "subtree newline metric mismatch" unless expected_newlines == node.newline_count
      raise "subtree codepoint metric mismatch" unless expected_codepoints == node.codepoint_count
      raise "subtree UTF-16 metric mismatch" unless expected_utf16_units == node.utf16_unit_count
      raise "subtree piece metric mismatch" unless expected_count == node.piece_count
      raise "subtree height metric mismatch" unless expected_height == node.height
      raise "subtree first-byte metric mismatch" unless expected_starts_with_lf == node.starts_with_lf
      raise "subtree last-byte metric mismatch" unless expected_ends_with_cr == node.ends_with_cr
      raise "tree height bound violated" if expected_height > MAX_TREE_HEIGHT
      {expected_bytes, expected_newlines, expected_count, expected_height}
    end

    private def validate_source_boundary!(source : Source, offset : Int32) : Nil
      bytes = source.to_slice
      return if offset == 0 || offset == bytes.size
      raise "piece splits a UTF-8 codepoint" if bytes[offset] & 0xc0 == 0x80
    end

    private def roots_same?(left : Node?, right : Node?) : Bool
      return true if left.nil? && right.nil?
      return false if left.nil? || right.nil?
      left.not_nil!.same?(right.not_nil!)
    end
  end
end
