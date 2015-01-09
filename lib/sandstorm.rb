require 'sandstorm/version'

require 'time'

module Sandstorm

  # backport for Ruby 1.8
  unless Enumerable.instance_methods.include?(:each_with_object)
    module ::Enumerable
      def each_with_object(memo)
        return to_enum :each_with_object, memo unless block_given?
          each do |element|
            yield element, memo
          end
        memo
      end
    end
  end

  # acceptable class types, which will be normalized on a per-backend basis
  ATTRIBUTE_TYPES  = {:string     => [String],
                      :integer    => [Integer],
                      :float      => [Float],
                      :id         => [String],
                      :timestamp  => [Integer, Time, DateTime],
                      :boolean    => [TrueClass, FalseClass],
                     }

  COLLECTION_TYPES = {:list       => [Enumerable],
                      :set        => [Set],
                      :hash       => [Hash],
                      :sorted_set => [Enumerable]
                     }

  ALL_TYPES = ATTRIBUTE_TYPES.merge(COLLECTION_TYPES)

  class << self
    def valid_type?(type)
      ALL_TYPES.keys.include?(type)
    end

    # Thread and fiber-local
    [:redis, :influxdb].each do |backend|
      define_method(backend) do
        Thread.current["sandstorm_#{backend.to_s}".to_sym]
      end
      define_method("#{backend.to_s}=".to_sym) do |connection|
        Thread.current["sandstorm_#{backend.to_s}".to_sym] = connection
      end
    end

  end
end
