module Tango
  module Frontend
    module Bundle
      module Codec
        # Mechanical mapping for scalar and compound values reused throughout
        # the document. Compiler-owned types remain free of wire annotations.
        module Value
          extend self

          def write_nullable(builder : JSON::Builder, value, &)
            if value.nil?
              builder.null
            else
              yield value
            end
          end

          def write_range(builder : JSON::Builder, range : Tango::Source::Range) : Nil
            builder.object do
              builder.field("path", range.path)
              builder.field("start_offset", range.start_offset)
              builder.field("end_offset", range.end_offset)
              builder.field("line") { write_nullable(builder, range.line) { |line| builder.number(line) } }
              builder.field("column") { write_nullable(builder, range.column) { |column| builder.number(column) } }
            end
          end

          def read_range(value : JSON::Any, location : String) : Tango::Source::Range
            object = object(value, location)
            expect_keys(object, %w(path start_offset end_offset line column), location)
            Tango::Source::Range.new(
              string(required(object, "path", location), "#{location}.path"),
              int32(required(object, "start_offset", location), "#{location}.start_offset"),
              int32(required(object, "end_offset", location), "#{location}.end_offset"),
              optional_int32(required(object, "line", location), "#{location}.line"),
              optional_int32(required(object, "column", location), "#{location}.column")
            )
          end

          def write_type(builder : JSON::Builder, type : IR::Type) : Nil
            builder.object do
              builder.field("family", type.family.to_s)
              builder.field("width") do
                write_nullable(builder, type.width) { |width| builder.string(width.to_s) }
              end
              builder.field("name") do
                write_nullable(builder, type.name) { |name| builder.string(name) }
              end
              builder.field("members") do
                builder.array { type.members.each { |member| write_type(builder, member) } }
              end
              builder.field("type_args") do
                builder.array { type.type_args.each { |argument| write_type(builder, argument) } }
              end
            end
          end

          def read_type(value : JSON::Any, location : String) : IR::Type
            object = object(value, location)
            expect_keys(object, %w(family width name members type_args), location)
            IR::Type.new(
              parse_enum(IR::Type::Family, required(object, "family", location), "#{location}.family"),
              optional_string(required(object, "width", location), "#{location}.width").try do |width|
                parse_enum_value(IR::Type::Width, width, "#{location}.width")
              end,
              optional_string(required(object, "name", location), "#{location}.name"),
              array(required(object, "members", location), "#{location}.members").map_with_index do |member, index|
                read_type(member, "#{location}.members[#{index}]")
              end,
              array(required(object, "type_args", location), "#{location}.type_args").map_with_index do |argument, index|
                read_type(argument, "#{location}.type_args[#{index}]")
              end
            )
          end

          def write_method_site(builder : JSON::Builder, site : IR::NIR::MethodSite) : Nil
            builder.object do
              builder.field("owner") { write_type(builder, site.owner) }
              builder.field("name", site.name)
              builder.field("argument_types") do
                builder.array { site.argument_types.each { |type| write_type(builder, type) } }
              end
              builder.field("return_type") { write_type(builder, site.return_type) }
              builder.field("name_span") do
                write_nullable(builder, site.name_span) { |range| write_range(builder, range) }
              end
              builder.field("kind", site.kind.to_s)
            end
          end

          def read_method_site(value : JSON::Any, location : String) : IR::NIR::MethodSite
            object = object(value, location)
            expect_keys(object, %w(owner name argument_types return_type name_span kind), location)
            IR::NIR::MethodSite.new(
              read_type(required(object, "owner", location), "#{location}.owner"),
              string(required(object, "name", location), "#{location}.name"),
              array(required(object, "argument_types", location), "#{location}.argument_types").map_with_index do |type, index|
                read_type(type, "#{location}.argument_types[#{index}]")
              end,
              read_type(required(object, "return_type", location), "#{location}.return_type"),
              optional(required(object, "name_span", location)) do |range|
                read_range(range, "#{location}.name_span")
              end,
              parse_enum(IR::NIR::CallableKind, required(object, "kind", location), "#{location}.kind")
            )
          end

          def write_signature(builder : JSON::Builder, signature : IR::ProcSignature) : Nil
            builder.object do
              builder.field("param_types") do
                builder.array { signature.param_types.each { |type| write_type(builder, type) } }
              end
              builder.field("return_type") do
                write_nullable(builder, signature.return_type) { |type| write_type(builder, type) }
              end
            end
          end

          def read_signature(value : JSON::Any, location : String) : IR::ProcSignature
            object = object(value, location)
            expect_keys(object, %w(param_types return_type), location)
            IR::ProcSignature.new(
              array(required(object, "param_types", location), "#{location}.param_types").map_with_index do |type, index|
                read_type(type, "#{location}.param_types[#{index}]")
              end,
              optional(required(object, "return_type", location)) do |type|
                read_type(type, "#{location}.return_type")
              end
            )
          end

          def write_field(builder : JSON::Builder, field : IR::Field) : Nil
            builder.object do
              builder.field("name", field.name)
              builder.field("type") { write_type(builder, field.type) }
            end
          end

          def read_field(value : JSON::Any, location : String) : IR::Field
            object = object(value, location)
            expect_keys(object, %w(name type), location)
            IR::Field.new(
              string(required(object, "name", location), "#{location}.name"),
              read_type(required(object, "type", location), "#{location}.type")
            )
          end

          def write_conformance(builder : JSON::Builder, witness : IR::CapabilityConformance) : Nil
            builder.object do
              builder.field("concrete") { write_type(builder, witness.concrete) }
              builder.field("capability") { write_type(builder, witness.capability) }
            end
          end

          def read_conformance(value : JSON::Any, location : String) : IR::CapabilityConformance
            object = object(value, location)
            expect_keys(object, %w(concrete capability), location)
            IR::CapabilityConformance.new(
              read_type(required(object, "concrete", location), "#{location}.concrete"),
              read_type(required(object, "capability", location), "#{location}.capability")
            )
          end

          def write_annotation(builder : JSON::Builder, target_annotation : IR::NIR::TargetAnnotation) : Nil
            builder.object do
              builder.field("path", target_annotation.path)
              builder.field("string_args", target_annotation.string_args)
              builder.field("symbol_args", target_annotation.symbol_args)
            end
          end

          def read_annotation(value : JSON::Any, location : String) : IR::NIR::TargetAnnotation
            object = object(value, location)
            expect_keys(object, %w(path string_args symbol_args), location)
            IR::NIR::TargetAnnotation.new(
              string_array(required(object, "path", location), "#{location}.path"),
              string_array(required(object, "string_args", location), "#{location}.string_args"),
              string_array(required(object, "symbol_args", location), "#{location}.symbol_args")
            )
          end

          def write_call_target(builder : JSON::Builder, target : IR::NIR::CallTarget) : Nil
            builder.object do
              builder.field("name", target.name)
              builder.field("owner") { write_nullable(builder, target.owner) { |owner| builder.string(owner) } }
              builder.field("annotations") do
                builder.array do
                  target.annotations.each do |target_annotation|
                    write_annotation(builder, target_annotation)
                  end
                end
              end
            end
          end

          def read_call_target(value : JSON::Any, location : String) : IR::NIR::CallTarget
            object = object(value, location)
            expect_keys(object, %w(name owner annotations), location)
            IR::NIR::CallTarget.new(
              string(required(object, "name", location), "#{location}.name"),
              optional_string(required(object, "owner", location), "#{location}.owner"),
              array(required(object, "annotations", location), "#{location}.annotations").map_with_index do |target_annotation, index|
                read_annotation(target_annotation, "#{location}.annotations[#{index}]")
              end
            )
          end

          def write_primitive(builder : JSON::Builder, primitive : IR::NIR::Primitive) : Nil
            builder.object do
              builder.field("kind", primitive.kind.to_s)
              builder.field("name", primitive.name)
            end
          end

          def read_primitive(value : JSON::Any, location : String) : IR::NIR::Primitive
            object = object(value, location)
            expect_keys(object, %w(kind name), location)
            IR::NIR::Primitive.new(
              parse_enum(IR::NIR::Primitive::Kind, required(object, "kind", location), "#{location}.kind"),
              string(required(object, "name", location), "#{location}.name")
            )
          end

          def object(value : JSON::Any, location : String) : Hash(String, JSON::Any)
            value.as_h
          rescue TypeCastError
            invalid(location, "expected object")
          end

          def array(value : JSON::Any, location : String) : Array(JSON::Any)
            value.as_a
          rescue TypeCastError
            invalid(location, "expected array")
          end

          def string(value : JSON::Any, location : String) : String
            value.as_s
          rescue TypeCastError
            invalid(location, "expected string")
          end

          def bool(value : JSON::Any, location : String) : Bool
            value.as_bool
          rescue TypeCastError
            invalid(location, "expected boolean")
          end

          def int32(value : JSON::Any, location : String) : Int32
            value.as_i.to_i32
          rescue TypeCastError | OverflowError
            invalid(location, "expected 32-bit integer")
          end

          def optional_int32(value : JSON::Any, location : String) : Int32?
            optional(value) { |present| int32(present, location) }
          end

          def optional_string(value : JSON::Any, location : String) : String?
            optional(value) { |present| string(present, location) }
          end

          def optional(value : JSON::Any, &)
            value.raw.nil? ? nil : yield value
          end

          def string_array(value : JSON::Any, location : String) : Array(String)
            array(value, location).map_with_index do |item, index|
              string(item, "#{location}[#{index}]")
            end
          end

          def required(object : Hash(String, JSON::Any), key : String, location : String) : JSON::Any
            object[key]? || invalid(location, "missing field #{key.inspect}")
          end

          def expect_keys(object : Hash(String, JSON::Any), keys : Enumerable(String), location : String) : Nil
            expected = keys.to_set
            if extra = object.keys.find { |key| !expected.includes?(key) }
              invalid(location, "unknown field #{extra.inspect}")
            end
            if missing = expected.find { |key| !object.has_key?(key) }
              invalid(location, "missing field #{missing.inspect}")
            end
          end

          def parse_enum(type : T.class, value : JSON::Any, location : String) : T forall T
            parse_enum_value(type, string(value, location), location)
          end

          def parse_enum_value(type : T.class, value : String, location : String) : T forall T
            type.parse(value)
          rescue ArgumentError
            invalid(location, "unknown #{type} value #{value.inspect}")
          end

          def invalid(location : String, detail : String) : NoReturn
            raise CodecError.new(location, detail)
          end
        end
      end
    end
  end
end
