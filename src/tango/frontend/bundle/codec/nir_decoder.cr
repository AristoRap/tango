module Tango
  module Frontend
    module Bundle
      module Codec
        # Strict schema-v1 NIR reader. Every node kind owns an exact field set;
        # reconstruction invokes only ordinary NIR constructors.
        module NirDecoder
          extend self

          STMT_FIELDS = %w(kind id span)
          EXPR_FIELDS = %w(kind id span type method_site)

          def read_program(value : JSON::Any, location : String) : IR::NIR::Program
            object = Value.object(value, location)
            Value.expect_keys(object, %w(body type_annotations), location)
            body = read_nodes(Value.required(object, "body", location), "#{location}.body")
            annotations = {} of IR::Type => Array(IR::NIR::TargetAnnotation)
            Value.array(Value.required(object, "type_annotations", location), "#{location}.type_annotations")
              .each_with_index do |entry, index|
                entry_location = "#{location}.type_annotations[#{index}]"
                row = Value.object(entry, entry_location)
                Value.expect_keys(row, %w(type annotations), entry_location)
                type = Value.read_type(Value.required(row, "type", entry_location), "#{entry_location}.type")
                if annotations.has_key?(type)
                  Value.invalid(entry_location, "duplicate type-annotation row")
                end
                annotations[type] = Value.array(
                  Value.required(row, "annotations", entry_location),
                  "#{entry_location}.annotations"
                ).map_with_index do |target_annotation, annotation_index|
                  Value.read_annotation(target_annotation, "#{entry_location}.annotations[#{annotation_index}]")
                end
              end
            IR::NIR::Program.new(body, annotations)
          end

          def read_node(value : JSON::Any, location : String) : IR::NIR::Stmt
            object = Value.object(value, location)
            kind = Value.string(Value.required(object, "kind", location), "#{location}.kind")
            Value.expect_keys(object, expected_fields(kind, location), location)
            id = NodeId.new(Value.string(Value.required(object, "id", location), "#{location}.id"))
            span = optional_range(object, "span", location)
            type = expression_kind?(kind) ? optional_type(object, "type", location) : nil
            method_site = if expression_kind?(kind)
                            optional_method_site(object, "method_site", location)
                          end

            case kind
            when "block"
              IR::NIR::Block.new(id, read_nodes(field(object, "body", location), "#{location}.body"), span)
            when "local"
              IR::NIR::Local.new(id, text(object, "name", location), type, span, optional_range(object, "name_span", location))
            when "class_ref"
              IR::NIR::ClassRef.new(id, text(object, "name", location), type, span, optional_range(object, "name_span", location))
            when "enum_member"
              IR::NIR::EnumMember.new(id, required_type(object, "enum_type", location), text(object, "name", location), type, span, optional_range(object, "name_span", location))
            when "constant_reference"
              IR::NIR::ConstantReference.new(id, string_array(object, "path", location), type, span, optional_range(object, "name_span", location))
            when "instance_var"
              IR::NIR::InstanceVar.new(id, text(object, "name", location), text(object, "owner", location), type, span, optional_range(object, "name_span", location))
            when "param"
              IR::NIR::Param.new(id, text(object, "name", location), optional_type(object, "type", location), span, optional_range(object, "name_span", location))
            when "assign"
              target = read_node(field(object, "target", location), "#{location}.target")
              value = expr(object, "value", location)
              case target
              when IR::NIR::Local
                IR::NIR::Assign.new(id, target, value, type, span)
              when IR::NIR::InstanceVar
                IR::NIR::Assign.new(id, target, value, type, span)
              else
                Value.invalid("#{location}.target", "expected local or instance variable")
              end
            when "if"
              IR::NIR::If.new(
                id,
                expr(object, "cond", location),
                block(object, "then_branch", location),
                optional_node(object, "else_branch", location) { |node| as_block(node, "#{location}.else_branch") },
                type,
                span
              )
            when "unsupported_expr"
              IR::NIR::UnsupportedExpr.new(id, text(object, "crystal_node", location), type, span)
            when "int_literal"
              IR::NIR::IntLiteral.new(id, text(object, "value", location), type, span)
            when "float_literal"
              IR::NIR::FloatLiteral.new(id, text(object, "value", location), type, span)
            when "string_literal"
              IR::NIR::StringLiteral.new(id, text(object, "value", location), type, span)
            when "bool_literal"
              IR::NIR::BoolLiteral.new(id, boolean(object, "value", location), type, span)
            when "nil_literal"
              IR::NIR::NilLiteral.new(id, span)
            when "block_arg"
              IR::NIR::BlockArg.new(id, text(object, "name", location), span, optional_range(object, "name_span", location))
            when "block_literal"
              IR::NIR::BlockLiteral.new(
                id,
                typed_nodes(object, "args", location, IR::NIR::BlockArg),
                block(object, "body", location),
                Value.read_signature(field(object, "signature", location), "#{location}.signature"),
                type,
                span
              )
            when "block_param"
              IR::NIR::BlockParam.new(
                id,
                text(object, "name", location),
                Value.read_signature(field(object, "signature", location), "#{location}.signature"),
                span,
                optional_range(object, "name_span", location),
                boolean(object, "yield_parameter", location),
                boolean(object, "value_required", location)
              )
            when "invoke_block"
              IR::NIR::InvokeBlock.new(
                id,
                expr(object, "receiver", location),
                exprs(object, "args", location),
                type,
                span,
                method_site,
                boolean(object, "yield_site", location)
              )
            when "call"
              read_call(object, location, id, type, span, method_site)
            when "collection_map"
              IR::NIR::CollectionMap.new(call(object, "fallback", location))
            when "collection_filter"
              IR::NIR::CollectionFilter.new(
                call(object, "fallback", location),
                Value.parse_enum(IR::NIR::CollectionFilter::Mode, field(object, "mode", location), "#{location}.mode")
              )
            when "collection_each"
              IR::NIR::CollectionEach.new(call(object, "fallback", location))
            when "collection_fold"
              IR::NIR::CollectionFold.new(call(object, "fallback", location))
            when "indexed_read"
              IR::NIR::IndexedRead.new(call(object, "fallback", location))
            when "indexed_write"
              IR::NIR::IndexedWrite.new(call(object, "fallback", location))
            when "interpolation"
              IR::NIR::Interpolation.new(id, exprs(object, "pieces", location), type, span)
            when "size"
              IR::NIR::Size.new(id, expr(object, "value", location), type, span, method_site)
            when "string_char_at"
              IR::NIR::StringCharAt.new(id, expr(object, "string", location), expr(object, "index", location), type, span, method_site)
            when "string_each_char"
              IR::NIR::StringEachChar.new(id, expr(object, "string", location), block_literal(object, "block", location), type, span, method_site)
            when "string_split"
              IR::NIR::StringSplit.new(
                id,
                expr(object, "string", location),
                type,
                span,
                optional_node(object, "separator", location) { |node| as_expr(node, "#{location}.separator") },
                method_site
              )
            when "string_to_float"
              IR::NIR::StringToFloat.new(id, expr(object, "string", location), type, span, method_site)
            when "string_to_integer"
              IR::NIR::StringToInteger.new(id, expr(object, "string", location), exprs(object, "options", location), type, span, method_site)
            when "array_new"
              IR::NIR::ArrayNew.new(id, required_type(object, "element", location), type, span, method_site)
            when "array_build"
              IR::NIR::ArrayBuild.new(id, required_type(object, "element", location), expr(object, "size", location), type, span, method_site)
            when "array_get"
              IR::NIR::ArrayGet.new(id, expr(object, "array", location), expr(object, "index", location), required_type(object, "element", location), type, span, method_site)
            when "array_set"
              IR::NIR::ArraySet.new(id, expr(object, "array", location), expr(object, "index", location), expr(object, "value", location), required_type(object, "element", location), type, span, method_site)
            when "array_push"
              IR::NIR::ArrayPush.new(id, expr(object, "array", location), expr(object, "value", location), required_type(object, "element", location), type, span, method_site)
            when "value_sequence"
              IR::NIR::ValueSequence.new(id, block(object, "prefix", location), expr(object, "value", location), type, span)
            when "hash_new"
              IR::NIR::HashNew.new(id, required_type(object, "hash_type", location), type, span, method_site)
            when "hash_get"
              IR::NIR::HashGet.new(id, expr(object, "hash", location), expr(object, "key", location), required_type(object, "hash_type", location), type, span, method_site)
            when "hash_set"
              IR::NIR::HashSet.new(id, expr(object, "hash", location), expr(object, "key", location), expr(object, "value", location), required_type(object, "hash_type", location), type, span, method_site)
            when "hash_fetch"
              IR::NIR::HashFetch.new(id, expr(object, "hash", location), expr(object, "key", location), expr(object, "default", location), required_type(object, "hash_type", location), type, span, method_site)
            when "hash_has_key"
              IR::NIR::HashHasKey.new(id, expr(object, "hash", location), expr(object, "key", location), required_type(object, "hash_type", location), type, span, method_site)
            when "hash_key_at"
              IR::NIR::HashKeyAt.new(id, expr(object, "hash", location), expr(object, "index", location), required_type(object, "hash_type", location), type, span, method_site)
            when "not"
              IR::NIR::Not.new(id, expr(object, "value", location), type, span)
            when "type_test"
              IR::NIR::TypeTest.new(id, expr(object, "value", location), required_type(object, "target", location), type, span)
            when "cast"
              IR::NIR::Cast.new(id, expr(object, "value", location), required_type(object, "target", location), type, span)
            when "new"
              IR::NIR::New.new(
                id,
                text(object, "class_name", location),
                exprs(object, "args", location),
                type,
                span,
                optional_range(object, "name_span", location),
                method_site,
                boolean(object, "invokes_initializer", location)
              )
            when "spawn"
              IR::NIR::Spawn.new(id, expr(object, "proc", location), type, span)
            when "channel_new"
              IR::NIR::ChannelNew.new(
                id,
                required_type(object, "element", location),
                optional_node(object, "capacity", location) { |node| as_expr(node, "#{location}.capacity") },
                type,
                span,
                method_site
              )
            when "mutex_new"
              IR::NIR::MutexNew.new(id, type, span, method_site)
            when "channel_op"
              read_channel_operation(id, type, span, method_site, field(object, "operation", location), "#{location}.operation")
            when "select"
              arms = Value.array(field(object, "arms", location), "#{location}.arms").map_with_index do |arm, index|
                read_select_arm(arm, "#{location}.arms[#{index}]")
              end
              IR::NIR::Select.new(
                id,
                arms,
                optional_node(object, "else_body", location) { |node| as_block(node, "#{location}.else_body") },
                type,
                span
              )
            when "raise"
              IR::NIR::Raise.new(
                id,
                expr(object, "value", location),
                Value.parse_enum(IR::NIR::Raise::Kind, field(object, "raise_kind", location), "#{location}.raise_kind"),
                type,
                span
              )
            when "exception_new"
              IR::NIR::ExceptionNew.new(
                id,
                text(object, "class_name", location),
                optional_node(object, "message", location) { |node| as_expr(node, "#{location}.message") },
                type,
                span
              )
            when "exception_handler"
              clauses = Value.array(field(object, "clauses", location), "#{location}.clauses").map_with_index do |clause, index|
                read_rescue_clause(clause, "#{location}.clauses[#{index}]")
              end
              IR::NIR::ExceptionHandler.new(
                id,
                block(object, "body", location),
                clauses,
                optional_node(object, "else_branch", location) { |node| as_block(node, "#{location}.else_branch") },
                optional_node(object, "ensure_branch", location) { |node| as_block(node, "#{location}.ensure_branch") },
                type,
                span
              )
            when "return", "break", "next"
              value_node = optional_node(object, "value", location) { |node| as_expr(node, "#{location}.value") }
              target = Value.optional_string(field(object, "target", location), "#{location}.target").try { |raw| NodeId.new(raw) }
              case kind
              when "return" then IR::NIR::Return.new(id, value_node, target, span)
              when "break"  then IR::NIR::Break.new(id, value_node, target, span)
              else               IR::NIR::Next.new(id, value_node, target, span)
              end
            when "field_initializer"
              IR::NIR::FieldInitializer.new(
                id,
                Value.read_field(field(object, "field", location), "#{location}.field"),
                expr(object, "value", location),
                span,
                optional_range(object, "name_span", location)
              )
            when "class"
              IR::NIR::Class.new(
                id,
                text(object, "name", location),
                Value.optional_string(field(object, "superclass_name", location), "#{location}.superclass_name"),
                read_fields(object, "fields", location),
                span,
                optional_range(object, "name_span", location),
                boolean(object, "reference", location),
                typed_nodes(object, "initializers", location, IR::NIR::FieldInitializer),
                required_type(object, "concrete_type", location),
                optional_type(object, "superclass_type", location)
              )
            when "enum"
              members = Value.array(field(object, "members", location), "#{location}.members").map_with_index do |value, index|
                member_location = "#{location}.members[#{index}]"
                member = Value.object(value, member_location)
                Value.expect_keys(member, %w(name value name_span), member_location)
                IR::NIR::Enum::Member.new(
                  text(member, "name", member_location),
                  text(member, "value", member_location),
                  optional_range(member, "name_span", member_location)
                )
              end
              IR::NIR::Enum.new(
                id,
                required_type(object, "type", location),
                required_type(object, "base_type", location),
                members,
                span,
                optional_range(object, "name_span", location)
              )
            when "namespace"
              IR::NIR::Namespace.new(
                id,
                string_array(object, "path", location),
                block(object, "body", location),
                span,
                optional_range(object, "name_span", location)
              )
            when "type_alias"
              IR::NIR::TypeAlias.new(
                id,
                string_array(object, "path", location),
                required_type(object, "target", location),
                span,
                optional_range(object, "name_span", location)
              )
            when "type_alias_reference"
              IR::NIR::TypeAliasReference.new(
                id,
                string_array(object, "path", location),
                required_type(object, "target", location),
                span,
                optional_range(object, "name_span", location)
              )
            when "constant"
              IR::NIR::Constant.new(
                id,
                string_array(object, "path", location),
                expr(object, "value", location),
                required_type(object, "type", location),
                span,
                optional_range(object, "name_span", location)
              )
            when "def"
              IR::NIR::Def.new(
                id,
                text(object, "name", location),
                typed_nodes(object, "params", location, IR::NIR::Param),
                block(object, "body", location),
                optional_type(object, "return_type", location),
                span,
                optional_node(object, "block_param", location) { |node| as_type(node, IR::NIR::BlockParam, "#{location}.block_param") },
                optional_range(object, "name_span", location),
                optional_type(object, "owner", location),
                Value.parse_enum(IR::NIR::CallableKind, field(object, "callable_kind", location), "#{location}.callable_kind"),
                read_conformances(object, "capability_witnesses", location),
                string_array(object, "namespace_path", location),
                optional_node(object, "return_type_reference", location) { |node| as_type(node, IR::NIR::TypeAliasReference, "#{location}.return_type_reference") }
              )
            when "while"
              IR::NIR::While.new(id, expr(object, "cond", location), block(object, "body", location), span)
            else
              Value.invalid("#{location}.kind", "unknown NIR node kind #{kind.inspect}")
            end
          rescue error : CodecError | UnsupportedVersionError
            raise error
          rescue error
            Value.invalid(location, error.message || error.class.name)
          end

          private def read_call(object, location, id, type, span, method_site) : IR::NIR::Call
            targets = Value.array(field(object, "targets", location), "#{location}.targets").map_with_index do |target, index|
              Value.read_call_target(target, "#{location}.targets[#{index}]")
            end
            IR::NIR::Call.new(
              id,
              text(object, "name", location),
              exprs(object, "args", location),
              targets,
              optional_node(object, "block", location) { |node| as_type(node, IR::NIR::BlockLiteral, "#{location}.block") },
              type,
              span,
              Value.optional(field(object, "primitive", location)) { |value| Value.read_primitive(value, "#{location}.primitive") },
              optional_range(object, "name_span", location),
              method_site,
              optional_node(object, "dispatch_receiver", location) { |node| as_type(node, IR::NIR::ClassRef, "#{location}.dispatch_receiver") }
            )
          end

          private def read_channel_operation(id : NodeId, type : IR::Type?, span : Tango::Source::Range?, method_site : IR::NIR::MethodSite?, value, location) : IR::NIR::ChannelOp
            object = Value.object(value, location)
            Value.expect_keys(object, %w(kind channel value element), location)
            IR::NIR::ChannelOp.new(
              id,
              Value.parse_enum(IR::NIR::ChannelOp::Kind, field(object, "kind", location), "#{location}.kind"),
              expr(object, "channel", location),
              optional_node(object, "value", location) { |node| as_expr(node, "#{location}.value") },
              required_type(object, "element", location),
              type,
              span,
              method_site
            )
          end

          private def read_select_arm(value, location) : IR::NIR::Select::Arm
            object = Value.object(value, location)
            Value.expect_keys(object, %w(operation captured body), location)
            operation = as_type(read_node(field(object, "operation", location), "#{location}.operation"), IR::NIR::ChannelOp, "#{location}.operation")
            captured = optional_node(object, "captured", location) { |node| as_type(node, IR::NIR::Local, "#{location}.captured") }
            IR::NIR::Select::Arm.new(operation, captured, block(object, "body", location))
          end

          private def read_rescue_clause(value, location) : IR::NIR::RescueClause
            object = Value.object(value, location)
            Value.expect_keys(object, %w(types binding body), location)
            types = Value.array(field(object, "types", location), "#{location}.types").map_with_index do |type, index|
              Value.read_type(type, "#{location}.types[#{index}]")
            end
            binding = optional_node(object, "binding", location) { |node| as_type(node, IR::NIR::Local, "#{location}.binding") }
            IR::NIR::RescueClause.new(types, binding, block(object, "body", location))
          end

          private def read_nodes(value, location) : Array(IR::NIR::Stmt)
            Value.array(value, location).map_with_index { |node, index| read_node(node, "#{location}[#{index}]") }
          end

          private def typed_nodes(object, key, location, type : T.class) : Array(T) forall T
            read_nodes(field(object, key, location), "#{location}.#{key}").map_with_index do |node, index|
              as_type(node, type, "#{location}.#{key}[#{index}]")
            end
          end

          private def exprs(object, key, location) : Array(IR::NIR::Expr)
            typed_nodes(object, key, location, IR::NIR::Expr)
          end

          private def expr(object, key, location) : IR::NIR::Expr
            as_expr(read_node(field(object, key, location), "#{location}.#{key}"), "#{location}.#{key}")
          end

          private def block(object, key, location) : IR::NIR::Block
            as_block(read_node(field(object, key, location), "#{location}.#{key}"), "#{location}.#{key}")
          end

          private def block_literal(object, key, location) : IR::NIR::BlockLiteral
            as_type(read_node(field(object, key, location), "#{location}.#{key}"), IR::NIR::BlockLiteral, "#{location}.#{key}")
          end

          private def call(object, key, location) : IR::NIR::Call
            as_type(read_node(field(object, key, location), "#{location}.#{key}"), IR::NIR::Call, "#{location}.#{key}")
          end

          private def optional_node(object, key, location, &)
            Value.optional(field(object, key, location)) do |value|
              yield read_node(value, "#{location}.#{key}")
            end
          end

          private def as_expr(node, location) : IR::NIR::Expr
            as_type(node, IR::NIR::Expr, location)
          end

          private def as_block(node, location) : IR::NIR::Block
            as_type(node, IR::NIR::Block, location)
          end

          private def as_type(node, type : T.class, location) : T forall T
            node.as?(T) || Value.invalid(location, "expected #{type}, got #{node.class.name}")
          end

          private def field(object, key, location) : JSON::Any
            Value.required(object, key, location)
          end

          private def text(object, key, location) : String
            Value.string(field(object, key, location), "#{location}.#{key}")
          end

          private def boolean(object, key, location) : Bool
            Value.bool(field(object, key, location), "#{location}.#{key}")
          end

          private def required_type(object, key, location) : IR::Type
            Value.read_type(field(object, key, location), "#{location}.#{key}")
          end

          private def optional_type(object, key, location) : IR::Type?
            Value.optional(field(object, key, location)) { |value| Value.read_type(value, "#{location}.#{key}") }
          end

          private def optional_range(object, key, location) : Tango::Source::Range?
            Value.optional(field(object, key, location)) { |value| Value.read_range(value, "#{location}.#{key}") }
          end

          private def optional_method_site(object, key, location) : IR::NIR::MethodSite?
            Value.optional(field(object, key, location)) { |value| Value.read_method_site(value, "#{location}.#{key}") }
          end

          private def string_array(object, key, location) : Array(String)
            Value.string_array(field(object, key, location), "#{location}.#{key}")
          end

          private def read_fields(object, key, location) : Array(IR::Field)
            Value.array(field(object, key, location), "#{location}.#{key}").map_with_index do |value, index|
              Value.read_field(value, "#{location}.#{key}[#{index}]")
            end
          end

          private def read_conformances(object, key, location) : Array(IR::CapabilityConformance)
            Value.array(field(object, key, location), "#{location}.#{key}").map_with_index do |value, index|
              Value.read_conformance(value, "#{location}.#{key}[#{index}]")
            end
          end

          private def expression_kind?(kind : String) : Bool
            !%w(block param block_arg block_param return break next field_initializer class enum namespace type_alias type_alias_reference constant def while).includes?(kind)
          end

          private def expected_fields(kind : String, location : String) : Array(String)
            base = expression_kind?(kind) ? EXPR_FIELDS : STMT_FIELDS
            extra = case kind
                    when "block"                                                                                 then %w(body)
                    when "local", "class_ref"                                                                    then %w(name name_span)
                    when "enum_member"                                                                           then %w(enum_type name name_span)
                    when "constant_reference"                                                                    then %w(path name_span)
                    when "instance_var"                                                                          then %w(name name_span owner)
                    when "param"                                                                                 then %w(name type name_span)
                    when "assign"                                                                                then %w(target value)
                    when "if"                                                                                    then %w(cond then_branch else_branch)
                    when "unsupported_expr"                                                                      then %w(crystal_node)
                    when "int_literal", "float_literal", "string_literal", "bool_literal"                        then %w(value)
                    when "nil_literal", "mutex_new"                                                              then [] of String
                    when "block_arg"                                                                             then %w(name name_span)
                    when "block_literal"                                                                         then %w(args body signature)
                    when "block_param"                                                                           then %w(name signature name_span yield_parameter value_required)
                    when "invoke_block"                                                                          then %w(receiver args yield_site)
                    when "call"                                                                                  then %w(name args targets block primitive name_span dispatch_receiver)
                    when "collection_map", "collection_each", "collection_fold", "indexed_read", "indexed_write" then %w(fallback)
                    when "collection_filter"                                                                     then %w(fallback mode)
                    when "interpolation"                                                                         then %w(pieces)
                    when "size", "not"                                                                           then %w(value)
                    when "string_char_at"                                                                        then %w(string index)
                    when "string_each_char"                                                                      then %w(string block)
                    when "string_split"                                                                          then %w(string separator)
                    when "string_to_float"                                                                       then %w(string)
                    when "string_to_integer"                                                                     then %w(string options)
                    when "array_new"                                                                             then %w(element)
                    when "array_build"                                                                           then %w(element size)
                    when "array_get"                                                                             then %w(array element index)
                    when "array_set"                                                                             then %w(array element index value)
                    when "array_push"                                                                            then %w(array element value)
                    when "value_sequence"                                                                        then %w(prefix value)
                    when "hash_new"                                                                              then %w(hash_type)
                    when "hash_get", "hash_has_key"                                                              then %w(hash_type hash key)
                    when "hash_set"                                                                              then %w(hash_type hash key value)
                    when "hash_fetch"                                                                            then %w(hash_type hash key default)
                    when "hash_key_at"                                                                           then %w(hash_type hash index)
                    when "type_test", "cast"                                                                     then %w(value target)
                    when "new"                                                                                   then %w(class_name args name_span invokes_initializer)
                    when "spawn"                                                                                 then %w(proc)
                    when "channel_new"                                                                           then %w(element capacity)
                    when "channel_op"                                                                            then %w(operation)
                    when "select"                                                                                then %w(arms else_body)
                    when "raise"                                                                                 then %w(value raise_kind)
                    when "exception_new"                                                                         then %w(class_name message)
                    when "exception_handler"                                                                     then %w(body clauses else_branch ensure_branch)
                    when "return", "break", "next"                                                               then %w(value target)
                    when "field_initializer"                                                                     then %w(field value name_span)
                    when "class"                                                                                 then %w(name concrete_type superclass_name superclass_type fields initializers reference name_span)
                    when "enum"                                                                                  then %w(type base_type members name_span)
                    when "namespace"                                                                             then %w(path body name_span)
                    when "type_alias"                                                                            then %w(path target name_span)
                    when "type_alias_reference"                                                                  then %w(path target name_span)
                    when "constant"                                                                              then %w(path value type name_span)
                    when "def"                                                                                   then %w(name owner callable_kind namespace_path params block_param body return_type return_type_reference name_span capability_witnesses)
                    when "while"                                                                                 then %w(cond body)
                    else
                      Value.invalid("#{location}.kind", "unknown NIR node kind #{kind.inspect}")
                    end
            base + extra
          end
        end
      end
    end
  end
end
