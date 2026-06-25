class Scene_Documentation
  def initialize(docid)
    @docid=docid
  end
  def main
    label=""
    text=""
    case @docid
    when "license"
      label=p_("Documentation", "License agreement")
      text= licensetext
      when "rules"
        label=p_("Documentation", "EltenLink terms and conditions")
        text=_doc('rules')
        when "privacypolicy"
          label=p_("Documentation", "EltenLink Privacy Policy")
          text=_doc('privacypolicy')
          when "readme"
            label=p_("Documentation", "Read me")
            text=_doc('readme')
            when "migration24"
              label=p_("Documentation", "Information about migration to Elten version 2.4")
            text=_doc('migration24')
    end
    @form=Form.new([
    edt_text = EditBox.new(label, type: EditBox::Flags::ReadOnly|EditBox::Flags::MultiLine|EditBox::Flags::MarkDown, text: text, quiet: true),
    btn_close = Button.new(p_("Documentation", "Close"))
    ], index: 0, silent: false, quiet: true)
    btn_close.on(:press) {@form.resume}
    @form.cancel_button=@form.accept_button=btn_close
    @form.wait
    $scene=Scene_Main.new
  end
end