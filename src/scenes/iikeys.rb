class Scene_IIKeys
  def main
    @keys=[]
    add("Up/Down Arrow", p_("IIKeys", "Navigate up or down on lists"))
    add("Left/Right Arrow", p_("IIKeys", "Change current tab"))
    add("Home/End", p_("IIKeys", "Jump to the first or last item"))
    add("Page up / Page down", p_("IIKeys", "In messages, jump to another conversation"))
    add("Enter", p_("IIKeys", "Activate the selected item"))
    add("Backspace", p_("IIKeys", "Cancel speech and stop currently played audio"))
    add("Space", p_("IIKeys", "Repeat the currently selected item"))
add("R", p_("IIKeys", "Reply"))
add("K", p_("IIKeys", "Like or dislike a feed message"))
    add("M", p_("IIKeys", "Write a new message"))
    add("F", p_("IIKeys", "Post on a feed"))
show    
loop {
loop_update
@sel.update
break if key_pressed?(:key_escape)
}
$scene=Scene_Main.new
  end
  def add(k, v)
    @keys.push([k, v])
    end
  def show
    hk=Configuration.iimodifiers
         keys=[]
         keys.push("ALT") if (hk&0x1)>0
         keys.push("CTRL") if (hk&0x2)>0
         keys.push("SHIFT") if (hk&0x4)>0
         keys.push("WINDOWS") if (hk&0x8)>0
         hkname=keys.join(" + ")
         selt = @keys.map{|k|
         [hkname+" + "+k[0], k[1]]
         }
         @sel = TableBox.new([nil, nil], selt, index: 0, header: p_("IIKeys", "Invisible Interface Hotkeys"), quiet: false)
  end
  end