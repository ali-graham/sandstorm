require 'active_support/concern'

require 'zermelo/records/errors'

require 'zermelo/filters/steps/list_step'
require 'zermelo/filters/steps/set_step'
require 'zermelo/filters/steps/sorted_set_step'
require 'zermelo/filters/steps/sort_step'

module Zermelo

  module Filters

    module Base

      extend ActiveSupport::Concern

      attr_reader :backend, :steps

      # initial set         a Zermelo::Record::Key object
      # associated_class    the class of the result record
      def initialize(data_backend, initial_key, associated_class, ancestor = nil, step = nil)
        @backend          = data_backend
        @initial_key      = initial_key
        @associated_class = associated_class
        @steps            = ancestor.nil? ? [] : ancestor.steps.dup
        @steps << step unless step.nil?
      end

      def intersect(attrs = {})
        self.class.new(@backend, @initial_key, @associated_class, self,
          ::Zermelo::Filters::Steps::SetStep.new({:op => :intersect}, attrs))
      end

      def union(attrs = {})
        self.class.new(@backend, @initial_key, @associated_class, self,
          ::Zermelo::Filters::Steps::SetStep.new({:op => :union}, attrs))
      end

      def diff(attrs = {})
        self.class.new(@backend, @initial_key, @associated_class, self,
          ::Zermelo::Filters::Steps::SetStep.new({:op => :diff}, attrs))
      end

      def sort(keys, opts = {})
        self.class.new(@backend, @initial_key, @associated_class, self,
          ::Zermelo::Filters::Steps::SortStep.new({:keys => keys,
            :desc => opts[:desc], :limit => opts[:limit],
            :offset => opts[:offset]}, {})
          )
      end

      def offset(amount, opts = {})
        self.class.new(@backend, @initial_key, @associated_class, self,
          ::Zermelo::Filters::Steps::ListStep.new({:offset => amount,
            :limit => opts[:limit]}, {}))
      end

      def page(num, opts = {})
        per_page = opts[:per_page].to_i || 20
        start  = per_page * (num - 1)
        finish = start + (per_page - 1)
        self.class.new(@backend, @initial_key, @associated_class, self,
          ::Zermelo::Filters::Steps::ListStep.new({:offset => start,
            :limit => per_page}, {}))
      end

      def intersect_range(start, finish, attrs_opts = {})
        self.class.new(@backend, @initial_key, @associated_class, self,
          ::Zermelo::Filters::Steps::SortedSetStep.new(
            {:op => :intersect_range, :start => start, :finish => finish,
             :by_score => attrs_opts.delete(:by_score)},
            attrs_opts)
          )
      end

      def union_range(start, finish, attrs_opts = {})
        self.class.new(@backend, @initial_key, @associated_class, self,
          ::Zermelo::Filters::Steps::SortedSetStep.new(
            {:op => :union_range, :start => start, :finish => finish,
             :by_score => attrs_opts.delete(:by_score)},
            attrs_opts)
          )
      end

      def diff_range(start, finish, attrs_opts = {})
        self.class.new(@backend, @initial_key, @associated_class, self,
          ::Zermelo::Filters::Steps::SortedSetStep.new(
            {:op => :diff_range, :start => start, :finish => finish,
             :by_score => attrs_opts.delete(:by_score)},
            attrs_opts)
          )
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
        raise ::Zermelo::Records::Errors::RecordNotFound.new(@associated_class, f_id) if ret.nil?
        ret
      end

      def find_by_ids(*f_ids)
        lock { f_ids.collect {|f_id| _find_by_id(f_id) } }
      end

      def find_by_ids!(*f_ids)
        ret = lock { f_ids.collect {|f_id| _find_by_id(f_id) } }
        if ret.any? {|r| r.nil? }
          raise ::Zermelo::Records::Errors::RecordsNotFound.new(@associated_class, f_ids - ret.compact.map(&:id))
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
        lock(*@associated_class.send(:associated_classes)) do
          _all.each {|r| r.destroy }
        end
      end

      def associated_ids_for(name, options = {})
        klass = @associated_class.send(:with_association_data, name.to_sym) do |data|
          data.type_klass
        end

        lock {
          case klass.name
          when ::Zermelo::Associations::BelongsTo.name
            klass.send(:associated_ids_for, @backend,
              @associated_class, name,
              options[:inversed].is_a?(TrueClass), *_ids)
          else
            klass.send(:associated_ids_for, @backend,
              @associated_class, name, *_ids)
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