module Tango
  module Compiler
    module Editor
      # One editor-facing callable model for free functions, instance methods,
      # and class/metaclass methods. A site may have an exact resolved symbol or
      # only candidates while source is incomplete; both states use the same
      # receiver identity and declaration catalog. Prelude, bundled stdlib, and
      # user callables enter through the same indices—there are no API-name
      # cases here.
      module Callables
        record Parameter, label : String, documentation : String? = nil
        record Candidate,
          name : String,
          label : String,
          parameters : Array(Parameter),
          documentation : String? = nil,
          declaration : Index::SymbolId? = nil
        record Site,
          name : String,
          receiver : Index::Receiver?,
          resolved : Index::SymbolId? = nil

        def self.members(
          surface : Frontend::SyntaxSurface::Index,
          index : Index,
          receiver : Index::Receiver,
          path : String,
          offset : Int32,
        ) : Array(Candidate)
          current_type = surface.enclosing_type(path, offset)
          owner = owner_name(receiver.type)
          semantic = index.declarations.compact_map do |declaration|
            signature = declaration.signature
            next unless signature && signature.owner == receiver.type
            constructor = receiver.kind.class? && signature.kind.initializer?
            next unless constructor || callable_kind_matches?(signature.kind, receiver.kind)
            next if declaration.visibility.private? && current_type != owner

            semantic_candidate(declaration, signature, receiver.kind, constructor ? "new" : declaration.name)
          end
          syntax = surface.declarations.compact_map do |declaration|
            next unless declaration.kind.method? && declaration.container == owner
            constructor = receiver.kind.class? && declaration.callable_kind.try(&.initializer?)
            next unless constructor || surface_kind_matches?(declaration.callable_kind, receiver.kind)
            next unless visible?(declaration, current_type, path)

            surface_candidate(declaration, receiver.kind, constructor ? "new" : declaration.name)
          end
          (semantic + syntax).uniq(&.name)
        end

        def self.candidates(
          site : Site,
          surface : Frontend::SyntaxSurface::Index,
          index : Index,
          path : String,
          offset : Int32,
        ) : Array(Candidate)
          receiver = site.receiver
          current_type = surface.enclosing_type(path, offset)
          owner = receiver.try { |value| owner_name(value.type) }
          semantic_ranges = Set({String, Int32, Int32}).new
          candidates = index.declarations.compact_map do |declaration|
            signature = declaration.signature
            next unless signature && source_name_matches?(site.name, declaration.name, signature.kind)
            if receiver
              next unless signature.owner == receiver.type
              next unless callable_site_kind_matches?(site.name, signature.kind, receiver.kind)
            else
              next if signature.owner
            end
            next if declaration.visibility.private? && current_type != owner && declaration.range.path != path

            semantic_ranges << range_key(declaration.range)
            semantic_candidate(
              declaration,
              signature,
              receiver.try(&.kind) || Index::ReceiverKind::Instance,
              site.name
            )
          end

          surface.declarations.each do |declaration|
            kind = declaration.callable_kind
            next unless kind && source_name_matches?(site.name, declaration.name, kind)
            if receiver
              next unless declaration.container == owner
              next unless surface_site_kind_matches?(site.name, kind, receiver.kind)
            else
              next unless kind.function?
            end
            next unless visible?(declaration, current_type, path)
            next if semantic_ranges.includes?(range_key(declaration.selection_range))

            candidates << surface_candidate(
              declaration,
              receiver.try(&.kind) || Index::ReceiverKind::Instance,
              site.name
            )
          end

          candidates.uniq(&.label)
        end

        def self.active_index(site : Site, candidates : Array(Candidate)) : Int32
          site.resolved.try do |symbol|
            candidates.index { |candidate| candidate.declaration == symbol }
          end || 0
        end

        private def self.semantic_candidate(
          declaration : Index::Declaration,
          signature : Index::Signature,
          receiver_kind : Index::ReceiverKind,
          source_name : String = declaration.name,
        ) : Candidate
          Candidate.new(
            source_name,
            semantic_label(source_name, signature, receiver_kind),
            signature.parameters.map { |parameter| Parameter.new("#{parameter.name} : #{parameter.type.to_semantic_s}") },
            declaration.documentation,
            declaration.id
          )
        end

        private def self.surface_candidate(
          declaration : Frontend::SyntaxSurface::Declaration,
          receiver_kind : Index::ReceiverKind,
          source_name : String = declaration.name,
        ) : Candidate
          Candidate.new(
            source_name,
            surface_label(declaration, receiver_kind, source_name),
            declaration.parameters.map { |parameter| Parameter.new(parameter_label(parameter)) },
            declaration.documentation
          )
        end

        private def self.callable_kind_matches?(
          kind : IR::NIR::CallableKind,
          receiver_kind : Index::ReceiverKind,
        ) : Bool
          receiver_kind.class? ? kind.class_method? : kind.instance_method?
        end

        private def self.callable_site_kind_matches?(
          source_name : String,
          kind : IR::NIR::CallableKind,
          receiver_kind : Index::ReceiverKind,
        ) : Bool
          return receiver_kind.class? if source_name == "new" && kind.initializer?
          callable_kind_matches?(kind, receiver_kind)
        end

        private def self.surface_kind_matches?(
          kind : Frontend::SyntaxSurface::CallableKind?,
          receiver_kind : Index::ReceiverKind,
        ) : Bool
          return false unless kind
          receiver_kind.class? ? kind.class_method? : kind.instance_method?
        end

        private def self.surface_site_kind_matches?(
          source_name : String,
          kind : Frontend::SyntaxSurface::CallableKind,
          receiver_kind : Index::ReceiverKind,
        ) : Bool
          return receiver_kind.class? if source_name == "new" && kind.initializer?
          surface_kind_matches?(kind, receiver_kind)
        end

        private def self.source_name_matches?(
          source_name : String,
          declaration_name : String,
          kind : IR::NIR::CallableKind | Frontend::SyntaxSurface::CallableKind,
        ) : Bool
          declaration_name == source_name || (source_name == "new" && kind.initializer?)
        end

        private def self.visible?(
          declaration : Frontend::SyntaxSurface::Declaration,
          current_type : String?,
          path : String,
        ) : Bool
          return true unless declaration.visibility.private?
          declaration.container ? declaration.container == current_type : declaration.selection_range.path == path
        end

        private def self.owner_name(type : IR::Type) : String
          type.name || type.to_s
        end

        private def self.semantic_label(
          name : String,
          signature : Index::Signature,
          receiver_kind : Index::ReceiverKind,
        ) : String
          String.build do |io|
            if owner = signature.owner
              io << owner.to_semantic_s << receiver_separator(receiver_kind)
            end
            io << name << '('
            signature.parameters.each_with_index do |parameter, index|
              io << ", " if index > 0
              io << parameter.name << " : " << parameter.type.to_semantic_s
            end
            io << ')'
            if signature.kind.initializer?
              signature.owner.try { |owner| io << " : " << owner.to_semantic_s }
            else
              signature.return_type.try { |type| io << " : " << type.to_semantic_s }
            end
          end
        end

        private def self.surface_label(
          declaration : Frontend::SyntaxSurface::Declaration,
          receiver_kind : Index::ReceiverKind,
          source_name : String,
        ) : String
          String.build do |io|
            declaration.container.try { |owner| io << owner << receiver_separator(receiver_kind) }
            io << source_name << '('
            declaration.parameters.each_with_index do |parameter, index|
              io << ", " if index > 0
              io << parameter_label(parameter)
            end
            io << ')'
            if declaration.callable_kind.try(&.initializer?)
              declaration.container.try { |owner| io << " : " << owner }
            else
              declaration.explicit_type.try { |type| io << " : " << type }
            end
          end
        end

        private def self.receiver_separator(kind : Index::ReceiverKind) : Char
          kind.class? ? '.' : '#'
        end

        private def self.parameter_label(parameter : Frontend::SyntaxSurface::Parameter) : String
          parameter.explicit_type ? "#{parameter.name} : #{parameter.explicit_type}" : parameter.name
        end

        private def self.range_key(range : Source::Range) : {String, Int32, Int32}
          {range.path, range.start_offset, range.end_offset}
        end
      end
    end
  end
end
