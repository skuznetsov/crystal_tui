require "../spec_helper"

describe Tui::BorderStyle do
  it "has all expected styles" do
    Tui::BorderStyle::None.should be_a(Tui::BorderStyle)
    Tui::BorderStyle::Light.should be_a(Tui::BorderStyle)
    Tui::BorderStyle::Heavy.should be_a(Tui::BorderStyle)
    Tui::BorderStyle::Double.should be_a(Tui::BorderStyle)
    Tui::BorderStyle::Round.should be_a(Tui::BorderStyle)
    Tui::BorderStyle::Ascii.should be_a(Tui::BorderStyle)
  end
end

describe Tui::BorderChars do
  it "stores all border characters" do
    chars = Tui::BorderChars.new(
      h: '─', v: '│',
      tl: '┌', tr: '┐', bl: '└', br: '┘',
      t_down: '┬', t_up: '┴', t_right: '├', t_left: '┤',
      cross: '┼'
    )

    chars.h.should eq '─'
    chars.v.should eq '│'
    chars.tl.should eq '┌'
    chars.tr.should eq '┐'
    chars.bl.should eq '└'
    chars.br.should eq '┘'
    chars.t_down.should eq '┬'
    chars.t_up.should eq '┴'
    chars.t_right.should eq '├'
    chars.t_left.should eq '┤'
    chars.cross.should eq '┼'
  end
end

describe Tui::BORDERS do
  it "contains Light style" do
    chars = Tui::BORDERS[Tui::BorderStyle::Light]
    chars.tl.should eq '┌'
    chars.h.should eq '─'
    chars.v.should eq '│'
  end

  it "contains Heavy style" do
    chars = Tui::BORDERS[Tui::BorderStyle::Heavy]
    chars.tl.should eq '┏'
    chars.h.should eq '━'
    chars.v.should eq '┃'
  end

  it "contains Double style" do
    chars = Tui::BORDERS[Tui::BorderStyle::Double]
    chars.tl.should eq '╔'
    chars.h.should eq '═'
    chars.v.should eq '║'
  end

  it "contains Round style" do
    chars = Tui::BORDERS[Tui::BorderStyle::Round]
    chars.tl.should eq '╭'
    chars.tr.should eq '╮'
    chars.bl.should eq '╰'
    chars.br.should eq '╯'
  end

  it "contains Ascii style" do
    chars = Tui::BORDERS[Tui::BorderStyle::Ascii]
    chars.tl.should eq '+'
    chars.h.should eq '-'
    chars.v.should eq '|'
  end
end

describe "Tui.border_chars" do
  it "returns chars for valid style" do
    chars = Tui.border_chars(Tui::BorderStyle::Heavy)
    chars.tl.should eq '┏'
  end

  it "returns Light chars as default" do
    # This tests the fallback behavior
    chars = Tui.border_chars(Tui::BorderStyle::Light)
    chars.tl.should eq '┌'
  end
end

describe "Buffer.draw_box with BorderStyle" do
  it "draws box with Light style" do
    buffer = Tui::Buffer.new(10, 5)
    buffer.draw_box(0, 0, 10, 5, border_style: Tui::BorderStyle::Light)

    buffer.get(0, 0).char.should eq '┌'
    buffer.get(9, 0).char.should eq '┐'
    buffer.get(5, 0).char.should eq '─'
  end

  it "draws box with Heavy style" do
    buffer = Tui::Buffer.new(10, 5)
    buffer.draw_box(0, 0, 10, 5, border_style: Tui::BorderStyle::Heavy)

    buffer.get(0, 0).char.should eq '┏'
    buffer.get(9, 0).char.should eq '┓'
    buffer.get(5, 0).char.should eq '━'
  end

  it "draws box with Double style" do
    buffer = Tui::Buffer.new(10, 5)
    buffer.draw_box(0, 0, 10, 5, border_style: Tui::BorderStyle::Double)

    buffer.get(0, 0).char.should eq '╔'
    buffer.get(5, 0).char.should eq '═'
  end

  it "draws box with Round style" do
    buffer = Tui::Buffer.new(10, 5)
    buffer.draw_box(0, 0, 10, 5, border_style: Tui::BorderStyle::Round)

    buffer.get(0, 0).char.should eq '╭'
    buffer.get(9, 0).char.should eq '╮'
    buffer.get(0, 4).char.should eq '╰'
    buffer.get(9, 4).char.should eq '╯'
  end

  it "draws box with Ascii style" do
    buffer = Tui::Buffer.new(10, 5)
    buffer.draw_box(0, 0, 10, 5, border_style: Tui::BorderStyle::Ascii)

    buffer.get(0, 0).char.should eq '+'
    buffer.get(5, 0).char.should eq '-'
    buffer.get(0, 2).char.should eq '|'
  end

  it "accepts Symbol for backwards compatibility" do
    buffer = Tui::Buffer.new(10, 5)
    buffer.draw_box(0, 0, 10, 5, Tui::Style.default, :heavy)

    buffer.get(0, 0).char.should eq '┏'
  end
end
