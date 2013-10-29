require 'sandstorm/redis_key'

module Sandstorm
  module Associations
    class UniqueIndex

      def initialize(parent, class_key, att)
        @indexers = {}

        @parent = parent
        @class_key = class_key
        @attribute = att
      end

      def value
        @value
      end

      def value=(value)
        @value = value
      end

      def delete_id(id)
        Sandstorm.redis.hdel(indexer.key, @value)
      end

      def add_id(id)
        Sandstorm.redis.hset(indexer.key, @value, id)
      end

      def move_id(id, indexer_to)
        Sandstorm.redis.hdel(indexer.key, @value)
        Sandstorm.redis.hset(indexer.key, indexer_to.value, id)
      end

      def clear_if_empty
        Sandstorm.redis.del(indexer.key) if (Sandstorm.redis.hlen(indexer.key) == 0)
      end

      def key
        indexer.key
      end

      private

      def indexer
        @indexer ||= Sandstorm::RedisKey.new("#{@class_key}::by_#{@attribute}", :hash)
      end

    end
  end
end