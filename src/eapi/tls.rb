# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "openssl"

module EltenAPI
  module TLS
    class Error < StandardError
    end

    class << self
      def install!
        pem = EltenAPI::Resources.read("ssl/cert.pem").to_s.b
        if pem == ""
          raise Error, "Embedded TLS CA bundle is unavailable" if defined?(::EltenEmbedded)
          Log.warning("Embedded TLS CA bundle is unavailable; using OpenSSL defaults") if defined?(Log)
          return OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE
        end

        certificates = OpenSSL::X509::Certificate.load(pem)
        raise Error, "Embedded TLS CA bundle contains no certificates" if certificates.empty?

        store = OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE
        added = 0
        certificates.each do |certificate|
          begin
            store.add_cert(certificate)
            added += 1
          rescue OpenSSL::X509::StoreError => e
            raise if e.message !~ /already in hash table/i
          end
        end
        Log.info("Embedded TLS certificate store installed: #{certificates.size} CAs, #{added} added") if defined?(Log)
        store
      rescue ArgumentError, OpenSSL::OpenSSLError => e
        raise Error, "Cannot install embedded TLS CA bundle: #{e.message}"
      end
    end
  end
end

EltenAPI::TLS.install!
