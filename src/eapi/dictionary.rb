# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

require_relative "resources" if !defined?(EltenAPI::Resources)
require_relative "dictionary_plural_rule"

module EltenAPI
  module Dictionary
    private
    Catalogs = {nil => [].freeze}
    CatalogMutex = Mutex.new
    Docs={}
    Languages=[]

    class Catalog
      def initialize(data)
        @entries = {}
        @plural_count = 2
        @plural_rule = PluralRule.new("n != 1")
        if data != nil && !data.empty?
          data = data.to_s.b
          raise ArgumentError, "Truncated translation catalog" if data.bytesize < 28
          order = case data.unpack1("V")
          when 0x950412de then "V"
          when 0xde120495 then "N"
          else raise ArgumentError, "Invalid translation catalog"
          end
          revision, count, originals, translations = data.byteslice(4, 16).unpack("#{order}4")
          if revision != 0 || [originals, translations].any? { |offset| offset < 28 || offset + count * 8 > data.bytesize }
            raise ArgumentError, "Invalid translation catalog tables"
          end
          read = lambda do |table, index|
            length, offset = data.byteslice(table + index * 8, 8).unpack("#{order}2")
            if offset < 28 || offset + length >= data.bytesize || data.getbyte(offset + length) != 0
              raise ArgumentError, "Truncated translation catalog string"
            end
            data.byteslice(offset, length)
          end
          entries = count.times.map { |index| [read.call(originals, index), read.call(translations, index)] }
          header = entries.find { |source, _translation| source.empty? }&.last.to_s
          charset = header[/^Content-Type:[^\r\n]*\bcharset\s*=\s*"?([^;\s"]+)/i, 1] || "UTF-8"
          encoding = Encoding.find(charset)
          raise ArgumentError, "Invalid translation encoding" if !encoding.ascii_compatible?
          forms = header[/^Plural-Forms:\s*([^\r\n]+)/i, 1]
          if forms != nil
            @plural_count = forms[/\bnplurals\s*=\s*(\d+)\s*;/, 1].to_i
            raise ArgumentError, "Invalid plural form count" if !(1..16).include?(@plural_count)
            @plural_rule = PluralRule.new(forms[/\bplural\s*=\s*([^;]+);?/, 1])
          end
          entries.each do |source, translation|
            next if source.empty?
            values = [source, translation].map do |value|
              value.force_encoding(encoding)
              raise ArgumentError, "Invalid translation encoding" if !value.valid_encoding?
              value.encode(Encoding::UTF_8).split("\0", -1).each(&:freeze).freeze
            end
            @entries[values[0].first] ||= values.freeze
          end
        end
        @entries.freeze
        freeze
      end

      def translate(forms, count = nil)
        entry = @entries[forms.first]
        return nil if entry == nil || entry[0].size < forms.size || entry[0][0, forms.size] != forms
        index = count == nil ? 0 : plural_index(count)
        return nil if index == nil
        value = entry[1][index]
        value.dup if value != nil && !value.empty?
      end

      def plural_index(count)
        index = @plural_rule.index(count)
        index if index != nil && index >= 0 && index < @plural_count
      end
    end
    private_constant :Catalog, :Catalogs, :CatalogMutex
  def locale_text(value)
    str=value.to_s.dup
    if str.encoding==Encoding::UTF_8
      return str if str.valid_encoding?
    elsif str.encoding==Encoding::ASCII_8BIT
      str.force_encoding(Encoding::UTF_8)
      return str if str.valid_encoding?
    end
    str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  rescue Encoding::CompatibilityError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    value.to_s.b.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  end
  class Language
    attr_accessor :code, :mo, :docs
    def initialize(code="")
      @code=code
      @mo=""
      @docs={}
    end
    def realcode
      value=@code.to_s.tr("_","-")
      if value =~ /\A([a-zA-Z]{2})-([a-zA-Z]{2})\z/
        return $1.downcase+"-"+$2.upcase
      elsif value =~ /\A([a-zA-Z]{2})([a-zA-Z]{2})\z/
        return $1.downcase+"-"+$2.upcase
      end
      value
      end
     end
     def loadedlanguages
      return (Languages.deep_dup)||[] if Languages.respond_to?(:deep_dup)
      Languages.map do |language|
        copy=Language.new(language.code)
        copy.mo=language.mo.to_s.dup
        copy.docs=language.docs.dup
        copy
      end
      end
     def loadlocaledata(file=nil)
       languages=load_resource_locales
       Languages.clear
       languages.each { |language| Languages.push(language) }
     rescue Exception => e
       Log.warning("Cannot load locale resources: #{e.class}: #{e.message}") if defined?(Log)
     end
     def getlocale(code)
       normalized=normalize_locale_code(code)
       lang=nil
     Languages.each do |l|
      if l.realcode.downcase==normalized.downcase
        lang=l
        break
        end
    end
    return lang
       end
def setlocale(code)
  code = normalize_locale_code(code)
  lang = getlocale(code)
  return if lang == nil
  catalog = Catalog.new(lang.mo)
  CatalogMutex.synchronize do
    catalogs = {nil => [catalog].freeze}
    Catalogs.each_key do |runtime|
      catalogs[runtime] = read_program_catalog(runtime, code) if runtime != nil
    end
    Catalogs.replace(catalogs)
    Docs.replace(lang.docs)
  end
rescue ArgumentError, EncodingError => e
  Log.warning("Cannot load locale #{code}: #{e.class}: #{e.message}") if defined?(Log)
  nil
end

def loadlocale(file, reset=true)
  loadmo(File.binread(file), reset) if File.file?(file)
end

def loadmo(data, reset=true)
  catalog = Catalog.new(data)
  CatalogMutex.synchronize do
    Catalogs[nil] = (reset ? [catalog] : Catalogs[nil] + [catalog]).freeze
  end
  true
rescue ArgumentError, EncodingError => e
  Log.warning("Cannot load translation catalog: #{e.class}: #{e.message}") if defined?(Log)
  nil
end
def _doc(d)
  fallback=getlocale("en-GB")
  locale_text(Docs[d]||(fallback!=nil ? fallback.docs[d] : nil)||"")
  end
def _(src)
  source = locale_text(src)
  translate_message([source], implicit: true) || source
end

def n_(*params)
  forms, count = plural_arguments(params)
  translate_message(forms, count, implicit: true) || plural_source(forms, count)
end

def p_(context, src)
  source = locale_text(src)
  translate_message([source], context: locale_text(context)) || source
end
def s_(str)
  s=_(str)
  if s==str
    return str[str.index("|")+1..-1]
  else
    return str
    end
  end
def np_(context, src, *params)
  forms, count = plural_arguments([src.to_s, *params])
  translate_message(forms, count, context: locale_text(context)) || n_(src, *params)
end
def ns_(context, src, *params)
  str=n_(context+"|"+src, *params)
  str.sub(context+"|","")
end
def N_(*params);end
  def Nn_(*params);end
private
def normalize_locale_code(code)
  value=code.to_s.tr("_","-")
  if value =~ /\A([a-zA-Z]{2})-([a-zA-Z]{2})\z/
    return $1.downcase+"-"+$2.upcase
  elsif value =~ /\A([a-zA-Z]{2})([a-zA-Z]{2})\z/
    return $1.downcase+"-"+$2.upcase
  end
  value
end

def load_resource_locales
  keys=EltenAPI::Resources.keys("locale", base: ".")
  by_code={}
  keys.each do |key|
    parts=key.split("/")
    next if parts[0]!="locale" || parts[1].to_s==""
    code=normalize_locale_code(parts[1])
    next if code==""
    by_code[code]||=[]
    by_code[code] << key
  end
  by_code.keys.sort_by(&:downcase).map do |code|
    build_resource_locale(code, by_code[code])
  end.compact
end

def build_resource_locale(code, keys)
  lang=Language.new(code)
  mo_key=keys.find { |key| key =~ /\Alocale\/[^\/]+\/lc_messages\/[^\/]+\.mo\z/i }
  lang.mo=EltenAPI::Resources.read(mo_key, base: ".").to_s.b if mo_key!=nil
  keys.each do |key|
    next if File.extname(key).downcase!=".md"
    relative=key.split("/")[2..-1].join("/")
    next if relative.to_s=="" || relative.downcase.start_with?("lc_messages/")
    name=relative.sub(/\.md\z/i, "")
    doc=EltenAPI::Resources.read(key, base: ".")
    lang.docs[locale_text(name)]=locale_text(doc) if doc!=nil
  end
  return nil if lang.mo.to_s=="" && lang.docs.empty?
  lang
end

def program_translation_runtime
  return nil if !defined?(Programs)
  Programs.current_runtime || Programs.runtime_from_caller
rescue StandardError
  nil
end

def translation_catalogs(runtime)
  CatalogMutex.synchronize do
    host = Catalogs[nil]
    catalog = Catalogs[runtime] if runtime != nil
    catalog == nil ? host : host + [catalog]
  end
end

def translate_message(forms, count = nil, context: nil, implicit: false)
  return nil if forms.empty?
  runtime = program_translation_runtime
  catalogs = translation_catalogs(runtime)
  context = runtime.manifest.name if implicit && runtime != nil && runtime.manifest != nil
  if context != nil
    contextual = forms.dup
    contextual[0] = locale_text(context) + "\004" + forms.first.to_s
    catalogs.each do |catalog|
      value = catalog.translate(contextual, count)
      return value if value != nil
    end
    return nil if !implicit
  end
  catalogs.each do |catalog|
    value = catalog.translate(forms, count)
    return value if value != nil
  end
  nil
end

def plural_arguments(params)
  [params.grep(String).map { |value| locale_text(value) }, params.grep(Integer).last || 0]
end

def plural_source(forms, count)
  index = count == 1 ? 0 : 1
  if forms.size > 2
    catalog = CatalogMutex.synchronize { Catalogs[nil].first }
    index = catalog.plural_index(count) || index if catalog != nil
  end
  forms[index] || forms.last
end

def load_program_locale(runtime, code)
  CatalogMutex.synchronize { Catalogs[runtime] = read_program_catalog(runtime, code, Catalogs[runtime]) }
end

def remove_program_locale(runtime)
  CatalogMutex.synchronize { Catalogs.delete(runtime) }
end

def read_program_catalog(runtime, code, previous = nil)
  return nil if code == nil
  data = runtime.language_data(code)
  Catalog.new(data) if data != nil && !data.empty?
rescue StandardError => e
  Log.warning("Cannot load program locale #{runtime.entry_id}: #{e.class}: #{e.message}") if defined?(Log)
  previous
end
  end
  include Dictionary
  end
