module EltenAPI
  module Dictionary
    class PluralRule
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
        freeze
      end

      def index(count)
        evaluate(@tree, count)
      rescue ZeroDivisionError
        nil
      end

      private

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
    private_constant :PluralRule
  end
end
