# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

require "fileutils"
require "tmpdir"

class Scene_Programs
  PROGRAM_LANGUAGE_FILTER_KEY = "ProgramsLanguageFilter"
  PROGRAM_LANGUAGE_FILTER_KNOWN_OR_ENGLISH = "known_or_english"
  PROGRAM_LANGUAGE_FILTER_KNOWN = "known"
  PROGRAM_LANGUAGE_FILTER_ALL = "all"

  def initialize(initial_action=nil)
    @initial_action=initial_action
  end

  def self.program_target(uuid)
    {"type"=>"program","uuid"=>uuid.to_s}
  end

  def main
    if program_launch_target?(@initial_action)
      target=@initial_action
      @initial_action=nil
      return launch_program(target)
    end
    @installed=Programs.local_entries
    @programs=[]
    @all=@installed
    rows=@all.map{|program| installed_row(program)}
     @sel=TableBox.new([p_("Programs", "Name"), p_("Programs", "Version"), p_("Programs", "Installation"), p_("Programs", "Status")], rows, index: 0, header: p_("Programs", "Installed programs"), quiet: false)
     @sel.bind_context{|menu|context(menu)}
     @refresh=false
     if @initial_action==:updates
       @initial_action=nil
       check_updates
       return main if @refresh
     end
     loop do
       loop_update
       @sel.update
         if @sel.selected? && @all.size>0
       program=@all[@sel.index]
         show_program_details(program)
loop_update
end
       return main if @refresh
       break if key_pressed?(:key_escape) or $scene!=self
     end
         $scene=Scene_Main.new if $scene==self
     end
     def context(menu)
       menu.option(p_("Programs", "Check for updates")) {
         check_updates
       }
       program=@all[@sel.index]
       if program==nil
         add_install_options(menu)
         return
       end
       menu.option(p_("Programs", "Details")) {
         show_program_details(program)
       }
       if program_loaded?(program)
         menu.option(p_("Programs", "Unload")) {
case           selector([p_("Programs", "Unload for this session only"), p_("Programs", "Unload and do not load automatically"), _("Cancel")], header: p_("Programs", "Unload program %{name}")%{:name=>program.name}, cancel_index: 2)
when 0
             unload_program_entry(program)
when 1
             unload_program_always(program)
           end
         }
       elsif program_loadable?(program)
         menu.option(p_("Programs", "Load")) {
           load_program_entry(program)
         }
         if program.respond_to?(:registered) && program.registered
           menu.option(p_("Programs", "Unload always")) {
             confirm(p_("Programs", "Keep program %{name} disabled?")%{:name=>program.name}) {
               unload_program_always(program)
             }
           }
         end
       end
       menu.option(p_("Programs", "Uninstall"), nil, :del) {
         case selector([p_("Programs", "Uninstall program"), p_("Programs", "Remove program and data"), _("Cancel")], header: p_("Programs", "What do you want to do with %{name}?")%{:name=>program.name}, cancel_index: 2, flags: 1)
         when 0
           confirm(p_("Programs", "Uninstall the program %{name}? The program data will be kept.")%{:name=>program.name}) {
             remove_program_entry(program, remove_data: false)
             alert(p_("Programs", "Program uninstalled."))
             @refresh=true
           }
         when 1
           confirm(p_("Programs", "Remove the program %{name} and all its data?")%{:name=>program.name}) {
             remove_program_entry(program, remove_data: true)
             alert(p_("Programs", "Program and data removed."))
             @refresh=true
           }
         end
       }
       if program_uuid(program)!=""
         menu.option(p_("Programs", "Add this program to quick actions"), nil, "q") {
           if QuickActions.create(Scene_Programs, program.name.to_s+" (#{p_("Programs", "Program")})", [Scene_Programs.program_target(program_uuid(program))])
             alert(p_("Programs", "Program added to quick actions"), false)
           else
             alert(_("Error"))
           end
         }
       end
       add_install_options(menu)
     end

     def add_install_options(menu)
       menu.option(p_("Programs", "Install new program from server"), nil, "i") {
         install_from_server
       }
       menu.option(p_("Programs", "Install new program from file"), nil, "I") {
         install_from_file
       }
     end

     def program_launch_target?(value)
       value.is_a?(Hash) && value["type"].to_s=="program" && value["uuid"].to_s!=""
     end

     def launch_program(target)
       uuid=target["uuid"].to_s.downcase
       program=uuid=="" ? nil : Programs.installed_entry_for_id(uuid)
       if program==nil
         alert(p_("Programs", "This program is no longer installed."))
         return finish_launch
       end
       if !program_loaded?(program)
         if program_loadable?(program)
           entry=program_realpath(program)
           if entry=="" || !Programs.load_sig(entry)
             alert(p_("Programs", "The program could not be launched."))
             return finish_launch
           end
         else
           alert(p_("Programs", "The program could not be launched."))
           return finish_launch
         end
       end
       cls=program_class_for_uuid(uuid)
       if cls==nil
         alert(p_("Programs", "The program could not be launched."))
         return finish_launch
       end
       $scene=cls.new
     end

     def program_class_for_uuid(uuid)
       uuid=uuid.to_s.downcase
       return nil if uuid==""
       Programs.list.find{|cls| cls.respond_to?(:app_uuid) && cls.app_uuid.to_s.downcase==uuid}
     end

     def finish_launch
       $scene=Scene_Main.new if $scene==self
     end

     def installed_row(program)
       [program.name.to_s, program.version.to_s, installation_label(program), status_label(program)]
     end

     def program_loaded?(program)
       program!=nil && program.respond_to?(:status) && program.status==:loaded
     end

     def program_loadable?(program)
       return false if program==nil || !program.respond_to?(:status)
       return false if program.status==:loaded
       return false if program.respond_to?(:id) && program.id.to_s==""
       program.status==:not_loaded
     end

     def load_program_entry(program)
       entry=program_realpath(program)
       if entry==nil || entry==""
         alert(p_("Programs", "Program could not be loaded."))
         return false
       end
       if Programs.load_sig(entry)
         setlocale(Configuration.language)
         alert(p_("Programs", "Program loaded."))
         @refresh=true
         true
       else
         alert(p_("Programs", "Program could not be loaded."))
         false
       end
     end

     def unload_program_entry(program)
       entry=program_realpath(program)
       if entry==nil || entry==""
         alert(p_("Programs", "Program could not be unloaded."))
         return false
       end
       if Programs.delete(entry)
         alert(p_("Programs", "Program unloaded."))
         @refresh=true
         true
       else
         alert(p_("Programs", "Program is not loaded."))
         false
       end
     end

     def unload_program_always(program)
       entry=program_realpath(program)
       if entry==nil || entry==""
         alert(p_("Programs", "Program could not be unloaded."))
         return false
       end
       Programs.set_entry_loaded(entry,false)
       Programs.delete(entry) if program_loaded?(program)
       alert(p_("Programs", "Program disabled."))
       @refresh=true
       true
     end

     def show_program_details(program)
       lines=[
         p_("Programs", "Name: %{name}")%{:name=>program.name.to_s},
         p_("Programs", "Version: %{version}")%{:version=>program.version.to_s},
         p_("Programs", "Build ID: %{build}")%{:build=>program.build_id.to_s},
         p_("Programs", "Author: %{author}")%{:author=>program.author.to_s},
         p_("Programs", "UUID: %{uuid}")%{:uuid=>program.respond_to?(:id) ? program.id.to_s : ""},
         p_("Programs", "Elten API: %{version}")%{:version=>program.respond_to?(:elten_api_version) ? program.elten_api_version.to_s : ""},
         p_("Programs", "Platforms: %{platforms}")%{:platforms=>program.respond_to?(:platforms) ? Array(program.platforms).join(", ") : ""},
         p_("Programs", "Installation: %{type}")%{:type=>installation_label(program)},
         p_("Programs", "Installed from: %{source}")%{:source=>installation_source_label(program)},
         p_("Programs", "Status: %{status}")%{:status=>status_label(program)},
         p_("Programs", "Size: %{size}")%{:size=>format_size(program.respond_to?(:size) ? program.size : 0)}
       ]
       lines.push(p_("Programs", "Installation time: %{time}")%{:time=>format_registry_time(program.installation_time)}) if program.respond_to?(:installation_time) && program.installation_time.to_i>0
       lines.push(p_("Programs", "Update time: %{time}")%{:time=>format_registry_time(program.update_time)}) if program.respond_to?(:update_time) && program.update_time.to_i>0
       lines.push(p_("Programs", "Folder ID: %{id}")%{:id=>program_storage_id(program)})
       lines.push(p_("Programs", "Loaded at startup: %{loaded}")%{:loaded=>program.respond_to?(:registry_loaded) && program.registry_loaded ? p_("Programs", "yes") : p_("Programs", "no")})
       lines.push(p_("Programs", "Entry: %{path}")%{:path=>program.respond_to?(:realpath) ? program.realpath.to_s : ""})
       lines.push(p_("Programs", "Path: %{path}")%{:path=>program_file_path(program)})
       lines.push(p_("Programs", "Source: %{path}")%{:path=>program_source_path(program)})
       lines.push(p_("Programs", "Data path: %{path}")%{:path=>program_data_path(program)})
       lines.push(p_("Programs", "Cache path: %{path}")%{:path=>program_cache_path(program)})
       if program.respond_to?(:signature_info) && program.signature_info.is_a?(Hash)
         lines.push(p_("Programs", "Signed by: %{subject}")%{:subject=>program.signature_info[:subject].to_s})
         lines.push(p_("Programs", "Signature fingerprint: %{fingerprint}")%{:fingerprint=>program.signature_info[:fingerprint].to_s})
       end
       lines.push(p_("Programs", "Error: %{error}")%{:error=>program.error.to_s}) if program.respond_to?(:error) && program.error.to_s!=""
       input_text(p_("Programs", "Program details"), flags: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly, text: lines.join("\n"), escapable: true)
     end

     def program_realpath(program)
       entry=program.respond_to?(:realpath) ? program.realpath.to_s : ""
       if entry==""
         found=Programs.installed_entry_for_id(program_uuid(program)) if program_uuid(program)!=""
         entry=found.realpath.to_s if found!=nil
       end
       entry
     end

     def program_file_path(program)
       entry=program_realpath(program)
       entry=="" ? "" : EltenPath.join(Dirs.apps,entry)
     end

     def program_source_path(program)
       path=program.respond_to?(:source_path) ? program.source_path.to_s : ""
       return path if path!=""
       file=program_file_path(program)
       return "" if file==""
       if File.file?(file)
         file
       elsif program.respond_to?(:main) && program.main.to_s!=""
         EltenPath.join(file,program.main.to_s)
       else
         file
       end
     end

     def program_data_path(program)
       id=program_storage_id(program)
       id=="" ? "" : EltenPath.join(Programs.apps_data_root,id)
     end

     def program_cache_path(program)
       id=program_storage_id(program)
       id=="" ? "" : EltenPath.join(Programs.apps_cache_root,id)
     end

     def program_storage_id(program)
       return program.storage_id.to_s if program.respond_to?(:storage_id) && program.storage_id.to_s!=""
       entry=program_realpath(program)
       entry.to_s=="" ? "" : Programs.entry_storage_id(entry)
     end

     def installation_label(program)
       case program.install_type
       when :signed_application_bundle
         p_("Programs", "signed application bundle")
       when :application_bundle
         p_("Programs", "application bundle")
       when :code_file
         p_("Programs", "code file")
       when :legacy
         p_("Programs", "legacy format")
       when :incompatible
         p_("Programs", "incompatible")
       else
         p_("Programs", "unknown")
       end
     end

     def installation_source_label(program)
       source=program.respond_to?(:installation_source) ? program.installation_source.to_s : ""
       case source
       when "server"
         p_("Programs", "server")
       when "file"
         p_("Programs", "file")
       when "autodetected", ""
         p_("Programs", "autodetection")
       else
         source
       end
     end

     def format_registry_time(value)
       time=value.to_i
       return "" if time<=0
       Time.at(time).strftime("%Y-%m-%d %H:%M:%S")
     rescue Exception
       value.to_s
     end

     def status_label(program)
       case program.status
       when :loaded
         p_("Programs", "loaded")
       when :not_loaded
         p_("Programs", "not loaded")
       when :unsupported_platform
         p_("Programs", "unsupported platform")
       when :developer_mode_only
         p_("Programs", "developer mode only")
       when :not_signed
         p_("Programs", "not signed")
       when :legacy
         p_("Programs", "unsupported legacy format")
       when :incompatible
         p_("Programs", "incompatible")
       when :invalid
         p_("Programs", "invalid")
       else
         program.status.to_s
       end
     end

     def install_from_server
       @installed=Programs.local_entries
       server_programs=fetch_server_programs
       if server_programs.empty?
         alert(p_("Programs", "No programs available."))
         return
       end
       @programs=filter_server_programs(server_programs)
       authors=@programs.map{|program|server_program_author(program)}.reject{|author|author==""}.uniq.polsort
       categories=[p_("Programs", "Featured")]+authors
       sel=ListBox.new(categories, header: p_("Programs", "Programs available on server"), index: 0, flags: 0, quiet: false)
       sel.disable_item(0) if !@programs.any?{|program|program.respond_to?(:recommended) && program.recommended}
       refresh_filter=proc do
         @programs=filter_server_programs(server_programs)
         authors=@programs.map{|program|server_program_author(program)}.reject{|author|author==""}.uniq.polsort
         sel.options=[p_("Programs", "Featured")]+authors
         sel.disable_item(0) if !@programs.any?{|program|program.respond_to?(:recommended) && program.recommended}
         sel.index=0
         sel.focus
       end
       sel.bind_context do |menu|
         server_program_language_filter_menu(menu) { refresh_filter.call }
       end
       loop do
         loop_update
         sel.update
         if sel.selected? || sel.expanded?
           category=sel.index==0 ? :featured : authors[sel.index-1]
           if install_server_category(category)
             @refresh=true
             return
           end
           sel.focus
         end
         break if key_pressed?(:key_escape)
       end
     end

     def server_row(program)
       [
         program.name.to_s,
         program.version.to_s,
         program.description.to_s,
         server_program_author(program),
         server_status_label(program),
         format_size(program.size)
       ]
     end

     def install_server_category(category)
       programs=if category==:featured
         @programs.select{|program|program.respond_to?(:recommended) && program.recommended}
       else
         @programs.select{|program|server_program_author(program)==category.to_s}
       end
       programs=programs.sort_by{|program|program.name.to_s.downcase}
       return false if programs.empty?
       header=category==:featured ? p_("Programs", "Featured programs") : p_("Programs", "Programs by %{author}")%{:author=>category.to_s}
       rows=programs.map{|program|server_row(program)}
       sel=TableBox.new(
         [p_("Programs", "Name"), p_("Programs", "Version"), p_("Programs", "Description"), p_("Programs", "Author"), p_("Programs", "Status"), p_("Programs", "Size")],
         rows,
         index: 0,
         header: header,
         quiet: false
       )
       sel.focus
       loop do
         loop_update
         sel.update
         if sel.selected?
           program=programs[sel.index]
           return true if program!=nil && install_remote_program(program, ask: true)
         end
         break if key_pressed?(:key_escape) || sel.collapsed?
       end
       false
     end

     def server_status_label(program)
       installed=installed_program_for(program)
       if !remote_program_api_compatible?(program)
         p_("Programs", "requires Elten API %{version}")%{:version=>program.elten_api_version.to_s}
       elsif installed==nil
         p_("Programs", "not installed")
       elsif update_available?(installed, program)
         p_("Programs", "update available")
       else
         p_("Programs", "installed")
       end
     end

     def server_program_author(program)
       if program.respond_to?(:owner)
         uploader=program.owner.to_s
         return uploader if uploader!=""
       end
       program.respond_to?(:author) ? program.author.to_s : ""
     end

     def server_program_language_filter
       mode=LocalConfig[PROGRAM_LANGUAGE_FILTER_KEY, PROGRAM_LANGUAGE_FILTER_KNOWN_OR_ENGLISH, type: :string]
       [PROGRAM_LANGUAGE_FILTER_KNOWN_OR_ENGLISH, PROGRAM_LANGUAGE_FILTER_KNOWN, PROGRAM_LANGUAGE_FILTER_ALL].include?(mode) ? mode : PROGRAM_LANGUAGE_FILTER_KNOWN_OR_ENGLISH
     end

     def filter_server_programs(programs)
       mode=server_program_language_filter
       return Array(programs) if mode==PROGRAM_LANGUAGE_FILTER_ALL
       known=Session.languages.to_s.split(",").filter_map{|language|normalize_server_program_language(language)}.uniq
       known.push("en") if mode==PROGRAM_LANGUAGE_FILTER_KNOWN_OR_ENGLISH && !known.include?("en")
       Array(programs).select do |program|
         !(server_program_languages(program)&known).empty?
       end
     end

     def server_program_languages(program)
       languages=[]
       if program.respond_to?(:supported_languages)
         languages.concat(Array(program.supported_languages))
       end
       languages.push(program.main_language) if program.respond_to?(:main_language)
       languages.filter_map{|language|normalize_server_program_language(language)}.uniq
     end

     def normalize_server_program_language(language)
       match=/\A([a-zA-Z]{2})(?:[-_][a-zA-Z]{2})?\z/.match(language.to_s.strip)
       match==nil ? nil : match[1].downcase
     end

     def server_program_language_filter_menu(menu, &on_change)
       menu.submenu(p_("Programs", "Language filter")) do |submenu|
         [
           [PROGRAM_LANGUAGE_FILTER_KNOWN_OR_ENGLISH, p_("Programs", "Hide programs in foreign languages except English")],
           [PROGRAM_LANGUAGE_FILTER_KNOWN, p_("Programs", "Hide all programs in unknown languages")],
           [PROGRAM_LANGUAGE_FILTER_ALL, p_("Programs", "Show all programs, including those in unknown languages")]
         ].each do |mode,label|
           submenu.option(label) do
             LocalConfig[PROGRAM_LANGUAGE_FILTER_KEY]=mode
             on_change.call if on_change!=nil
           end
         end
       end
     end

     def check_updates
       @installed=Programs.local_entries
       @programs=fetch_server_programs
       updates=available_updates
       if updates.empty?
         alert(p_("Programs", "All installed programs are up to date."))
         return
       end
       lines=[p_("Programs", "Updates available:"), ""]
       updates.each do |installed, remote|
         lines.push("#{remote.name} #{installed.version} -> #{remote.version}")
       end
       lines.push("", p_("Programs", "Do you want to update all programs now?"))
       confirm(lines.join("\n")) do
         ok=0
         failed=[]
         updates.each do |_installed, remote|
           if install_remote_program(remote, ask: false)
             ok+=1
           else
             failed.push(remote.name)
           end
         end
         @refresh=true if ok>0
         if failed.empty?
           alert(p_("Programs", "Updates installed."))
         else
           alert(p_("Programs", "Some updates could not be installed: %{names}")%{:names=>failed.join(", ")})
         end
       end
     end

     def fetch_server_programs
       EltenLink::Apps.list(elten_link, os: platform_target)
     rescue EltenLink::Error => e
       Log.warning("Apps list failed: #{e.message}")
       alert(p_("Programs", "The list of programs could not be loaded."))
       []
     end

     def available_updates
       updates=[]
       @installed.each do |installed|
         next if program_uuid(installed)==""
         remote=@programs.find{|program| same_program?(installed,program)}
         updates.push([installed,remote]) if remote!=nil && update_available?(installed,remote)
       end
       updates
     end

     def update_available?(installed, remote)
       return false if installed==nil || remote==nil
       return false if !remote_program_api_compatible?(remote)
       if installed.respond_to?(:build_id) && remote.respond_to?(:build_id) && build_id_present?(installed.build_id) && build_id_present?(remote.build_id)
         normalize_build_id(installed.build_id)!=normalize_build_id(remote.build_id)
       else
         installed.version.to_s!=remote.version.to_s
       end
     end

     def normalize_build_id(value)
       return nil if value == nil

       text=value.to_s.strip
       return nil if text=="" || text=="0"

       text
     end

     def build_id_present?(value)
       normalize_build_id(value)!=nil
     end

     def remote_program_api_compatible?(program)
       program!=nil && program.respond_to?(:elten_api_version) && Programs.api_version_compatible?(program.elten_api_version)
     end

     def install_remote_program(program, ask: true)
       return false if program==nil
       if !remote_program_api_compatible?(program)
         alert(p_("Programs", "This program requires Elten API %{required}. The current Elten API version is %{current}.")%{
           :required=>program.elten_api_version.to_s,
           :current=>Programs.elten_api_version
         }) if ask
         return false
       end
       if ask
         confirmed=false
         confirm(install_details(program, format_size(program.size), nil)) { confirmed=true }
         return false if !confirmed
       end
       return false if !confirm_unverified_program_install(program)
       tempfile=nil
       tempdir=nil
       installed_entry=nil
       install_error=nil
       cancelled=false
       begin
         waiting
         tempdir=Dir.mktmpdir(["elten-program-", ""], Dirs.temp)
         tempfile=EltenPath.join(tempdir, Programs.remote_package_filename(program))
         package_url=EltenLink::Apps.package_url(program)
         download_file(package_url, tempfile, use_waiting: false, can_cancel: true, override: true)
         if !FileTest.exists?(tempfile)
           cancelled=true
         else
           waiting_end
           installed_entry=Programs.install_package(tempfile,
             preferred_program: program, installation_source: "server")
         end
       rescue Exception => e
         Log.warning("Program installation failed: #{e.class}: #{e.message}")
         install_error=e
       ensure
         waiting_end rescue nil
         begin
           if tempdir!=nil && File.directory?(tempdir)
             FileUtils.remove_entry(tempdir)
           elsif tempfile!=nil && FileTest.exists?(tempfile)
             File.delete(tempfile)
           end
         rescue Exception => e
           Log.warning("Program package cleanup failed: #{e.class}: #{e.message}")
         end
       end
       if installed_entry!=nil
         alert(p_("Programs", "Installation completed.")) if ask
         setlocale(Configuration.language)
         true
       elsif install_error!=nil
         alert(program_install_error_message(install_error)) if ask
         false
       else
         alert(p_("Programs", "Installation cancelled.")) if ask && cancelled
         false
       end
     end

     def confirm_unverified_program_install(program)
       return true if installed_program_for(program)!=nil
       return true if program.respond_to?(:verified?) && program.verified? == true

       confirmed=false
       confirm(unverified_program_warning(program)) { confirmed=true }
       confirmed
     end

     def unverified_program_warning(program)
       p_("Programs", "Warning! The program %{name} was released by 3rd party developer. It will have access to your computer, including your files and data. Install programs only from publishers you trust. Do you want to continue?")%{
         :name=>program.name.to_s
       }
     end

     def install_from_file
       file=get_file(p_("Programs", "Select program package"), path: EltenPath.with_separator(Dirs.documents), save: false, extensions: [".eltsetup"])
       return if file==nil || file==""
       if File.extname(file).downcase!=".eltsetup"
         alert(p_("Programs", "The selected file is not an Elten program package."))
         return
       end
       begin
         info=Programs.setup_package_info(file)
       rescue Exception => e
         Log.warning("Program package read failed: #{e.class}: #{e.message}")
         alert(program_install_error_message(e))
         return
       end
       confirm(install_details(info[:manifest], format_size(info[:size]), File.basename(file))) {
         install_package_file(file, info)
       }
     end

     def install_package_file(file, info=nil)
       waiting
       installed_entry=nil
       install_error=nil
       begin
         info=Programs.setup_package_info(file) if info==nil
         installed_entry=Programs.install_package(file, info: info, installation_source: "file")
       rescue Exception => e
         Log.warning("Program local installation failed: #{e.class}: #{e.message}")
         install_error=e
       ensure
         waiting_end
       end
       if installed_entry!=nil
         alert(p_("Programs", "Installation completed."))
         setlocale(Configuration.language)
         @refresh=true
       elsif install_error!=nil
         alert(program_install_error_message(install_error))
       else
         alert(p_("Programs", "Installation cancelled."))
       end
     end

     def install_details(program, size, package_file=nil)
       lines=[p_("Programs", "Do you want to install this program?"), ""]
       lines.push(p_("Programs", "Name: %{name}")%{:name=>program.name.to_s}) if program.respond_to?(:name)
       lines.push(p_("Programs", "Description: %{description}")%{:description=>program.description.to_s}) if program.respond_to?(:description) && program.description.to_s!=""
       lines.push(p_("Programs", "Version: %{version}")%{:version=>program.version.to_s}) if program.respond_to?(:version)
       lines.push(p_("Programs", "Build ID: %{build}")%{:build=>program.build_id.to_s}) if program.respond_to?(:build_id)
       author=program.respond_to?(:owner) ? server_program_author(program) : (program.respond_to?(:author) ? program.author.to_s : "")
       lines.push(p_("Programs", "Author: %{author}")%{:author=>author}) if author!=""
       lines.push(p_("Programs", "Elten API: %{version}")%{:version=>program.elten_api_version.to_s}) if program.respond_to?(:elten_api_version)
       if program.respond_to?(:platforms)
         lines.push(p_("Programs", "Platforms: %{platforms}")%{:platforms=>Array(program.platforms).join(", ")})
       end
       lines.push(p_("Programs", "Package: %{file}")%{:file=>package_file.to_s}) if package_file!=nil && package_file.to_s!=""
       lines.push(p_("Programs", "Size: %{size}")%{:size=>size.to_s})
       lines.join("\n")
     end

     def program_install_error_message(error)
       if (specific=program_install_error_cause(error, Programs::UnsupportedAPIVersionError))!=nil
         return p_("Programs", "This program requires Elten API %{required}. The current Elten API version is %{current}.")%{
           :required=>specific.required,
           :current=>specific.current
         }
       end
       if (specific=program_install_error_cause(error, Programs::UnsupportedEltenLinkContractError))!=nil
         return p_("Programs", "This program requires EltenLink contract %{required}. The current contract version is %{current}.")%{
           :required=>specific.required,
           :current=>specific.current
         }
       end
       if (specific=program_install_error_cause(error, Programs::UnsupportedPlatformError))!=nil
         return p_("Programs", "This program does not support the current platform %{current}. Supported platforms: %{required}.")%{
           :current=>specific.current,
           :required=>specific.required.join(", ")
         }
       end
       if program_install_error_cause(error, Programs::ProgramSigning::VerificationUnavailableError)!=nil
         return p_("Programs", "The program package signature cannot be verified because trusted signing information is unavailable.")
       end
       if program_install_error_cause(error, Programs::ProgramSigning::MissingSignatureError)!=nil
         return p_("Programs", "The program package is not signed.")
       end
       if (specific=program_install_error_cause(error, Programs::ProgramSigning::SignatureError))!=nil
         return p_("Programs", "The program package signature could not be verified: %{reason}")%{
           :reason=>program_install_error_detail(specific)
         }
       end
       p_("Programs", "The program could not be installed: %{reason}")%{
         :reason=>program_install_error_detail(error)
       }
     end

     def program_install_error_cause(error, klass)
       current=error
       seen={}
       while current!=nil && !seen[current.object_id]
         return current if current.is_a?(klass)
         seen[current.object_id]=true
         current=current.respond_to?(:cause) ? current.cause : nil
       end
       nil
     end

     def program_install_error_detail(error)
       detail=error.respond_to?(:message) ? error.message.to_s : error.to_s
       detail=error.class.to_s if detail=="" && error!=nil
       detail.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
     rescue Exception
       p_("Programs", "Unknown error")
     end

     def format_size(size)
       size=size.to_i
       if size>1024**3
         (((size*100.0/1024**3).round)/100.0).to_s+"GB"
       elsif size>1024**2
         (((size*100.0/1024**2).round)/100.0).to_s+"MB"
       elsif size>1024
         (((size*100.0/1024).round)/100.0).to_s+"kB"
       else
         size.to_s+"B"
       end
     end

     def program_uuid(program)
       return "" if program==nil || !program.respond_to?(:id)
       program.id.to_s.downcase
     end

     def same_program?(a,b)
       aid=program_uuid(a)
       bid=program_uuid(b)
       return aid==bid if aid!="" && bid!=""
       a!=nil && b!=nil && a.path.to_s==b.path.to_s && a.author.to_s==b.author.to_s && a.name.to_s==b.name.to_s
     end

     def installed_program_for(program)
       (@installed||=Programs.local_entries).find{|entry| same_program?(entry,program)}
     end

     def remote_program_for(program)
       @programs.find{|entry| same_program?(entry,program)}
     end

     def remove_program_entry(program, remove_data: false)
       entry=program.respond_to?(:realpath) ? program.realpath : nil
       if entry==nil || entry==""
         found=Programs.installed_entry_for_id(program_uuid(program)) if program_uuid(program)!=""
         entry=found.realpath if found!=nil
       end
       storage_id=program_storage_id(program)
       if entry!=nil && entry!=""
         Programs.set_entry_loaded(entry,false)
         Programs.delete(entry, reason: :uninstall)
       end
       Programs.cleanup_uninstalled_program(storage_id, entry: entry, remove_data: remove_data)
     end

  end
  
class Struct_Programs_Program
    attr_accessor :id, :name, :size, :version, :build_id, :author, :path
    attr_reader :realpath
def self.load(path)
  entry=Programs.installed_entry(path)
  return nil if entry==nil
  new(entry.path, entry.name, entry.version, entry.author, entry.size, entry.realpath, entry.build_id, entry.id)
end
def initialize(path, name, version, author, size, realpath=nil, build_id=nil, id="")
  @id=id.to_s
  @realpath=realpath
  @name=name
  @version=version
  @build_id=normalize_build_id(build_id)
  @author=author
  @size=size.to_i
  @path=path
  end
def normalize_build_id(value)
  return nil if value==nil
  text=value.to_s.strip
  return nil if text=="" || text=="0"
  text
end
end
