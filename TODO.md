# Crystal TUI - Roadmap to v1.0

## Goal: Feature parity with [Textual](https://textual.textualize.io/) for Crystal

---

## 1. CSS Styling (TCSS)

### Current State
- [x] Type selectors (`Button`)
- [x] ID selectors (`#my-id`)
- [x] Class selectors (`.active`)
- [x] Pseudo-classes (`:focus`, `:visible`, `:disabled`)
- [x] Compound selectors (`Button.active`)
- [x] Universal selector (`*`)
- [x] Variables (`$primary: cyan`)
- [x] Colors (hex `#ff0`, rgb `rgb(255,0,0)`)
- [x] Comments (`/* */`, `//`)

### Recently Added ✓
- [x] Descendant selector (`Panel Button`)
- [x] Child selector (`Panel > Button`)
- [x] Layout properties: `width`, `height`, `min-width`, `max-width`, `min-height`, `max-height`
- [x] Box model: `margin`, `margin-top/right/bottom/left`, `padding`, `padding-top/right/bottom/left`
- [x] Dimension units: `px`, `%`, `fr`, `auto`

### Pseudo-classes ✓
- [x] `:hover` - mouse hover state
- [x] `:empty` - no children
- [x] `:first-child`, `:last-child`, `:only-child`
- [x] `:nth-child(n)` - nth child selector
- [x] `:even`, `:odd` - even/odd children
- [x] `:enabled`, `:disabled` - form states

### Recently Added (Phase 2) ✓
- [x] Theme pseudo-classes: `:dark`, `:light`
- [x] Text properties: `text-align`, `text-style`, `color`
- [x] Grid layout: `Grid` container with `grid-columns`, `grid-rows`, `grid-gutter`, `column-span`, `row-span`

### Missing (Priority: MEDIUM)
- [ ] Dock property: `dock` (top, bottom, left, right)
- [ ] Offset: `offset`, `offset-x`, `offset-y`
- [x] Visual properties: `visibility` (visible, hidden), `display` (block, none)
- [ ] Remaining visual properties:
  - [ ] `opacity`, `text-opacity`
  - [ ] `tint`, `background-tint`
- [ ] Text properties:
  - [ ] `text-wrap` (wrap, nowrap)
  - [ ] `text-overflow` (ellipsis, clip)
- [ ] Border properties:
  - [ ] `border-title-color`, `border-title-style`
  - [ ] `border-subtitle-*`
- [ ] Scrollbar styling:
  - [ ] `scrollbar-size`
  - [ ] `scrollbar-color`, `scrollbar-background`
- [ ] CSS nesting with `&`
- [ ] `!important` modifier
- [ ] Live CSS reload (hot reload)

---

## 2. Widgets

### Current Widgets (41)
- [x] Panel - container with border/title
- [x] Button - clickable button
- [x] Label - text display
- [x] Input - single-line text input
- [x] Checkbox - toggle checkbox
- [x] RadioGroup - radio button group
- [x] ComboBox - dropdown select
- [x] DataTable - data grid with sorting
- [x] TabbedPanel - tabbed content
- [x] Dialog - modal dialog
- [x] MenuBar - application menu
- [x] FilePanel - file browser
- [x] TextEditor - multi-line editor
- [x] TextViewer - scrollable text
- [x] MarkdownView - markdown renderer
- [x] ProgressBar - progress indicator
- [x] RichText - styled text
- [x] Collapsible - expandable section
- [x] Footer - key bindings footer
- [x] IconSidebar - VSCode-style sidebar
- [x] DraggableWindow / WindowManager

### Missing Widgets (Priority Order)

#### Priority 1 - Essential ✓
- [x] **Header** - App title bar with clock/status
- [x] **Tree** - Generic tree view (not just files)
- [x] **Switch** - iOS-style toggle switch
- [x] **LoadingIndicator** - Spinner/loading animation
- [x] **Toast/Notification** - Popup notifications
- [x] **Rule** - Horizontal/vertical divider

#### Priority 2 - Common ✓
- [x] **ListView** - Virtual scrolling list
- [x] **SelectionList** - Multi-select list
- [x] **Log/RichLog** - Scrolling log viewer
- [x] **Link** - Clickable URL
- [x] **Sparkline** - Mini chart

#### Priority 3 - Complete ✓
- [x] **Slider** - Range slider with keyboard/mouse
- [x] **MaskedInput** - Input with format mask (phone, date, etc.)
- [x] **Digits** - Large ASCII art number display
- [x] **Calendar** - Date picker with month navigation
- [x] **ColorPicker** - 16/256 color palette selection
- [x] **TimePicker** - Time selection (24h/12h, seconds toggle)
- [x] **Placeholder** - Dev placeholder widget with dimensions
- [x] **Pretty** - Pretty-print data structures with syntax highlighting

---

## 3. Hot Reload

### Architecture
```
┌─────────────────┐     ┌──────────────┐
│   App Process   │────▶│  File Watcher │
│                 │◀────│  (FSEvent)    │
│  ┌───────────┐  │     └──────────────┘
│  │ CSS Cache │  │            │
│  └───────────┘  │            │
│        │        │     ┌──────────────┐
│        ▼        │     │  .tcss files │
│  ┌───────────┐  │     └──────────────┘
│  │ Re-render │  │
│  └───────────┘  │
└─────────────────┘
```

### Tasks ✓
- [x] File watcher for `.tcss` files (polling-based, cross-platform)
- [x] CSS cache invalidation
- [x] Widget style recomputation
- [x] Smooth re-render without flicker
- [ ] Dev mode flag (`--dev` or `TUI_DEV=1`)
- [ ] Error overlay for CSS parse errors

---

## 4. Documentation

### Structure (like Textual)
```
docs/
├── index.md                 # Landing page
├── getting-started/
│   ├── installation.md
│   ├── hello-world.md
│   └── tutorial.md
├── guide/
│   ├── app.md              # App basics
│   ├── widgets.md          # Widget system
│   ├── css.md              # TCSS styling
│   ├── events.md           # Event handling
│   ├── layout.md           # Layout system
│   ├── screens.md          # Screen management
│   └── reactivity.md       # Reactive state
├── widgets/
│   ├── index.md            # Widget gallery
│   ├── button.md
│   ├── input.md
│   └── ...
├── css-reference/
│   ├── index.md
│   ├── selectors.md
│   ├── properties.md
│   └── colors.md
├── api/                    # Generated from crystal docs
└── examples/
    ├── index.md
    ├── calculator.md
    ├── file-manager.md
    └── chat-ui.md
```

### Tasks
- [ ] Set up documentation site (MkDocs/Docusaurus)
- [ ] Write Getting Started guide
- [ ] Document each widget with examples
- [ ] CSS reference with all properties
- [ ] API documentation (crystal docs)
- [ ] Interactive examples (if possible)
- [ ] Video tutorials

---

## 5. Developer Experience

### Tooling
- [ ] `crystal_tui` CLI tool:
  - [ ] `tui new myapp` - scaffold new app
  - [ ] `tui dev` - run with hot reload
  - [ ] `tui build` - production build
- [ ] VS Code extension (syntax highlighting for .tcss)
- [ ] Widget inspector (devtools)

### Testing
- [ ] Widget testing helpers
- [ ] Snapshot testing for renders
- [ ] Event simulation helpers

---

## 6. Performance

- [ ] Virtual scrolling for large lists
- [ ] Lazy widget mounting
- [ ] Render batching
- [ ] Memory profiling

---

## Implementation Order

### Phase 1: CSS Foundation (Week 1-2)
1. Descendant/child selectors
2. Layout properties (width, height, margin, padding)
3. More pseudo-classes (:hover, :first-child, etc.)
4. Live CSS reload

### Phase 2: Essential Widgets (Week 3-4)
1. Header
2. Tree
3. Switch
4. LoadingIndicator
5. Toast/Notification

### Phase 3: Documentation (Week 5-6)
1. Getting Started guide
2. Widget documentation
3. CSS reference
4. API docs

### Phase 4: Polish (Week 7-8)
1. Grid layout
2. Remaining widgets
3. CLI tooling
4. Examples

---

## Resources

- [Textual Documentation](https://textual.textualize.io/)
- [Textual CSS Guide](https://textual.textualize.io/guide/CSS/)
- [Textual Widget Gallery](https://textual.textualize.io/widget_gallery/)
