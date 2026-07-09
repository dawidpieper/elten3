root = File.expand_path(__dir__)
Dir.chdir(root)
$LOAD_PATH.unshift(File.join(root, "src")) unless defined?(::EltenEmbedded)

module Elten
  VERSION_STRING = "ELTEN 3.0 BETA 20"
  BRANCH = "beta"

  class << self
    def version
      VERSION_STRING
    end

    def window_title
      VERSION_STRING
    end

    def build_id
      return nil if !const_defined?(:BuildID, false)

      const_get(:BuildID)
    end

    def build_date
      return nil if !const_defined?(:BuildDate, false) || const_get(:BuildDate) == nil

      t = Time.at(const_get(:BuildDate))
      sprintf("%04d-%02d-%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.min)
    rescue Exception
      nil
    end

    def branch
      BRANCH
    end
  end
end

module EltenBoot
  HIDDEN_FLAGS = ["/hidden", "-hidden", "--hidden"]
  DEVELOPER_FLAGS = ["/developer", "-developer", "--developer", "/dev", "-dev", "--dev"]

  class << self
    def platform_tags
      return @platform_tags if @platform_tags != nil
      platform = ENV["ELTEN_LAUNCHER_PLATFORM"].to_s.downcase
      platform = "windows" if platform == "" && RUBY_PLATFORM =~ /mswin|mingw|cygwin/i
      platform = "osx" if platform == "" && RUBY_PLATFORM =~ /darwin/i
      tags = platform == "" ? [] : [platform.to_sym]
      arch = platform_architecture(platform)
      tags << "#{platform}-#{arch}".to_sym if platform != "" && arch != ""
      @platform_tags = tags.uniq
    end

    def platform?(name)
      platform_tags.include?(name.to_s.downcase.to_sym)
    end

    def configure_osx_dyld!
      return unless platform?(:osx)
      runtime_dir = File.join(app_root, "bin", "osx")
      return unless File.directory?(runtime_dir)

      changed = false
      ["DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH"].each do |key|
        entries = ENV[key].to_s.split(":").reject { |entry| entry.to_s == "" }
        next if entries.include?(runtime_dir)
        ENV[key] = ([runtime_dir] + entries).uniq.join(":")
        changed = true
      end

      return if ENV["ELTEN_OSX_DYLD_BOOTSTRAPPED"] == "1"
      return unless changed
      return if defined?(::EltenEmbedded)

      ENV["ELTEN_OSX_DYLD_BOOTSTRAPPED"] = "1"
      ENV["ELTEN_ROOT"] = app_root
      require "rbconfig"
      exec(RbConfig.ruby, File.join(app_root, "elten.rb"), *ARGV)
    end

    def configure_local_gems!
      return if launched_by_launcher?

      require "rbconfig"
      gem_dir = local_build_gem_dir
      return if gem_dir == nil || !File.directory?(gem_dir)

      ENV["GEM_HOME"] = gem_dir
      ENV["GEM_PATH"] = gem_dir
      ENV.delete("BUNDLE_PATH")
      ENV["BUNDLE_IGNORE_CONFIG"] = "1"
      Gem.use_paths(gem_dir, [gem_dir]) if defined?(Gem) && Gem.respond_to?(:use_paths)
    rescue Exception
    end

    def filelist_entry(line)
      text = line.to_s.strip
      return nil if text == "" || text.start_with?("#")
      file = text
      tags = []
      if text =~ /\A(.+?)(?:\s*):([A-Za-z][A-Za-z0-9_-]*)\s*\z/
        file = $1.to_s.strip
        tags = [$2.to_s.downcase.to_sym]
      end
      return nil if file == ""
      return nil if tags.size > 0 && (tags & platform_tags).empty?
      file
    end

    def early_datadir
      return @early_datadir if @early_datadir != nil
      datadir = datadir_argument
      datadir = File.join(".", "eltendata") if datadir == nil && portable?
      datadir = File.join(appdata, "elten") if datadir == nil
      @early_datadir = datadir
    end

    def startup_hidden?
      return @startup_hidden if @startup_hidden != nil
      @startup_hidden = ARGV.any? { |arg| hidden_flag?(arg) }
      @startup_hidden = command_line_args.any? { |arg| hidden_flag?(arg) } if @startup_hidden != true && platform?(:windows) && defined?(Fiddle)
      @startup_hidden
    rescue Exception
      @startup_hidden = false
    end

    def developer_mode?
      return @developer_mode if @developer_mode != nil
      return @developer_mode = true unless launched_by_launcher?
      @developer_mode = ARGV.any? { |arg| developer_flag?(arg) }
      @developer_mode = command_line_args.any? { |arg| developer_flag?(arg) } if @developer_mode != true && platform?(:windows) && defined?(Fiddle)
      @developer_mode
    rescue Exception
      @developer_mode = false
    end

    def launched_by_launcher?
      return @launched_by_launcher if @launched_by_launcher != nil
      @launched_by_launcher = defined?(::EltenEmbedded) != nil
    end

    def activate_existing_instance
      return false unless platform?(:windows)
      user32 = Fiddle.dlopen("user32")
      type_int = Fiddle::TYPE_INT
      type_ptr = Fiddle::TYPE_VOIDP
      find_window = Fiddle::Function.new(user32["FindWindowW"], [type_ptr, type_ptr], type_ptr)
      show_window = Fiddle::Function.new(user32["ShowWindow"], [type_ptr, type_int], type_int)
      set_foreground_window = Fiddle::Function.new(user32["SetForegroundWindow"], [type_ptr], type_int)
      set_active_window = Fiddle::Function.new(user32["SetActiveWindow"], [type_ptr], type_ptr)
      set_focus = Fiddle::Function.new(user32["SetFocus"], [type_ptr], type_ptr)
      hwnd = nil
      [Elten.window_title, "Elten"].uniq.each do |title|
        hwnd = find_window.call(wide_string("STATIC"), wide_string(title))
        break if hwnd != nil && hwnd.to_i != 0
      end
      return false if hwnd == nil || hwnd.to_i == 0
      show_window.call(hwnd, 5)
      show_window.call(hwnd, 9)
      set_foreground_window.call(hwnd)
      set_active_window.call(hwnd)
      set_focus.call(hwnd)
      true
    rescue Exception
      false
    end

    def command_line_text
      return ARGV.join(" ") unless platform?(:windows)
      kernel32 = Fiddle.dlopen("kernel32")
      get_command_line = Fiddle::Function.new(kernel32["GetCommandLineW"], [], Fiddle::TYPE_VOIDP)
      wide_pointer_to_utf8(get_command_line.call)
    rescue Exception
      ARGV.join(" ")
    end

    def wide_string(text)
      (text.to_s.encode("UTF-16LE") + [0].pack("S").force_encoding("UTF-16LE")).dup.force_encoding(Encoding::BINARY)
    end

    def create_window
      $elten_start_hidden = startup_hidden?
      return unless platform?(:windows)
      return if defined?($wnd) && $wnd != nil && $wnd != 0
      user32 = Fiddle.dlopen("user32")
      kernel32 = Fiddle.dlopen("kernel32")
      type_int = Fiddle::TYPE_INT
      type_ptr = Fiddle::TYPE_VOIDP
      get_module_handle = Fiddle::Function.new(kernel32["GetModuleHandleW"], [type_ptr], type_ptr)
      create_window_ex = Fiddle::Function.new(
        user32["CreateWindowExW"],
        [type_int, type_ptr, type_ptr, type_int, type_int, type_int, type_int, type_int, type_ptr, type_ptr, type_ptr, type_ptr],
        type_ptr
      )
      set_menu = Fiddle::Function.new(user32["SetMenu"], [type_ptr, type_ptr], type_int)
      show_window = Fiddle::Function.new(user32["ShowWindow"], [type_ptr, type_int], type_int)
      hwnd = create_window_ex.call(
        0,
        wide_string("STATIC"),
        wide_string(Elten.window_title),
        0x00CA0000,
        -2147483648,
        -2147483648,
        640,
        360,
        0,
        0,
        get_module_handle.call(nil),
        nil
      )
      return if hwnd == nil || hwnd == 0
      $wnd = hwnd.to_i
      set_menu.call($wnd, 0)
      show_window.call($wnd, 5) if $elten_start_hidden != true
    rescue Exception
    end

    private

    def datadir_argument
      args = command_line_args
      args = ARGV if args == nil || args.empty?
      args.each_with_index do |arg, index|
        text = arg.to_s
        return args[index + 1].to_s if text.downcase == "/datadir" && args[index + 1] != nil
        if text.downcase.start_with?("/datadir=")
          return text.split("=", 2)[1].to_s
        end
      end
      nil
    rescue Exception
      nil
    end

    def portable?
      in_section = false
      ini = File.join(app_root, "elten.ini")
      return false if !FileTest.exist?(ini)
      File.foreach(ini) do |line|
        text = line.to_s.strip
        if text =~ /^\[(.+)\]$/
          in_section = $1.to_s.casecmp("Elten") == 0
        elsif in_section && text =~ /^Portable\s*=\s*(.+)$/i
          return $1.to_i != 0
        end
      end
      false
    rescue Exception
      false
    end

    def appdata
      return File.join(Dir.home, "Library", "Application Support", "Elten") if EltenBoot.platform?(:osx)
      ENV["APPDATA"].to_s != "" ? ENV["APPDATA"] : File.join(Dir.home, "AppData", "Roaming")
    rescue Exception
      "."
    end

    def app_root
      ENV["ELTEN_ROOT"].to_s != "" ? ENV["ELTEN_ROOT"] : File.expand_path(__dir__)
    end

    def local_build_gem_dir
      runtime = local_build_runtime_dir
      return nil if runtime == nil

      api = defined?(RbConfig) ? RbConfig::CONFIG["ruby_version"].to_s : ""
      return nil if api == ""

      File.join(app_root, "build", runtime, "ruby", local_runtime_package, "lib", "ruby", "gems", api)
    end

    def local_build_runtime_dir
      if platform?(:windows)
        "launcher-windows-#{platform_architecture("windows")}"
      elsif platform?(:osx)
        "launcher-osx-#{platform_architecture("osx")}"
      end
    end

    def local_runtime_package
      if platform?(:windows)
        "windows-#{platform_architecture("windows")}"
      elsif platform?(:osx)
        "osx-#{platform_architecture("osx")}"
      end
    end

    def platform_architecture(platform)
      platform = platform.to_s.downcase
      cpu_key = platform == "windows" ? "target_cpu" : "host_cpu"
      cpu = defined?(RbConfig) ? RbConfig::CONFIG[cpu_key].to_s.downcase : ""
      cpu = RbConfig::CONFIG["host_cpu"].to_s.downcase if cpu == "" && defined?(RbConfig)
      cpu = RUBY_PLATFORM.to_s.downcase if cpu == ""
      return "arm64" if cpu =~ /arm64|aarch64/
      return "x64" if cpu =~ /x64|x86_64|amd64|64/
      "x86"
    rescue Exception
      [nil].pack("p").bytesize == 8 ? "x64" : "x86"
    end

    def hidden_flag?(arg)
      HIDDEN_FLAGS.include?(arg.to_s.downcase)
    end

    def developer_flag?(arg)
      DEVELOPER_FLAGS.include?(arg.to_s.downcase)
    end

    def command_line_args
      return ARGV unless EltenBoot.platform?(:windows)
      kernel32 = Fiddle.dlopen("kernel32")
      shell32 = Fiddle.dlopen("shell32")
      get_command_line = Fiddle::Function.new(kernel32["GetCommandLineW"], [], Fiddle::TYPE_VOIDP)
      command_line_to_argv = Fiddle::Function.new(shell32["CommandLineToArgvW"], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      local_free = Fiddle::Function.new(kernel32["LocalFree"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      argc = [0].pack("l")
      argv = command_line_to_argv.call(get_command_line.call, argc)
      return [] if argv == nil || argv.to_i == 0
      count = argc.unpack("l").first
      table = Fiddle::Pointer.new(argv.to_i)
      pointer_size = Fiddle::SIZEOF_VOIDP
      pointer_pack = pointer_size == 8 ? "Q" : "L"
      args = []
      for i in 0...count
        pointer = table[i * pointer_size, pointer_size].unpack(pointer_pack).first
        args << wide_pointer_to_utf8(pointer) if pointer != nil && pointer != 0
      end
      args
    ensure
      local_free.call(argv) if defined?(local_free) && argv != nil && argv.to_i != 0
    end

    def wide_pointer_to_utf8(pointer)
      ptr = Fiddle::Pointer.new(pointer.to_i)
      bytes = +""
      offset = 0
      loop do
        chunk = ptr[offset, 2]
        break if chunk == nil || chunk.bytesize < 2 || chunk == "\0\0"
        bytes << chunk
        offset += 2
      end
      bytes.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
    end
  end
end

class NoLauncherError < StandardError
end unless defined?(NoLauncherError)

unless Object.private_method_defined?(:get_stamp) || Kernel.private_method_defined?(:get_stamp)
  def get_stamp(*)
    raise NoLauncherError, "get_stamp is available only when Elten is started by the launcher"
  end
end

unless Object.private_method_defined?(:developer_mode?) || Kernel.private_method_defined?(:developer_mode?)
  def developer_mode?
    defined?($developer_mode) && $developer_mode == true
  end
end

unless Object.private_method_defined?(:launched_by_launcher?) || Kernel.private_method_defined?(:launched_by_launcher?)
  def launched_by_launcher?
    defined?(EltenBoot) && EltenBoot.launched_by_launcher?
  rescue Exception
    false
  end
end

boot_profile_path = nil
boot_profile_started = nil
boot_profile_events = []
boot_profile_requires = Hash.new { |hash, key| hash[key] = [0, 0.0] }
if ENV["ELTEN_BOOT_PROFILE"].to_s != ""
  boot_profile_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  value = ENV["ELTEN_BOOT_PROFILE"].to_s
  boot_profile_path = if value == "1" || value.casecmp("true") == 0
    File.join(root, "tmp", "elten-boot-profile.txt")
  else
    File.expand_path(value, root)
  end

  Kernel.module_eval do
    alias __elten_boot_profile_require require unless method_defined?(:__elten_boot_profile_require)

    def require(path)
      if defined?($elten_boot_profile_requires) && $elten_boot_profile_requires.is_a?(Hash)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          return __elten_boot_profile_require(path)
        ensure
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          entry = $elten_boot_profile_requires[path.to_s]
          entry[0] += 1
          entry[1] += elapsed
        end
      end
      __elten_boot_profile_require(path)
    end
  end
  $elten_boot_profile_requires = boot_profile_requires
end

write_boot_profile = lambda do |reason|
  next if boot_profile_path == nil

  total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - boot_profile_started
  FileUtils.mkdir_p(File.dirname(boot_profile_path)) rescue nil
  File.open(boot_profile_path, "wb") do |file|
    file.puts("Elten boot profile")
    file.puts("reason=#{reason}")
    file.puts("total_ms=#{(total * 1000).round(2)}")
    file.puts
    file.puts("Loaded files:")
    boot_profile_events.sort_by { |event| -event[1] }.each do |file_name, elapsed|
      file.puts(Kernel.sprintf("%8.2f ms  %s", elapsed * 1000, file_name))
    end
    file.puts
    file.puts("Requires:")
    boot_profile_requires.sort_by { |_name, stat| -stat[1] }.each do |name, stat|
      file.puts(Kernel.sprintf("%8.2f ms  %4d  %s", stat[1] * 1000, stat[0], name))
    end
  end
  warn("Elten boot profile written to #{boot_profile_path}")
end
boot_trace = lambda do |message|
  __elten_launcher_trace(message) if defined?(__elten_launcher_trace)
rescue Exception
end

verbose = $VERBOSE
$VERBOSE = nil
begin
  boot_trace.call("elten.rb before configure")
  EltenBoot.configure_osx_dyld!
  EltenBoot.configure_local_gems!
  Signal.trap("INT") { exit!(130) } if EltenBoot.platform?(:osx)
  boot_trace.call("elten.rb before require fiddle")
  require "fiddle"
  boot_trace.call("elten.rb after require fiddle")
  $commandline = EltenBoot.command_line_text
  $developer_mode = EltenBoot.developer_mode?
  $developer = $developer_mode
  boot_trace.call("elten.rb before activate_existing_instance")
  exit if EltenBoot.activate_existing_instance
  boot_trace.call("elten.rb before create_window")
  EltenBoot.create_window
  boot_trace.call("elten.rb after create_window")
ensure
  $VERBOSE = verbose
end

filelist_lines = if defined?(EltenEmbedded) && EltenEmbedded.respond_to?(:filelist_lines)
  EltenEmbedded.filelist_lines
else
  File.readlines(File.join(root, "filelist"))
end

deferred_main = nil

filelist_lines.each do |line|
  file = EltenBoot.filelist_entry(line)
  next if file == nil
  normalized_file = file.tr("\\", "/")
  if ENV["ELTEN_BOOT_STOP_BEFORE_MAIN"].to_s != "" && normalized_file.casecmp("src/main.rb") == 0
    write_boot_profile.call("before_main")
    exit
  end
  if EltenBoot.platform?(:osx) && normalized_file.casecmp("src/main.rb") == 0
    deferred_main = File.join(root, file.tr("/", File::SEPARATOR))
    next
  end
  if boot_profile_started != nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    load File.join(root, file.tr("/", File::SEPARATOR))
    boot_profile_events << [file, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
  else
    load File.join(root, file.tr("/", File::SEPARATOR))
  end
  EltenWindow.pump_messages if defined?(EltenWindow)
end

write_boot_profile.call("after_filelist")

if deferred_main != nil
  if EltenBoot.platform?(:osx) && defined?(EltenWindow) && EltenWindow.respond_to?(:run_appkit_main_loop)
    EltenWindow.ensure_window
    app_error = nil
    app_thread = Thread.new do
      begin
        load deferred_main
      rescue SystemExit => e
        app_error = e
      rescue Exception => e
        app_error = e
      ensure
        EltenWindow.request_appkit_exit if defined?(EltenWindow) && EltenWindow.respond_to?(:request_appkit_exit)
      end
    end
    EltenWindow.run_appkit_main_loop(app_thread)
    app_thread.join
    raise app_error if app_error != nil && !app_error.is_a?(SystemExit)
    raise app_error if app_error.is_a?(SystemExit)
  else
    load deferred_main
  end
end
