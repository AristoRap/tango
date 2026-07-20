module Tango
  module Analysis
    module Passes
      # Classifies whether the target may use native equality for a type. The
      # verdict separates target rejection from legal-but-wrong semantics so
      # planning can fail closed with a useful diagnostic.
      class Comparability
        def self.run(program : IR::NIR::Program, table : Facts::Table) : Nil
          new.run(table)
        end

        def run(table : Facts::Table) : Nil
          types = Set(IR::Type).new
          table.types.expressions.each_value { |type| types << type }
          table.types.hashes.each do |type|
            type.key_type.try { |key| types << key }
            type.value_type.try { |value| types << value }
          end
          table.struct_layouts.each_value do |layout|
            layout.fields.each { |field| types << field.type }
          end
          types.each { |type| classify(type, table, Set(IR::Type).new) }
        end

        private def classify(type : IR::Type, table : Facts::Table, visiting : Set(IR::Type)) : Facts::Comparability
          if verdict = table.comparabilities[type]?
            return verdict
          end
          return Facts::GoRejects.new("recursive value layout") unless visiting.add?(type)

          verdict = case type.family
                    when .int?, .float?, .bool?, .string?, .enum?, .null?
                      Facts::Comparable.new
                    when .proc?
                      Facts::GoRejects.new("function values only compare to nil")
                    when .array?, .hash?
                      Facts::WrongSemantics.new("collection identity is not Crystal value equality")
                    when .union?
                      classify_group(type.members, table, visiting, "member")
                    when .class?
                      classify_class(type, table, visiting)
                    else
                      Facts::GoRejects.new("no native equality mapping for #{type}")
                    end
          visiting.delete(type)
          table.comparabilities[type] = verdict
          verdict
        end

        private def classify_class(type : IR::Type, table : Facts::Table, visiting : Set(IR::Type)) : Facts::Comparability
          name = type.name
          layout = table.struct_layouts[type.to_s]? || name.try { |value| table.struct_layouts[value]? }
          return Facts::Comparable.new unless layout
          return Facts::Comparable.new if layout.reference

          layout.fields.each do |field|
            verdict = classify(field.type, table, visiting)
            next if verdict.is_a?(Facts::Comparable)
            return wrap(verdict, "field #{field.name} : #{field.type}")
          end
          Facts::Comparable.new
        end

        private def classify_group(types : Array(IR::Type), table : Facts::Table, visiting : Set(IR::Type), label : String) : Facts::Comparability
          types.each do |type|
            verdict = classify(type, table, visiting)
            next if verdict.is_a?(Facts::Comparable)
            return wrap(verdict, "#{label} #{type}")
          end
          Facts::Comparable.new
        end

        private def wrap(verdict : Facts::Comparability, prefix : String) : Facts::Comparability
          case verdict
          when Facts::GoRejects
            Facts::GoRejects.new("#{prefix} — #{verdict.reason}")
          when Facts::WrongSemantics
            Facts::WrongSemantics.new("#{prefix} — #{verdict.reason}")
          else
            verdict
          end
        end
      end
    end
  end
end
