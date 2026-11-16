# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "securerandom"

module ForumTemplatesScene
  TEMPLATE_TYPES = %w[checkbox select multiselect text multiline].freeze
  TEMPLATE_MODES = %w[default manual tag].freeze

  def select_thread_template(forum)
    return nil unless forum.has_templates
    templates = forum_fetch(nil) { EltenLink::Forum.list_forum_templates(elten_link, forumid: forum.id) }
    return nil if templates == nil || templates.empty?
    index = selector(templates.map { |item| item["name"] } + [p_("Forum", "Write manually")],
      header: p_("Forum", "Thread template"), cancel_index: -1, flags: ListBox::Flags::AnyDir)
    index < 0 ? false : templates[index]
  end

  def fill_thread_template(definition, draft, data)
    template = EltenLink::ForumTemplate.new(definition)
    title = EditBox.new(p_("Forum", "Thread name"), text: data.fetch("template_title", data["title"]).to_s)
    answers = data.fetch("template_answers", {})
    controls = template.fields.map { |field| thread_template_control(field, answers[field["id"]]) }
    fields = [title]
    information = definition.fetch("information", "")
    unless information.strip.empty?
      fields << EditBox.new(p_("Forum", "Additional information"), type: EditBox::Flags::MultiLine | EditBox::Flags::ReadOnly, text: information)
    end
    form = Form.new(fields + controls + [Button.new(_("Continue")), Button.new(_("Cancel"))], quiet: true)
    snapshot = proc do
      answers = thread_template_answers(template.fields, controls)
      data.merge(template.render(title.text, answers)).merge(
        "template" => definition, "template_answers" => answers, "template_title" => title.text)
    end
    draft.bind(form, title, &snapshot)
    form.focus
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) || form.fields[-1].pressed?
        return nil if draft.close(editor: false)
        form.focus
      elsif form.fields[-2].pressed? || (key_held?(0x11) && key_pressed?(:key_enter))
        values = snapshot.call
        missing = template.missing_field(values["template_answers"])
        invalid = template.invalid_tag_field(values["template_answers"])
        if missing || invalid
          alert(missing ? p_("Forum", "Complete the required field.") : thread_template_tag_error)
          form.index = template.fields.index(missing || invalid) + fields.size
          form.focus
          next
        end
        return values.reject { |key, _| %w[template template_answers template_title].include?(key) }.merge("from_template" => true)
      end
    end
  ensure
    draft.detach
  end

  def thread_template_control(field, value)
    label = field["label"]
    label += " (#{p_("Forum", "required")})" if field["required"]
    case field["type"]
    when "checkbox"
      CheckBox.new(label, checked: value == true)
    when "select", "multiselect"
      options = field["options"]
      multiple = field["type"] == "multiselect"
      selected = Array(value)
      control = ListBox.new([p_("Forum", "No value")] + options.map { |option| option["label"] },
        header: label, index: multiple ? 0 : (options.index { |option| selected.include?(option["id"]) } || -1) + 1,
        flags: multiple ? ListBox::Flags::MultiSelection : 0)
      if multiple
        control.select_multiselection_indices(options.each_index.select { |index| selected.include?(options[index]["id"]) }.map { |index| index + 1 })
        control.on(:multiselection_selected) do |params|
          if params[0] == 0
            control.deselect_multiselection_indices((0..options.size).to_a)
          end
        end
      end
      control
    else
      thread_template_text(label, value.to_s, multiline: field["type"] == "multiline")
    end
  end

  def thread_template_answers(fields, controls)
    fields.each_with_index.to_h do |field, index|
      control = controls[index]
      value = case field["type"]
      when "checkbox"
        control.checked
      when "select"
        control.index > 0 ? field["options"][control.index - 1]["id"] : nil
      when "multiselect"
        field["options"].each_with_index.filter_map { |option, i| option["id"] if control.selected[i + 1] }
      else
        control.text
      end
      [field["id"], value]
    end
  end

  def assign_thread_template_tags!(values, lists, selections)
    values.reject do |value|
      list = lists.find { |tag|
        tag[2..-1].include?(value) && (selections[tag[0].to_s] == nil || selections[tag[0].to_s] == value)
      }
      selections[list[0].to_s] = value if list
      list != nil
    end
  end

  def edit_forum_templates(forum)
    templates = forum_fetch(nil) { EltenLink::Forum.list_forum_templates(elten_link, forumid: forum.id) }
    return if templates == nil
    saved_templates = templates
    loop do
      templates = edit_template_list(templates, header: p_("Forum", "Thread templates"), label_key: "name", limit: 32, original: saved_templates) { |item|
        edit_thread_template(item)
      }
      return if templates == nil
      begin
        EltenLink::Forum.set_forum_templates(elten_link, forumid: forum.id, templates: templates)
        forum.has_templates = !templates.empty?
        alert(_("Saved"))
        return
      rescue EltenLink::Error => error
        log_forum_error(error)
        alert(p_("Forum", "Could not save templates: %{error}") % { error: error.message })
      end
    end
  end

  def edit_thread_template(template)
    template ||= { "id" => SecureRandom.uuid, "name" => "", "fields" => [] }
    edit_template_list(template["fields"], header: p_("Forum", "Template fields"),
      label_key: "label", limit: 64, minimum: 1, template: template) { |field| edit_thread_template_field(field) }
  end

  def edit_template_list(items, header:, label_key:, limit:, minimum: 0, template: nil, original: nil, &editor)
    items = JSON.parse(JSON.generate(items))
    list = ListBox.new(items.map { |item| item[label_key] }, header: header)
    fields = [list, Button.new(_("Save")), Button.new(_("Cancel"))]
    if template
      name_field = EditBox.new(p_("Forum", "Template name"), text: template["name"])
      name_field.max_length = 128
      information_field = thread_template_text(p_("Forum", "Additional information"), template.fetch("information", ""), multiline: true)
      information_field.max_length = 8192
      tags_field = thread_template_text(p_("Forum", "Automatic tags (one per line)"), template.fetch("automatic_tags", []).join("\r\n"), multiline: true)
      prefix_field = thread_template_text(p_("Forum", "Post introduction"), template.fetch("post_prefix", ""), multiline: true)
      prefix_field.max_length = 8192
      fields.unshift(name_field, information_field, tags_field, prefix_field)
    end
    snapshot = proc do
      template ? template.merge("name" => name_field.text, "information" => information_field.text, "fields" => items, "post_prefix" => prefix_field.text,
        "automatic_tags" => tags_field.text.lines.map(&:strip).reject(&:empty?).uniq) : items
    end
    original = JSON.parse(JSON.generate(original || snapshot.call))
    form = Form.new(fields)
    refresh = proc do |index = list.index|
      list.options = items.map { |item| item[label_key] }
      list.index = [[index, items.size - 1].min, 0].max
      form.focus
    end
    edit = proc do
      if items[list.index]
        item = editor.call(items[list.index])
        items[list.index] = item if item
        refresh.call
      end
    end
    list.bind_context do |menu|
      menu.option(_("New"), nil, "n") do
        if items.size >= limit
          alert(p_("Forum", "The list can contain at most %{count} items.") % { count: limit })
        else
          item = editor.call(nil)
          items << item if item
          refresh.call(item ? items.size - 1 : list.index)
        end
      end
      unless items.empty?
        menu.option(_("Edit"), nil, "e") { edit.call }
        menu.option(_("Delete"), nil, :del) do
          if confirm(p_("Forum", "Delete %{name}?") % { name: items[list.index][label_key] })
            items.delete_at(list.index)
          end
          refresh.call
        end
        if list.index > 0
          menu.option(p_("Forum", "Move up")) do
            index = list.index
            items[index - 1], items[index] = items[index], items[index - 1]
            refresh.call(index - 1)
          end
        end
        if list.index < items.size - 1
          menu.option(p_("Forum", "Move down")) do
            index = list.index
            items[index + 1], items[index] = items[index], items[index + 1]
            refresh.call(index + 1)
          end
        end
      end
    end
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) || form.fields[-1].pressed?
        return nil if discard_template_changes?(snapshot.call, original)
        form.focus
        next
      end
      if form.fields[-2].pressed? || (key_held?(0x11) && key_pressed?(:key_enter))
        result = snapshot.call
        if template && name_field.text.strip.empty?
          alert(p_("Forum", "Enter a template name."))
          form.index = 0
          form.focus
        elsif items.size < minimum
          alert(p_("Forum", "Add at least one item."))
        elsif template && result["automatic_tags"].size > 32
          alert(p_("Forum", "A template can contain at most 32 automatic tags."))
        elsif template && result["automatic_tags"].any? { |tag| tag.length > 128 || tag.match?(/[\[\]\r\n\x00]/) }
          alert(thread_template_tag_error)
        elsif template && JSON.generate(result).bytesize > 65_536
          alert(p_("Forum", "A template cannot exceed 64 KiB."))
        else
          return result
        end
      elsif form.fields[form.index] == list && key_pressed?(:key_enter)
        edit.call
      end
    end
  end

  def edit_thread_template_field(field)
    field ||= { "id" => SecureRandom.uuid, "type" => "text", "mode" => "default", "label" => "" }
    options = JSON.parse(JSON.generate(field.fetch("options", [])))
    fields = [
      EditBox.new(p_("Forum", "Field description"), text: field["label"]),
      ListBox.new([p_("Forum", "Checkbox"), p_("Forum", "Single choice"), p_("Forum", "Multiple choice"),
        p_("Forum", "Single-line text"), p_("Forum", "Multiline text")], header: p_("Forum", "Field type"), index: TEMPLATE_TYPES.index(field["type"])),
      CheckBox.new(p_("Forum", "Required"), checked: field["required"]),
      ListBox.new([p_("Forum", "Heading and value"), p_("Forum", "Custom text"), p_("Forum", "Thread tag")],
        header: p_("Forum", "Field output"), index: TEMPLATE_MODES.index(field.fetch("mode", "default"))),
      EditBox.new(p_("Forum", "Heading"), text: field.fetch("heading", field["label"])),
      thread_template_text(p_("Forum", "Text prefix"), field.fetch("prefix", ""), multiline: true),
      thread_template_text(p_("Forum", "Output when checked"), field.fetch("checked", ""), multiline: true),
      CheckBox.new(p_("Forum", "Include output when unchecked"), checked: field.key?("unchecked")),
      thread_template_text(p_("Forum", "Output when unchecked"), field.fetch("unchecked", ""), multiline: true),
      Button.new(p_("Forum", "Edit choices")), Button.new(_("Save")), Button.new(_("Cancel"))
    ]
    fields[0].max_length = fields[4].max_length = 256
    [5, 6, 8].each { |index| fields[index].max_length = 8192 }
    form = Form.new(fields, quiet: true)
    visibility = proc do
      type = TEMPLATE_TYPES[fields[1].index]
      mode = TEMPLATE_MODES[fields[3].index]
      visible = {
        4 => mode == "default", 5 => %w[text multiline].include?(type) && mode != "default",
        6 => type == "checkbox" && mode != "default", 7 => type == "checkbox",
        8 => type == "checkbox" && fields[7].checked, 9 => %w[select multiselect].include?(type)
      }
      visible.each { |index, show| show ? form.show(index) : form.hide(index) }
    end
    fields[1].on(:move, &visibility)
    fields[3].on(:move, &visibility)
    fields[7].on(:change, &visibility)
    visibility.call
    form.focus
    snapshot = proc do
      [fields[0].text, fields[1].index, fields[2].checked, fields[3].index, fields[4].text,
        fields[5].text, fields[6].text, fields[7].checked, fields[8].text, options]
    end
    original = JSON.parse(JSON.generate(snapshot.call))
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) || fields[-1].pressed?
        return nil if discard_template_changes?(snapshot.call, original)
        form.focus
        next
      end
      type = TEMPLATE_TYPES[fields[1].index]
      mode = TEMPLATE_MODES[fields[3].index]
      if fields[9].pressed?
        result = edit_template_list(options, header: p_("Forum", "Choices"), label_key: "label", limit: 128, minimum: 1) { |option|
          edit_thread_template_option(option, mode)
        }
        options = result if result
        form.focus
      elsif fields[-2].pressed? || (key_held?(0x11) && key_pressed?(:key_enter))
        result = { "id" => field["id"], "label" => fields[0].text, "type" => type, "mode" => mode, "required" => fields[2].checked }
        result["heading"] = fields[4].text.empty? ? fields[0].text : fields[4].text if mode == "default"
        outputs = []
        case type
        when "text", "multiline"
          if mode != "default"
            result["prefix"] = fields[5].text
            outputs << result["prefix"]
          end
        when "checkbox"
          if mode != "default"
            result["checked"] = fields[6].text
            outputs << result["checked"]
          end
          if fields[7].checked
            result["unchecked"] = fields[8].text
            outputs << result["unchecked"]
          end
        else
          result["options"] = options.map { |option|
            item = option.slice("id", "label")
            item["output"] = option.fetch("output", option["label"]) if mode != "default"
            item
          }
          outputs = result["options"].map { |option| option["output"] }.compact
        end
        if result["label"].strip.empty? || (mode == "default" && result["heading"].strip.empty?)
          alert(p_("Forum", "Enter a field description and heading."))
        elsif %w[select multiselect].include?(type) && options.empty?
          alert(p_("Forum", "Add at least one choice."))
        elsif mode == "tag" && outputs.any? { |value| value.length > 128 || value.match?(/[\[\]\r\n]/) }
          alert(thread_template_tag_error)
        else
          return result
        end
      end
    end
  end

  def edit_thread_template_option(option, mode)
    option ||= { "id" => SecureRandom.uuid, "label" => "" }
    fields = [EditBox.new(p_("Forum", "Choice description"), text: option["label"]),
      thread_template_text(p_("Forum", "Output"), option.fetch("output", option["label"]), multiline: mode != "tag"),
      Button.new(_("Save")), Button.new(_("Cancel"))]
    fields[0].max_length = 256
    fields[1].max_length = mode == "tag" ? 128 : 8192
    form = Form.new(fields, quiet: true)
    form.hide(1) if mode == "default"
    form.focus
    original = fields[0..1].map(&:text)
    loop do
      loop_update
      form.update
      if key_pressed?(:key_escape) || fields[-1].pressed?
        return nil if discard_template_changes?(fields[0..1].map(&:text), original)
        form.focus
        next
      end
      if fields[-2].pressed? || (key_held?(0x11) && key_pressed?(:key_enter))
        if fields[0].text.strip.empty?
          alert(p_("Forum", "Enter a choice description."))
        elsif mode == "tag" && fields[1].text.match?(/[\[\]\r\n]/)
          alert(thread_template_tag_error)
        else
          result = option.merge("label" => fields[0].text)
          result["output"] = fields[1].text unless mode == "default"
          return result
        end
      end
    end
  end

  def discard_template_changes?(current, original)
    current == original || confirm(p_("Forum", "Discard unsaved changes?"))
  end

  def thread_template_text(label, text, multiline: false)
    control = EditBox.new(label, type: multiline ? EditBox::Flags::MultiLine : 0, text: text)
    control.text_replace!(0, control.text_len, text.delete("\r"), true)
    control.index = control.check = control.text_len
    control
  end

  def thread_template_tag_error
    p_("Forum", "Tags cannot contain brackets or line breaks and must not exceed 128 characters.")
  end
end
