# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module ServerData
    MUTEX = Mutex.new
    EMPTY = {}.freeze
    private_constant :MUTEX, :EMPTY

    class << self
      def [](key)
        values[key.to_s]
      end

      def fetch(key, *args, &block)
        values.fetch(key.to_s, *args, &block)
      end

      def available?
        MUTEX.synchronize { @snapshot != nil }
      end

      def revision
        MUTEX.synchronize { @snapshot&.revision }
      end

      private

      def values
        MUTEX.synchronize { @snapshot&.values || EMPTY }
      end

      def receive(data)
        snapshot = data.is_a?(EltenLink::ServerDataSnapshot) ? data : EltenLink::ServerDataSnapshot.new(data)
        MUTEX.synchronize { @snapshot = snapshot }
        true
      rescue StandardError => error
        Log.warning("Server data update failed: #{error.class}: #{error.message}")
        false
      end
    end
  end
end
