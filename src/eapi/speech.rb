# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

module EltenAPI
  module Speech
    DEFAULT_SPEECH_TEXT_LIMIT = 75_000
    private

    def nvda_output
      defined?(NVDA) ? NVDA : nil
    end

    def sapi_output
      defined?(Sapi) ? Sapi : nil
    end

    def nvda_check?
      nvda = nvda_output
      nvda != nil && nvda.respond_to?(:check) && nvda.check
    end

    def speech_output
      output = SpeechOutput.current_output
      nvda = nvda_output
      if nvda != nil && output == nvda && !output.usable?
        Configuration.voice = ""
        output = SpeechOutput.current_output
      end
      output || sapi_output || SpeechOutput
    end

    def speech_output_nvda?
      nvda = nvda_output
      nvda != nil && speech_output == nvda
    end

    def speech_output_sapi?
      sapi = sapi_output
      sapi != nil && speech_output == sapi
    end

    def speech_text_limit(limit=nil)
      limit == nil ? DEFAULT_SPEECH_TEXT_LIMIT : limit.to_i
    end

    def limit_speech_text(text, limit=nil)
      text = text.to_s
      max = speech_text_limit(limit)
      return text if max <= 0 || text.length <= max
      text[0...max]
    end

    def limit_speech_sequence(sequence, limit=nil)
      max = speech_text_limit(limit)
      return sequence if max <= 0 || !sequence.respond_to?(:limited)
      sequence.limited(max)
    end

  # Speech related functions
    
    def alert(text, wait=true)
      Programs.emit_event(:speech_alert)
      speak(text)
      braille=text.is_a?(SpeechSequence) ? text.braille_text : text
      nvda_output.braille_alert(braille) if nvda_check?
      speech_wait if wait
      end
  
      @@current_speechsequence=nil
      def current_speechsequence
        return @@current_speechsequence
        end
      
      # Says a text
  #
  # @param text [String] a text to speak
  # @param stop [Boolean] whether to stop the previous message
  # @param use_dictionary [Boolean] whether to use Elten's character dictionary
  # @param id [Integer, nil] speech identifier
  # @param break_sequence [Boolean] whether to clear the active speech sequence
  # @param pan [Numeric] sound pan for commands embedded in speech sequences
  # @param limit [Integer, nil] maximum text length, 0 disables limiting
    def speak(text, stop: true, use_dictionary: true, id: nil, break_sequence: true, pan: 50, limit: nil)
      if text.is_a?(SpeechSequence)
        return speak_sequence(text, pan: pan, limit: limit)
        end
      Programs.emit_event(:speech_speak)
      if break_sequence
        @@current_speechsequence=nil
      end
      spelling=false
      id=rand(2**32) if id==nil
      $speechid=id
      swait=false
      method=stop ? 1 : 0
                  if $speech_wait==true
      method=0
      $speech_wait=false
      swait=true
      speech_wait if !speech_output_nvda?
    end
            output=speech_output
            output.set_paused(false) if text!=nil and text!="" and method!=0 and output.pause_supported?
  text = text.to_s.dup
  text.force_encoding(Encoding::UTF_8) if text.encoding != Encoding::UTF_8
  text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  text = EltenLink.legacy_line_to_text(text, eol: "\n")
  text = limit_speech_text(text, limit)
  if text == " "
    if Configuration.soundthemeactivation == true
    play_sound("editbox_space")
  else
    speak(p_("EAPI_Speech", "Space"))
    end
    return
  end
  if text == "\n"
    if Configuration.soundthemeactivation == true
    play_sound("editbox_endofline")
  else
    speak(p_("EAPI_Speech", "End of line"))
    end
    return
  end
  if text.length!=0 and ((l=text.split("")).size==1) and l[0].bigletter
      play_sound("editbox_bigletter")
              end
  if text != ""
        spelling=true if text.chrsize==1
    text = text.gsub("_"," ") if !spelling
  text_d = text
text_d.gsub!("\r\n\r\n","\n\n")
text_d.gsub!("\r\n"," ")
text_d.gsub!("\n\n","\r\n\r\n")
if spelling and use_dictionary && Configuration.usevoicedictionary==false
    text_d = get_character_name(text_d)
    spelling=false
    end
output=speech_output
nvda = nvda_output
if nvda != nil && output == nvda && !nvda.check && spelling && use_dictionary
    text_d = get_character_name(text_d)
    spelling=false
end
output.speak_text(text_d, method: method, spelling: spelling, interrupt: !swait, pitch: Configuration.voicepitch)
$speech_lasttext = text_d
end
text_d = text if text_d == nil
return text_d
end

def speak_sequence(seq, pan: 50, limit: nil)
  seq=limit_speech_sequence(seq, limit)
  $speechid=seq.id if seq.respond_to?(:id)
  output=speech_output
  nvda = nvda_output
  if nvda != nil && output == nvda && !nvda.check
    seq.reset
    seq.start(pan)
    output.speak_sequence(seq)
    @@current_speechsequence=seq
    return
  elsif nvda != nil && output == nvda
    seq.reset
    seq.start(pan)
    output.speak_sequence(seq)
    @@current_speechsequence=seq
  else
    seq.reset
seq.start(pan)
output.speak_sequence(seq)
@@current_speechsequence=seq    
end
  end

                             def speech_getindex
                               speech_output.index
                               end

# Determines if the speech is used
#
# @return [Boolean] if the speech is ued, returns true, otherwise the return value is false
def speech_actived(ignoreaudio=false)
          if !speech_output.speaking?
    return(false)
  else
    return(true)
  end
  end

  # Stops the speech
  def speech_stop(audio=true)
    Programs.emit_event(:speech_stop)
        $speech_wait=false
    @@current_speechsequence=nil
      speech_output.stop
  
  end
  
  # Waits for a speech to finish reading of the previous message
      def speech_wait
        if !speech_output_nvda?
    while speech_actived == true
loop_update(false)
end
else
  $speech_wait = true
  end
  return
end

# Returns the character dictionary name
#
# @param text [String] a character you want to search dictionary for
# @return [String] a dictionary name of the character
def get_character_name(text, abs=false)
  r=""
  case text
  when "."
    r=p_("EAPI_Speech", "dot")
    when ","
      r=p_("EAPI_Speech", "comma")
      when "/"
        r=p_("EAPI_Speech", "slash")
        when ";"
          r=p_("EAPI_Speech", "semi")
          when "'"
            r=p_("EAPI_Speech", "tick")
            when "["
              r=p_("EAPI_Speech", "left bracket")
              when "]"
                r=p_("EAPI_Speech", "right bracket")
                when "\\"
                  r=p_("EAPI_Speech", "backslash")
                  when "-"
                    r=p_("EAPI_Speech", "dash")
                    when "="
                      r=p_("EAPI_Speech", "equals")
                      when "`"
                        r=p_("EAPI_Speech", "graav")
                        when "<"
                          r=p_("EAPI_Speech", "less")
                          when ">"
                            r=p_("EAPI_Speech", "greater")
                            when "?"
                              r=p_("EAPI_Speech", "question")
                              when ":"
                                r=p_("EAPI_Speech", "colon")
                                when "\""
                                  r=p_("EAPI_Speech", "quote")
                                  when "{"
                                    r=p_("EAPI_Speech", "left brace")
                                    when "}"
                                      r=p_("EAPI_Speech", "right brace")
                                      when "|"
                                        r=p_("EAPI_Speech", "bar")
                                        when "_"
                                          r=p_("EAPI_Speech", "line")
                                          when "+"
                                            r=p_("EAPI_Speech", "plus")
                                            when "!"
                                              r=p_("EAPI_Speech", "bang")
                                              when "@"
                                                r=p_("EAPI_Speech", "at")
                                                when "#"
                                                  r=p_("EAPI_Speech", "hash")
                                                  when "$"
                                                    r=p_("EAPI_Speech", "dollar")
                                                    when "%"
                                                      r=p_("EAPI_Speech", "percent")
                                                      when "^"
                                                        r=p_("EAPI_Speech", "caret")
                                                        when "\&"
                                                          r=p_("EAPI_Speech", "and")
                                                          when "*"
                                                            r=p_("EAPI_Speech", "star")
                                                            when "("
                                                              r=p_("EAPI_Speech", "left paren")
                                                              when ")"
                                                                r=p_("EAPI_Speech", "right paren")
                                                                when "ü"
                                                                                                                                    r="u umlaut" if Configuration.language=="pl-PL"
                                                                  when "Ü"
                                                                    r="U umlaut" if Configuration.language=="pl-PL"
                                                                    when "ä"
                                                                      r="a umlaut" if Configuration.language=="pl-PL"
                                                                      when "Ä"
                                                                 r="A umlaut" if Configuration.language=="pl-PL"
                                                                 when "ö"
                                                                   r="o umlaut" if Configuration.language=="pl-PL"
                                                                   when "Ö"
                                                                     r="O umlaut" if Configuration.language=="pl-PL"
when "ß"
                                                                     r="długie s" if Configuration.language=="pl-PL"
                                                                     when "´"
                                                                     r="ostry akcent" if Configuration.language=="pl-PL"
                                                                   end
                                                                   if abs and text==" "
                                                                     r=p_("EAPI_Speech", "Space")
                                                                     end
                      if r==""
                        return(text)
                      else
                        return(r)
                        end
                      end
                      
                      # Toggles the speech pause
     def speech_togglepause
       Programs.emit_event(:speech_toggle)
       output=speech_output
       return if !output.pause_supported?
  if !output.paused?
  output.set_paused(true)
    else
  output.set_paused(false)
  end
  end

module SpeechCommands
class SpeechCommand
  def immediate?
    false
  end

  def speech_text
    ""
  end

  def braille_text
    speech_text
  end

  def to_s
    speech_text.to_s
  end

  def execute(_pos=50)
    end
  end

  class SoundCommand < SpeechCommand
    attr_reader :sound, :speech_fallback, :braille_fallback

    def initialize(sound=nil, speech_fallback=nil, braille_fallback=nil, immediate: true, play_immediately: nil)
      @sound=sound
      @speech_fallback=speech_fallback
      @braille_fallback=braille_fallback
      @immediate=play_immediately==nil ? immediate : play_immediately
    end

    def immediate?
      @immediate!=false
    end

    def speech_text
      return "" if sound_only?
      @speech_fallback.to_s
    end

    def braille_text
      fallback=@braille_fallback==nil ? @speech_fallback : @braille_fallback
      fallback.to_s
    end

    def to_s
      @speech_fallback.to_s
    end

    def execute_at(pos=50)
      play_sound(@sound, pan: pos) if @sound!=nil && @sound.to_s!=""
    end

    def execute(pos=50)
      execute_at(pos)
    end

    private

    def sound_only?
      Configuration.soundthemeactivation==true
    end
  end
  class CustomCommand < SpeechCommand
    def initialize(*arg, immediate: false, &p)
      @arg=arg
      @proc=p
      @immediate=immediate
    end

    def immediate?
      @immediate==true
    end

    def execute(_pos=50)
      @proc.call(*@arg) if @proc!=nil
    end
    end
end

class SpeechSequence
  attr_reader :id, :commands

  def initialize(*commands)
    commands=commands[0] if commands.size==1 && commands[0].is_a?(Array)
    @commands=normalize_commands(commands||[])
    @id = rand(10**9)
    rebuild
    reset
  end

  def <<(part)
    @commands+=normalize_commands([part])
    rebuild
    self
  end

  def +(other)
    SpeechSequence.new(@commands+normalize_commands([other]))
  end

  def prepend(part)
    @commands=normalize_commands([part])+@commands
    rebuild
    self
  end

  def append(part)
    self << part
  end

  def reset
    @lastindex=0
    @started=false
    @pos||=50
  end

  def start(pos=50)
    return if @started
    @pos=pos||50
    @started=true
    @initial_commands.each{|command|command.execute(@pos)}
  end

  def size
    to_s.size
  end

  alias length size

  def empty?
    to_s.empty?
  end

  def texts
    @texts.dup
  end

  def text
    return @speech_text_cache if @speech_text_cache!=nil
    @speech_text_cache=@texts.join("")
  end

  def braille_text
    return @braille_text_cache if @braille_text_cache!=nil
    @braille_text_cache=@commands.map{|command|
      command.is_a?(SpeechCommands::SpeechCommand) ? command.braille_text.to_s : command.to_s
    }.join("")
  end

  def indexes
    @indexes.dup
  end

  def indexed?
    @indexes.size>0
  end

  def limited(max_chars)
    max_chars=max_chars.to_i
    return self if max_chars<=0
    remaining=max_chars
    limited_commands=[]
    changed=false
    @commands.each do |command|
      text=command.to_s
      length=text.length
      if length==0
        limited_commands.push(command) if remaining>0
        next
      end
      if length<=remaining
        limited_commands.push(command)
        remaining-=length
      else
        limited_commands.push(text[0...remaining]) if remaining>0
        changed=true
        remaining=0
        break
      end
    end
    changed=true if limited_commands.size!=@commands.size
    changed ? SpeechSequence.new(limited_commands) : self
  end

  def execute(index, pos=nil)
    sleep(0.01) while @running
    @running=true
    index=index.to_i
    (@lastindex+1..index).each do |i|
      (@indexed_commands[i]||[]).each do |command|
        command.execute(pos||@pos||50)
      end
    end
    @running=false
    @lastindex=index
  ensure
    @running=false
    end

    def run
      speak_sequence(self)
    end

    def speech_text
      text
    end

    def to_s
      return @textcache if @textcache!=nil
      @textcache=@commands.map{|command|command.to_s}.join("")
    end

    def []( *arg)
      to_s.[](*arg)
    end

    def include?(*arg)
      to_s.include?(*arg)
    end

    def downcase(*arg)
      to_s.downcase(*arg)
    end

    def upcase(*arg)
      to_s.upcase(*arg)
    end

    def delete(*arg)
      to_s.delete(*arg)
    end

    def gsub(*arg, &block)
      to_s.gsub(*arg, &block)
    end

    def split(*arg, &block)
      to_s.split(*arg, &block)
    end

    def chrsize
      to_s.chrsize
    end

    def match(*arg)
      to_s.match(*arg)
    end

    def =~(other)
      to_s=~other
    end

    protected

    def normalize_commands(commands)
      normalized=[]
      commands.each do |command|
        if command.is_a?(SpeechSequence)
          normalized+=command.commands
        elsif command.is_a?(Array)
          normalized+=normalize_commands(command)
        elsif command.is_a?(SpeechCommands::SpeechCommand) || command.is_a?(String)
          normalized.push(command)
        else
          normalized.push(command.to_s)
        end
      end
      normalized
    end

    def rebuild
      @texts=[]
      @indexes=[]
      @indexed_commands={}
      @initial_commands=[]
      index=0
      @commands.each do |command|
        if command.is_a?(SpeechCommands::SpeechCommand)
          if command.immediate?
            @initial_commands.push(command)
            text=command.speech_text.to_s
            if text!=""
              index+=1
              @indexes.push(index)
              @texts.push(text)
            end
          else
            index+=1
            @indexes.push(index)
            @texts.push(command.speech_text.to_s)
            @indexed_commands[index]||=[]
            @indexed_commands[index].push(command)
          end
        else
          text=command.to_s
          next if text==""
          index+=1
          @indexes.push(index)
          @texts.push(text)
        end
      end
      @textcache=nil
      @speech_text_cache=nil
      @braille_text_cache=nil
    @running=false
    end
end

class SpeechSoundsCollection
  attr_accessor :text
  def initialize(text="", coll=[])
    @text=text
    @collection=coll.dup
  end
  def add_sound(c)
@collection.push(c)
end
def play(pos=50)
  @collection.each{|c|
  play_sound(c, volume: 100, pitch: 100, pan: pos)
  }
  speak(text)
end
def to_s
  @text
  end
  end
end
 include Speech
end
