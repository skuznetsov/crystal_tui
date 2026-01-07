# TUI CLI - Command line tool for Crystal TUI development
require "option_parser"
require "file_utils"

module TuiCLI
  VERSION = "0.1.0"

  class CLI
    @command : String = ""
    @args : Array(String) = [] of String

    def run(args : Array(String))
      parse_args(args)

      case @command
      when "new"
        new_project(@args.first?)
      when "dev"
        dev_mode
      when "build"
        build_release
      when "version"
        puts "tui #{VERSION}"
      when "help", ""
        show_help
      else
        STDERR.puts "Unknown command: #{@command}"
        STDERR.puts "Run 'tui help' for usage"
        exit 1
      end
    end

    private def parse_args(args : Array(String))
      if args.empty?
        @command = "help"
        return
      end

      @command = args.first
      @args = args[1..]? || [] of String
    end

    private def new_project(name : String?)
      unless name
        STDERR.puts "Usage: tui new <project-name>"
        exit 1
      end

      if File.exists?(name)
        STDERR.puts "Error: Directory '#{name}' already exists"
        exit 1
      end

      puts "Creating new Crystal TUI project: #{name}"

      # Create directories
      FileUtils.mkdir_p("#{name}/src")
      FileUtils.mkdir_p("#{name}/styles")

      # Create shard.yml
      File.write("#{name}/shard.yml", <<-YAML
      name: #{name}
      version: 0.1.0

      targets:
        #{name}:
          main: src/#{name}.cr

      dependencies:
        tui:
          github: skuznetsov/crystal_tui

      crystal: ">= 1.10.0"
      YAML
      )

      # Create main file
      File.write("#{name}/src/#{name}.cr", <<-CRYSTAL
      require "tui"

      class #{name.camelcase}App < Tui::App
        # Path to CSS file (optional)
        @@css_path = "styles/app.tcss"

        def compose : Array(Tui::Widget)
          [
            Tui::Panel.new("#{name.camelcase}", id: "main") do |panel|
              panel.content = Tui::VBox.new do |vbox|
                vbox.add_child Tui::Label.new("Welcome to #{name.camelcase}!", id: "welcome")
                vbox.add_child Tui::Label.new("Press Ctrl+C to exit", id: "hint")
              end
            end
          ]
        end
      end

      #{name.camelcase}App.new.run
      CRYSTAL
      )

      # Create CSS file
      File.write("#{name}/styles/app.tcss", <<-TCSS
      /* #{name.camelcase} Styles */

      /* Variables */
      $primary: cyan;
      $bg: #1a1a2e;

      /* Main panel */
      #main {
        border: round $primary;
        padding: 1;
      }

      /* Welcome message */
      #welcome {
        color: $primary;
        text-style: bold;
        text-align: center;
      }

      #hint {
        color: #666;
        text-align: center;
      }
      TCSS
      )

      # Create .gitignore
      File.write("#{name}/.gitignore", <<-GITIGNORE
      /bin/
      /lib/
      /.shards/
      /docs/
      *.dwarf
      .DS_Store
      GITIGNORE
      )

      # Create README
      File.write("#{name}/README.md", <<-README
      # #{name.camelcase}

      A Crystal TUI application.

      ## Installation

      ```bash
      shards install
      ```

      ## Development

      Run with hot reload:

      ```bash
      TUI_DEV=1 crystal run src/#{name}.cr
      ```

      Or use the TUI CLI:

      ```bash
      tui dev
      ```

      ## Build

      ```bash
      crystal build src/#{name}.cr -o bin/#{name} --release
      ```
      README
      )

      puts "  Created #{name}/shard.yml"
      puts "  Created #{name}/src/#{name}.cr"
      puts "  Created #{name}/styles/app.tcss"
      puts "  Created #{name}/.gitignore"
      puts "  Created #{name}/README.md"
      puts ""
      puts "Next steps:"
      puts "  cd #{name}"
      puts "  shards install"
      puts "  TUI_DEV=1 crystal run src/#{name}.cr"
    end

    private def dev_mode
      # Find the main file
      main_file = find_main_file
      unless main_file
        STDERR.puts "Error: Could not find main Crystal file"
        STDERR.puts "Make sure you're in a Crystal TUI project directory"
        exit 1
      end

      puts "Starting dev mode with hot reload..."
      puts "Main file: #{main_file}"
      puts "Press Ctrl+C to stop"
      puts ""

      # Run with TUI_DEV=1
      ENV["TUI_DEV"] = "1"
      Process.exec("crystal", ["run", main_file])
    end

    private def build_release
      main_file = find_main_file
      unless main_file
        STDERR.puts "Error: Could not find main Crystal file"
        exit 1
      end

      # Determine output name from shard.yml or directory
      output_name = File.basename(Dir.current)
      if File.exists?("shard.yml")
        content = File.read("shard.yml")
        if match = content.match(/name:\s*(\w+)/)
          output_name = match[1]
        end
      end

      FileUtils.mkdir_p("bin")

      puts "Building release: bin/#{output_name}"
      status = Process.run("crystal", ["build", main_file, "-o", "bin/#{output_name}", "--release"], output: STDOUT, error: STDERR)

      if status.success?
        puts "Build successful!"
      else
        STDERR.puts "Build failed"
        exit 1
      end
    end

    private def find_main_file : String?
      # Check shard.yml for targets
      if File.exists?("shard.yml")
        content = File.read("shard.yml")
        if match = content.match(/main:\s*(.+\.cr)/)
          file = match[1].strip
          return file if File.exists?(file)
        end
      end

      # Check common locations
      ["src/app.cr", "src/main.cr"].each do |file|
        return file if File.exists?(file)
      end

      # Check src/ for any .cr file with App class
      if Dir.exists?("src")
        Dir.glob("src/*.cr").each do |file|
          content = File.read(file)
          if content.includes?("< Tui::App")
            return file
          end
        end
      end

      nil
    end

    private def show_help
      puts <<-HELP
      TUI CLI - Crystal TUI Development Tool

      Usage:
        tui <command> [arguments]

      Commands:
        new <name>    Create a new Crystal TUI project
        dev           Run in development mode with hot reload
        build         Build release binary
        version       Show version
        help          Show this help

      Examples:
        tui new myapp     Create new project 'myapp'
        tui dev           Run current project with hot reload
        tui build         Build optimized binary

      Environment:
        TUI_DEV=1         Enable development mode (auto CSS hot reload)

      More info: https://github.com/skuznetsov/crystal_tui
      HELP
    end
  end
end

# Run CLI
TuiCLI::CLI.new.run(ARGV)
