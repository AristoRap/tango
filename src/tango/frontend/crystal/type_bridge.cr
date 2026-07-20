module Tango
  module Frontend
    module Crystal
      # The one Crystal Type -> target-neutral IR::Type bridge. The semantic
      # frontend has already inferred and narrowed these types; this module only
      # preserves their structured identity for downstream phases.
      module TypeBridge
        private def type_of(node : ::Crystal::ASTNode) : IR::Type?
          crystal_type = node.type?
          crystal_type ? build_type(crystal_type) : nil
        end

        private def build_type(type : ::Crystal::Type) : IR::Type
          built = if type.is_a?(::Crystal::VirtualType)
                    build_type(type.base_type)
                  elsif type.is_a?(::Crystal::EnumType)
                    IR::Type.enumeration(type.name)
                  elsif type.is_a?(::Crystal::UnionType)
                    IR::Type.union(type.union_types.map { |member| build_type(member) })
                  elsif type.is_a?(::Crystal::ProcInstanceType)
                    IR::Type.proc(type.arg_types.map { |arg| build_type(arg) }, build_type(type.return_type))
                  elsif ordinary_generic?(type)
                    generic = type.as(::Crystal::GenericInstanceType)
                    name = generic.generic_type.name
                    args = generic_args(generic)
                    case name
                    when "Array" then IR::Type.array(args.first? || IR::Type.unknown)
                    when "Hash"  then IR::Type.hash(args.first? || IR::Type.unknown, args[1]? || IR::Type.unknown)
                    else              IR::Type.klass(name, args)
                    end
                  else
                    case name = type.to_s
                    when "Nil"    then IR::Type::NIL
                    when "Bool"   then IR::Type.bool
                    when "Char"   then IR::Type.char
                    when "String" then IR::Type.string
                    when "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64"
                      IR::Type.int(int_width(name))
                    when "Float64" then IR::Type.float64
                    else                IR::Type.klass(name)
                    end
                  end

          record_type_annotations(type, built)
          built
        end

        private def record_type_annotations(type : ::Crystal::Type, built : IR::Type) : Nil
          owner = type.is_a?(::Crystal::GenericClassInstanceType) ? type.generic_type : type
          annotations = target_annotations(owner.all_annotations)
          return if annotations.empty?

          @state.type_annotations[built] = annotations
        end

        private def ordinary_generic?(type : ::Crystal::Type) : Bool
          type.is_a?(::Crystal::GenericInstanceType) &&
            !type.is_a?(::Crystal::ProcInstanceType) &&
            !type.is_a?(::Crystal::TupleInstanceType) &&
            !type.is_a?(::Crystal::NamedTupleInstanceType)
        end

        private def array_owner?(type : ::Crystal::Type) : Bool
          type.is_a?(::Crystal::GenericClassInstanceType) && type.generic_type.name == "Array"
        end

        private def array_element(type : IR::Type?) : IR::Type
          type.try(&.element_type) || IR::Type.unknown
        end

        private def implicit_array_owner_type(node : ::Crystal::Call) : IR::Type?
          owner = node.target_defs.try(&.first?).try(&.owner?)
          owner && array_owner?(owner) ? build_type(owner) : nil
        end

        private def generic_args(type : ::Crystal::GenericInstanceType) : Array(IR::Type)
          type.type_vars.values.compact_map do |var|
            var.is_a?(::Crystal::Var) ? var.type?.try { |resolved| build_type(resolved) } : nil
          end
        end

        private def int_width(name : String) : IR::Type::Width
          case name
          when "Int8"   then IR::Type::Width::I8
          when "Int16"  then IR::Type::Width::I16
          when "Int32"  then IR::Type::Width::I32
          when "Int64"  then IR::Type::Width::I64
          when "UInt8"  then IR::Type::Width::U8
          when "UInt16" then IR::Type::Width::U16
          when "UInt32" then IR::Type::Width::U32
          when "UInt64" then IR::Type::Width::U64
          else               IR::Type::Width::I32
          end
        end
      end
    end
  end
end
