# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

require "base64"
require "http/2"
require "io/wait"
require "json"
require "monitor"
require "openssl"
require "securerandom"
require "timeout"
require "uri"

module EltenAPI
  class ERDownloadProgress
    attr_reader :downloaded, :total, :percent

    def initialize(downloaded, total)
      @downloaded = downloaded.to_i
      @total = total.to_i
      @percent = @total > 0 ? (@downloaded.to_f / @total.to_f * 100.0).floor : 0
    end
  end

  module HTTPClient
    HOST = "api.elten.link".freeze
    PORT = 443
    HTTP2_ALPN = "h2".freeze
    CONNECT_TIMEOUT = 8
    READ_TIMEOUT = 20
    STALE_AFTER = 20
    MAX_REDIRECTS = 5
    TRANSPORT_SESSION_ALGORITHM = "AES-256-GCM-SESSION"
    TRANSPORT_SESSION_INFO = "elten transport session v1".b
    TRANSPORT_SESSION_NONCE_BYTES = 32
    TRANSPORT_SESSION_KEY_BYTES = 32
    TRANSPORT_SESSION_SECRET_BYTES = TRANSPORT_SESSION_KEY_BYTES * 3
    TRANSPORT_SESSION_CLIENT_TTL = 300

    class << self
      def init(force=false)
        @conn_mutex ||= Mutex.new
        @http_mutex ||= Monitor.new
        @ssl_mutex ||= Mutex.new
        @conn_mutex.synchronize do
          return true if !force && connected?
          close_http2(false)
          socket = connect_socket(HOST, PORT)
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.alpn_protocols = [HTTP2_ALPN]
          ctx.options |= OpenSSL::SSL::OP_IGNORE_UNEXPECTED_EOF
          ssl = OpenSSL::SSL::SSLSocket.new(socket, ctx)
          ssl.sync_close = true
          ssl.hostname = HOST if ssl.respond_to?(:hostname=)
          Timeout.timeout(CONNECT_TIMEOUT) { ssl.connect }
          @ssl = ssl
          @http = HTTP2::Client.new(settings_max_frame_size: 131072)
          @last_response = Time.now.to_i
          @http.on(:frame) { |bytes| write_http2_frame(bytes) }
          @http.on(:error) do |error|
            log_warning("HTTP/2 connection error: #{error}")
            close_http2(false)
          end
          start_reader
          true
        end
      rescue Exception => e
        log_error("HTTP/2 init error: #{format_exception(e)}")
        close_http2(false)
        false
      end

      def close
        close_http2(true)
      end

      def ejrequest(method, path, params, data=nil, encrypted: nil, headers: nil, transport_session_retry: true, &block)
        params = {} unless params.is_a?(Hash)
        headers = headers.is_a?(Hash) ? headers : {}
        Thread.new do
          Thread.current.report_on_exception = false
          attempts = 0
          begin
            attempts += 1
            init(true) if stale?
            raise "HTTP/2 unavailable" unless init
            encrypted_request = encrypted.nil? ? encrypted_transport? : encrypted == true
            json, decrypt_context = json_request_body(params, encrypted_request)
            body = "".b
            response_headers = {}
            @http_mutex.synchronize do
              stream = @http.new_stream
              head = {
                ":scheme" => "https",
                ":authority" => "api.elten.link:443",
                ":path" => path,
                ":method" => method.to_s.upcase,
                "user-agent" => user_agent,
                "accept-encoding" => "zstd, identity",
                "content-type" => "application/json",
                "content-length" => json.bytesize.to_s
              }
              headers.each do |key, value|
                next if key.to_s.empty? || value == nil
                head[key.to_s.downcase] = value.to_s
              end
              stream.on(:headers) do |h|
                response_headers = h.to_h
                data["headers"] = h if data.is_a?(Hash)
              end
              stream.on(:data) { |chunk| body << chunk.to_s.b }
              stream.on(:close) do
                begin
                  @last_response = Time.now.to_i
                  decoded = decode_body(body, response_headers)
                  decoded = decrypt_json_response(decoded, decrypt_context) if decrypt_context != nil
                  safe_call(block, decoded, data)
                rescue Exception => e
                  if transport_session_retry && decrypt_context.is_a?(Hash) && decrypt_context[:mode] == :session
                    log_warning("Encrypted session request failed, retrying with RSA: #{format_exception(e)}")
                    clear_transport_session
                    ejrequest(method, path, params, data, encrypted: true, headers: headers, transport_session_retry: false, &block)
                    next
                  end
                  log_error("JSON body error: #{format_exception(e)}")
                  safe_call(block, :error, data)
                end
              end
              stream.headers(head, end_stream: false)
              until json.empty?
                chunk = json.slice!(0...4096)
                stream.data(chunk, end_stream: json.empty?)
              end
            end
          rescue Exception => e
            log_error("JSON request error: #{format_exception(e)}")
            close_http2(false)
            retry if attempts < 2
            safe_call(block, :error, data)
          end
        end
      end

      def downloadfile(source, destination, data=nil, redirects=0, &block)
        Thread.new do
          Thread.current.report_on_exception = false
          begin
            result = downloadfile_sync(source, destination, data, redirects, &block)
            safe_call(block, result, data) if result.is_a?(Integer)
          rescue Exception => e
            log_error("downloadfile worker error: #{format_exception(e)}")
            safe_call(block, :error, data)
          end
        end
      end

      def readurl(url, method="get", body="", headers={}, data=nil, redirects=0, &block)
        Thread.new do
          Thread.current.report_on_exception = false
          begin
            response = readurl_sync(url, method, body, headers, data, redirects)
            safe_call(block, response[:body], data, response[:headers])
          rescue Exception => e
            log_error("readurl worker error: #{format_exception(e)}")
            safe_call(block, :error, data, {})
          end
        end
      end

      def server_verify
        self.encrypted_transport_enabled = false
        return false if server_rsa == nil
        token = SecureRandom.alphanumeric(32)
        response = nil
        client_time = Time.now.to_f
        ejrequest(
          "GET",
          "/api/v1/system/time",
          { "client_time" => client_time, "challenge" => token, "seed" => SecureRandom.alphanumeric(32) },
          nil,
          encrypted: true
        ) { |resp, _data| response = resp }
        started = Time.now.to_f
        while response == nil && Time.now.to_f - started < 15
          if defined?(loop_update)
            loop_update(false)
          else
            sleep 0.01
          end
        end
        return false unless response.is_a?(String)
        begin
          json = JSON.load(response)
        rescue JSON::ParserError, TypeError
          return false
        end
        response_hash = json.is_a?(Hash) ? json : {}
        data = response_hash["data"]
        verified = response_hash["success"] == true &&
                   data.is_a?(Hash) &&
                   (data["time"].to_f - Time.now.to_f).abs <= 86_400 &&
                   (data["client_time"].to_f - client_time).abs < 0.01 &&
                   data["challenge"].to_s == token
        self.encrypted_transport_enabled = verified
        verified
      rescue Exception => e
        log_warning("Server verification error: #{format_exception(e)}")
        self.encrypted_transport_enabled = false
        false
      end

      def encrypted_transport_enabled=(enabled)
        @encrypted_transport_enabled = enabled == true
        clear_transport_session unless @encrypted_transport_enabled
      end

      private

      def connected?
        @http != nil && @ssl != nil && !@ssl.closed? && @reader_thread != nil && @reader_thread.alive?
      end

      def stale?
        @last_response != nil && @last_response < Time.now.to_i - STALE_AFTER
      end

      def disable_http2?
        Configuration.disablehttp2.to_i == 1
      end

      def encrypted_transport?
        @encrypted_transport_enabled == true && server_rsa != nil
      end

      def user_agent
        version = if defined?(Elten) && Elten.respond_to?(:version)
          Elten.version
        else
          "ELTEN"
        end
        version.to_s
      end

      def connect_socket(host, port)
        Socket.tcp(host, port, connect_timeout: CONNECT_TIMEOUT)
      end

      def start_reader
        @reader_thread = Thread.new do
          Thread.current.report_on_exception = false
          loop do
            break unless connected?
            begin
              chunk = @ssl.read_nonblock(16_384)
              @http_mutex.synchronize { @http << chunk } if chunk != nil && chunk.bytesize > 0
            rescue IO::WaitReadable
              IO.select([@ssl], nil, nil, 0.5)
            rescue EOFError, IOError
              break
            rescue Exception => e
              log_error("HTTP reader error: #{format_exception(e)}")
              break
            end
          end
          close_http2(false)
        end
      end

      def close_http2(kill_reader)
        reader = @reader_thread
        @reader_thread = nil
        @http = nil
        ssl = @ssl
        @ssl = nil
        close_io(ssl)
        reader.kill if kill_reader && reader != nil && reader != Thread.current && reader.alive?
      rescue Exception
      end

      def write_http2_frame(bytes)
        @ssl_mutex ||= Mutex.new
        @ssl_mutex.synchronize do
          return if @ssl == nil || @ssl.closed?
          @ssl.write(bytes)
          @ssl.flush
        end
      rescue Exception => e
        log_error("HTTP frame write error: #{format_exception(e)}")
        close_http2(false)
      end

      def write_http1_request(io, method, path, host, headers, body)
        request = "#{method} #{path} HTTP/1.1\r\nHost: #{host}\r\n".b
        headers.each { |key, value| request << "#{key}: #{value}\r\n".b }
        request << "\r\n".b
        io.write(request)
        io.write(body) if body != nil && !body.empty?
        io.flush if io.respond_to?(:flush)
      end

      def read_http1_response(io)
        response = read_http1_head(io)
        response[:body] = read_http_body(io, response[:headers])
        response
      end

      def read_http1_head(io)
        header = "".b
        line = "".b
        until line == "\r\n"
          line = read_line(io)
          header << line
        end
        lines = header.split("\r\n")
        status_line = lines.shift.to_s
        raise "Invalid HTTP response: #{status_line}" unless status_line.start_with?("HTTP/")
        headers = {}
        lines.each do |entry|
          index = entry.index(":")
          next if index == nil
          headers[entry[0...index]] = entry[index + 1..-1].to_s.strip
        end
        { status: status_line.split(" ")[1].to_i, headers: headers }
      end

      def read_http_body(io, headers)
        transfer = header_value(headers, "Transfer-Encoding").to_s.downcase
        length = header_value(headers, "Content-Length")
        if transfer.include?("chunked")
          read_chunked_body(io)
        elsif length != nil
          read_exact_body(io, length.to_i)
        else
          read_until_eof(io)
        end
      end

      def read_chunked_body(io)
        body = "".b
        loop do
          line = read_line(io)
          size = line.split(";", 2)[0].to_i(16)
          break if size == 0
          body << read_exact_body(io, size)
          read_exact_body(io, 2)
        end
        body
      end

      def read_exact_body(io, size)
        body = "".b
        while body.bytesize < size
          chunk = read_partial(io, size - body.bytesize)
          break if chunk == nil || chunk.empty?
          body << chunk
        end
        body
      end

      def read_until_eof(io)
        body = "".b
        loop do
          chunk = read_partial(io, 16_384)
          break if chunk == nil || chunk.empty?
          body << chunk
        end
        body
      end

      def read_line(io)
        wait_readable(io)
        io.readline
      end

      def read_partial(io, size)
        wait_readable(io)
        io.readpartial([size, 16_384].min)
      rescue EOFError
        nil
      end

      def wait_readable(io)
        ready = IO.select([io], nil, nil, READ_TIMEOUT)
        raise Timeout::Error, "network read timeout" if ready == nil
      end

      def decode_body(body, headers)
        data = body.to_s.b
        encoding = header_value(headers, "content-encoding").to_s.downcase
        transfer = header_value(headers, "transfer-encoding").to_s.downcase
        if (encoding == "gzip" || transfer == "gzip") && data.getbyte(0) == 0x1f && data.getbyte(1) == 0x8b
          Zlib::GzipReader.new(StringIO.new(data)).read
        elsif transfer == "deflate" || encoding == "deflate"
          Zlib::Inflate.inflate(data)
        elsif encoding == "zstd"
          require "zstd-ruby" unless defined?(Zstd)
          Zstd.decompress(data)
        else
          data
        end
      end

      def json_request_body(params, encrypt)
        payload = JSON.generate(params).b
        return [payload, nil] unless encrypt

        if (session = current_transport_session)
          envelope = encrypted_session_request_envelope(payload, session)
          return [JSON.generate(envelope).b, { mode: :session, key: session[:server_to_client_key], session_id: session[:id] }]
        end

        envelope, key, session_open = encrypted_request_envelope(payload, open_session: transport_sessions_enabled?)
        [JSON.generate(envelope).b, { mode: :rsa, key: key, session_open: session_open }]
      end

      def encrypted_request_envelope(payload, open_session: false)
        key = OpenSSL::Random.random_bytes(32)
        iv = OpenSSL::Random.random_bytes(12)
        compressed = zstd_compress(payload)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = key
        cipher.iv = iv
        encrypted = cipher.update(compressed) + cipher.final
        envelope = {
          "elten_encryption" => "v1",
          "alg" => "RSA-OAEP+AES-256-GCM",
          "content_encoding" => "zstd",
          "key" => Base64.strict_encode64(server_rsa.public_encrypt(key, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)),
          "iv" => Base64.strict_encode64(iv),
          "tag" => Base64.strict_encode64(cipher.auth_tag),
          "payload" => Base64.strict_encode64(encrypted)
        }
        session_open = nil
        if open_session
          client_nonce_raw = OpenSSL::Random.random_bytes(TRANSPORT_SESSION_NONCE_BYTES)
          client_nonce = Base64.strict_encode64(client_nonce_raw)
          envelope["session"] = {
            "op" => "open",
            "client_nonce" => client_nonce
          }
          session_open = {
            request_key: key,
            client_nonce_raw: client_nonce_raw,
            client_nonce: client_nonce
          }
        end
        [envelope, key, session_open]
      end

      def encrypted_session_request_envelope(payload, session)
        iv = OpenSSL::Random.random_bytes(12)
        compressed = zstd_compress(payload)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = session[:client_to_server_key]
        cipher.iv = iv
        cipher.auth_data = transport_session_auth_data(session[:id], "request", "zstd")
        encrypted = cipher.update(compressed) + cipher.final
        {
          "elten_encryption" => "v1",
          "alg" => TRANSPORT_SESSION_ALGORITHM,
          "session_id" => session[:id],
          "content_encoding" => "zstd",
          "iv" => Base64.strict_encode64(iv),
          "tag" => Base64.strict_encode64(cipher.auth_tag),
          "payload" => Base64.strict_encode64(encrypted)
        }
      end

      def decrypt_json_response(body, context)
        envelope = JSON.load(body.to_s)
        unless envelope.is_a?(Hash) && envelope["elten_encryption"].to_s == "v1"
          raise "Invalid encrypted response envelope"
        end

        key = context.is_a?(Hash) ? context[:key] : context
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = key
        cipher.iv = Base64.strict_decode64(envelope.fetch("iv"))
        cipher.auth_tag = Base64.strict_decode64(envelope.fetch("tag"))
        if envelope["alg"].to_s == TRANSPORT_SESSION_ALGORITHM
          cipher.auth_data = transport_session_auth_data(envelope.fetch("session_id"), "response", envelope["content_encoding"].to_s)
        end
        plaintext = cipher.update(Base64.strict_decode64(envelope.fetch("payload"))) + cipher.final
        process_transport_session_response(envelope["session"], context[:session_open]) if context.is_a?(Hash) && context[:mode] == :rsa
        decode_encrypted_payload(plaintext, envelope["content_encoding"])
      rescue JSON::ParserError, KeyError, ArgumentError, OpenSSL::Cipher::CipherError => e
        raise "Invalid encrypted response: #{e.message}"
      end

      def process_transport_session_response(session_response, session_open)
        return false unless session_open.is_a?(Hash)
        return false unless session_response.is_a?(Hash)
        return false unless session_response["op"].to_s == "open"
        return false unless session_response["alg"].to_s == TRANSPORT_SESSION_ALGORITHM

        session_id = session_response["id"].to_s
        server_nonce = session_response["server_nonce"].to_s
        ttl = session_response["ttl"].to_i
        return false if session_id.empty? || server_nonce.empty? || ttl <= 0

        server_nonce_raw = Base64.strict_decode64(server_nonce)
        keys = derive_transport_session_keys(session_open[:request_key], session_open[:client_nonce_raw], server_nonce_raw)
        expected = transport_session_proof(
          keys[:proof_key],
          session_id: session_id,
          client_nonce: session_open[:client_nonce],
          server_nonce: server_nonce,
          ttl: ttl
        )
        return false unless secure_compare(expected, session_response["proof"].to_s)

        set_transport_session(
          id: session_id,
          client_to_server_key: keys[:client_to_server_key],
          server_to_client_key: keys[:server_to_client_key],
          expires_at: Time.now.to_f + [ttl, transport_session_client_ttl].min
        )
        true
      rescue Exception => e
        log_warning("Encrypted transport session open failed: #{format_exception(e)}")
        false
      end

      def derive_transport_session_keys(request_key, client_nonce_raw, server_nonce_raw)
        secret = hkdf(request_key.to_s.b, salt: client_nonce_raw.to_s.b + server_nonce_raw.to_s.b, info: TRANSPORT_SESSION_INFO, length: TRANSPORT_SESSION_SECRET_BYTES)
        {
          client_to_server_key: secret.byteslice(0, TRANSPORT_SESSION_KEY_BYTES),
          server_to_client_key: secret.byteslice(TRANSPORT_SESSION_KEY_BYTES, TRANSPORT_SESSION_KEY_BYTES),
          proof_key: secret.byteslice(TRANSPORT_SESSION_KEY_BYTES * 2, TRANSPORT_SESSION_KEY_BYTES)
        }
      end

      def hkdf(secret, salt:, info:, length:)
        salt = "\0".b * 32 if salt.to_s.empty?
        prk = OpenSSL::HMAC.digest("SHA256", salt, secret)
        output = +"".b
        previous = +"".b
        counter = 1
        while output.bytesize < length
          previous = OpenSSL::HMAC.digest("SHA256", prk, previous + info + counter.chr)
          output << previous
          counter += 1
        end
        output.byteslice(0, length)
      end

      def transport_session_proof(proof_key, session_id:, client_nonce:, server_nonce:, ttl:)
        payload = ["open", session_id, client_nonce, server_nonce, ttl.to_i, TRANSPORT_SESSION_ALGORITHM].join(":")
        Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", proof_key, payload))
      end

      def transport_session_auth_data(session_id, direction, content_encoding)
        ["v1", TRANSPORT_SESSION_ALGORITHM, session_id.to_s, direction.to_s, content_encoding.to_s].join("|").b
      end

      def secure_compare(a, b)
        a = a.to_s.b
        b = b.to_s.b
        return false unless a.bytesize == b.bytesize

        diff = 0
        a.bytes.zip(b.bytes) { |left, right| diff |= left ^ right }
        diff == 0
      end

      def transport_sessions_enabled?
        @transport_sessions_enabled != false
      end

      def transport_session_client_ttl
        value = ENV.fetch("ELTEN_TRANSPORT_SESSION_CLIENT_TTL", TRANSPORT_SESSION_CLIENT_TTL.to_s).to_i
        value.positive? ? value : TRANSPORT_SESSION_CLIENT_TTL
      end

      def transport_session_mutex
        @transport_session_mutex ||= Mutex.new
      end

      def current_transport_session
        transport_session_mutex.synchronize do
          session = @transport_session
          return nil unless session.is_a?(Hash)
          if session[:expires_at].to_f <= Time.now.to_f + 5
            @transport_session = nil
            return nil
          end

          session
        end
      end

      def set_transport_session(session)
        transport_session_mutex.synchronize { @transport_session = session }
      end

      def clear_transport_session
        transport_session_mutex.synchronize { @transport_session = nil }
      end

      def decode_encrypted_payload(payload, content_encoding)
        case content_encoding.to_s.downcase
        when "", "identity"
          payload
        when "zstd"
          require "zstd-ruby" unless defined?(Zstd)
          Zstd.decompress(payload.to_s.b)
        else
          raise "Unsupported encrypted response encoding: #{content_encoding}"
        end
      end

      def zstd_compress(payload)
        require "zstd-ruby" unless defined?(Zstd)
        Zstd.compress(payload.to_s.b, level: 3)
      end

      def normalize_headers(headers)
        result = {}
        return result unless headers.is_a?(Hash)
        headers.each { |key, value| result[key.to_s] = value.to_s }
        result
      end

      def header_value(headers, name)
        return nil unless headers.is_a?(Hash)
        name = name.to_s.downcase
        headers.each { |key, value| return value if key.to_s.downcase == name }
        nil
      end

      def downloadfile_sync(source, destination, data=nil, redirects=0, &block)
        raise "Too many redirects" if redirects > MAX_REDIRECTS
        uri = URI.parse(source)
        socket = connect_socket(uri.host, uri.port || (uri.scheme == "https" ? 443 : 80))
        io = socket
        if uri.scheme == "https"
          ctx = OpenSSL::SSL::SSLContext.new
          ssl = OpenSSL::SSL::SSLSocket.new(socket, ctx)
          ssl.sync_close = true
          ssl.hostname = uri.host if ssl.respond_to?(:hostname=)
          Timeout.timeout(CONNECT_TIMEOUT) { ssl.connect }
          io = ssl
        end
        write_http1_request(io, "GET", uri.request_uri, uri.host, {
          "User-Agent" => user_agent,
          "Connection" => "close",
          "Accept-Encoding" => "identity, chunked, *;q=0"
        }, nil)
        response = read_http1_head(io)
        location = header_value(response[:headers], "Location")
        return downloadfile_sync(uri.merge(location).to_s, destination, data, redirects + 1, &block) if location != nil
        status = response[:status].to_i
        return :error if status < 200 || status >= 300
        File.open(destination, "wb") do |file|
          stream_http_body(io, response[:headers], file, data, block)
        end
      ensure
        close_io(io) if defined?(io)
        close_io(socket) if defined?(socket)
      end

      def readurl_sync(url, method="get", body="", headers={}, data=nil, redirects=0)
        raise "Too many redirects" if redirects > MAX_REDIRECTS
        uri = URI.parse(url)
        body_data = body.nil? ? nil : body.to_s.b
        request_headers = {
          "User-Agent" => user_agent,
          "Connection" => "close",
          "Accept-Encoding" => "identity, chunked, *;q=0"
        }.merge(normalize_headers(headers))
        request_headers["Content-Length"] = body_data.bytesize.to_s if body_data != nil
        response = http1_request_uri(uri, method.to_s.upcase, body_data, request_headers, data)
        if response[:redirect] != nil
          return readurl_sync(uri.merge(response[:redirect]).to_s, method, body, headers, data, redirects + 1)
        end
        status = response[:status].to_i
        return { body: :error, headers: response[:headers] } if status < 200 || status >= 300
        { body: decode_body(response[:body], response[:headers]), headers: response[:headers] }
      end

      def http1_request_uri(uri, method, body, headers, data=nil)
        socket = connect_socket(uri.host, uri.port || (uri.scheme == "https" ? 443 : 80))
        io = socket
        if uri.scheme == "https"
          ctx = OpenSSL::SSL::SSLContext.new
          ssl = OpenSSL::SSL::SSLSocket.new(socket, ctx)
          ssl.sync_close = true
          ssl.hostname = uri.host if ssl.respond_to?(:hostname=)
          Timeout.timeout(CONNECT_TIMEOUT) { ssl.connect }
          io = ssl
        end
        write_http1_request(io, method, uri.request_uri, uri.host, headers, body)
        response = read_http1_response(io)
        location = header_value(response[:headers], "Location")
        response[:redirect] = location if location != nil
        response
      ensure
        close_io(io) if defined?(io)
        close_io(socket) if defined?(socket)
      end

      def stream_http_body(io, headers, file, data=nil, block=nil)
        transfer = header_value(headers, "Transfer-Encoding").to_s.downcase
        total = header_value(headers, "Content-Length").to_i
        downloaded = 0
        last_progress = Time.now.to_f
        if transfer.include?("chunked")
          loop do
            raise "cancelled" if cancelled?(data)
            size = read_line(io).split(";", 2)[0].to_i(16)
            break if size == 0
            chunk = read_exact_body(io, size)
            file.write(chunk)
            downloaded += chunk.bytesize
            read_exact_body(io, 2)
            if total > 0 && Time.now.to_f - last_progress > 5
              last_progress = Time.now.to_f
              safe_call(block, ERDownloadProgress.new(downloaded, total), data)
            end
          end
        elsif total > 0
          while downloaded < total
            raise "cancelled" if cancelled?(data)
            chunk = read_partial(io, [16_384, total - downloaded].min)
            break if chunk == nil || chunk.empty?
            file.write(chunk)
            downloaded += chunk.bytesize
            if Time.now.to_f - last_progress > 5
              last_progress = Time.now.to_f
              safe_call(block, ERDownloadProgress.new(downloaded, total), data)
            end
          end
        else
          loop do
            raise "cancelled" if cancelled?(data)
            chunk = read_partial(io, 16_384)
            break if chunk == nil || chunk.empty?
            file.write(chunk)
            downloaded += chunk.bytesize
          end
        end
        downloaded
      end

      def cancelled?(data)
        data.is_a?(Hash) && data[:cancelled] == true
      end

      def server_rsa
        return @server_rsa if defined?(@server_rsa)
        pem = EltenAPI::Resources.read("eltenpub.pem")
        @server_rsa = pem.to_s == "" ? nil : OpenSSL::PKey::RSA.new(pem)
      rescue Exception => e
        log_error("Server key load error: #{format_exception(e)}")
        @server_rsa = nil
      end

      def safe_call(block, *args)
        block.call(*args) if block != nil
      rescue Exception => e
        log_error("HTTP callback error: #{format_exception(e)}")
      end

      def close_io(io)
        io.close if io != nil && io.respond_to?(:close) && !io.closed?
      rescue Exception
      end

      def format_exception(error)
        "#{error.class}: #{error.message} #{Array(error.backtrace).join(" ")}"
      end

      def log_error(message)
          Log.error(message)
      rescue Exception
      end

      def log_warning(message)
          Log.warning(message)
      rescue Exception
      end
    end
  end

  module HTTP
    private

    def ejrequest(method, path, params, data=nil, headers: nil, &block)
      elten_link.e_json_request(method, path, params, data, headers: headers, &block)
    end

    def readurl(url, method="get", body="", headers={}, data=nil, &block)
      elten_link.e_read_url(url, method, body, headers, data, &block)
    end

    def downloadfile(source, destination, data=nil, &block)
      elten_link.e_download_file(source, destination, data, &block)
    end

    def srvverify
      elten_link.e_server_verify
    end
  end

  include HTTP
end
