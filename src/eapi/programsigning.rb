# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "openssl"
require_relative "resources" if !defined?(EltenAPI::Resources)

module Programs
  module ProgramSigning
    SIGNATURE_MAGIC = "EltenPKSignature".b.freeze
    SIGNATURE_VERSION = 1
    ALGORITHM_RSA_SHA256 = 1
    TRUST_ROOT_RESOURCE = "program-signing-root.pem"

    class SignatureError < StandardError
    end

    class MissingSignatureError < SignatureError
    end

    class VerificationUnavailableError < MissingSignatureError
    end

    class << self
      def default_certificate_path
        File.join(project_root, "private", "certificates", "programs", "developers", "dawid_pieper.crt.pem")
      end

      def default_private_key_path
        File.join(project_root, "private", "certificates", "programs", "private", "dawid_pieper.key.pem")
      end

      def signing_available?(certificate_path = default_certificate_path, private_key_path = default_private_key_path)
        File.file?(certificate_path) && File.file?(private_key_path)
      end

      def developer_mode?
        probe = Object.new
        return !!probe.send(:developer_mode?) if probe.respond_to?(:developer_mode?, true)
        return !!$developer_mode
        false
      rescue Exception
        false
      end

      def sign_code_file(code_file, certificate_path: default_certificate_path, private_key_path: default_private_key_path)
        code_file = code_file.to_s.b
        certificate = OpenSSL::X509::Certificate.new(File.binread(certificate_path))
        private_key = OpenSSL::PKey.read(File.binread(private_key_path))
        certificate_der = certificate.to_der
        signature = private_key.sign(OpenSSL::Digest::SHA256.new, code_file)
        SIGNATURE_MAGIC +
          [SIGNATURE_VERSION, ALGORITHM_RSA_SHA256, certificate_der.bytesize, signature.bytesize].pack("CCL<L<") +
          certificate_der +
          signature +
          code_file
      end

      def decode_package(data, source: "eltenapp")
        data = data.to_s.b
        if data.start_with?(SIGNATURE_MAGIC)
          decode_signed_package(data, source)
        else
          { :signed => false, :code_file => data }
        end
      end

      def verify_decoded!(decoded, source: "eltenapp")
        raise MissingSignatureError, "missing package signature" if !decoded[:signed]
        raise VerificationUnavailableError, "program signing trust is unavailable" if trusted_roots.empty?
        certificate = decoded[:certificate]
        root = trusted_root_for(certificate)
        raise SignatureError, "untrusted signing certificate" if root == nil
        validate_certificate_time!(root, "root certificate")
        validate_certificate_time!(certificate, "signing certificate")
        raise SignatureError, "signing certificate is not valid for code signing" if !code_signing_certificate?(certificate)

        ok = certificate.public_key.verify(OpenSSL::Digest::SHA256.new, decoded[:signature], decoded[:code_file])
        raise SignatureError, "invalid signature" if !ok
        {
          :subject => certificate.subject.to_s,
          :fingerprint => fingerprint(certificate),
          :root => fingerprint(root)
        }
      rescue ArgumentError, OpenSSL::OpenSSLError => e
        raise SignatureError, "#{e.class}: #{e.message}"
      end

      private

      def project_root
        File.expand_path("../..", __dir__)
      end

      def decode_signed_package(data, source)
        pos = SIGNATURE_MAGIC.bytesize
        header = data.byteslice(pos, 10)
        raise SignatureError, "truncated package signature in #{source}" if header == nil || header.bytesize != 10
        version, algorithm, certificate_size, signature_size = header.unpack("CCL<L<")
        raise SignatureError, "unsupported package signature version #{version}" if version != SIGNATURE_VERSION
        raise SignatureError, "unsupported package signature algorithm #{algorithm}" if algorithm != ALGORITHM_RSA_SHA256
        pos += 10
        certificate_der = data.byteslice(pos, certificate_size)
        raise SignatureError, "truncated signing certificate in #{source}" if certificate_der == nil || certificate_der.bytesize != certificate_size
        pos += certificate_size
        signature = data.byteslice(pos, signature_size)
        raise SignatureError, "truncated package signature bytes in #{source}" if signature == nil || signature.bytesize != signature_size
        pos += signature_size
        code_file = data.byteslice(pos, data.bytesize - pos).to_s.b
        raise SignatureError, "missing signed code file in #{source}" if code_file == ""
        {
          :signed => true,
          :code_file => code_file,
          :certificate => OpenSSL::X509::Certificate.new(certificate_der),
          :signature => signature
        }
      end

      def trusted_root_for(certificate)
        trusted_roots.find do |root|
          root.subject == certificate.issuer &&
            root.verify(root.public_key) &&
            certificate.verify(root.public_key)
        end
      end

      def trusted_roots
        @trusted_roots ||= trusted_root_pems.filter_map { |pem| OpenSSL::X509::Certificate.new(pem) rescue nil }
      end

      def trusted_root_pems
        pem = EltenAPI::Resources.read(TRUST_ROOT_RESOURCE).to_s
        pem.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m)
      end

      def validate_certificate_time!(certificate, label)
        now = Time.now.utc
        raise SignatureError, "#{label} is not valid yet" if now < certificate.not_before
        raise SignatureError, "#{label} has expired" if now > certificate.not_after
      end

      def code_signing_certificate?(certificate)
        certificate.extensions.any? do |extension|
          extension.oid == "extendedKeyUsage" && extension.value.to_s =~ /Code Signing|codeSigning/i
        end
      end

      def fingerprint(certificate)
        OpenSSL::Digest::SHA256.hexdigest(certificate.to_der)
      end
    end
  end
end
