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
            Transport::RangeData.new(range).to_json(builder)
          end

          def read_range(value : JSON::Any, location : String) : Tango::Source::Range
            read_data(value, location, Transport::RangeData).to_range
          end

          def write_type(builder : JSON::Builder, type : IR::Type) : Nil
            Transport::TypeData.new(type).to_json(builder)
          end

          def read_type(value : JSON::Any, location : String) : IR::Type
            read_data(value, location, Transport::TypeData).to_type
          rescue error : ArgumentError
            invalid(location, error.message || "invalid type")
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
              builder.field("owner_path", target.owner_path)
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
            expect_keys(object, %w(name owner owner_path annotations), location)
            IR::NIR::CallTarget.new(
              string(required(object, "name", location), "#{location}.name"),
              optional_string(required(object, "owner", location), "#{location}.owner"),
              array(required(object, "annotations", location), "#{location}.annotations").map_with_index do |target_annotation, index|
                read_annotation(target_annotation, "#{location}.annotations[#{index}]")
              end,
              string_array(required(object, "owner_path", location), "#{location}.owner_path")
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

          def read_data(value : JSON::Any, location : String, type : T.class) : T forall T
            type.from_json(value.to_json)
          rescue error : JSON::SerializableError
            invalid(serialization_location(error, location), serialization_detail(error))
          end

          def invalid(location : String, detail : String) : NoReturn
            raise CodecError.new(location, detail)
          end

          private def serialization_location(error : JSON::SerializableError, location : String) : String
            attributes = [] of String
            current : Exception? = error
            while serializable = current.as?(JSON::SerializableError)
              serializable.attribute.try { |attribute| attributes << attribute }
              current = serializable.cause
            end
            attributes.reduce(location) { |path, attribute| "#{path}.#{attribute}" }
          end

          private def serialization_detail(error : JSON::SerializableError) : String
            error.message.to_s.lines.first? || "invalid generated transport value"
          end
        end
      end
    end
  end
end
