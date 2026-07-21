module Tango
  module Frontend
    module Bundle
      module Codec
        # Canonical NIR writer. Kind tags and field order are schema-v1 data;
        # phase dumps and Crystal class layout are deliberately irrelevant.
        module NirEncoder
          extend self

          def write_program(builder : JSON::Builder, program : IR::NIR::Program) : Nil
            builder.object do
              builder.field("body") { write_nodes(builder, program.body) }
              builder.field("type_annotations") do
                builder.array do
                  program.type_annotations
                    .to_a
                    .sort_by { |type, _| canonical_type_key(type) }
                    .each do |type, annotations|
                      builder.object do
                        builder.field("type") { Value.write_type(builder, type) }
                        builder.field("annotations") do
                          builder.array do
                            annotations.each { |target_annotation| Value.write_annotation(builder, target_annotation) }
                          end
                        end
                      end
                    end
                end
              end
            end
          end

          def write_node(builder : JSON::Builder, node : IR::NIR::Stmt) : Nil
            builder.object do
              builder.field("kind", kind(node))
              builder.field("id", node.id.value)
              builder.field("span") do
                Value.write_nullable(builder, node.span) { |range| Value.write_range(builder, range) }
              end
              if expression = node.as?(IR::NIR::Expr)
                builder.field("type") do
                  Value.write_nullable(builder, expression.type) { |type| Value.write_type(builder, type) }
                end
                builder.field("method_site") do
                  Value.write_nullable(builder, expression.method_site) do |site|
                    Value.write_method_site(builder, site)
                  end
                end
              end
              write_node_fields(builder, node)
            end
          end

          private def write_node_fields(builder : JSON::Builder, node : IR::NIR::Stmt) : Nil
            case node
            when IR::NIR::Block
              builder.field("body") { write_nodes(builder, node.body) }
            when IR::NIR::Local, IR::NIR::ClassRef
              write_named(builder, node)
            when IR::NIR::EnumMember
              builder.field("enum_type") { Value.write_type(builder, node.enum_type) }
              builder.field("name", node.name)
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::ConstantReference
              builder.field("path", node.path)
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::InstanceVar
              write_named(builder, node)
              builder.field("owner", node.owner)
            when IR::NIR::Param
              builder.field("name", node.name)
              builder.field("type") do
                Value.write_nullable(builder, node.type) { |type| Value.write_type(builder, type) }
              end
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::Assign
              builder.field("target") { write_node(builder, node.target) }
              builder.field("value") { write_node(builder, node.value) }
            when IR::NIR::If
              builder.field("cond") { write_node(builder, node.cond) }
              builder.field("then_branch") { write_node(builder, node.then_branch) }
              write_nullable_node(builder, "else_branch", node.else_branch)
            when IR::NIR::UnsupportedExpr
              builder.field("crystal_node", node.crystal_node)
            when IR::NIR::IntLiteral, IR::NIR::FloatLiteral, IR::NIR::StringLiteral
              builder.field("value", node.value)
            when IR::NIR::BoolLiteral
              builder.field("value", node.value)
            when IR::NIR::NilLiteral
            when IR::NIR::BlockArg
              builder.field("name", node.name)
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::BlockLiteral
              builder.field("args") { write_nodes(builder, node.args) }
              builder.field("body") { write_node(builder, node.body) }
              builder.field("signature") { Value.write_signature(builder, node.signature) }
            when IR::NIR::BlockParam
              builder.field("name", node.name)
              builder.field("signature") { Value.write_signature(builder, node.signature) }
              write_nullable_range(builder, "name_span", node.name_span)
              builder.field("yield_parameter", node.yield_parameter?)
              builder.field("value_required", node.value_required?)
            when IR::NIR::InvokeBlock
              builder.field("receiver") { write_node(builder, node.receiver) }
              builder.field("args") { write_nodes(builder, node.args) }
              builder.field("yield_site", node.yield_site?)
            when IR::NIR::Call
              write_call(builder, node)
            when IR::NIR::CollectionMap, IR::NIR::CollectionEach, IR::NIR::CollectionFold,
                 IR::NIR::IndexedRead, IR::NIR::IndexedWrite
              builder.field("fallback") { write_node(builder, node.fallback) }
            when IR::NIR::CollectionFilter
              builder.field("fallback") { write_node(builder, node.fallback) }
              builder.field("mode", node.mode.to_s)
            when IR::NIR::Interpolation
              builder.field("pieces") { write_nodes(builder, node.pieces) }
            when IR::NIR::Size
              builder.field("value") { write_node(builder, node.value) }
            when IR::NIR::StringCharAt
              builder.field("string") { write_node(builder, node.string) }
              builder.field("index") { write_node(builder, node.index) }
            when IR::NIR::StringEachChar
              builder.field("string") { write_node(builder, node.string) }
              builder.field("block") { write_node(builder, node.block) }
            when IR::NIR::StringSplit
              builder.field("string") { write_node(builder, node.string) }
              write_nullable_node(builder, "separator", node.separator)
            when IR::NIR::StringToFloat
              builder.field("string") { write_node(builder, node.string) }
            when IR::NIR::StringToInteger
              builder.field("string") { write_node(builder, node.string) }
              builder.field("options") { write_nodes(builder, node.options) }
            when IR::NIR::ArrayNew
              builder.field("element") { Value.write_type(builder, node.element) }
            when IR::NIR::ArrayBuild
              builder.field("element") { Value.write_type(builder, node.element) }
              builder.field("size") { write_node(builder, node.size) }
            when IR::NIR::ArrayGet
              write_array_operation(builder, node)
              builder.field("index") { write_node(builder, node.index) }
            when IR::NIR::ArraySet
              write_array_operation(builder, node)
              builder.field("index") { write_node(builder, node.index) }
              builder.field("value") { write_node(builder, node.value) }
            when IR::NIR::ArrayPush
              write_array_operation(builder, node)
              builder.field("value") { write_node(builder, node.value) }
            when IR::NIR::ValueSequence
              builder.field("prefix") { write_node(builder, node.prefix) }
              builder.field("value") { write_node(builder, node.value) }
            when IR::NIR::HashNew
              write_hash_type(builder, node)
            when IR::NIR::HashGet, IR::NIR::HashHasKey
              write_hash_type(builder, node)
              builder.field("hash") { write_node(builder, node.hash) }
              builder.field("key") { write_node(builder, node.key) }
            when IR::NIR::HashSet
              write_hash_type(builder, node)
              builder.field("hash") { write_node(builder, node.hash) }
              builder.field("key") { write_node(builder, node.key) }
              builder.field("value") { write_node(builder, node.value) }
            when IR::NIR::HashFetch
              write_hash_type(builder, node)
              builder.field("hash") { write_node(builder, node.hash) }
              builder.field("key") { write_node(builder, node.key) }
              builder.field("default") { write_node(builder, node.default) }
            when IR::NIR::HashKeyAt
              write_hash_type(builder, node)
              builder.field("hash") { write_node(builder, node.hash) }
              builder.field("index") { write_node(builder, node.index) }
            when IR::NIR::Not
              builder.field("value") { write_node(builder, node.value) }
            when IR::NIR::TypeTest, IR::NIR::Cast
              builder.field("value") { write_node(builder, node.value) }
              builder.field("target") { Value.write_type(builder, node.target) }
            when IR::NIR::New
              builder.field("class_name", node.class_name)
              builder.field("args") { write_nodes(builder, node.args) }
              write_nullable_range(builder, "name_span", node.name_span)
              builder.field("invokes_initializer", node.invokes_initializer?)
            when IR::NIR::Spawn
              builder.field("proc") { write_node(builder, node.proc) }
            when IR::NIR::ChannelNew
              builder.field("element") { Value.write_type(builder, node.element) }
              write_nullable_node(builder, "capacity", node.capacity)
            when IR::NIR::MutexNew
            when IR::NIR::ChannelOp
              builder.field("operation") { write_channel_operation(builder, node) }
            when IR::NIR::Select
              builder.field("arms") do
                builder.array { node.arms.each { |arm| write_select_arm(builder, arm) } }
              end
              write_nullable_node(builder, "else_body", node.else_body)
            when IR::NIR::Raise
              builder.field("value") { write_node(builder, node.value) }
              builder.field("raise_kind", node.kind.to_s)
            when IR::NIR::ExceptionNew
              builder.field("class_name", node.class_name)
              write_nullable_node(builder, "message", node.message)
            when IR::NIR::ExceptionHandler
              builder.field("body") { write_node(builder, node.body) }
              builder.field("clauses") do
                builder.array { node.clauses.each { |clause| write_rescue_clause(builder, clause) } }
              end
              write_nullable_node(builder, "else_branch", node.else_branch)
              write_nullable_node(builder, "ensure_branch", node.ensure_branch)
            when IR::NIR::Return, IR::NIR::Break, IR::NIR::Next
              write_nullable_node(builder, "value", node.value)
              builder.field("target") do
                Value.write_nullable(builder, node.target) { |target| builder.string(target.value) }
              end
            when IR::NIR::FieldInitializer
              builder.field("field") { Value.write_field(builder, node.field) }
              builder.field("value") { write_node(builder, node.value) }
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::Class
              builder.field("name", node.name)
              builder.field("concrete_type") { Value.write_type(builder, node.concrete_type) }
              builder.field("superclass_name") do
                Value.write_nullable(builder, node.superclass_name) { |name| builder.string(name) }
              end
              builder.field("superclass_type") do
                Value.write_nullable(builder, node.superclass_type) { |type| Value.write_type(builder, type) }
              end
              builder.field("fields") do
                builder.array { node.fields.each { |field| Value.write_field(builder, field) } }
              end
              builder.field("initializers") { write_nodes(builder, node.initializers) }
              builder.field("reference", node.reference?)
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::Enum
              builder.field("type") { Value.write_type(builder, node.type) }
              builder.field("base_type") { Value.write_type(builder, node.base_type) }
              builder.field("members") do
                builder.array do
                  node.members.each do |member|
                    builder.object do
                      builder.field("name", member.name)
                      builder.field("value", member.value)
                      write_nullable_range(builder, "name_span", member.name_span)
                    end
                  end
                end
              end
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::Namespace
              builder.field("path", node.path)
              builder.field("body") { write_node(builder, node.body) }
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::TypeAlias
              builder.field("path", node.path)
              builder.field("target") { Value.write_type(builder, node.target) }
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::TypeAliasReference
              builder.field("path", node.path)
              builder.field("target") { Value.write_type(builder, node.target) }
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::Constant
              builder.field("path", node.path)
              builder.field("value") { write_node(builder, node.value) }
              builder.field("type") { Value.write_type(builder, node.type) }
              write_nullable_range(builder, "name_span", node.name_span)
            when IR::NIR::Def
              builder.field("name", node.name)
              builder.field("owner") do
                Value.write_nullable(builder, node.owner) { |type| Value.write_type(builder, type) }
              end
              builder.field("callable_kind", node.callable_kind.to_s)
              builder.field("namespace_path", node.namespace_path)
              builder.field("params") { write_nodes(builder, node.params) }
              write_nullable_node(builder, "block_param", node.block_param)
              builder.field("body") { write_node(builder, node.body) }
              builder.field("return_type") do
                Value.write_nullable(builder, node.return_type) { |type| Value.write_type(builder, type) }
              end
              write_nullable_node(builder, "return_type_reference", node.return_type_reference)
              write_nullable_range(builder, "name_span", node.name_span)
              builder.field("capability_witnesses") do
                builder.array do
                  node.capability_witnesses.each { |witness| Value.write_conformance(builder, witness) }
                end
              end
            when IR::NIR::While
              builder.field("cond") { write_node(builder, node.cond) }
              builder.field("body") { write_node(builder, node.body) }
            else
              raise CodecError.new("$.normalized_nir", "unhandled NIR node #{node.class.name}")
            end
          end

          private def write_named(builder, node) : Nil
            builder.field("name", node.name)
            write_nullable_range(builder, "name_span", node.name_span)
          end

          private def write_call(builder, node : IR::NIR::Call) : Nil
            builder.field("name", node.name)
            builder.field("args") { write_nodes(builder, node.args) }
            builder.field("targets") do
              builder.array { node.targets.each { |target| Value.write_call_target(builder, target) } }
            end
            write_nullable_node(builder, "block", node.block)
            builder.field("primitive") do
              Value.write_nullable(builder, node.primitive) { |primitive| Value.write_primitive(builder, primitive) }
            end
            write_nullable_range(builder, "name_span", node.name_span)
            write_nullable_node(builder, "dispatch_receiver", node.dispatch_receiver)
          end

          private def write_array_operation(builder, node : IR::NIR::ArrayOperation) : Nil
            builder.field("array") { write_node(builder, node.array) }
            builder.field("element") { Value.write_type(builder, node.element) }
          end

          private def write_hash_type(builder, node : IR::NIR::HashExpr) : Nil
            builder.field("hash_type") { Value.write_type(builder, node.hash_type) }
          end

          private def write_channel_operation(builder, operation : IR::NIR::ChannelOp) : Nil
            builder.object do
              builder.field("kind", operation.kind.to_s)
              builder.field("channel") { write_node(builder, operation.channel) }
              write_nullable_node(builder, "value", operation.value)
              builder.field("element") { Value.write_type(builder, operation.element) }
            end
          end

          private def write_select_arm(builder, arm : IR::NIR::Select::Arm) : Nil
            builder.object do
              builder.field("operation") { write_node(builder, arm.operation) }
              write_nullable_node(builder, "captured", arm.captured)
              builder.field("body") { write_node(builder, arm.body) }
            end
          end

          private def write_rescue_clause(builder, clause : IR::NIR::RescueClause) : Nil
            builder.object do
              builder.field("types") do
                builder.array { clause.types.each { |type| Value.write_type(builder, type) } }
              end
              write_nullable_node(builder, "binding", clause.binding)
              builder.field("body") { write_node(builder, clause.body) }
            end
          end

          private def write_nodes(builder, nodes) : Nil
            builder.array { nodes.each { |node| write_node(builder, node) } }
          end

          private def write_nullable_node(builder, key : String, node) : Nil
            builder.field(key) do
              Value.write_nullable(builder, node) { |present| write_node(builder, present) }
            end
          end

          private def write_nullable_range(builder, key : String, range) : Nil
            builder.field(key) do
              Value.write_nullable(builder, range) { |present| Value.write_range(builder, present) }
            end
          end

          private def canonical_type_key(type : IR::Type) : String
            JSON.build { |builder| Value.write_type(builder, type) }
          end

          private def kind(node : IR::NIR::Stmt) : String
            case node
            when IR::NIR::Block              then "block"
            when IR::NIR::Local              then "local"
            when IR::NIR::ClassRef           then "class_ref"
            when IR::NIR::EnumMember         then "enum_member"
            when IR::NIR::ConstantReference  then "constant_reference"
            when IR::NIR::InstanceVar        then "instance_var"
            when IR::NIR::Param              then "param"
            when IR::NIR::Assign             then "assign"
            when IR::NIR::If                 then "if"
            when IR::NIR::UnsupportedExpr    then "unsupported_expr"
            when IR::NIR::IntLiteral         then "int_literal"
            when IR::NIR::FloatLiteral       then "float_literal"
            when IR::NIR::StringLiteral      then "string_literal"
            when IR::NIR::BoolLiteral        then "bool_literal"
            when IR::NIR::NilLiteral         then "nil_literal"
            when IR::NIR::BlockArg           then "block_arg"
            when IR::NIR::BlockLiteral       then "block_literal"
            when IR::NIR::BlockParam         then "block_param"
            when IR::NIR::InvokeBlock        then "invoke_block"
            when IR::NIR::Call               then "call"
            when IR::NIR::CollectionMap      then "collection_map"
            when IR::NIR::CollectionFilter   then "collection_filter"
            when IR::NIR::CollectionEach     then "collection_each"
            when IR::NIR::CollectionFold     then "collection_fold"
            when IR::NIR::IndexedRead        then "indexed_read"
            when IR::NIR::IndexedWrite       then "indexed_write"
            when IR::NIR::Interpolation      then "interpolation"
            when IR::NIR::Size               then "size"
            when IR::NIR::StringCharAt       then "string_char_at"
            when IR::NIR::StringEachChar     then "string_each_char"
            when IR::NIR::StringSplit        then "string_split"
            when IR::NIR::StringToFloat      then "string_to_float"
            when IR::NIR::StringToInteger    then "string_to_integer"
            when IR::NIR::ArrayNew           then "array_new"
            when IR::NIR::ArrayBuild         then "array_build"
            when IR::NIR::ArrayGet           then "array_get"
            when IR::NIR::ArraySet           then "array_set"
            when IR::NIR::ArrayPush          then "array_push"
            when IR::NIR::ValueSequence      then "value_sequence"
            when IR::NIR::HashNew            then "hash_new"
            when IR::NIR::HashGet            then "hash_get"
            when IR::NIR::HashSet            then "hash_set"
            when IR::NIR::HashFetch          then "hash_fetch"
            when IR::NIR::HashHasKey         then "hash_has_key"
            when IR::NIR::HashKeyAt          then "hash_key_at"
            when IR::NIR::Not                then "not"
            when IR::NIR::TypeTest           then "type_test"
            when IR::NIR::Cast               then "cast"
            when IR::NIR::New                then "new"
            when IR::NIR::Spawn              then "spawn"
            when IR::NIR::ChannelNew         then "channel_new"
            when IR::NIR::MutexNew           then "mutex_new"
            when IR::NIR::ChannelOp          then "channel_op"
            when IR::NIR::Select             then "select"
            when IR::NIR::Raise              then "raise"
            when IR::NIR::ExceptionNew       then "exception_new"
            when IR::NIR::ExceptionHandler   then "exception_handler"
            when IR::NIR::Return             then "return"
            when IR::NIR::Break              then "break"
            when IR::NIR::Next               then "next"
            when IR::NIR::FieldInitializer   then "field_initializer"
            when IR::NIR::Class              then "class"
            when IR::NIR::Enum               then "enum"
            when IR::NIR::Namespace          then "namespace"
            when IR::NIR::TypeAlias          then "type_alias"
            when IR::NIR::TypeAliasReference then "type_alias_reference"
            when IR::NIR::Constant           then "constant"
            when IR::NIR::Def                then "def"
            when IR::NIR::While              then "while"
            else
              raise CodecError.new("$.normalized_nir", "unhandled NIR node #{node.class.name}")
            end
          end
        end
      end
    end
  end
end
