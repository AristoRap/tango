module Tango
  module Compiler
    module Editor
      # Rich LSP presentation for a protocol-neutral Hover::Result. Signatures
      # are isolated in a Tango code block, declaration docs retain Markdown,
      # and secondary analysis notes stay visually subordinate.
      module HoverMarkdown
        def self.render(result : Hover::Result) : String
          sections = ["```tango\n#{signature(result.subject)}\n```"]

          if documentation = result.documentation
            documentation = documentation.strip
            sections << documentation unless documentation.empty?
          end

          if result.notes.includes?(Hover::Note::CapturedByGoroutine)
            sections << "---\n\n*Captured by a goroutine.*"
          end

          sections.join("\n\n")
        end

        private def self.signature(subject : Hover::Subject) : String
          case subject
          when Hover::ClassSubject
            "class #{subject.name}"
          when Hover::StructSubject
            "struct #{subject.name}"
          when Hover::EnumSubject
            "enum #{subject.name}"
          when Hover::EnumMemberSubject
            "#{subject.owner.to_semantic_s}::#{subject.name} : #{subject.owner.to_semantic_s}"
          when Hover::ConstantSubject
            "const #{subject.name} : #{subject.type.to_semantic_s}"
          when Hover::TypeAliasSubject
            "alias #{subject.name} = #{subject.target.to_semantic_s}"
          when Hover::BindingSubject
            "#{subject.name} : #{subject.type.to_semantic_s}"
          when Hover::CallableSubject
            callable_signature(subject)
          when Hover::ProcSubject
            result_type = subject.return_type.try(&.to_semantic_s) || "Nil"
            "#{subject.name} : (#{subject.parameter_types.map(&.to_semantic_s).join(", ")}) -> #{result_type}"
          else
            ""
          end
        end

        private def self.callable_signature(subject : Hover::CallableSubject) : String
          String.build do |io|
            io << "def "
            if owner = subject.owner
              separator = subject.kind.in?(IR::NIR::CallableKind::ClassMethod, IR::NIR::CallableKind::Constructor) ? '.' : '#'
              io << owner.to_semantic_s << separator
            end
            io << subject.name

            unless subject.parameters.empty?
              io << '('
              subject.parameters.each_with_index do |parameter, index|
                io << ", " if index > 0
                io << parameter.name << " : " unless parameter.name.empty?
                io << parameter.type.to_semantic_s
              end
              io << ')'
            end

            subject.return_type.try { |type| io << " : " << type.to_semantic_s }
          end
        end
      end
    end
  end
end
