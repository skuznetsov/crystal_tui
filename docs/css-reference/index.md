# CSS Reference

Crystal TUI uses TCSS (TUI CSS), a simplified CSS dialect for terminal styling.

## Selectors

### Type Selector
```css
Button {
  background: blue;
}
```

### ID Selector
```css
#main-panel {
  border: light white;
}
```

### Class Selector
```css
.primary {
  background: cyan;
}
```

### Universal Selector
```css
* {
  margin: 0;
}
```

### Compound Selector
```css
Button.primary {
  background: green;
}
```

### Descendant Selector
```css
Panel Button {
  margin: 1;
}
```

### Child Selector
```css
Panel > Label {
  color: yellow;
}
```

## Pseudo-Classes

### State
```css
Button:focus {
  background: white;
  color: black;
}

Button:hover {
  background: cyan;
}

Input:disabled {
  color: gray;
}
```

### Position
```css
/* First/last child */
Button:first-child { margin-top: 0; }
Button:last-child { margin-bottom: 0; }
Button:only-child { margin: 0; }

/* Nth child */
Item:nth-child(2) { background: blue; }
Item:even { background: #333; }
Item:odd { background: #444; }
```

### Content
```css
Panel:empty {
  display: none;
}
```

### Theme
```css
/* Dark theme (default) */
Panel:dark {
  background: #1a1a1a;
}

/* Light theme */
Panel:light {
  background: #f0f0f0;
}
```

## Variables

```css
/* Define variables */
$primary: cyan;
$bg-dark: rgb(30, 30, 40);
$border-color: #666;

/* Use variables */
Button {
  background: $primary;
  border: light $border-color;
}
```

## Properties

### Layout

| Property | Values | Description |
|----------|--------|-------------|
| `width` | `auto`, `50`, `50%`, `1fr` | Widget width |
| `height` | `auto`, `10`, `100%`, `2fr` | Widget height |
| `min-width` | `10` | Minimum width |
| `max-width` | `100` | Maximum width |
| `min-height` | `5` | Minimum height |
| `max-height` | `50` | Maximum height |

```css
Panel {
  width: 50%;
  height: 1fr;
  min-width: 20;
}
```

### Box Model

| Property | Values | Description |
|----------|--------|-------------|
| `margin` | `1`, `1 2`, `1 2 1 2` | Outer spacing |
| `margin-top/right/bottom/left` | `1` | Individual margins |
| `padding` | `1`, `1 2`, `1 2 1 2` | Inner spacing |
| `padding-top/right/bottom/left` | `1` | Individual padding |

```css
Panel {
  margin: 1 2;      /* vertical horizontal */
  padding: 1;       /* all sides */
}
```

### Visual

| Property | Values | Description |
|----------|--------|-------------|
| `background` | color | Background color |
| `color` | color | Text color |
| `opacity` | `0.0`-`1.0`, `0%`-`100%` | Transparency |
| `visibility` | `visible`, `hidden` | Show/hide |
| `display` | `block`, `none` | Display mode |
| `z-index` | integer | Stack order |

```css
Panel {
  background: blue;
  color: white;
  opacity: 80%;
}
```

### Border (Panel)

| Property | Values | Description |
|----------|--------|-------------|
| `border` | `<style> <color>` | Border shorthand |
| `border-style` | `light`, `heavy`, `double`, `round`, `ascii`, `none` | Border style |
| `border-color` | color | Border color |
| `border-title-color` | color | Title text color |
| `border-title-style` | `brackets`, `spaces`, `none` | Title decoration |
| `title-align` | `left`, `center`, `right` | Title alignment |

```css
Panel {
  border: round cyan;
  border-title-color: yellow;
  title-align: center;
}
```

### Text (Label)

| Property | Values | Description |
|----------|--------|-------------|
| `text-align` | `left`, `center`, `right` | Text alignment |
| `text-style` | `bold`, `dim`, `italic`, `underline`, `blink`, `reverse`, `strikethrough` | Text attributes |
| `text-overflow` | `clip`, `ellipsis` | Overflow handling |
| `text-wrap` | `wrap`, `nowrap` | Text wrapping |
| `text-opacity` | `0.0`-`1.0` | Text transparency |

```css
Label {
  text-align: center;
  text-style: bold underline;
  text-overflow: ellipsis;
}
```

### Position

| Property | Values | Description |
|----------|--------|-------------|
| `dock` | `top`, `bottom`, `left`, `right` | Dock position |
| `offset-x` | integer | Horizontal offset |
| `offset-y` | integer | Vertical offset |

```css
Header {
  dock: top;
}

Footer {
  dock: bottom;
}
```

### Grid (Grid container)

| Property | Values | Description |
|----------|--------|-------------|
| `grid-columns` | integer | Number of columns |
| `grid-rows` | integer | Number of rows |
| `grid-gutter` | integer | Gap between cells |
| `column-span` | integer | Columns to span |
| `row-span` | integer | Rows to span |

```css
Grid {
  grid-columns: 3;
  grid-gutter: 1;
}

#wide-widget {
  column-span: 2;
}
```

## Colors

### Named Colors
```css
color: white;
color: black;
color: red;
color: green;
color: blue;
color: yellow;
color: cyan;
color: magenta;
color: default;
```

### Hex Colors
```css
color: #fff;        /* Short hex */
color: #ff0000;     /* Full hex */
```

### RGB Colors
```css
color: rgb(255, 128, 0);
```

## Comments

```css
/* Block comment */
// Line comment

Button {
  background: blue; /* inline comment */
}
```

## Hot Reload

Enable with environment variable:

```bash
TUI_DEV=1 crystal run app.cr
```

Or programmatically:

```crystal
class MyApp < Tui::App
  def initialize
    super
    load_css("styles.tcss")
    enable_css_hot_reload
  end
end
```
