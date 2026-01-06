require "../../spec_helper"

describe Tui::Color do
  describe "#initialize" do
    it "creates default color with value -1" do
      color = Tui::Color.new
      color.value.should eq -1
      color.transparent?.should be_false
    end

    it "creates color with custom value" do
      color = Tui::Color.new(5)
      color.value.should eq 5
    end

    it "creates transparent color" do
      color = Tui::Color.new(transparent: true)
      color.transparent?.should be_true
    end
  end

  describe ".default" do
    it "returns default color" do
      color = Tui::Color.default
      color.default?.should be_true
      color.transparent?.should be_false
    end
  end

  describe ".transparent" do
    it "returns transparent color" do
      color = Tui::Color.transparent
      color.transparent?.should be_true
    end
  end

  describe "basic colors" do
    it "provides standard ANSI colors" do
      Tui::Color.black.value.should eq 0
      Tui::Color.red.value.should eq 1
      Tui::Color.green.value.should eq 2
      Tui::Color.yellow.value.should eq 3
      Tui::Color.blue.value.should eq 4
      Tui::Color.magenta.value.should eq 5
      Tui::Color.cyan.value.should eq 6
      Tui::Color.white.value.should eq 7
    end
  end

  describe ".palette" do
    it "creates 256-color palette color" do
      color = Tui::Color.palette(128)
      color.value.should eq 128
      color.rgb?.should be_false
    end
  end

  describe ".rgb" do
    it "creates true color" do
      color = Tui::Color.rgb(255, 128, 64)
      color.rgb?.should be_true
    end

    it "encodes and decodes RGB values" do
      color = Tui::Color.rgb(100, 150, 200)
      r, g, b = color.to_rgb
      r.should eq 100
      g.should eq 150
      b.should eq 200
    end

    it "handles edge values" do
      color = Tui::Color.rgb(0, 0, 0)
      r, g, b = color.to_rgb
      r.should eq 0
      g.should eq 0
      b.should eq 0

      color2 = Tui::Color.rgb(255, 255, 255)
      r2, g2, b2 = color2.to_rgb
      r2.should eq 255
      g2.should eq 255
      b2.should eq 255
    end
  end

  describe "#to_rgb" do
    it "returns zeros for non-RGB color" do
      color = Tui::Color.red
      r, g, b = color.to_rgb
      r.should eq 0
      g.should eq 0
      b.should eq 0
    end
  end

  describe "#default?" do
    it "returns true for default color" do
      Tui::Color.default.default?.should be_true
    end

    it "returns false for non-default color" do
      Tui::Color.red.default?.should be_false
      Tui::Color.transparent.default?.should be_false
    end
  end

  describe "#==" do
    it "compares colors by value and transparency" do
      (Tui::Color.red == Tui::Color.red).should be_true
      (Tui::Color.red == Tui::Color.blue).should be_false
      (Tui::Color.default == Tui::Color.transparent).should be_false
    end
  end

  describe "#dimmed" do
    it "dims RGB colors" do
      color = Tui::Color.rgb(200, 100, 50)
      dimmed = color.dimmed
      r, g, b = dimmed.to_rgb
      r.should eq 100
      g.should eq 50
      b.should eq 25
    end

    it "returns same color for basic colors" do
      color = Tui::Color.red
      color.dimmed.should eq color
    end
  end
end

describe Tui::Attributes do
  it "defaults to none" do
    attrs = Tui::Attributes::None
    attrs.bold?.should be_false
    attrs.italic?.should be_false
  end

  it "supports individual attributes" do
    Tui::Attributes::Bold.bold?.should be_true
    Tui::Attributes::Italic.italic?.should be_true
    Tui::Attributes::Underline.underline?.should be_true
    Tui::Attributes::Dim.dim?.should be_true
    Tui::Attributes::Reverse.reverse?.should be_true
  end

  it "supports combining attributes" do
    attrs = Tui::Attributes::Bold | Tui::Attributes::Italic
    attrs.bold?.should be_true
    attrs.italic?.should be_true
    attrs.underline?.should be_false
  end
end

describe Tui::Style do
  describe "#initialize" do
    it "creates default style" do
      style = Tui::Style.new
      style.fg.default?.should be_true
      style.bg.default?.should be_true
      style.attrs.should eq Tui::Attributes::None
    end

    it "creates style with colors" do
      style = Tui::Style.new(fg: Tui::Color.red, bg: Tui::Color.blue)
      style.fg.should eq Tui::Color.red
      style.bg.should eq Tui::Color.blue
    end

    it "creates style with attributes" do
      style = Tui::Style.new(attrs: Tui::Attributes::Bold | Tui::Attributes::Underline)
      style.bold?.should be_true
      style.underline?.should be_true
    end
  end

  describe ".default" do
    it "returns default style" do
      style = Tui::Style.default
      style.fg.default?.should be_true
      style.bg.default?.should be_true
    end
  end

  describe "attribute helpers" do
    it "delegates to attrs" do
      style = Tui::Style.new(attrs: Tui::Attributes::Bold | Tui::Attributes::Italic)
      style.bold?.should be_true
      style.italic?.should be_true
      style.dim?.should be_false
      style.underline?.should be_false
      style.reverse?.should be_false
    end
  end

  describe "#==" do
    it "compares styles" do
      style1 = Tui::Style.new(fg: Tui::Color.red)
      style2 = Tui::Style.new(fg: Tui::Color.red)
      style3 = Tui::Style.new(fg: Tui::Color.blue)

      (style1 == style2).should be_true
      (style1 == style3).should be_false
    end

    it "compares attributes" do
      style1 = Tui::Style.new(attrs: Tui::Attributes::Bold)
      style2 = Tui::Style.new(attrs: Tui::Attributes::Bold)
      style3 = Tui::Style.new(attrs: Tui::Attributes::Italic)

      (style1 == style2).should be_true
      (style1 == style3).should be_false
    end
  end

  describe "#to_ansi" do
    it "generates ANSI codes for colors" do
      style = Tui::Style.new(fg: Tui::Color.red)
      ansi = style.to_ansi
      ansi.should contain("\e[")  # Contains escape sequence
    end

    it "generates ANSI codes for attributes" do
      style = Tui::Style.new(attrs: Tui::Attributes::Bold)
      ansi = style.to_ansi
      ansi.should contain("\e[1m")  # Bold
    end

    it "handles RGB colors" do
      style = Tui::Style.new(fg: Tui::Color.rgb(100, 150, 200))
      ansi = style.to_ansi
      ansi.should contain("38;2;100;150;200")  # RGB foreground
    end
  end
end

describe Tui::Cell do
  describe "#initialize" do
    it "creates cell with default values" do
      cell = Tui::Cell.new
      cell.char.should eq ' '
      cell.style.should eq Tui::Style.default
    end

    it "creates cell with character" do
      cell = Tui::Cell.new('X')
      cell.char.should eq 'X'
    end

    it "creates cell with style" do
      style = Tui::Style.new(fg: Tui::Color.green)
      cell = Tui::Cell.new('A', style)
      cell.char.should eq 'A'
      cell.style.fg.should eq Tui::Color.green
    end
  end

  describe ".empty" do
    it "creates empty cell (space)" do
      cell = Tui::Cell.empty
      cell.char.should eq ' '
    end
  end

  describe ".transparent" do
    it "creates cell with transparent background" do
      cell = Tui::Cell.transparent
      cell.transparent_bg?.should be_true
    end
  end

  describe "#==" do
    it "compares cells by char and style" do
      cell1 = Tui::Cell.new('A', Tui::Style.new(fg: Tui::Color.red))
      cell2 = Tui::Cell.new('A', Tui::Style.new(fg: Tui::Color.red))
      cell3 = Tui::Cell.new('B', Tui::Style.new(fg: Tui::Color.red))
      cell4 = Tui::Cell.new('A', Tui::Style.new(fg: Tui::Color.blue))

      (cell1 == cell2).should be_true
      (cell1 == cell3).should be_false
      (cell1 == cell4).should be_false
    end
  end

  describe "#transparent_bg?" do
    it "returns true for transparent background" do
      cell = Tui::Cell.new('X', Tui::Style.new(bg: Tui::Color.transparent))
      cell.transparent_bg?.should be_true
    end

    it "returns false for opaque background" do
      cell = Tui::Cell.new('X', Tui::Style.new(bg: Tui::Color.blue))
      cell.transparent_bg?.should be_false
    end
  end

  describe "#with_dimmed_colors" do
    it "creates dimmed copy" do
      style = Tui::Style.new(fg: Tui::Color.rgb(200, 100, 50))
      cell = Tui::Cell.new('X', style)
      dimmed = cell.with_dimmed_colors

      dimmed.char.should eq 'X'
      dimmed.style.dim?.should be_true
      r, g, b = dimmed.style.fg.to_rgb
      r.should eq 100
    end
  end
end
