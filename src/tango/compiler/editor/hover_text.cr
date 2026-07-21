module Tango
  module Compiler
    module Editor
      # Plain source-language presentation for a structured Hover::Result. LSP
      # markup and protocol envelopes stay outside this formatter.
      module HoverText
        def self.render(result : Hover::Result) : String
          text =
            case subject = result.subject
            when Hover::ClassSubject
              "class #{subject.name}"
            when Hover::EnumSubject
              "enum #{subject.name}"
            when Hover::EnumMemberSubject
              "#{subject.owner.to_semantic_s}::#{subject.name} : #{subject.owner.to_semantic_s}"
            when Hover::BindingSubject
              "#{subject.name} : #{subject.type.to_semantic_s}"
            when Hover::CallableSubject
              parameters = subject.parameters.empty? ? "" : "(#{subject.parameter_types.map(&.to_semantic_s).join(", ")})"
              separator = subject.kind.in?(IR::NIR::CallableKind::ClassMethod, IR::NIR::CallableKind::Constructor) ? "." : "#"
              owner = subject.owner.try { |type| "#{type.to_semantic_s}#{separator}" } || ""
              suffix = subject.return_type.try { |type| " : #{type.to_semantic_s}" } || ""
              "#{owner}#{subject.name}#{parameters}#{suffix}"
            when Hover::ProcSubject
              result_type = subject.return_type.try(&.to_semantic_s) || "Nil"
              "#{subject.name} : (#{subject.parameter_types.map(&.to_semantic_s).join(", ")}) -> #{result_type}"
            else
              ""
            end

          if result.notes.includes?(Hover::Note::CapturedByGoroutine)
            text += " (captured by a goroutine)"
          end
          result.documentation.try { |documentation| text += "\n\n#{documentation}" }
          text
        end
      end
    end
  end
end
