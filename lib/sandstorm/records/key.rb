module Sandstorm
  module Records
    class Key

      # id       / if nil, it's a class variable
      # object   / :association, :attribute or :index
      # accessor / if a complex type, some way of getting sub-value
      attr_reader :klass, :id, :name, :accessor, :type, :object

      # TODO better validation of data, e.g. accessor valid for type, etc.
      def initialize(opts = {})
        [:klass, :id, :name, :accessor, :type, :object].each do |iv|
          instance_variable_set("@#{iv}", opts[iv])
        end
      end

    end
  end
end