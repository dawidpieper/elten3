# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

class Scene_KeyboardShortcuts
  def main
    @shortcut_keys=QuickActions.hotkey_keys
    @standard_actions=standard_action_definitions
    @standard_identities=@standard_actions.map { |definition| action_identity(definition) }
    @table=TableBox.new(
      [p_("KeyboardShortcuts", "Shortcut"), p_("KeyboardShortcuts", "Quick action")],
      [],
      header: p_("KeyboardShortcuts", "Keyboard shortcuts"),
      quiet: false
    )
    @table.bind_context { |menu| context(menu) }
    reload_table
    @table.focus
    loop do
      loop_update
      @table.update
      assign_current if @table.selected?
      if key_pressed?(:key_escape)
        $scene=Scene_Main.new
        break
      end
      break if $scene!=self
    end
  end

  def context(menu)
    menu.option(p_("KeyboardShortcuts", "Assign or change action"), nil, "e") { assign_current }
    if current_actions.size>0
      menu.option(p_("KeyboardShortcuts", "Remove shortcut"), nil, :del) { remove_current }
    end
  end

  def reload_table(announce=false)
    index=@table.index
    @table.rows=@shortcut_keys.map do |key|
      actions=QuickActions.hotkey_actions(key)
      label=if actions.empty?
        p_("KeyboardShortcuts", "Not assigned")
      else
        actions.map { |action| display_action_label(action) }.join(", ")
      end
      [QuickActions.hotkey_label(key), label]
    end
    @table.reload
    @table.index=index
    announce ? @table.say_option : nil
  end

  def assign_current
    key=current_key
    return if key==nil
    candidates=action_candidates
    current=current_actions.first
    current_identity=current==nil ? nil : QuickActions.action_identity(current.action, current.params)
    start_index=candidates.index { |candidate| action_identity(candidate)==current_identity }
    labels=[p_("KeyboardShortcuts", "Not assigned")]+candidates.map { |candidate| candidate_label(candidate) }
    selected=selector(
      labels,
      header: p_("KeyboardShortcuts", "Quick action for %{shortcut}") % { shortcut: QuickActions.hotkey_label(key) },
      start_index: start_index==nil ? 0 : start_index+1,
      cancel_index: -1
    )
    if selected<0
      @table.focus
      return
    end
    if selected==0
      remove_current
      return
    end
    candidate=candidates[selected-1]
    target=QuickActions.find_action(candidate[:action], candidate[:params])
    affected=current_actions.reject { |action| action.equal?(target) }
    affected.push(target) if target!=nil && target.key.to_i!=key
    return if !confirm_custom_change(affected)
    if QuickActions.assign_hotkey(key, candidate[:action], candidate[:label], candidate[:params])
      reload_table(true)
    else
      alert(_("Error"))
      @table.focus
    end
  end

  def remove_current
    actions=current_actions
    if actions.empty?
      @table.focus
      return
    end
    return if !confirm_custom_change(actions)
    if QuickActions.remove_hotkey(current_key)
      reload_table(true)
    else
      alert(_("Error"))
      @table.focus
    end
  end

  def confirm_custom_change(actions)
    custom=actions.compact.uniq.any? { |action| custom_action?(action) }
    return true if !custom
    confirmed=confirm(
      p_("KeyboardShortcuts", "This change affects a custom Quick Action. Elten cannot recreate custom actions here. You can restore its shortcut from the Quick Actions list in the main window. Do you want to continue?")
    )
    @table.focus if !confirmed
    confirmed
  end

  def action_candidates
    candidates=[]
    identities={}
    QuickActions.get.each do |action|
      identity=QuickActions.action_identity(action.action, action.params)
      next if identity==nil || identities.key?(identity)
      identities[identity]=true
      candidates.push({ action: action.action, label: action.label, params: action.params, custom: !@standard_identities.include?(identity) })
    end
    @standard_actions.each do |definition|
      identity=action_identity(definition)
      next if identity==nil || identities.key?(identity)
      identities[identity]=true
      candidates.push(definition.merge(custom: false))
    end
    candidates
  end

  def standard_action_definitions
    definitions=[]
    QuickActions.predefined_procs.each do |entry|
      definition=definition_from_quick_action(entry)
      definitions.push(definition) if definition!=nil && !program_owned?(definition[:action])
    end
    GlobalMenu.scenes.each do |label, target|
      next if !target.is_a?(Array) || target.empty?
      definition={ action: target[0], label: label, params: target[1..-1] }
      definitions.push(definition) if !program_owned?(definition[:action])
    end
    unique_definitions(definitions)
  end

  def definition_from_quick_action(entry)
    return nil if !entry.is_a?(Array) || entry.empty?
    {
      action: entry[0],
      label: entry[1].to_s,
      params: entry[2].is_a?(Array) ? entry[2] : []
    }
  end

  def unique_definitions(definitions)
    identities={}
    definitions.each_with_object([]) do |definition, result|
      identity=action_identity(definition)
      next if identity==nil || identities.key?(identity)
      identities[identity]=true
      result.push(definition)
    end
  end

  def program_owned?(action)
    return false if !defined?(Program)
    owner=QuickActions.program_owner(action)
    owner.is_a?(Program) || (owner.respond_to?(:ancestors) && owner.ancestors.include?(Program))
  rescue Exception
    false
  end

  def custom_action?(action)
    identity=QuickActions.action_identity(action.action, action.params)
    identity==nil || !@standard_identities.include?(identity)
  end

  def display_action_label(action)
    label=action.label.to_s
    label=action.action.to_s if label==""
    return label if !custom_action?(action)
    p_("KeyboardShortcuts", "Custom: %{name}") % { name: label }
  end

  def candidate_label(candidate)
    label=candidate[:label].to_s
    label=candidate[:action].to_s if label==""
    return label if candidate[:custom]!=true
    p_("KeyboardShortcuts", "Custom: %{name}") % { name: label }
  end

  def action_identity(definition)
    QuickActions.action_identity(definition[:action], definition[:params])
  end

  def current_key
    @shortcut_keys[@table.index]
  end

  def current_actions
    key=current_key
    key==nil ? [] : QuickActions.hotkey_actions(key)
  end
end
