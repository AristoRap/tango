module Tango
  module Dump
    module LIR
      def self.render(snapshot : Compiler::Snapshot) : String
        program = snapshot.lir
        return "" unless program

        String.build do |io|
          SourceGraphHeader.append(io, snapshot.source)
          io << "UncaughtException " << program.uncaught_exception << '\n'
          program.external_types.each do |binding|
            io << "ExternalType " << binding.type << " " << binding.binding.language << " " << binding.shape
            binding.binding.import_path.try { |import_path| io << " import=" << import_path }
            binding.binding.package_identifier.try { |package_identifier| io << " package=" << package_identifier }
            binding.binding.name.try { |name| io << " name=" << name }
            io << '\n'
          end
          program.enums.each { |definition| emit_enum(io, definition) }
          program.types.each { |type| emit_type(io, type) }
          program.unions.each { |union| emit_union(io, union) }
          program.conversions.each { |conversion| emit_conversion(io, conversion) }
          program.arrays.each { |array| emit_array(io, array) }
          program.hashes.each { |hash| emit_hash(io, hash) }
          program.globals.each do |global|
            io << "Global " << global.name << " : " << global.type
            emit_inline_value(io, global.value, 0)
            SourceLocations.append(io, global.loc)
            io << '\n'
          end
          program.functions.each { |function| emit_func(io, function) }
          program.body.each { |stmt| emit_stmt(io, stmt, 0) }
        end
      end

      private def self.emit_array(io : IO, array : IR::LIR::ArrayType) : Nil
        io << "Array " << array.type << " element=" << array.element
        io << " repr=" << (array.reference? ? "PointerSlice" : "Slice") << '\n'
      end

      private def self.emit_hash(io : IO, hash : IR::LIR::HashType) : Nil
        io << "Hash " << hash.type << " key=" << hash.key << " value=" << hash.value
        io << " repr=" << (hash.reference? ? "Reference" : "Value")
        io << " order=" << (hash.ordered? ? "Insertion" : "Unspecified") << '\n'
      end

      private def self.emit_enum(io : IO, definition : IR::LIR::EnumType) : Nil
        io << "Enum " << definition.target_name << " : " << definition.base_type
        definition.members.each do |member|
          io << " (" << member.name << '=' << member.value << " -> " << member.target_name << ')'
        end
        io << '\n'
      end

      private def self.emit_union(io : IO, union : IR::LIR::UnionType) : Nil
        io << "Union " << union.name
        union.variants.each do |variant|
          io << " (" << variant.tag << ":" << variant.label
          variant.payload.try { |payload| io << " : " << payload }
          io << ")"
        end
        io << '\n'
      end

      private def self.emit_conversion(io : IO, conversion : IR::LIR::UnionConversion) : Nil
        io << "UnionConversion " << conversion.mapping.name << " " << conversion.source << " -> " << conversion.target
        conversion.mapping.variants.each do |variant|
          io << " (" << variant.member << ":" << variant.source_tag << "->" << variant.target_tag << ")"
        end
        io << '\n'
      end

      private def self.emit_type(io : IO, type : IR::LIR::StructType) : Nil
        io << (type.reference ? "Struct " : "ValueStruct ") << type.name
        type.fields.each { |field| io << " (" << field.name << " : " << field.type << ")" }
        io << " ExceptionRuntime[#{type.exception_ancestors.join(" < ")}]" if type.exception_runtime?
        io << " IdentityPadding" if type.identity_padding?
        io << '\n'
      end

      private def self.emit_func(io : IO, function : IR::LIR::Func) : Nil
        io << "Func " << function.name
        function.params.each do |param|
          io << " (" << param.name
          param.type.try { |type| io << " : " << type }
          param.proc_signature.try { |signature| io << " : (" << signature.param_types.join(", ") << ") -> " << (signature.return_type || "Nil") }
          io << " repr=" << param.repr unless param.repr.native?
          io << " by_ref" if param.by_ref?
          io << ")"
        end
        function.return_type.try { |return_type| io << " : " << return_type }
        SourceLocations.append(io, function.loc)
        io << '\n'
        function.body.each { |stmt| emit_stmt(io, stmt, 1) }
      end

      private def self.emit_stmt(io : IO, stmt : IR::LIR::Stmt, depth : Int32) : Nil
        # A statement can carry a multi-line inline value (a Closure renders its
        # own body at depth+1), so build the line first and terminate it only if
        # that inline rendering didn't already end the line — mirroring how If/
        # While terminate their header before recursing into children.
        line = String.build do |head|
          head << "  " * depth << stmt.class.name.split("::").last
          case stmt
          when IR::LIR::ExternalCall
            stmt.args.each { |arg| emit_inline_value(head, arg, depth) }
          when IR::LIR::Assign
            head << " " << stmt.target << " " << stmt.mode
            emit_inline_value(head, stmt.value, depth)
          when IR::LIR::FieldAssign
            head << " " << stmt.field
            emit_inline_value(head, stmt.receiver, depth)
            emit_inline_value(head, stmt.value, depth)
          when IR::LIR::Discard
            emit_inline_value(head, stmt.value, depth)
          when IR::LIR::If
            emit_inline_value(head, stmt.cond, depth)
          when IR::LIR::While
            emit_inline_value(head, stmt.cond, depth)
          when IR::LIR::Handler
            surfaces = [] of String
            surfaces << "rescue" unless stmt.clauses.empty?
            surfaces << "else" if stmt.else_body
            surfaces << "ensure" if stmt.ensure_body
            head << " " << surfaces.join(",")
            head << " no_return" if stmt.no_return?
          when IR::LIR::AbruptExit
            head << " " << stmt.shape
            stmt.value.try { |value| emit_inline_value(head, value, depth) }
          when IR::LIR::ChanSend
            emit_inline_value(head, stmt.channel, depth)
            emit_inline_value(head, stmt.value, depth)
          when IR::LIR::ChanClose
            emit_inline_value(head, stmt.channel, depth)
          when IR::LIR::Spawn
            emit_inline_value(head, stmt.proc, depth)
          when IR::LIR::StringEachChar
            emit_inline_value(head, stmt.string, depth)
          when IR::LIR::Select
            head << " arms=" << stmt.arms.size
            head << " default" if stmt.default
          when IR::LIR::UnsupportedStmt
            head << " " << stmt.reason
          else
            raise ArgumentError.new("unhandled LIR dump statement: #{stmt.class.name}")
          end
        end
        io << line
        SourceLocations.append(io, stmt.loc) unless line.ends_with?('\n')
        io << '\n' unless line.ends_with?('\n')

        case stmt
        when IR::LIR::If
          stmt.then_body.each { |child| emit_stmt(io, child, depth + 1) }
          stmt.else_body.each { |child| emit_stmt(io, child, depth + 1) }
        when IR::LIR::While
          stmt.body.each { |child| emit_stmt(io, child, depth + 1) }
        when IR::LIR::Handler
          io << "  " * (depth + 1) << "Body\n"
          stmt.body.each { |child| emit_stmt(io, child, depth + 2) }
          stmt.clauses.each do |clause|
            io << "  " * (depth + 1) << "Rescue"
            io << " " << (clause.types.empty? ? "Exception" : clause.types.join(" | "))
            clause.binding.try { |binding| io << " as " << binding }
            io << '\n'
            clause.body.each { |child| emit_stmt(io, child, depth + 2) }
          end
          stmt.else_body.try do |body|
            io << "  " * (depth + 1) << "Else\n"
            body.each { |child| emit_stmt(io, child, depth + 2) }
          end
          stmt.ensure_body.try do |body|
            io << "  " * (depth + 1) << "Ensure\n"
            body.each { |child| emit_stmt(io, child, depth + 2) }
          end
        when IR::LIR::Select
          stmt.arms.each do |arm|
            io << "  " * (depth + 1) << "Arm " << arm.kind
            arm.binding.try { |binding| io << " " << binding }
            io << " : " << arm.element
            arm.result_type.try { |type| io << " -> " << type }
            emit_inline_value(io, arm.channel, depth + 1)
            arm.value.try { |value| emit_inline_value(io, value, depth + 1) }
            io << '\n'
            arm.body.each { |child| emit_stmt(io, child, depth + 2) }
          end
          stmt.default.try do |default|
            io << "  " * (depth + 1) << "Default\n"
            default.each { |child| emit_stmt(io, child, depth + 2) }
          end
        when IR::LIR::StringEachChar
          io << "  " * (depth + 1) << "Block\n"
          stmt.block.body.each { |child| emit_stmt(io, child, depth + 2) }
        end
      end

      private def self.emit_inline_value(io : IO, value : IR::LIR::Value, depth : Int32) : Nil
        case value
        when IR::LIR::IntConst
          io << " IntConst " << value.type << " " << value.value
        when IR::LIR::FloatConst
          io << " FloatConst " << value.type << " " << value.value
        when IR::LIR::StringConst
          io << " StringConst " << value.value.inspect
        when IR::LIR::EnumConst
          io << " EnumConst " << value.enum_type << "::" << value.member
        when IR::LIR::GlobalRef
          io << " GlobalRef " << value.name
        when IR::LIR::CollectionCount
          io << " CollectionCount " << value.source.class.name.split("::").last
          case source = value.source
          when IR::LIR::ArrayElements
            io << " " << source.element
          when IR::LIR::HashEntries
            io << " " << source.hash_type
          end
          emit_inline_value(io, source.value, depth)
        when IR::LIR::FusedCollectionTraversal
          io << " FusedCollectionTraversal " << value.type
          io << " Source=" << value.source.class.name.split("::").last
          if source = value.source.as?(IR::LIR::ArrayElements)
            io << '(' << source.element << ')'
          end
          emit_inline_value(io, value.source.value, depth)
          if source = value.source.as?(IR::LIR::StringSegments)
            emit_inline_value(io, source.separator, depth)
          end
          value.transforms.each do |transform|
            io << " Transform=" << transform.class.name.split("::").last
          end
          io << " Terminal=" << value.terminal.class.name.split("::").last
        when IR::LIR::StringCharAt
          io << " StringCharAt"
          emit_inline_value(io, value.string, depth)
          emit_inline_value(io, value.index, depth)
        when IR::LIR::StringToFloat
          io << " StringToFloat"
          emit_inline_value(io, value.string, depth)
        when IR::LIR::StringToInteger
          io << " StringToInteger " << value.type
          emit_inline_value(io, value.string, depth)
          value.options.each { |option| emit_inline_value(io, option, depth) }
        when IR::LIR::ScalarStringify
          io << " ScalarStringify " << value.presentation << " " << value.source
          io << " effects=" << value.effects.size unless value.effects.empty?
          value.value.try { |inner| emit_inline_value(io, inner, depth) }
        when IR::LIR::Interpolation
          io << " Interpolation pieces=" << value.pieces.size
          value.pieces.each { |piece| emit_inline_value(io, piece, depth) }
        when IR::LIR::ExceptionValue
          io << " ExceptionValue " << value.class_name
          value.message.try { |message| emit_inline_value(io, message, depth) }
        when IR::LIR::BoolConst
          io << " BoolConst " << value.value
        when IR::LIR::Temp
          io << " Temp " << value.name
        when IR::LIR::FieldAccess
          io << " FieldAccess " << value.field
          emit_inline_value(io, value.receiver, depth)
        when IR::LIR::Alloc
          io << " Alloc " << value.type_name
        when IR::LIR::AddressOf
          io << " AddressOf"
          emit_inline_value(io, value.value, depth)
        when IR::LIR::Call
          io << " Call " << value.name
          value.args.each { |arg| emit_inline_value(io, arg, depth) }
        when IR::LIR::ExternalCallValue
          io << " ExternalCall "
          value.target.package_identifier.try { |package_identifier| io << package_identifier << '.' }
          io << value.target.name
          value.target.import_path.try { |import_path| io << " import=" << import_path }
          value.target.dependency.try { |dependency| io << " module=" << dependency.identity << '@' << dependency.version }
          value.args.each { |arg| emit_inline_value(io, arg, depth) }
        when IR::LIR::Binary
          io << " Binary " << value.operator
          emit_inline_value(io, value.left, depth)
          emit_inline_value(io, value.right, depth)
        when IR::LIR::IntegerConvert
          io << " IntegerConvert " << value.mode << ' ' << value.source << " -> " << value.target
          emit_inline_value(io, value.value, depth)
        when IR::LIR::FloatToIntegerConvert
          io << " FloatToIntegerConvert " << value.source << " -> " << value.target
          emit_inline_value(io, value.value, depth)
        when IR::LIR::NumericConvert
          io << " NumericConvert " << value.source << " -> " << value.target
          emit_inline_value(io, value.value, depth)
        when IR::LIR::IntegerBitNot
          io << " IntegerBitNot " << value.type
          emit_inline_value(io, value.operand, depth)
        when IR::LIR::IntegerNegate
          io << " IntegerNegate " << value.type
          emit_inline_value(io, value.value, depth)
        when IR::LIR::IntegerOperationValue
          io << " IntegerOperation " << value.kind << ' ' << value.type
          emit_inline_value(io, value.left, depth)
          emit_inline_value(io, value.right, depth)
        when IR::LIR::StringCompare
          io << " StringCompare"
          emit_inline_value(io, value.left, depth)
          emit_inline_value(io, value.right, depth)
        when IR::LIR::FloatIntrinsic
          io << " FloatIntrinsic " << value.operation << ' ' << value.type
          emit_inline_value(io, value.value, depth)
        when IR::LIR::Not
          io << " Not"
          emit_inline_value(io, value.value, depth)
        when IR::LIR::TypeTest
          io << " TypeTest " << value.strategy << " " << value.source << " -> " << value.target
          emit_inline_value(io, value.value, depth)
        when IR::LIR::Cast
          io << " Cast " << value.strategy << " " << value.source << " -> " << value.target
          emit_inline_value(io, value.value, depth)
        when IR::LIR::CheckedArithmetic
          io << " CheckedArithmetic " << value.operation << ' ' << value.type << ' ' << value.strategy
          emit_inline_value(io, value.left, depth)
          emit_inline_value(io, value.right, depth)
        when IR::LIR::FloatArithmetic
          io << " FloatArithmetic " << value.operation
          emit_inline_value(io, value.left, depth)
          emit_inline_value(io, value.right, depth)
        when IR::LIR::FloorArithmetic
          io << " FloorArithmetic " << value.operation << ' ' << value.type
          emit_inline_value(io, value.left, depth)
          emit_inline_value(io, value.right, depth)
        when IR::LIR::IfValue
          io << " IfValue"
          emit_inline_value(io, value.cond, depth)
          emit_inline_value(io, value.then_value, depth)
          emit_inline_value(io, value.else_value, depth)
        when IR::LIR::RescueValue
          io << " RescueValue " << value.type << '\n'
          emit_rescue_arm(io, "Body", value.body, depth + 1)
          value.clauses.each do |clause|
            label = "Rescue #{clause.types.empty? ? "Exception" : clause.types.join(" | ")}"
            clause.binding.try { |binding| label += " as #{binding}" }
            emit_rescue_arm(io, label, clause.body, depth + 1)
          end
          value.else_arm.try { |arm| emit_rescue_arm(io, "Else", arm, depth + 1) }
          value.ensure_body.try do |body|
            io << "  " * (depth + 1) << "Ensure\n"
            body.each { |stmt| emit_stmt(io, stmt, depth + 2) }
          end
        when IR::LIR::InvokeClosure
          io << " InvokeClosure"
          emit_inline_value(io, value.callee, depth)
          value.args.each { |arg| emit_inline_value(io, arg, depth) }
        when IR::LIR::Closure
          io << " Closure"
          value.params.each { |param| io << " (" << param.name << ")" }
          io << '\n'
          value.body.each { |stmt| emit_stmt(io, stmt, depth + 1) }
        when IR::LIR::NilConst
          io << " NilConst"
        when IR::LIR::NilValue
          io << " NilValue"
        when IR::LIR::Box
          io << " Box " << value.union << " member=" << (value.member || IR::Type::NIL)
          value.value.try { |inner| emit_inline_value(io, inner, depth) }
        when IR::LIR::Unbox
          io << " Unbox " << value.union << " member=" << value.member
          emit_inline_value(io, value.value, depth)
        when IR::LIR::NilCheck
          io << " NilCheck " << value.union
          emit_inline_value(io, value.value, depth)
        when IR::LIR::Widen
          io << " Widen " << value.source << " -> " << value.union << " via=" << value.conversion
          emit_inline_value(io, value.value, depth)
        when IR::LIR::MakeChan
          io << " MakeChan " << value.element
          value.capacity.try { |capacity| emit_inline_value(io, capacity, depth) }
        when IR::LIR::MakeMutex
          io << " MakeMutex"
        when IR::LIR::ChanReceive
          io << " ChanReceive " << value.element
          emit_inline_value(io, value.channel, depth)
        when IR::LIR::ChanReceiveMaybe
          io << " ChanReceiveMaybe " << value.element
          emit_inline_value(io, value.channel, depth)
        when IR::LIR::ChanReceiveMaybeBox
          io << " ChanReceiveMaybeBox " << value.element << " -> " << value.union
          emit_inline_value(io, value.channel, depth)
        when IR::LIR::ChanReceiveState
          io << " ChanReceiveState " << value.element << " -> " << value.result_type
          io << " fields=" << value.value_field << ',' << value.open_field
          emit_inline_value(io, value.channel, depth)
        when IR::LIR::ArrayNew
          io << " ArrayNew " << value.type
        when IR::LIR::ArrayBuild
          io << " ArrayBuild " << value.type
          emit_inline_value(io, value.size, depth)
        when IR::LIR::ArrayGet
          io << " ArrayGet " << value.element
          emit_inline_value(io, value.array, depth)
          emit_inline_value(io, value.index, depth)
        when IR::LIR::ArraySet
          io << " ArraySet " << value.element
          emit_inline_value(io, value.array, depth)
          emit_inline_value(io, value.index, depth)
          emit_inline_value(io, value.value, depth)
        when IR::LIR::ArrayPush
          io << " ArrayPush " << value.element
          emit_inline_value(io, value.array, depth)
          emit_inline_value(io, value.value, depth)
        when IR::LIR::MaterializedStringSplit
          io << " MaterializedStringSplit " << value.type
          emit_inline_value(io, value.string, depth)
          value.separator.try { |separator| emit_inline_value(io, separator, depth) }
        when IR::LIR::HashNew
          io << " HashNew " << value.key_type << ", " << value.value_type
        when IR::LIR::HashGet
          io << " HashGet " << value.key_type << ", " << value.value_type
          emit_inline_value(io, value.hash, depth)
          emit_inline_value(io, value.key, depth)
        when IR::LIR::HashSet
          io << " HashSet " << value.key_type << ", " << value.value_type
          emit_inline_value(io, value.hash, depth)
          emit_inline_value(io, value.key, depth)
          emit_inline_value(io, value.value, depth)
        when IR::LIR::HashFetch
          io << " HashFetch " << value.key_type << ", " << value.value_type
          emit_inline_value(io, value.hash, depth)
          emit_inline_value(io, value.key, depth)
          emit_inline_value(io, value.default, depth)
        when IR::LIR::HashHasKey
          io << " HashHasKey " << value.key_type << ", " << value.value_type
          emit_inline_value(io, value.hash, depth)
          emit_inline_value(io, value.key, depth)
        when IR::LIR::HashKeyAt
          io << " HashKeyAt " << value.key_type << ", " << value.value_type
          emit_inline_value(io, value.hash, depth)
          emit_inline_value(io, value.index, depth)
        when IR::LIR::ValueSequence
          io << " ValueSequence " << value.type << '\n'
          value.body.each { |stmt| emit_stmt(io, stmt, depth + 1) }
          io << "  " * (depth + 1) << "Value"
          emit_inline_value(io, value.value, depth + 1)
        when IR::LIR::UnsupportedValue
          io << " UnsupportedValue " << value.reason
        else
          raise ArgumentError.new("unhandled LIR dump value: #{value.class.name}")
        end
      end

      private def self.emit_rescue_arm(io : IO, label : String, arm : IR::LIR::RescueValue::Arm, depth : Int32) : Nil
        io << "  " * depth << label << '\n'
        arm.body.each { |stmt| emit_stmt(io, stmt, depth + 1) }
        arm.value.try do |value|
          io << "  " * (depth + 1) << "Value"
          emit_inline_value(io, value, depth + 1)
          io << '\n'
        end
      end
    end
  end
end
