module Tango
  module Dump
    module NIR
      def self.render(snapshot : Compiler::Snapshot) : String
        program = snapshot.nir
        return "" unless program

        String.build do |io|
          SourceGraphHeader.append(io, snapshot.source)
          program.type_annotations.each do |type, entries|
            entries.each { |entry| io << "type_annotation " << type << " " << entry.path.join("::") << '\n' }
          end
          IR::NIR::Walk.children(program).each { |stmt| emit_stmt(io, stmt, 0) }
        end
      end

      private def self.emit_stmt(io : IO, node : IR::NIR::Stmt, depth : Int32) : Nil
        io << "  " * depth << node.id << " " << label(node)
        if node.is_a?(IR::NIR::Expr) && (type = node.type)
          io << " : " << type
        end
        SourceLocations.append(io, node.span)
        io << '\n'

        IR::NIR::Walk.children(node).each { |child| emit_stmt(io, child, depth + 1) }
      end

      private def self.label(node : IR::NIR::Stmt) : String
        base = node.class.name.split("::").last

        case node
        when IR::NIR::IntLiteral    then "#{base} #{node.value}"
        when IR::NIR::FloatLiteral  then "#{base} #{node.value}"
        when IR::NIR::StringLiteral then "#{base} #{node.value.inspect}"
        when IR::NIR::BoolLiteral   then "#{base} #{node.value}"
        when IR::NIR::Local         then "#{base} #{node.name}"
        when IR::NIR::ClassRef      then "#{base} #{node.name}"
        when IR::NIR::EnumMember    then "#{base} #{node.enum_type}::#{node.name}"
        when IR::NIR::InstanceVar   then "#{base} @#{node.name} of #{node.owner}"
        when IR::NIR::New           then "#{base} #{node.class_name}"
        when IR::NIR::Param
          if type = node.type
            "#{base} #{node.name} : #{type}"
          else
            "#{base} #{node.name}"
          end
        when IR::NIR::BlockArg         then "#{base} #{node.name}"
        when IR::NIR::FieldInitializer then "#{base} #{node.name} : #{node.type}"
        when IR::NIR::BlockParam
          kind = node.yield_parameter? ? "yield " : ""
          "#{base} #{kind}#{node.name} : #{proc_signature(node.signature)}"
        when IR::NIR::InvokeBlock
          node.yield_site? ? "#{base} yield" : base
        when IR::NIR::Call
          if primitive = node.primitive
            "#{base} #{node.name} primitive #{primitive.kind}"
          else
            "#{base} #{node.name}"
          end
        when IR::NIR::CollectionFilter then "#{base} #{node.mode} fallback=#{node.fallback.name}"
        when IR::NIR::CollectionMap    then "#{base} fallback=#{node.fallback.name}"
        when IR::NIR::CollectionEach   then "#{base} fallback=#{node.fallback.name}"
        when IR::NIR::CollectionFold   then "#{base} fallback=#{node.fallback.name}"
        when IR::NIR::IndexedRead      then "#{base} fallback=#{node.fallback.name}"
        when IR::NIR::IndexedWrite     then "#{base} fallback=#{node.fallback.name}"
        when IR::NIR::Interpolation    then "#{base} pieces=#{node.pieces.size}"
        when IR::NIR::StringSplit
          node.separator ? "#{base} separator" : base
        when IR::NIR::Size then base
        when IR::NIR::ArrayNew, IR::NIR::ArrayBuild, IR::NIR::ArrayGet, IR::NIR::ArraySet, IR::NIR::ArrayPush
          "#{base} #{node.element}"
        when IR::NIR::HashNew, IR::NIR::HashGet, IR::NIR::HashSet, IR::NIR::HashFetch, IR::NIR::HashHasKey, IR::NIR::HashKeyAt
          "#{base} #{node.key_type}, #{node.value_type}"
        when IR::NIR::TypeTest   then "#{base} #{node.target}"
        when IR::NIR::Cast       then "#{base} #{node.target}"
        when IR::NIR::ChannelNew then "#{base} #{node.element}"
        when IR::NIR::ChannelOp  then "#{base} #{node.kind}"
        when IR::NIR::Select
          kinds = node.arms.map(&.kind).join(", ")
          node.else_body ? "#{base} #{kinds}, else" : "#{base} #{kinds}"
        when IR::NIR::Raise        then "#{base} #{node.kind}"
        when IR::NIR::ExceptionNew then "#{base} #{node.class_name}"
        when IR::NIR::ExceptionHandler
          surface = [] of String
          surface << "rescue" unless node.clauses.empty?
          surface << "else" if node.else_branch
          surface << "ensure" if node.ensure_branch
          "#{base} #{surface.join(", ")}"
        when IR::NIR::Return, IR::NIR::Break, IR::NIR::Next then "#{base} target=#{node.target || "function"}"
        when IR::NIR::Def
          name = node.owner.try { |owner| "#{owner}##{node.name}" } || node.name
          header = if return_type = node.return_type
                     "#{base} #{name} : #{return_type}"
                   else
                     "#{base} #{name}"
                   end
          unless node.capability_witnesses.empty?
            witnesses = node.capability_witnesses.map { |witness| "#{witness.concrete} as #{witness.capability}" }
            header += " capabilities=[#{witnesses.join(", ")}]"
          end
          header
        when IR::NIR::Class
          header = node.superclass_name ? "#{base} #{node.name} < #{node.superclass_name}" : "#{base} #{node.name}"
          if node.fields.empty?
            header
          else
            "#{header} { #{node.fields.map { |field| "#{field.name} : #{field.type}" }.join(", ")} }"
          end
        when IR::NIR::Enum
          members = node.members.map { |member| "#{member.name}=#{member.value}" }.join(", ")
          "#{base} #{node.name} : #{node.base_type} { #{members} }"
        when IR::NIR::UnsupportedExpr then "#{base} #{node.crystal_node}"
        else                               base
        end
      end

      private def self.proc_signature(signature : IR::NIR::ProcSignature) : String
        "(#{signature.param_types.join(", ")}) -> #{signature.return_type || "Nil"}"
      end
    end
  end
end
