require 'sandstorm/errors'

module Sandstorm

  class Filter

    # initial set         a Sandstorm::RedisKey object
    # associated_class    the class of the result record
    def initialize(initial_set, associated_class)
      @initial_set = initial_set
      @associated_class = associated_class
      @steps = []
    end

    # step builders
    def intersect(opts = {})
      @steps += [:intersect, opts]
      self
    end

    def union(opts = {})
      @steps += [:union, opts]
      self
    end

    def diff(opts = {})
      @steps += [:diff, opts]
      self
    end

    def intersect_range(start, finish, opts = {})
      @steps += [:intersect_range, opts.merge(:start => start, :finish => finish)]
      self
    end

    def union_range(start, finish, opts = {})
      @steps += [:union_range, opts.merge(:start => start, :finish => finish)]
      self
    end
    # end step builders

    # step users
    def ids
      lock(false) { _ids }
    end

    def count
      lock(false) { _count }
    end

    def empty?
      lock(false) { _count == 0 }
    end

    def exists?(id)
      lock(false) { _exists?(id) }
    end

    def find_by_id(id)
      lock { _find_by_id(id) }
    end

    def find_by_id!(id)
      ret = lock { _find_by_id(id) }
      raise ::Sandstorm::Errors::RecordNotFound.new(@associated_class, id) if ret.nil?
      ret
    end

    def find_by_ids(ids)
      lock { _ids.collect {|id| _find_by_id(id) } }
    end

    def find_by_ids!(ids)
      ret = lock { _ids.collect {|id| _find_by_id(id) } }
      unless ids.length.eql?(ret.length)
        raise ::Sandstorm::Errors::RecordsNotFound.new(@associated_class, ids - ret.map(&:id))
      end
      ret
    end

    def all
      lock { _ids.map {|id| _load(id) } }
    end

    def first
      raise 'Can\'t get first member of a non-sorted set' unless @initial_set.type == :sorted_set
      lock {
        first_id = resolve_steps{|set, order_desc|
          Sandstorm.redis.send(:zrange, set, 0, 0).first
        }
        if first_id.nil?
          nil
        else
          _load(first_id)
        end
      }
    end

    def last
      raise 'Can\'t get last member of a non-sorted set' unless @initial_set.type == :sorted_set
      lock {
        last_id = resolve_steps{|set, order_desc|
          Sandstorm.redis.send(:zrevrange, set, 0, 0).first
        }
        if last_id.nil?
          nil
        else
          _load(last_id)
        end
      }
    end

    def collect(&block)
      lock { _ids.collect {|id| block.call(_load(id))} }
    end

    def each(&block)
      lock { _each(&block) }
    end

    def select(&block)
      lock { _all.select {|obj| block.call(obj) } }
    end
    alias_method :find_all, :select

    def reject(&block)
      lock { _all.reject {|obj| block.call(obj)} }
    end

    def destroy_all
      lock(*@associated_class.send(:associated_classes)) { _each {|r| r.destroy } }
    end
    # end step users

    private

    def lock(when_steps_empty = true, *klasses, &block)
      if !when_steps_empty && @steps.empty?
        return yield
      end
      klasses = [@associated_class] if klasses.empty?
      @associated_class.send(:lock, *klasses) { yield }
    end

    def _count
      case @initial_set.type
      when :sorted_set
        resolve_steps {|set, desc|
          Sandstorm.redis.zcard(set)
        }
      when :set, nil
        resolve_steps(:scard)
      end
    end

    def _exists?(id)
      return if id.nil?
      resolve_steps {|set, desc|
        case @initial_set.type
        when :sorted_set
          !Sandstorm.redis.zrank(set, id.to_s).nil?
        when :set, nil
          Sandstorm.redis.sismember(set, id.to_s)
        end
      }
    end

    def _find_by_id(id)
      if !id.nil? && _exists?(id)
        _load(id.to_s)
      else
        nil
      end
    end

    def _all
      _ids.map {|id| _load(id) }
    end

    def _ids
      case @initial_set.type
      when :sorted_set
        resolve_steps {|set, order_desc|
          Sandstorm.redis.send((order_desc ? :zrevrange : :zrange), set, 0, -1)
        }
      when :set, nil
        resolve_steps(:smembers)
      end
    end

    def _each(&block)
      _ids.each {|id| block.call(_load(id)) }
    end

    def _load(id)
      object = @associated_class.new
      object.load(id)
      object
    end

    def temp_set_name
      "#{@associated_class.send(:class_key)}::tmp:#{SecureRandom.hex(16)}"
    end

    def indexed_step_to_set(att, value)
      index = @associated_class.send("#{att}_index", value)

      case index
      when Sandstorm::Associations::UniqueIndex
        idx_result = temp_set_name
        Sandstorm.redis.sadd(idx_result,
          Sandstorm.redis.hget(@associated_class.send("#{att}_index", value).key, value))
        [idx_result, true]
      when Sandstorm::Associations::Index
        [index.key, false]
      end
    end

    def resolve_step(step, source_set, idx_attrs, &block)
      temp_sets   = []
      source_keys = [source_set]

      if [:intersect, :union, :diff].include?(step.first)

        source_keys += step.last.inject([]) do |memo, (att, value)|
          raise "'#{att}' property is not indexed" unless idx_attrs.include?(att.to_s)

          if value.is_a?(Enumerable)
            conditions_set = temp_set_name
            temp_idx_sets = []
            Sandstorm.redis.sunionstore(conditions_set, *value.collect {|val|
              idx_set, clear = indexed_step_to_set(att, val)
              temp_idx_sets << idx_set if clear
              idx_set
            })
            Sandstorm.redis.del(temp_idx_sets) unless temp_idx_sets.empty?
            temp_sets << conditions_set
            memo << conditions_set
          else
            idx_set, clear = indexed_step_to_set(att, value)
            temp_sets << idx_set if clear
            memo << idx_set
          end

          memo
        end

      elsif [:intersect_range, :union_range].include?(step.first)
        range_ids_set = temp_set_name

        options = step.last

        start = options[:start]
        finish = options[:finish]

        order_desc = options[:order] && 'desc'.eql?(options[:order].downcase)

        if options[:by_score]
          start = '-inf' if start.nil? || (start <= 0)
          finish = '+inf' if finish.nil? || (finish <= 0)
        else
          start = 0 if start.nil?
          finish = -1 if finish.nil?
        end

        args = [start, finish]

        if order_desc
          if options[:by_score]
            query = :zrevrangebyscore
            args = args.map(&:to_s).reverse
          else
            query = :zrevrange
          end
        elsif options[:by_score]
          query = :zrangebyscore
          args = args.map(&:to_s)
        else
          query = :zrange
        end

        args << {:with_scores => :true}

        if options[:limit]
          args.last.update(:limit => [0, options[:limit].to_i])
        end

        args.unshift(source_set)

        range_ids_scores = Sandstorm.redis.send(query, *args)

        unless range_ids_scores.empty?
          Sandstorm.redis.zadd(range_ids_set, range_ids_scores.map(&:reverse))
        end
        source_keys << range_ids_set
        temp_sets << range_ids_set
      end

      yield(source_keys)

      unless temp_sets.empty?
        Sandstorm.redis.del(*temp_sets)
        temp_sets.clear
      end
    end


    # TODO possible candidate for moving to a stored Lua script in the redis server?

    # takes a block and passes the name of the temporary set to it; deletes
    # the temporary set once done
    def resolve_steps(shortcut = nil, &block)
      source_set = @initial_set.key
      ret = nil

      if @steps.empty?
        ret = if shortcut
          value = Sandstorm.redis.send(shortcut, source_set)
          block ? block.call(value) : value
        else
          block.call(source_set, false)
        end
        return(ret)
      end

      dest_set  = (!shortcut || (@steps.size > 2)) ? temp_set_name : nil

      idx_attrs = @associated_class.send(:indexed_attributes)

      order_desc = nil

      step_num = 0
      members = nil

      @steps.each_slice(2) do |step|
        step_num += 2

        resolve_step(step, source_set, idx_attrs) do |source_keys|
          options = step.last
          order_desc = order_desc ^ (options[:order] && 'desc'.eql?(options[:order].downcase))

          smember_shortcut = :smembers.eql?(shortcut) && (step_num == @steps.size)

          case @initial_set.type
          when :sorted_set
            weights = [1.0] + ([0.0] * (source_keys.length - 1))
            case step.first
            when :union, :union_range
              Sandstorm.redis.zunionstore(dest_set, source_keys, :weights => weights, :aggregate => 'max')
            when :intersect, :intersect_range
              Sandstorm.redis.zinterstore(dest_set, source_keys, :weights => weights, :aggregate => 'max')
            end
          when :set, nil
            case step.first
            when :union
              if smember_shortcut
                members = Sandstorm.redis.sunion(*source_keys)
              else
                Sandstorm.redis.sunionstore(dest_set, *source_keys)
              end
            when :intersect
              if smember_shortcut
                members = Sandstorm.redis.sinter(*source_keys)
              else
                Sandstorm.redis.sinterstore(dest_set, *source_keys)
              end
            when :diff
              if smember_shortcut
                members = Sandstorm.redis.sdiff(*source_keys)
              else
                Sandstorm.redis.sdiffstore(dest_set, *source_keys)
              end
            end
          end
        end

        source_set = dest_set
      end

      ret = if shortcut
        value = members || Sandstorm.redis.send(shortcut, dest_set)
        block ? block.call(value) : value
      else
        block.call(dest_set, order_desc)
      end

      Sandstorm.redis.del(dest_set) unless :smembers.eql?(shortcut) && (step_num <= 2)
      ret
    end
  end

end
