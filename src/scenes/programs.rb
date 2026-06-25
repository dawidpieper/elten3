# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2023 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

class Scene_Programs
  def initialize(initial_action=nil)
    @initial_action=initial_action
  end

  def main
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
       menu.option(p_("Programs", "Install from file")) {
         install_from_file
       }
       menu.option(p_("Programs", "Install from server")) {
         install_from_server
       }
       menu.option(p_("Programs", "Check for updates")) {
         check_updates
       }
       program=@all[@sel.index]
       return if program==nil
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
           confirm(p_("Programs", "Uninstall program %{name}? Program data will be kept.")%{:name=>program.name}) {
             remove_program_entry(program, remove_data: false)
             alert(p_("Programs", "Program uninstalled."))
             @refresh=true
           }
         when 1
           confirm(p_("Programs", "Remove program %{name} and all its data?")%{:name=>program.name}) {
             remove_program_entry(program, remove_data: true)
             alert(p_("Programs", "Program and data removed."))
             @refresh=true
           }
         end
       }
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
       lines.push(p_("Programs", "Installation source path: %{path}")%{:path=>program.installation_source_path.to_s}) if program.respond_to?(:installation_source_path) && program.installation_source_path.to_s!=""
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
       @programs=fetch_server_programs
       if @programs.empty?
         alert(p_("Programs", "No programs available."))
         return
       end
       rows=@programs.map{|program| server_row(program)}
       sel=TableBox.new([p_("Programs", "Name"), p_("Programs", "Version"), p_("Programs", "Status"), p_("Programs", "Size")], rows, index: 0, header: p_("Programs", "Programs available on server"), quiet: false)
       loop do
         loop_update
         sel.update
         if sel.selected?
           program=@programs[sel.index]
           if program!=nil && install_remote_program(program, ask: true)
             @refresh=true
             return
           end
         end
         break if key_pressed?(:key_escape)
       end
     end

     def server_row(program)
       [program.name.to_s, program.version.to_s, server_status_label(program), format_size(program.size)]
     end

     def server_status_label(program)
       installed=installed_program_for(program)
       if installed==nil
         p_("Programs", "not installed")
       elsif update_available?(installed, program)
         p_("Programs", "update available")
       else
         p_("Programs", "installed")
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
       alert(p_("Programs", "Programs list could not be loaded."))
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

     def install_remote_program(program, ask: true)
       return false if program==nil
       if ask
         installed=false
         confirm(install_details(program, format_size(program.size), nil)) do
           installed=install_remote_program(program, ask: false)
         end
         return installed
       end
       tempfile=nil
       installed_entry=nil
       begin
         waiting
         tempfile=EltenPath.join(Dirs.temp, safe_install_base(program.path)+".eltsetup")
         package_url=EltenLink::Apps.package_url(program)
         download_file(package_url, tempfile, use_waiting: false, can_cancel: true, override: true)
         if !FileTest.exists?(tempfile)
           waiting_end
           alert(p_("Programs", "Installation canceled.")) if ask
           return false
         end
         waiting_end
         installed_entry=install_downloaded_package(tempfile, program, installation_source: "server", installation_source_path: package_url)
       rescue Exception => e
         Log.warning("Program installation failed: #{e.class}: #{e.message}")
       ensure
         waiting_end rescue nil
         begin
           File.delete(tempfile) if tempfile!=nil && FileTest.exists?(tempfile)
         rescue Exception => e
           Log.warning("Program package cleanup failed: #{e.class}: #{e.message}")
         end
       end
       if installed_entry!=nil
         alert(p_("Programs", "Installation completed.")) if ask
         setlocale(Configuration.language)
         true
       else
         alert(p_("Programs", "Installation canceled.")) if ask
         false
       end
     end

     def install_downloaded_package(file, preferred_program=nil, installation_source: nil, installation_source_path: nil)
       if Programs::EltenAppPackage.package?(file)
         package=Programs::EltenAppPackage.new(file)
         existing=installed_entry_for_manifest(package.manifest)
         destination=eltenapp_install_path(file,package.manifest,existing,preferred_program)
         install_eltenapp_package(file,destination,existing,installation_source: installation_source, installation_source_path: installation_source_path)
       else
         info=Programs.setup_package_info(file)
         existing=installed_entry_for_setup_info(info)
         destination=install_destination_for_info(file,info,existing,preferred_program)
         install_setup_package(file,destination,existing,info,installation_source: installation_source, installation_source_path: installation_source_path)
       end
     end
     def install_from_file
       file=get_file(p_("Programs", "Select program package"), path: EltenPath.with_separator(Dirs.documents), save: false, extensions: [".eltsetup"])
       return if file==nil || file==""
       if File.extname(file).downcase!=".eltsetup"
         alert(p_("Programs", "Invalid program package."))
         return
       end
       begin
         info=Programs.setup_package_info(file)
       rescue Exception => e
         Log.warning("Program package read failed: #{e.class}: #{e.message}")
         alert(p_("Programs", "Invalid program package."))
         return
       end
       confirm(install_details(info[:manifest], format_size(info[:size]), File.basename(file))) {
         install_package_file(file, info)
       }
     end

     def install_package_file(file, info=nil)
       waiting
       installed_entry=nil
       begin
         info=Programs.setup_package_info(file) if info==nil
         existing=installed_entry_for_setup_info(info)
         destination=install_destination_for_info(file,info,existing)
         installed_entry=install_setup_package(file,destination,existing,info,installation_source: "file", installation_source_path: file)
       rescue Exception => e
         Log.warning("Program local installation failed: #{e.class}: #{e.message}")
       ensure
         waiting_end
       end
       if installed_entry!=nil
         alert(p_("Programs", "Installation completed."))
         setlocale(Configuration.language)
         @refresh=true
       else
         alert(p_("Programs", "Installation canceled."))
       end
     end

     def install_details(program, size, package_file=nil)
       lines=[p_("Programs", "Do you want to install this program?"), ""]
       lines.push(p_("Programs", "Name: %{name}")%{:name=>program.name.to_s}) if program.respond_to?(:name)
       lines.push(p_("Programs", "Version: %{version}")%{:version=>program.version.to_s}) if program.respond_to?(:version)
       lines.push(p_("Programs", "Build ID: %{build}")%{:build=>program.build_id.to_s}) if program.respond_to?(:build_id)
       lines.push(p_("Programs", "Author: %{author}")%{:author=>program.author.to_s}) if program.respond_to?(:author)
       lines.push(p_("Programs", "Elten API: %{version}")%{:version=>program.elten_api_version.to_s}) if program.respond_to?(:elten_api_version)
       if program.respond_to?(:platforms)
         lines.push(p_("Programs", "Platforms: %{platforms}")%{:platforms=>Array(program.platforms).join(", ")})
       end
       lines.push(p_("Programs", "Package: %{file}")%{:file=>package_file.to_s}) if package_file!=nil && package_file.to_s!=""
       lines.push(p_("Programs", "Size: %{size}")%{:size=>size.to_s})
       lines.join("\n")
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

     def extract_setup_package(zip,destination)
       Programs.zip_entries(zip).each do |entry|
         name=Programs.safe_zip_entry_name(entry)
         next if name=="__manifest.json"
         target=EltenPath.join(destination,name)
         if Programs.zip_directory_entry?(entry)
            FileUtils.mkdir_p(target)
          else
            Programs.zip_extract(entry,target)
          end
        end
      end

     def install_setup_package(file,destination,existing_entry=nil,info=nil,installation_source: nil, installation_source_path: nil)
       info=Programs.setup_package_info(file) if info==nil
       return install_setup_single_file_package(file,destination,existing_entry,info,installation_source: installation_source, installation_source_path: installation_source_path) if info[:single_file]
       staging=unique_install_path("staging")
       backups=[]
       replaced=false
       begin
         FileUtils.mkdir_p(staging)
         Programs.open_zip(file) { |zip| extract_setup_package(zip,staging) }
         Programs.discover_folder_source(File.basename(destination),staging)
         replace_destination_with_staging(staging,destination,existing_entry,backups)
         replaced=true
         entry=EltenPath.relative_from(destination,Dirs.apps)
         activate_installed_entry(entry,existing_entry,destination,backups,installation_source: installation_source, installation_source_path: installation_source_path)
       rescue Exception => e
         Log.warning("Program setup installation failed: #{e.class}: #{e.message}")
         rollback_install(destination,backups,existing_entry,replaced)
         nil
       ensure
         remove_install_path(staging)
       end
     end

     def install_setup_single_file_package(file,destination,existing_entry,info,installation_source: nil, installation_source_path: nil)
       staging=unique_install_path("staging")+".eltenapp"
       begin
         Programs.open_zip(file) do |zip|
           entry=Programs.zip_entries(zip).find{|zip_entry| Programs.normalize_entry_name(zip_entry.name)==info[:entry]}
           raise RuntimeError, "Missing setup eltenapp payload" if entry==nil
           Programs.zip_extract(entry,staging)
         end
         install_eltenapp_package(staging,destination,existing_entry,installation_source: installation_source, installation_source_path: installation_source_path)
       rescue Exception => e
         Log.warning("Program single-file setup installation failed: #{e.class}: #{e.message}")
         nil
       ensure
         remove_install_path(staging)
       end
     end

     def install_eltenapp_package(file,destination,existing_entry=nil,installation_source: nil, installation_source_path: nil)
       backups=[]
       replaced=false
       begin
         Programs::EltenAppPackage.new(file)
         backup_install_path(destination,backups)
         backup_existing_entry(existing_entry,destination,backups)
         FileUtils.mkdir_p(File.dirname(destination))
         FileUtils.mv(file,destination)
         replaced=true
         entry=EltenPath.relative_from(destination,Dirs.apps)
         activate_installed_entry(entry,existing_entry,destination,backups,installation_source: installation_source, installation_source_path: installation_source_path)
       rescue Exception => e
         Log.warning("Program eltenapp installation failed: #{e.class}: #{e.message}")
         rollback_install(destination,backups,existing_entry,replaced)
         nil
       end
     end

     def replace_destination_with_staging(staging,destination,existing_entry,backups)
       backup_install_path(destination,backups)
       backup_existing_entry(existing_entry,destination,backups)
       FileUtils.mkdir_p(File.dirname(destination))
       FileUtils.mv(staging,destination)
     end

     def activate_installed_entry(entry,existing_entry,destination,backups,installation_source: nil, installation_source_path: nil)
       Programs.delete(existing_entry) if existing_entry!=nil
       Programs.delete(entry) if existing_entry==nil || existing_entry!=entry
       if Programs.load_sig(entry, installation_source: installation_source, installation_source_path: installation_source_path)
         cleanup_install_backups(backups)
         entry
       else
         Log.warning("Program registration failed after installation: #{entry}")
         Programs.delete(entry)
         rollback_install(destination,backups,existing_entry,true)
         nil
       end
     end

     def rollback_install(destination,backups,existing_entry=nil,replaced=false)
       remove_install_path(destination) if replaced
       backups.reverse_each do |original,backup|
         next if !File.exist?(backup)
         FileUtils.mkdir_p(File.dirname(original))
         remove_install_path(original)
         FileUtils.mv(backup,original)
       end
       Programs.load_sig(existing_entry) if existing_entry!=nil && File.exist?(EltenPath.join(Dirs.apps,existing_entry))
     rescue Exception => e
       Log.warning("Program installation rollback failed: #{e.class}: #{e.message}")
     end

     def backup_existing_entry(existing_entry,destination,backups)
       return if existing_entry==nil || existing_entry==""
       existing_path=EltenPath.join(Dirs.apps,existing_entry)
       return if same_install_path?(existing_path,destination)
       backup_install_path(existing_path,backups)
     end

     def backup_install_path(path,backups)
       return if path==nil || path=="" || !File.exist?(path)
       backup=unique_install_path("backup")
       FileUtils.mv(path,backup)
       backups.push([path,backup])
     end

     def cleanup_install_backups(backups)
       backups.each{|_original,backup| remove_install_path(backup)}
     end

     def remove_install_path(path)
       return if path==nil || path=="" || !File.exist?(path)
       FileUtils.rm_rf(path)
     rescue Exception => e
       Log.warning("Program install path cleanup failed for #{path}: #{e.class}: #{e.message}")
     end

     def unique_install_path(prefix)
       base=EltenPath.join(Dirs.apps,".#{prefix}-#{Time.now.to_i}-#{rand(36**6).to_s(36)}")
       path=base
       i=0
       while File.exist?(path)
         i+=1
         path="#{base}-#{i}"
       end
       path
     end

     def same_install_path?(a,b)
       File.expand_path(a.to_s).tr("\\","/").downcase==File.expand_path(b.to_s).tr("\\","/").downcase
     rescue Exception
       a.to_s==b.to_s
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
       @installed.find{|entry| same_program?(entry,program)}
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
         remove_install_path(EltenPath.join(Dirs.apps,entry))
         Programs.delete(entry)
       end
       if remove_data && storage_id!=""
         remove_install_path(EltenPath.join(Programs.apps_data_root,storage_id))
         remove_install_path(EltenPath.join(Programs.apps_cache_root,storage_id))
         Programs.remove_registry_storage(storage_id)
       end
     end

     def installed_entry_for_manifest(manifest)
       entry=Programs.installed_entry_for_id(manifest.id)
       entry!=nil ? entry.realpath : nil
     end

     def installed_entry_for_setup_info(info)
       installed_entry_for_manifest(info[:manifest])
     end

     def install_destination_for_info(file,info,existing_entry=nil,preferred_program=nil)
       if info[:single_file]
         eltenapp_install_path(file,info[:manifest],existing_entry,preferred_program,info[:entry])
       else
         folder_install_path(file,info[:payload],existing_entry,preferred_program,info[:entry],info[:manifest])
       end
     end

     def eltenapp_install_path(file,manifest,existing_entry=nil,preferred_program=nil,entry_name=nil)
       base=safe_install_base(entry_name)
       base=safe_install_base(preferred_program.path) if base=="program" && preferred_program!=nil && preferred_program.respond_to?(:path)
       base=safe_install_base(manifest.name) if base=="program" && manifest!=nil
       base=safe_install_base(File.basename(file,File.extname(file))) if base=="program"
       available_install_path(EltenPath.join(Dirs.apps,base+".eltenapp"),existing_entry,manifest==nil ? "" : manifest.id)
     end

     def folder_install_path(file,payload,existing_entry=nil,preferred_program=nil,entry_name=nil,manifest=nil)
       base=safe_install_base(payload["path"]) if payload.is_a?(Hash)
       base=safe_install_base(preferred_program.path) if (base==nil || base=="program") && preferred_program!=nil && preferred_program.respond_to?(:path)
       base=safe_install_base(File.basename(entry_name.to_s,File.extname(entry_name.to_s))) if (base==nil || base=="program") && entry_name!=nil
       base=safe_install_base(File.basename(file,File.extname(file))) if base==nil || base=="program"
       available_install_path(EltenPath.join(Dirs.apps,base),existing_entry,manifest==nil ? "" : manifest.id)
     end

     def safe_install_base(value)
       base=Programs.normalize_entry_name(value.to_s)
       base=value.to_s if base==nil
       base=File.basename(base)
       base=File.basename(base,File.extname(base)) if File.extname(base).downcase==".eltenapp" || File.extname(base).downcase==".eltsetup"
       base=base.gsub(/[\\\/:*?"<>|]/,"_").strip
       base="program" if base=="" || base=="." || base==".."
       base
     end

     def available_install_path(desired,existing_entry=nil,desired_uuid="")
       existing_path=existing_entry==nil ? nil : EltenPath.join(Dirs.apps,existing_entry)
       return desired if existing_path!=nil && same_install_path?(desired,existing_path)
       return desired if !File.exist?(desired) && !registry_path_conflict?(desired,desired_uuid)
       ext=File.extname(desired)
       base=ext=="" ? desired : desired[0...-ext.length]
       i=1
       loop do
         candidate=ext=="" ? "#{base}(#{i})" : "#{base}(#{i})#{ext}"
         return candidate if (!File.exist?(candidate) && !registry_path_conflict?(candidate,desired_uuid)) || (existing_path!=nil && same_install_path?(candidate,existing_path))
         i+=1
       end
     end

     def registry_path_conflict?(path,desired_uuid)
       desired_uuid=desired_uuid.to_s.downcase
       return false if desired_uuid==""
       entry=EltenPath.relative_from(path,Dirs.apps)
       storage_id=Programs.entry_storage_id(entry)
       registered_uuid=Programs.registry_uuid_for_storage_id(storage_id).to_s.downcase
       registered_uuid!="" && registered_uuid!=desired_uuid
     rescue Exception
       false
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
