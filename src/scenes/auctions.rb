class Scene_Auctions
  def main
    if Configuration.language!="pl-PL"
      alert("Sorry, this event is available for polish users only.")
      $scene=Scene_Main.new
      return
    end
    @sel = TableBox.new([nil, "Właściciel", "Obecna cena", "Użytkownik licytujący", "Zakończenie licytacji"], [], index: 0, header: "Aukcje")
    @sel.bind_context{|menu|context(menu)}
    refresh
    @sel.focus
    loop do
      loop_update
            @sel.update
            dlg if key_pressed?(:key_enter)
      break if key_pressed?(:key_escape)
    end
    $scene=Scene_Main.new
  end
  def refresh
    @auctions=[]
    @enrolled=false
    begin
      list = EltenLink::Auctions.list(elten_link)
      @auctions = list.auctions
      @enrolled = list.enrolled
    rescue EltenLink::Error => e
      Log.warning("Auctions list failed: #{e.message}")
      alert(_("Error"))
      return
      end
    @sel.rows = @auctions.map{|a|
    f=""
    begin
      f = format_date(Time.at(a.totime))
    rescue Exception
      end
    [a.name, a.creator, a.price.to_s+" zł", a.user, f]
    }
    @sel.reload
  end
  def context(menu)
    auction=@auctions[@sel.index]
    if auction!=nil
      menu.option("Pokaż") {dlg}
      if auction.user!=Session.name
      menu.option("Licytuj", nil, "l") {bit;@sel.focus}
      end
    end
    menu.option("Odśwież", nil, "r") {refresh;@sel.focus}
    end
  def dlg
    auction=@auctions[@sel.index]
    return if auction==nil
    dialog_open
    form = Form.new([
    txt_description = EditBox.new(auction.name, type: EditBox::Flags::ReadOnly|EditBox::Flags::MultiLine, text: auction.description),
    btn_bit = Button.new("Licytuj"),
    btn_close = Button.new("Zamknij")
    ], index: 0, silent: false, quiet: true)
    form.hide(btn_bit) if auction.user==Session.name
    btn_close.on(:press) {form.resume}
    btn_bit.on(:press) {bit}
    form.cancel_button=btn_close
    form.wait
    dialog_close
    @sel.focus
  end
  def bit
    auction=@auctions[@sel.index]
    return if auction==nil
    prices=(auction.price+1 .. auction.price+100).to_a
    pr = selector(prices.map{|r|r.to_s+" zł"}, header: "Twoja oferta", start_index: 0, cancel_index: -1)
    return if pr==-1
    price=prices[pr]
    enroll=false
    if @enrolled==false
      if acceptrules
        enroll=true
      else
        return
        end
      end
      confirm("Czy chcesz zaoferować #{price.to_s} zł w licytacji na aukcji \"#{auction.name}\"?") {
      bid_ok=true
      begin
        EltenLink::Auctions.bid(elten_link, auction: auction.id, price: price, enroll: enroll)
      rescue EltenLink::Error => e
        Log.warning("Auction bid failed: #{e.message}")
        bid_ok=false
      end
      if !bid_ok
      alert("Coś poszło nie tak. Aukcja mogła się już skończyć lub ktoś inny zdążył przedstawić wyższą ofertę.")
        else
        alert("Licytujesz tę aukcję")
      end
      refresh
      }
    end
  def acceptrules
begin
rules=EltenLink::Auctions.rules(elten_link)
rescue EltenLink::Error => e
  Log.warning("Auction rules failed: #{e.message}")
  alert("Błąd")
  return false
end
form = Form.new([
txt_rules = EditBox.new("Regulamin", type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly, text: rules, quiet: true),
btn_accept = Button.new("Akceptuj"),
btn_reject = Button.new("Odrzuć")
], index: 0, silent: false, quiet: true)
form.cancel_button = btn_reject
btn_reject.on(:press) {
form.resume
return false
}
btn_accept.on(:press) {
form.resume
return true
}
form.wait
    end
    end
  
  class Struct_Auctions_Auction < EltenLink::Auction
  end
