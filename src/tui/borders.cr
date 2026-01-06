# Shared border character definitions
module Tui
  # Border style enum used across widgets
  enum BorderStyle
    None
    Light   # ─ │ ┌ ┐ └ ┘
    Heavy   # ━ ┃ ┏ ┓ ┗ ┛
    Double  # ═ ║ ╔ ╗ ╚ ╝
    Round   # ─ │ ╭ ╮ ╰ ╯
    Ascii   # - | + + + +
  end

  # Border character set
  record BorderChars,
    h : Char,           # horizontal
    v : Char,           # vertical
    tl : Char,          # top-left
    tr : Char,          # top-right
    bl : Char,          # bottom-left
    br : Char,          # bottom-right
    t_down : Char,      # T pointing down (┬)
    t_up : Char,        # T pointing up (┴)
    t_right : Char,     # T pointing right (├)
    t_left : Char,      # T pointing left (┤)
    cross : Char        # cross junction (┼)

  # Border character sets for each style
  BORDERS = {
    BorderStyle::Light => BorderChars.new(
      h: '─', v: '│',
      tl: '┌', tr: '┐', bl: '└', br: '┘',
      t_down: '┬', t_up: '┴', t_right: '├', t_left: '┤',
      cross: '┼'
    ),
    BorderStyle::Heavy => BorderChars.new(
      h: '━', v: '┃',
      tl: '┏', tr: '┓', bl: '┗', br: '┛',
      t_down: '┳', t_up: '┻', t_right: '┣', t_left: '┫',
      cross: '╋'
    ),
    BorderStyle::Double => BorderChars.new(
      h: '═', v: '║',
      tl: '╔', tr: '╗', bl: '╚', br: '╝',
      t_down: '╦', t_up: '╩', t_right: '╠', t_left: '╣',
      cross: '╬'
    ),
    BorderStyle::Round => BorderChars.new(
      h: '─', v: '│',
      tl: '╭', tr: '╮', bl: '╰', br: '╯',
      t_down: '┬', t_up: '┴', t_right: '├', t_left: '┤',
      cross: '┼'
    ),
    BorderStyle::Ascii => BorderChars.new(
      h: '-', v: '|',
      tl: '+', tr: '+', bl: '+', br: '+',
      t_down: '+', t_up: '+', t_right: '+', t_left: '+',
      cross: '+'
    ),
  }

  # Get border characters for a style
  def self.border_chars(style : BorderStyle) : BorderChars
    BORDERS[style]? || BORDERS[BorderStyle::Light]
  end
end
