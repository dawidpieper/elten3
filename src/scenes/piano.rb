class Scene_Piano
  def main
    as=[]
    loop do
      freq=0
            loop_update
      if key_pressed?(:key_escape)
        $scene=Scene_Main.new
        break
        end
freqs = {
0x31=>77.8,
0x33=>92.5,
0x34=>103.8,
0x35=>116.6,
0x37=>138.6,
0x38=>155.6,
0x39=>185.0,
0xBD=>207.7,
0xBB=>266.2,
0x51=>82.4,
0x57=>87.3,
0x45=>98.0,
0x52=>110.0,
0x54=>123.5,
0x59=>130.8,
0x55=>146.9,
0x49=>164.8,
0x4F=>174.6,
0x50=>192.0,
0xDB=>220.0,
0xDD=>246.9,
0x41=>261.6,
0x53=>293.7,
0x44=>329.6,
0x46=>349.2,
0x47=>392.0,
0x48=>440.0,
0x4A=>493.9,
0x4B=>523.3,
0x4C=>587.3,
0xBA=>659.3,
0xDE=>698.5,
0x5A=>277.2,
0x58=>311.1,
0x56=>370.0,
0x42=>415.3,
0x4E=>466.2,
0xBC=>554.4,
0xBE=>622.3,
0xBF=>740.0
}
freqs.each do |k,freq|
  if key_pressed?(k)
if freq != 0
a=Sound.new(stream: getsound("signal", true))
a.frequency=a.frequency/466.2*freq
  a.frequency+=freq
a.play
as.push(a)
end
end
end
end
as.each {|a| a.close}
  end
  end
