module Tango
  module IR
    module NIR
      class Program
        getter body : Array(Stmt)
        getter type_annotations : Hash(IR::Type, Array(TargetAnnotation))

        def initialize(@body : Array(Stmt), @type_annotations : Hash(IR::Type, Array(TargetAnnotation)) = {} of IR::Type => Array(TargetAnnotation))
        end
      end
    end
  end
end
