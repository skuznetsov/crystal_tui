# Hot Reload - Watch CSS files and reload on changes
module Tui::CSS
  class HotReload
    # Watched file info
    struct WatchedFile
      property path : String
      property mtime : Time
      property callback : Proc(Stylesheet, Nil)

      def initialize(@path : String, @callback : Proc(Stylesheet, Nil))
        @mtime = File.info(@path).modification_time
      end

      def changed? : Bool
        current_mtime = File.info(@path).modification_time
        current_mtime > @mtime
      rescue
        false
      end

      def update_mtime : Nil
        @mtime = File.info(@path).modification_time
      rescue
      end
    end

    property interval : Time::Span = 500.milliseconds
    property enabled : Bool = true
    property on_error : Proc(String, Exception, Nil)?
    property on_reload : Proc(String, Nil)?

    @files : Array(WatchedFile) = [] of WatchedFile
    @running : Bool = false
    @fiber : Fiber?

    def initialize(@interval : Time::Span = 500.milliseconds)
    end

    # Watch a CSS file
    def watch(path : String, &callback : Stylesheet -> Nil) : Nil
      return unless File.exists?(path)
      @files << WatchedFile.new(path, callback)

      # Initial load
      reload_file(@files.last)
    end

    # Watch a CSS file and apply to app
    def watch_for_app(path : String, app : App) : Nil
      watch(path) do |stylesheet|
        app.apply_stylesheet(stylesheet)
        app.mark_dirty!
      end
    end

    # Start watching
    def start : Nil
      return if @running
      @running = true

      @fiber = spawn(name: "css-hot-reload") do
        while @running && @enabled
          check_files
          sleep @interval
        end
      end
    end

    # Stop watching
    def stop : Nil
      @running = false
      @fiber = nil
    end

    def running? : Bool
      @running
    end

    private def check_files : Nil
      @files.each do |file|
        if file.changed?
          reload_file(file)
        end
      end
    end

    private def reload_file(file : WatchedFile) : Nil
      begin
        content = File.read(file.path)
        stylesheet = CSS.parse(content)
        file.callback.call(stylesheet)
        file.update_mtime
        @on_reload.try &.call(file.path)
      rescue ex : CSS::ParseError
        @on_error.try &.call(file.path, ex)
      rescue ex
        @on_error.try &.call(file.path, ex)
      end
    end

    # Unwatch a file
    def unwatch(path : String) : Nil
      @files.reject! { |f| f.path == path }
    end

    # Clear all watched files
    def clear : Nil
      @files.clear
    end
  end

  # Global hot reload instance
  class_getter hot_reload : HotReload = HotReload.new

  # Convenience method to enable hot reload
  def self.enable_hot_reload(interval : Time::Span = 500.milliseconds) : HotReload
    hot_reload.interval = interval
    hot_reload.enabled = true
    hot_reload.start
    hot_reload
  end

  # Convenience method to disable hot reload
  def self.disable_hot_reload : Nil
    hot_reload.stop
    hot_reload.enabled = false
  end
end
