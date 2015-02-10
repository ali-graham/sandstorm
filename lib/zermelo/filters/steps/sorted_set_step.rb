require 'zermelo/filters/steps/base_step'

module Zermelo
  module Filters
    class Steps
      class SortedSetStep < Zermelo::Filters::Steps::BaseStep
        def self.accepted_types
          [:sorted_set]
        end

        def self.returns_type
          :sorted_set
        end

        def resolve(backend, associated_class, source, idx_attrs, attr_types,
          temp_keys, opts = {})

          op     = @options[:op]
          start  = @options[:start]
          finish = @options[:finish]

          case backend
          when Zermelo::Backends::RedisBackend

            range_temp_key = associated_class.send(:temp_key, :sorted_set)
            temp_keys << range_temp_key
            range_ids_set = backend.key_to_redis_key(range_temp_key)

            if @options[:by_score]
              start = '-inf' if start.nil? || (start <= 0)
              finish = '+inf' if finish.nil? || (finish <= 0)
            else
              start = 0 if start.nil?
              finish = -1 if finish.nil?
            end

            args = [start, finish]

            if @options[:by_score]
              query = :zrangebyscore
              args = args.map(&:to_s)
            else
              query = :zrange
            end

            args << {:with_scores => :true}

            if @options[:limit]
              args.last.update(:limit => [0, @options[:limit].to_i])
            end

            r_source   = backend.key_to_redis_key(source)
            args.unshift(r_source)

            range_ids_scores = Zermelo.redis.send(query, *args)

            unless range_ids_scores.empty?
              Zermelo.redis.zadd(range_ids_set, range_ids_scores.map(&:reverse))
            end

            self.class.evaluate(backend, @options[:op], associated_class,
              source, [range_temp_key], temp_keys, opts)
          end
        end

        def self.evaluate(backend, op, associated_class, source, source_keys, temp_keys, opts = {})
          weights = case op
          when :union, :union_range
            [0.0] * source_keys.length
          when :diff, :diff_range
            [-1.0] * source_keys.length
          end

          r_source   = backend.key_to_redis_key(source)
          r_source_keys = source_keys.collect {|sk| backend.key_to_redis_key(sk) }

          dest_sorted_set = associated_class.send(:temp_key, :sorted_set)
          temp_keys << dest_sorted_set
          r_dest_sorted_set = backend.key_to_redis_key(dest_sorted_set)

          case op
          when :union, :union_range
            Zermelo.redis.zinterstore(r_dest_sorted_set, r_source_keys, :weights => weights, :aggregate => 'max')
            Zermelo.redis.zunionstore(r_dest_sorted_set, [r_source, r_dest_sorted_set])
          when :intersect, :intersect_range
            Zermelo.redis.zinterstore(r_dest_sorted_set, [r_source] + r_source_keys, :weights => weights, :aggregate => 'max')
          when :diff, :diff_range
            # 'zdiffstore' via weights, relies on non-zero scores being used
            # see https://code.google.com/p/redis/issues/detail?id=579
            Zermelo.redis.zinterstore(r_dest_sorted_set, r_source_keys, :weights => weights, :aggregate => 'max')
            Zermelo.redis.zunionstore(r_dest_sorted_set, [r_source, r_dest_sorted_set])
            Zermelo.redis.zremrangebyscore(r_dest_sorted_set, "0", "0")
          end

          dest_sorted_set
        end

      end
    end
  end
end