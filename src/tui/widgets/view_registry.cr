# ViewRegistry - Maps tool names to View factories
#
# Usage:
#   ViewRegistry.register("shell") { CodeView.new }
#   ViewRegistry.register("git_diff") { DiffView.new }
#
#   view = ViewRegistry.create("shell")  # => CodeView
#   view = ViewRegistry.create("unknown")  # => CodeView (default)

module Tui
  module ViewRegistry
    alias ViewFactory = Proc(View)

    @@factories = {} of String => ViewFactory
    @@default_factory : ViewFactory = ->{ CodeView.new.as(View) }

    # Register a factory for a tool name
    def self.register(tool_name : String, &block : -> View) : Nil
      @@factories[tool_name] = block
    end

    # Register with explicit factory proc
    def self.register(tool_name : String, factory : ViewFactory) : Nil
      @@factories[tool_name] = factory
    end

    # Set default factory (used when tool not registered)
    def self.set_default(&block : -> View) : Nil
      @@default_factory = block
    end

    # Create a View for the given tool
    def self.create(tool_name : String, id : String? = nil) : View
      factory = @@factories[tool_name]? || @@default_factory
      view = factory.call
      view.id = id if id
      view
    end

    # Check if a tool has a registered factory
    def self.registered?(tool_name : String) : Bool
      @@factories.has_key?(tool_name)
    end

    # List registered tool names
    def self.registered_tools : Array(String)
      @@factories.keys
    end

    # Clear all registrations (for testing)
    def self.clear : Nil
      @@factories.clear
    end

    # ─────────────────────────────────────────────────────────────
    # Default registrations
    # ─────────────────────────────────────────────────────────────

    # Register default views for common tools
    def self.register_defaults : Nil
      # Text/code output tools → CodeView
      %w[shell read_file grep find write_file edit_file].each do |tool|
        register(tool) { CodeView.new.as(View) }
      end

      # Git diff → DiffView (if DiffView inherits from View)
      # register("git_diff") { DiffView.new.as(View) }

      # Future: structured data tools
      # register("list_files") { TreeView.new.as(View) }
      # register("search") { SearchResultsView.new.as(View) }
    end
  end
end

# Auto-register defaults on load
Tui::ViewRegistry.register_defaults
