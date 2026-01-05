# Reactive property system using macros
module Tui
  module Reactive
    # Define a reactive property that triggers watchers on change
    #
    # Usage:
    #   reactive current_path : Path = Path.home
    #
    # This creates:
    #   - getter @current_path
    #   - setter that calls watch_current_path(value) on change
    #   - abstract watch_current_path(value) to override
    #
    macro reactive(decl)
      {% name = decl.var %}
      {% type = decl.type %}
      {% default = decl.value %}

      @{{name}} : {{type}} {% if default %} = {{default}} {% end %}

      def {{name}} : {{type}}
        @{{name}}
      end

      def {{name}}=(value : {{type}}) : {{type}}
        old_value = @{{name}}
        @{{name}} = value
        if old_value != value
          watch_{{name}}(value)
          request_render
        end
        value
      end

      # Override this to react to changes
      def watch_{{name}}(value : {{type}})
      end
    end

    # Request re-render (to be implemented by Widget)
    def request_render
    end
  end
end
