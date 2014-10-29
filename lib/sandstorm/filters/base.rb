require 'active_support/concern'

require 'sandstorm/records/errors'

require 'sandstorm/filters/steps/diff_range_step'
require 'sandstorm/filters/steps/diff_step'
require 'sandstorm/filters/steps/intersect_range_step'
require 'sandstorm/filters/steps/intersect_step'
require 'sandstorm/filters/steps/limit_step'
require 'sandstorm/filters/steps/offset_step'
require 'sandstorm/filters/steps/sort_step'
require 'sandstorm/filters/steps/union_range_step'
require 'sandstorm/filters/steps/union_step'

module Sandstorm

  module Filters

    module Base

      extend ActiveSupport::Concern

      attr_reader :backend

      # initial set         a Sandstorm::Record::Key object
      # associated_class    the class of the result record
      def initialize(data_backend, initial_set, associated_class)
        @backend          = data_backend
        @initial_set      = initial_set
        @associated_class = associated_class
        @steps            = []
      end

      # TODO each step type have class methods list its acceptable input types, and
      # have a class method giving its output type

      def intersect(attrs = {})
        @steps << ::Sandstorm::Filters::Steps::IntersectStep.new({}, attrs)
        self
      end

      def union(attrs = {})
        @steps << ::Sandstorm::Filters::Steps::UnionStep.new({}, attrs)
        self
      end

      def diff(attrs = {})
        @steps << ::Sandstorm::Filters::Steps::DiffStep.new({}, attrs)
        self
      end

      def sort(att, opts = {})
        @steps << ::Sandstorm::Filters::Steps::SortStep.new({:key => att,
          :order => opts[:order], :limit => opts[:limit],
          :offset => opts[:offset]}, {})
        self
      end

      def limit(amount)
        @steps << Sandstorm::Filters::Steps::LimitStep.new({:amount => amount}, {})
        self
      end

      def offset(amount)
        @steps << Sandstorm::Filters::Steps::OffsetStep({:amount => amount}, {})
        self
      end

      def intersect_range(start, finish, attrs_opts = {})
        @steps << ::Sandstorm::Filters::Steps::IntersectRangeStep.new(
          {:start => start, :finish => finish,
           :order => attrs_opts.delete(:order),
           :by_score => attrs_opts.delete(:by_score)},
          attrs_opts
        )
        self
      end

      def union_range(start, finish, attrs_opts = {})
        @steps << ::Sandstorm::Filters::Steps::UnionRangeStep.new(
          {:start => start, :finish => finish,
           :order => attrs_opts.delete(:order),
           :by_score => attrs_opts.delete(:by_score)},
          attrs_opts
        )
        self
      end

      def diff_range(start, finish, attrs_opts = {})
        @steps << ::Sandstorm::Filters::Steps::DiffRangeStep.new(
          {:start => start, :finish => finish,
           :order => attrs_opts.delete(:order),
           :by_score => attrs_opts.delete(:by_score)},
          attrs_opts
        )
        self
      end

      # step users
      def exists?(e_id)
        lock(false) { _exists?(e_id) }
      end

      def find_by_id(f_id)
        lock { _find_by_id(f_id) }
      end

      def find_by_id!(f_id)
        ret = lock { _find_by_id(f_id) }
        raise ::Sandstorm::Records::Errors::RecordNotFound.new(@associated_class, f_id) if ret.nil?
        ret
      end

      def find_by_ids(*f_ids)
        lock { f_ids.collect {|f_id| _find_by_id(f_id) } }
      end

      def find_by_ids!(*f_ids)
        ret = lock { f_ids.collect {|f_id| _find_by_id(f_id) } }
        if ret.any? {|r| r.nil? }
          raise ::Sandstorm::Records::Errors::RecordsNotFound.new(@associated_class, f_ids - ret.compact.map(&:id))
        end
        ret
      end

      def ids
        lock(false) { _ids }
      end

      def count
        lock(false) { _count }
      end

      def empty?
        lock(false) { _count == 0 }
      end

      def all
        lock { _all }
      end

      # NB makes no sense to apply this without order clause
      def page(num, opts = {})
        ret = nil
        per_page = opts[:per_page].to_i || 20
        if (num > 0) && (per_page > 0)
          lock do
            start  = per_page * (num - 1)
            finish = start + (per_page - 1)
            @steps += [Sandstorm::Filters::Steps::OffsetStep.new({:amount => start},    {}),
                       Sandstorm::Filters::Steps::LimitStep.new({:amount => per_page}, {})]
            page_ids = _ids
            ret = page_ids.collect {|f_id| _load(f_id)} unless page_ids.nil?
          end
        end
        ret || []
      end

      def collect(&block)
        lock { _ids.collect {|id| block.call(_load(id))} }
      end
      alias_method :map, :collect

      def each(&block)
        lock { _ids.each {|id| block.call(_load(id)) } }
      end

      def select(&block)
        lock { _all.select {|obj| block.call(obj) } }
      end
      alias_method :find_all, :select

      def reject(&block)
        lock { _all.reject {|obj| block.call(obj)} }
      end

      def destroy_all
        lock(*@associated_class.send(:associated_classes)) { _all.each {|r| r.destroy } }
      end

      def associated_ids_for(name, options = {})
        klass = @associated_class.send(:with_association_data, name.to_sym) do |data|
          data.type_klass
        end

        lock {
          case klass.name
          when ::Sandstorm::Associations::BelongsTo.name
            klass.send(:associated_ids_for, @backend,
              @associated_class.send(:class_key), name,
              options[:inversed].is_a?(TrueClass), *_ids)
          else
            klass.send(:associated_ids_for, @backend,
              @associated_class.send(:class_key), name, *_ids)
          end
        }
      end

      protected

      def lock(when_steps_empty = true, *klasses, &block)
        return(block.call) if !when_steps_empty && @steps.empty?
        klasses += [@associated_class] if !klasses.include?(@associated_class)
        @backend.lock(*klasses, &block)
      end

      private

      def _find_by_id(id)
        if !id.nil? && _exists?(id)
          _load(id.to_s)
        else
          nil
        end
      end

      def _load(id)
        object = @associated_class.new
        object.load(id)
        object
      end

      def _all
        _ids.map {|id| _load(id) }
      end

    end

  end

end
