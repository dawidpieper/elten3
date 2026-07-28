# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

module EltenAPI
  module InvisibleInterface
    class << self
      def available?
        false
      end

      def start
        false
      end

      def stop
        true
      end

      def tick
        false
      end

      def session_changed
        false
      end

      def reset_for_loading
        false
      end

      def reset_feeds
        false
      end

      def set_feed_id(_id)
        false
      end

      def open_message_dialog(*_args, **_kwargs)
        false
      end

      def open_feed_dialog(*_args, **_kwargs)
        false
      end

      def open_chat_dialog(*_args, **_kwargs)
        false
      end
    end
  end
end
