module Tango
  module Target
    module Go
      class FromLIR
        # Indexes the representation descriptors already committed to LIR and
        # gives them their mechanical Go spelling. It owns no strategy choice:
        # missing collection plans fail loud, and struct/union representation
        # comes directly from the corresponding LIR declaration.
        private class TypeSpeller
          @structs = {} of Tango::IR::Type => Tango::IR::LIR::StructType
          @carriers = {} of Tango::IR::Type => Tango::IR::LIR::UnionType
          @arrays = {} of Tango::IR::Type => Tango::IR::LIR::ArrayType
          @hashes = {} of Tango::IR::Type => Tango::IR::LIR::HashType
          @external_types = {} of Tango::IR::Type => Tango::IR::ExternalType
          @enums = {} of Tango::IR::Type => Tango::IR::LIR::EnumType

          def initialize(program : Tango::IR::LIR::Program, @requirements : Array(Runtime::Requirement))
            program.types.each { |type| @structs[type.type] = type }
            program.unions.each { |union| @carriers[union.type] = union }
            program.arrays.each { |array| @arrays[array.type] = array }
            program.hashes.each { |hash| @hashes[hash.type] = hash }
            program.external_types.each { |binding| @external_types[binding.type] = binding }
            program.enums.each { |definition| @enums[definition.type] = definition }
          end

          def spell(type : Tango::IR::Type?) : String
            return "interface{}" if type.nil?

            case type.family
            when .int?
              spell_integer(type)
            when .float?
              "float64"
            when .bool?
              "bool"
            when .char?
              "rune"
            when .string?
              "string"
            when .enum?
              enumeration(type).target_name
            when .array?
              spell_array(type)
            when .hash?
              spell_hash(type)
            when .proc?
              spell_proc(type)
            when .class?
              spell_class(type)
            when .union?
              spell_union(type)
            when .null?
              @requirements << Runtime::Helper.new("tangoNil")
              "tangoNil"
            else
              # Unknown — no standalone spelling this slice.
              "interface{}"
            end
          end

          def value_struct?(type : Tango::IR::Type) : Bool
            declaration = @structs[type]?
            !!declaration && !declaration.reference
          end

          def struct_name(type : Tango::IR::Type) : String
            @structs[type]?.try(&.name) || raise "missing struct representation for #{type}"
          end

          def carrier?(type : Tango::IR::Type) : Bool
            @carriers.has_key?(type)
          end

          def enum_member_name(type : Tango::IR::Type, member : String) : String
            enumeration(type).members.find { |candidate| candidate.name == member }.try(&.target_name) ||
              raise "missing enum member #{type}::#{member}"
          end

          def carrier(type : Tango::IR::Type) : Tango::IR::LIR::UnionType
            @carriers[type]? || raise "missing carrier representation for #{type}"
          end

          def variant(union : Tango::IR::Type, member : Tango::IR::Type) : Tango::IR::LIR::UnionType::Variant
            carrier = carrier(union)
            carrier.variants.find { |variant| variant.payload == member } ||
              raise "no carrier variant for #{member} in #{carrier.name}"
          end

          def payload_field(union : Tango::IR::Type, member : Tango::IR::Type) : String
            "v#{variant(union, member).label}"
          end

          def nil_tag(union : Tango::IR::Type) : Int32
            carrier(union).variants.find(&.payload.nil?).try(&.tag) ||
              raise "no nil variant for #{union}"
          end

          def require_ordered_reference_hash(type : Tango::IR::Type) : Nil
            hash = hash(type)
            return if hash.ordered? && hash.reference?

            raise "unsupported hash representation #{type}: expected insertion-ordered reference"
          end

          def array_reference?(element : Tango::IR::Type) : Bool
            array = @arrays.each_value.find { |candidate| candidate.element == element } ||
                    raise "unplanned array representation for #{element}"
            array.reference?
          end

          def external_literal_type(type : Tango::IR::Type) : String
            binding = external(type)
            unless binding.shape.named_pointer? || binding.shape.named_value?
              raise "external type #{type} cannot be used as a composite literal"
            end
            qualified_name(binding)
          end

          def floor_arithmetic_suffix(type : Tango::IR::Type) : String
            case type.family
            when .int?
              type.width.try(&.to_s) || raise "floor arithmetic has no integer width"
            when .float?
              "F64"
            else
              raise "floor arithmetic has non-numeric type #{type}"
            end
          end

          private def spell_integer(type : Tango::IR::Type) : String
            case type.width
            when Tango::IR::Type::Width::I8
              "int8"
            when Tango::IR::Type::Width::U8
              "uint8"
            when Tango::IR::Type::Width::I16
              "int16"
            when Tango::IR::Type::Width::U16
              "uint16"
            when Tango::IR::Type::Width::I32
              "int32"
            when Tango::IR::Type::Width::U32
              "uint32"
            when Tango::IR::Type::Width::I64
              "int64"
            when Tango::IR::Type::Width::U64
              "uint64"
            else
              raise "unsupported integer width #{type.width}"
            end
          end

          private def enumeration(type : Tango::IR::Type) : Tango::IR::LIR::EnumType
            @enums[type]? || raise "missing enum representation for #{type}"
          end

          private def spell_array(type : Tango::IR::Type) : String
            array = @arrays[type]? || raise "unplanned array representation #{type}"
            slice = "[]#{spell(array.element)}"
            array.reference? ? "*#{slice}" : slice
          end

          private def spell_hash(type : Tango::IR::Type) : String
            hash = hash(type)
            value = "tangoHash[#{spell(hash.key)}, #{spell(hash.value)}]"
            hash.reference? ? "*#{value}" : value
          end

          private def hash(type : Tango::IR::Type) : Tango::IR::LIR::HashType
            @hashes[type]? || raise "unplanned hash representation #{type}"
          end

          private def spell_class(type : Tango::IR::Type) : String
            if binding = @external_types[type]?
              return spell_external(binding)
            end

            declaration = @structs[type]?
            return "interface{}" unless declaration

            declaration.reference ? "*#{declaration.name}" : declaration.name
          end

          private def spell_proc(type : Tango::IR::Type) : String
            params = type.proc_param_types.map { |param| spell(param) }.join(", ")
            result = type.proc_return_type
            suffix = result && !result.nil_type? ? " #{spell(result)}" : ""
            "func(#{params})#{suffix}"
          end

          private def spell_external(binding : Tango::IR::ExternalType) : String
            external = binding.binding
            raise "unsupported external type language #{external.language}" unless external.language == "go"

            case binding.shape
            in .native_channel?
              "chan #{spell(binding.type.type_args.first?)}"
            in .named_pointer?
              "*#{qualified_name(binding)}"
            in .named_value?
              qualified_name(binding)
            end
          end

          private def external(type : Tango::IR::Type) : Tango::IR::ExternalType
            @external_types[type]? || raise "missing external type binding for #{type}"
          end

          private def qualified_name(binding : Tango::IR::ExternalType) : String
            external = binding.binding
            name = external.name || raise "external named type #{binding.type} has no name"
            external.package_identifier.try do |package_identifier|
              import_path = external.import_path || package_identifier
              @requirements << Runtime::Import.new(import_path, package_identifier)
              return "#{package_identifier}.#{name}"
            end
            name
          end

          private def spell_union(type : Tango::IR::Type) : String
            if carrier = @carriers[type]?
              carrier.name
            else
              spell(type.without_nil)
            end
          end
        end
      end
    end
  end
end
