class Scene_PremiumPackages
  CURRENCIES = ["PLN", "EUR", "USD", "GBP"].freeze

  def main
    if Session.name=="guest"
      alert(_("This section is unavailable for guests"))
      $scene=Scene_Main.new
      return
    end
    currency = LocalConfig['PremiumPackagesCurrency', "unset", type: :string]
    select_currency if currency == "unset"
    currency = LocalConfig['PremiumPackagesCurrency', "unset", type: :string]
    @currency = CURRENCIES.include?(currency) ? currency : CURRENCIES[0]
    @sel = TableBox.new([nil, p_("PremiumPackages", "status"), p_("PremiumPackages", "Yearly price"), p_("PremiumPackages", "Monthly price"), p_("PremiumPackages", "Conversion price")], [], index: 0, header: p_("PremiumPackages", "Premium packages"))
      @sel.bind_context{|menu|context(menu)}
      refresh
      @sel.focus
      loop do
        loop_update
        @sel.update
        break if key_pressed?(:key_escape)
        if key_pressed?(:key_enter) and @packages.size>0
          package=@packages[@sel.index]
show(package)          
@sel.focus
          end
        end
      $scene=Scene_Main.new
  end
    def get_courier
    return Struct_PremiumPackages_PremiumPackage.new("courier", p_("PremiumPackages", "Courier"), [
    p_("PremiumPackages", "Following forums in not moderated groups"),
    p_("PremiumPackages", "Disabling signatures visibility"),
    p_("PremiumPackages", "Thread marking and bookmarks"),
    p_("PremiumPackages", "Private messages protection against erroneous removal"),
    p_("PremiumPackages", "History of mentions and replying to mentions"),
    p_("PremiumPackages", "Groups pinning"),
    p_("PremiumPackages", "Following blog posts"),
        p_("PremiumPackages", "Extended limit of attachment size in private messages to 32MB"),
    p_("PremiumPackages", "Attaching polls to private messages"),
    p_("PremiumPackages", "Using Markdown in forum posts"),
    p_("PremiumPackages", "Reading transcriptions of audio posts in recommended groups"),
    ])
  end
  def get_audiophile
    return Struct_PremiumPackages_PremiumPackage.new("audiophile", p_("PremiumPackages", "Audiophile"), [
        p_("PremiumPackages", "Lifting the 2-minute limit for private voice messages"),
    p_("PremiumPackages", "Lifting the 32kbps quality limit in private voice messages"),
    p_("PremiumPackages", "Recording conferences"),
    p_("PremiumPackages", "Creation of up to three public channels in conferences"),
    p_("PremiumPackages", "Creation of group channels in conferences"),
    p_("PremiumPackages", "Using VST plugins in conferences"),
    p_("PremiumPackages", "Setting specific ringtones for users"),
    #p_("PremiumPackages", "Placing beacons in HRTF channels"),
    p_("PremiumPackages", "Splitting audio into chapters"),
    p_("PremiumPackages", "Creating hidden channels in conferences"),
    ])
  end
  def get_scribe
    return Struct_PremiumPackages_PremiumPackage.new("scribe", p_("PremiumPackages", "Scribe"), [
p_("PremiumPackages", "Creation of second and following blogs"),
p_("PremiumPackages", "Pinning blogs to groups"),
p_("PremiumPackages", "Spell checking"),
p_("PremiumPackages", "Changing of blog address"),
p_("PremiumPackages", "Option to disable request for support on blogs"),
p_("PremiumPackages", "Informing about new blog followers"),
p_("PremiumPackages", "Translator"),
p_("PremiumPackages", "Blog posts scheduling"),
    ])
  end
  def get_director
    return Struct_PremiumPackages_PremiumPackage.new("director", p_("PremiumPackages", "Director"), [
    p_("PremiumPackages", "Conference streaming to shoutcast servers"),
p_("PremiumPackages", "Setting VST plugins on specific users"),
p_("PremiumPackages", "Placing own sceneries in channels"),
p_("PremiumPackages", "Creating conference-mode channels, where only administrators and allowed users can speak"),
p_("PremiumPackages", "Setting different output soundcard for conferences than the one selected in Elten"),
        p_("PremiumPackages", "Changing channels dimensions"),
])
end
def get_orchestra
    return Struct_PremiumPackages_PremiumPackage.new("orchestra", p_("PremiumPackages", "Orchestra package"), [
    p_("PremiumPackages", "Includes profits from courier, audiophile, scribe and director"),
  ])
end
  def get_sponsor
    return Struct_PremiumPackages_PremiumPackage.new("sponsor", p_("PremiumPackages", "Sponsorship package"), [
    p_("PremiumPackages", "Includes profits from all other packages, including future packages"),
    p_("PremiumPackages", "Special assigning of user on lists and forum"),
    p_("PremiumPackages", "Entry in the list of sponsors"),
  ])
end
def context(menu)
    if @packages.size>0
      package=@packages[@sel.index]
      menu.option(p_("PremiumPackages", "Show profits")) {
show(package)
@sel.focus
      }
      if package.allowed
        s=p_("PremiumPackages", "Buy")
        s=p_("PremiumPackages", "Extend") if package.totime>0
        menu.option(s) {
        buy(package)
        refresh
        @sel.focus
        }
                if !package.special && package.activable
          s=p_("PremiumPackages", "Activate package using code")
          s=p_("PremiumPackages", "Extend package using code") if package.totime>0
                menu.option(s) {
                activate(package)
                refresh
        @sel.focus
                }
              elsif package.totime==0
                menu.option(p_("PremiumPackages", "Convert")) {
                buy(package, true)
        refresh
        @sel.focus
                }
              end
              end
              menu.option(p_("PremiumPackages", "Buy premium codes for use by any user")) {
              buy(nil)
        refresh
        @sel.focus
              }
            end
            menu.option(p_("PremiumPackages", "Change currency")) {
            select_currency
            refresh
            }
    menu.option(_("Refresh"), nil, "r") {
    refresh
    @sel.focus
    }
  end
  def select_currency
    c = selector([p_("PremiumPackages", "Polish zloty")+" (PLN)", p_("PremiumPackages", "Euro")+" (EUR)", p_("PremiumPackages", "US dollar")+" (USD)", p_("PremiumPackages", "British pound")+" (GBP)"], header: p_("PremiumPackages", "Select your currency."))
    return if c < 0 || c >= CURRENCIES.size
    @currency = CURRENCIES[c]
    LocalConfig['PremiumPackagesCurrency'] = @currency
end
  def show(package)
    sbuy=p_("PremiumPackages", "Buy")
        sbuy=p_("PremiumPackages", "Extend") if package.totime>0
sactivate=p_("PremiumPackages", "Activate package using code")
          sactivate=p_("PremiumPackages", "Extend package using code") if package.totime>0
    form=Form.new([
    lst_profits = ListBox.new(package.profits, header: p_("PremiumPackages", "Profits of package %{name}")%{:name=>package.name}),
    btn_buy = Button.new(sbuy),
    btn_convert = Button.new(p_("PremiumPackages", "Convert")),
    btn_buycode = Button.new(p_("PremiumPackages", "Buy premium codes for use by any user")),
    btn_activate = Button.new(sactivate),
    btn_close=Button.new(p_("PremiumPackages", "Close"))
    ], index: 0, silent: false, quiet: true)
    form.hide(btn_buycode) if package.special || !package.activable
    form.hide(btn_activate) if package.special || !package.activable
    form.hide(btn_convert) if package.package!="sponsor"
    form.cancel_button=btn_close
    btn_close.on(:press) {form.resume}
    btn_buy.on(:press) {
    buy(package)
        refresh
        form.resume
    }
    btn_buycode.on(:press) {
    buy(nil)
        refresh
        form.resume
    }
    btn_convert.on(:press) {
    buy(package, true)
        refresh
        form.resume
    }
    btn_activate.on(:press) {
    activate(package)
                refresh
                form.resume
    }
    form.wait
    end
  def refresh
        @packages=[
    get_courier,
    get_audiophile,
    get_scribe,
    get_director,
    get_orchestra,
    get_sponsor
    ]
    begin
      active_until=EltenLink::PremiumPackages.active_until(elten_link)
      active_until.each do |package, totime|
        for c in @packages
          c.totime=totime if c.package==package
          end
        end
    rescue EltenLink::Error
    end
      begin
        j=EltenLink::Payments.prices(elten_link)
        for k in j.keys
          for c in @packages
            if c.package==k
              c.activable=true  
              c.price=j[k]["price$#{@currency}"]
                c.monthlyprice=j[k]["monthlyprice$#{@currency}"]
                c.available=j[k]['available']
                c.allowed=true if c.totime==0 || j[k]['yearlimit']>=Time.at(c.totime).year
                c.special=j[k]['special']
              end
            end
          end
        end
        @sel.rows=@packages.map{|c|
        st=p_("PremiumPackages", "Inactive")
        st=p_("PremiumPackages", "Active until %{time}")%{:time=>format_date(Time.at(c.totime))} if c.totime>0
        monthlyprice=nil
        price=nil
        conversionprice=nil
                if c.package=="sponsor"
          z=0
          for g in @packages.find_all{|pc|pc.package!="sponsor"}
            d=((g.totime-Time.now.to_f)/86400).floor
            d=0 if d<0
            z+=(g.price*0.9)/365.0*d
          end
          conversionprice=(c.price-z).ceil if z>0
        end
if c.package=="orchestra"
          z=0
          for g in @packages.find_all{|pc|pc.package!="orchestra"}
            d=((g.totime-Time.now.to_f)/86400).floor
            d=0 if d<0
            z+=(g.price*0.9)/365.0*d
          end
          conversionprice=(c.price-z).ceil if z>0
end       
monthlyprice=c.monthlyprice.to_s+" "+@currency if c.monthlyprice!=nil
        price=c.price.to_s+" "+@currency if c.price!=nil
        conversionprice=nil if conversionprice!=nil && conversionprice<=0
        conversionprice=conversionprice.to_s+" "+@currency if conversionprice!=nil
          [c.name, st, price, monthlyprice, conversionprice]
        }
        @sel.reload
      rescue EltenLink::Error, JSON::ParserError
      end
      def buy(package, convert=false)
        return if convert && !confirm(p_("PremiumPackages", "Regardless of the remaining duration of other packages, they will be replaced by the selected package. This package will be activated for a period of one year. The remaining period for other packages will be deducted from the package price. Do you want to continue?"))
        if package!=nil && !package.available
          alert(p_("PremiumPackages", "This package is currently unavailable. Try to buy it in the next month."))
          return
        end
        type = 0
        if package!=nil && package.monthlyprice!=nil && package.monthlyprice!=0 && !convert
          type = selector([p_("PremiumPackages", "One year") + ": " + package.price.to_s + " " + @currency, p_("PremiumPackage", "One month") + ": " + package.monthlyprice.to_s + " " + @currency], header: p_("PremiumPackages", "How long do you want to buy this package for?"), start_index: 0, cancel_index: -1)
        end
        return if type==-1
        accepted=false
        form=Form.new([
        edt_info = EditBox.new(p_("PremiumPackages", "Information"), type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly, text: p_("PremiumPackages",
        "EltenLink's premium packages are given to users as a reward for supporting the portal.
A project of this size cannot exist without the help of users.
The granting of a premium package does not constitute a commitment or a commercial contract. The user who supports the project is aware that if the necessary amount is not raised for EltenLink to continue, the premium packages will become unavailable.")),
        btn_accept = Button.new(p_("PremiumPackages", "I accept")),
        btn_refuse = Button.new(p_("PremiumPackages", "I refuse"))
        ], index: 0, silent: false, quiet: true)
      form.cancel_button=btn_refuse
      btn_refuse.on(:press) {form.resume}
      btn_accept.on(:press) {accepted=true;form.resume}
      form.wait
      return if !accepted
     transfer=nil
     methods=[]
     begin
       j=EltenLink::Payments.methods(elten_link, currency: @currency, language: Configuration.language)
       for m in j
         if m['id']=='transfer' and m['type']=='transfer'
           transfer=m
         end
         methods.push(m) if m['type']=="transfer" || m['type']=="url" || m['type']=="blik"
         end
     rescue EltenLink::Error, JSON::ParserError
       alert(_("Error"))
       return
       end
       dict={
       'transfer'=>p_("PremiumPackages", "Traditional bank transfer"),
       'paypal'=>p_("PremiumPackages", "Paypal (using Paypal account or credit/debit card)"),
       'p24'=>p_("PremiumPackages", "Przelewy24 (fast transfer from polish banks)"),
       }
       selt=methods.map{|m|d=m['id'];dict[d]||d}
       l=selector(selt, header: p_("PremiumPackages", "Select payment method"), start_index: 0, cancel_index: -1)
       return if l==-1
       method=methods[l]
       if method['acceptance']!=nil && method['acceptance']!=""
         accepted=false
         form = Form.new([
         edt_acceptance=EditBox.new(p_("PremiumPackages", "Acceptance"), type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly, text: method['acceptance']),
         btn_accept = Button.new(p_("PremiumPackages", "Accept")),
         btn_reject = Button.new(p_("PremiumPackages", "Reject"))
         ], index: 0, silent: false, quiet: true)
         btn_accept.on(:press) {accepted=true;form.resume}
         btn_reject.on(:press) {form.resume}
         form.cancel_button=btn_reject
         form.wait
         return if accepted==false
 end
       if method['type']=='transfer'
         transfer=method
      info=p_("PremiumPackages", "Below are the transfer details.\n")
      if package!=nil
info+=p_("PremiumPackages", "In the title of the transfer, please indicate your user name on the EltenLink portal and which package the payment concerns.")
else
  info+=p_("PremiumPackages", "If you wish to receive a code that can be used to activate any of the packages: %{packages} by any user, mark this information in the transfer title.")%{:packages=>@packages.find_all{|pc|pc.special==false}.map{|pc|pc.name}.join(", ")}
end
info+="\n"+p_("PremiumPackages", "Please note that if you transfer a larger amount, the remainder will be treated as a donation.

In order to reduce the processing time of your payment, you can forward the transfer confirmation to the Council of Elders.")
info+="\n\n"
info+=p_("PremiumPackages", "National transfer details (from Poland):
%{holder}
Address: %{address}
Account number: %{placcount}

Additional data for foreign transfers:
IBAN number: %{iban}
BIC / SWIFT: %{swift}
Bank address: %{bankaddress}
Sort code: %{sortcode}")%{:holder=>transfer['holder'], :address=>transfer['address'], :placcount=>transfer['placcount'], :iban=>transfer['iban'], :swift=>transfer['swift'], :bankaddress=>transfer['bankaddress'], :sortcode=>transfer['sortcode']}
form=Form.new([
        edt_info = EditBox.new(p_("PremiumPackages", "Information"), type: EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly, text: info),
        btn_accept = Button.new(p_("PremiumPackages", "I accept"))
        ], index: 0, silent: false, quiet: true)
      form.cancel_button=btn_accept
      btn_accept.on(:press) {form.resume}
      form.wait
    elsif method['type']=='url'
      confirm(p_("PremiumPackages", "This payment method requires a redirect to an external website. A web browser will open. Do you wish to continue?")) {
      payment_package = package.package if package!=nil
      payment_time = type==1 ? 'month' : nil
      payment_amount = nil
      price=0
      price=package.price if package!=nil
      price=package.monthlyprice if type==1 && package!=nil
      if package!=nil and package.package=="sponsor" and convert==true
        conversionprice=package.price
          z=0
          for g in @packages.find_all{|c|c.package!="sponsor"}
            d=((g.totime-Time.now.to_f)/86400).floor
            d=0 if d<0
            z+=(g.price*0.9)/365.0*d
          end
          conversionprice=(package.price-z).ceil if z>0
        price=conversionprice
        payment_package='sponsor_c'
        end
      if package==nil
      payment_amount=selector((1..20).to_a.map{|a|a.to_s}, header: p_("PremiumPackages", "How many premium codes would you like to buy?"), start_index: 0, cancel_index: -1)+1
      return if payment_amount==0
      pr=@packages.find{|pc|!pc.special}
    price=pr.price*payment_amount if pr!=nil
      end
            per=0
            per+=method['plus'] if method['plus'].is_a?(Numeric)
            per+=method['perc_plus']*price/100.0 if method['perc_plus'].is_a?(Numeric)
      return if (per!=0 && !confirm(p_("PremiumPackages", "You will be charged a %{amount} commission for the selected payment method. Do you want to continue?")%{:amount=>per.to_s+" "+@currency}))
      begin
        url=EltenLink::Payments.pay(elten_link, method: method['id'], package: payment_package, currency: @currency, time: payment_time, amount: payment_amount)
      rescue EltenLink::Error
        alert(_("Error"))
      else
        platform_open_url(url)
        end
      }
      elsif method['type']=='blik'
      payment_package = package.package if package!=nil
      payment_time = type==1 ? 'month' : nil
      payment_amount = nil
      price=0
      price=package.price if package!=nil
      price=package.monthlyprice if type==1 && package!=nil
      if package!=nil and package.package=="sponsor" and convert==true
        conversionprice=package.price
          z=0
          for g in @packages.find_all{|c|c.package!="sponsor"}
            d=((g.totime-Time.now.to_f)/86400).floor
            d=0 if d<0
            z+=(g.price*0.9)/365.0*d
          end
          conversionprice=(package.price-z).ceil if z>0
        price=conversionprice
        payment_package='sponsor_c'
        end
      if package==nil
      payment_amount=selector((1..20).to_a.map{|a|a.to_s}, header: p_("PremiumPackages", "How many premium codes would you like to buy?"), start_index: 0, cancel_index: -1)+1
      return if payment_amount==0
      pr=@packages.find{|pc|!pc.special}
    price=pr.price*payment_amount if pr!=nil
      end
            per=0
            per+=method['plus'] if method['plus'].is_a?(Numeric)
            per+=method['perc_plus']*price/100.0 if method['perc_plus'].is_a?(Numeric)
      return if (per!=0 && !confirm(p_("PremiumPackages", "You will be charged a %{amount} commission for the selected payment method. Do you want to continue?")%{:amount=>per.to_s+" "+@currency}))
code = input_text(p_("PremiumPackages", "Enter blik code"), flags: EditBox::Flags::Numbers, text: "", escapable: true, permitted_characters: [], denied_characters: [], max_length: 6)
return if code==nil
      begin
        EltenLink::Payments.pay(elten_link, method: method['id'], package: payment_package, currency: @currency, time: payment_time, amount: payment_amount, code: code)
      rescue EltenLink::Error
        alert(_("Error"))
      else
alert(p_("PremiumPackages", "Payment has been ordered. Additional confirmation may be required. The order will be processed once the payment is complete."))
        end
      end
    end
    def activate(package)
      code=input_text(p_("PremiumPackages", "Type code to activate this package"), flags: 0, text: "", escapable: true)
      return if code==nil
      begin
        duration=EltenLink::PremiumPackages.test_code(elten_link, code)
      rescue EltenLink::Error => e
        case e.code.to_i
        when -4
          alert(p_("PremiumPackages", "Code not found."))
          when -5
            alert(p_("PremiumPackages", "This code has been already used."))
      else
        alert(_("Error"))
      end
      return
      end
      tim=package.totime
      tim=Time.now.to_i if tim==0
      tim+=duration
      confirm(p_("PremiumPackages", "The package %{name} will be active until %{time}. This code will be used up and you will not be able to use it again. Do you want to continue?")%{:name=>package.name, :time=>format_date(Time.at(tim))}) {
      begin
        EltenLink::PremiumPackages.use_code(elten_link, package: package.package, code: code)
      rescue EltenLink::Error
        alert(_("Error"))
      else
        alert(p_("PremiumPackages", "Package activated"))
        end
      }
      return
      end
      end

class Struct_PremiumPackages_PremiumPackage
  attr_accessor :package, :name, :profits, :totime, :monthlyprice, :price, :available, :allowed, :special, :activable
  def initialize(package, name, profits=[])
    @package, @name, @profits = package, name, profits
    @totime=0
    @available, @allowed, @special = false, false, false
    @activable=false
    @price=0
  end
  end
