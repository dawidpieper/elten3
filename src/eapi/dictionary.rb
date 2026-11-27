# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3. 
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details. 
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>. 

require_relative "resources" if !defined?(EltenAPI::Resources)

module EltenAPI
  module Dictionary
    private
    CatalogMutex = Mutex.new
    Docs={}
    Languages=[]

    class CatalogRegistry
      attr_accessor :host
      attr_reader :programs

      def initialize
        @host = [].freeze
        @programs = {}.freeze
        @key_counts = Hash.new(0)
      end

      # Readers keep this immutable map after releasing CatalogMutex.
      def programs_for_key(key)
        @programs if @key_counts.key?(key)
      end

      def programs=(catalogs)
        @programs.each_pair do |runtime, old|
          next if !old || old.equal?(catalogs[runtime])
          old.each_context_key do |key|
            @key_counts[key] -= 1
            @key_counts.delete(key) if @key_counts[key].zero?
          end
        end
        catalogs.each_pair do |runtime, catalog|
          next if !catalog || catalog.equal?(@programs[runtime])
          catalog.each_context_key { |key| @key_counts[key] += 1 }
        end
        @programs = catalogs.freeze
      end
    end
    Catalogs = CatalogRegistry.new

    class PluralRule
      MAX_PERIOD_ENTRIES = 256
      OPERATORS = [%w[||], %w[&&], %w[== !=], %w[< <= > >=], %w[+ -], %w[* / %]].each(&:freeze).freeze

      def initialize(expression)
        source = expression.to_s
        raise ArgumentError, "Invalid plural expression" if source.empty? || source.bytesize > 2048
        @tokens = source.scan(/\d+|n|&&|\|\||==|!=|<=|>=|\S/)
        raise ArgumentError, "Invalid plural expression" if @tokens.size > 256
        @position = 0
        @tree = expression_tree
        raise ArgumentError, "Unexpected plural token" if @position != @tokens.size
        @tokens = nil
        cycle = eventual_period(@tree)
        if cycle
          @cycle_start, @period = cycle
          @indices = Array.new(@cycle_start + @period) { |count| interpret(count) }.freeze
        end
        freeze
      end

      def index(count)
        if @indices && count.is_a?(Integer) && count >= 0
          return @indices[count] if count < @indices.size
          return @indices[@cycle_start + (count - @cycle_start) % @period]
        end
        interpret(count)
      end

      private

      def interpret(count)
        evaluate(@tree, count)
      rescue ZeroDivisionError
        nil
      end

      # For nonnegative n, the value repeats every period once n reaches start.
      # Recognize bare n in a comparison with a literal or a remainder by a literal.
      def eventual_period(tree)
        return [0, 1] if tree.is_a?(Integer)
        return nil if tree == :n

        operator, left, right = tree
        case operator
        when "%"
          return [0, right] if left == :n && right.is_a?(Integer) && right.between?(1, MAX_PERIOD_ENTRIES)
        when "==", "!=", "<", "<=", ">", ">="
          bound = right if left == :n
          bound = left if right == :n
          return [bound + 1, 1] if bound.is_a?(Integer) && bound < MAX_PERIOD_ENTRIES - 1
        end

        # Once every operand repeats, their combination repeats at the common period.
        start = 0
        period = 1
        tree.drop(1).each do |operand|
          cycle = eventual_period(operand)
          return nil unless cycle
          start = [start, cycle[0]].max
          period = period.lcm(cycle[1])
          return nil if start + period > MAX_PERIOD_ENTRIES
        end
        [start, period]
      end

      def take(token)
        return false if @tokens[@position] != token
        @position += 1
        true
      end

      def expect(token)
        raise ArgumentError, "Invalid plural expression" if !take(token)
      end

      def expression_tree
        tree = binary_tree(0)
        if take("?")
          positive = expression_tree
          expect(":")
          tree = ["?", tree, positive, expression_tree]
        end
        tree
      end

      def binary_tree(level)
        return unary_tree if level == OPERATORS.size
        tree = binary_tree(level + 1)
        while OPERATORS[level].include?(@tokens[@position])
          operator = @tokens[@position]
          @position += 1
          tree = [operator, tree, binary_tree(level + 1)]
        end
        tree
      end

      def unary_tree
        return ["!", unary_tree] if take("!")
        return ["negate", unary_tree] if take("-")
        return unary_tree if take("+")
        if take("(")
          tree = expression_tree
          expect(")")
          return tree
        end
        token = @tokens[@position]
        raise ArgumentError, "Invalid plural operand" if token == nil || (token != "n" && !token.match?(/\A\d+\z/))
        @position += 1
        token == "n" ? :n : token.to_i
      end

      def evaluate(tree, count)
        return count if tree == :n
        return tree if tree.is_a?(Integer)
        operator, left, right, other = tree
        a = evaluate(left, count)
        case operator
        when "?" then evaluate(a != 0 ? right : other, count)
        when "!" then a == 0 ? 1 : 0
        when "negate" then -a
        when "&&" then a != 0 && evaluate(right, count) != 0 ? 1 : 0
        when "||" then a != 0 || evaluate(right, count) != 0 ? 1 : 0
        else
          b = evaluate(right, count)
          case operator
          when "+" then a + b
          when "-" then a - b
          when "*" then a * b
          when "/", "%"
            quotient = a.abs.div(b.abs)
            quotient = -quotient if (a < 0) != (b < 0)
            operator == "/" ? quotient : a - quotient * b
          when "==" then a == b ? 1 : 0
          when "!=" then a != b ? 1 : 0
          when "<" then a < b ? 1 : 0
          when "<=" then a <= b ? 1 : 0
          when ">" then a > b ? 1 : 0
          when ">=" then a >= b ? 1 : 0
          end
        end
      end
    end

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

      def singular_label(key)
        entry = @entries[key]
        return unless entry
        value = entry[1][0]
        value if value && !value.empty?
      end

      def translate(forms, count = nil)
        entry = @entries[forms.first]
        return nil if entry == nil
        return nil if forms.size > 1 && entry[0][0, forms.size] != forms
        index = count == nil ? 0 : plural_index(count)
        return nil if index == nil
        value = entry[1][index]
        value.dup if value != nil && !value.empty?
      end

      def each_context_key
        @entries.each_key { |key| yield key if key.include?("\004") }
      end

      def plural_index(count)
        index = @plural_rule.index(count)
        index if index != nil && index >= 0 && index < @plural_count
      end
    end
    private_constant :PluralRule, :Catalog, :CatalogRegistry, :Catalogs, :CatalogMutex
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
    programs = Catalogs.programs.to_h { |runtime, _| [runtime, read_program_catalog(runtime, code)] }
    Catalogs.programs = programs
    Catalogs.host = [catalog].freeze
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
    Catalogs.host = (reset ? [catalog] : Catalogs.host + [catalog]).freeze
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
  translate_message([source]) || source
end

def n_(*params)
  forms, count = plural_arguments(params)
  translate_message(forms, count) || plural_source(forms, count)
end

def p_(context, src)
  source = locale_text(src)
  translate_contextual_label(source, context) || source
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
  translate_contextual_message(forms, context, count) || n_(src, *params)
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

def translate_contextual_label(source, context)
  key = "#{locale_text(context)}\004#{source}"
  programs = nil
  value = nil
  CatalogMutex.synchronize do
    hosts = Catalogs.host
    index = 0
    while (catalog = hosts[index])
      value = catalog.singular_label(key)
      break if value
      index += 1
    end
    programs = Catalogs.programs_for_key(key) unless value
  end
  value = programs[program_translation_runtime]&.singular_label(key) if programs
  value&.dup
end

def translate_contextual_message(forms, context, count = nil)
  return nil if forms.empty?
  key = "#{locale_text(context)}\004#{forms.first}"
  forms[0] = key
  programs = nil
  host = CatalogMutex.synchronize do
    programs = Catalogs.programs_for_key(key)
    Catalogs.host
  end
  index = 0
  while (catalog = host[index])
    value = catalog.translate(forms, count)
    return value if value != nil
    index += 1
  end
  if programs
    catalog = programs[program_translation_runtime]
    catalog&.translate(forms, count)
  end
end

def translate_message(forms, count = nil)
  return nil if forms.empty?
  runtime = program_translation_runtime
  catalogs = CatalogMutex.synchronize do
    program = Catalogs.programs[runtime]
    program ? Catalogs.host + [program] : Catalogs.host
  end
  context = runtime.manifest.name if runtime != nil && runtime.manifest != nil
  if context != nil
    contextual = forms.dup
    contextual[0] = locale_text(context) + "\004" + forms.first.to_s
    catalogs.each do |catalog|
      value = catalog.translate(contextual, count)
      return value if value != nil
    end
  end
  catalogs.each do |catalog|
    value = catalog.translate(forms, count)
    return value if value != nil
  end
  nil
end

def plural_arguments(params)
  forms = []
  count = 0
  params.each do |argument|
    case argument
    when String
      forms << locale_text(argument)
    when Integer
      count = argument
    end
  end
  [forms, count]
end

def plural_source(forms, count)
  index = count == 1 ? 0 : 1
  if forms.size > 2
    catalog = CatalogMutex.synchronize { Catalogs.host.first }
    index = catalog.plural_index(count) || index if catalog != nil
  end
  forms[index] || forms.last
end

def load_program_locale(runtime, code)
  CatalogMutex.synchronize do
    catalog = read_program_catalog(runtime, code, Catalogs.programs[runtime])
    Catalogs.programs = Catalogs.programs.merge(runtime => catalog)
    catalog
  end
end

def remove_program_locale(runtime)
  CatalogMutex.synchronize do
    programs = Catalogs.programs.dup
    removed = programs.delete(runtime)
    Catalogs.programs = programs
    removed
  end
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
