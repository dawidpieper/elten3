#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "openssl"
require "securerandom"

ROOT = File.expand_path("..", __dir__)
RESOURCES = File.join(ROOT, "resources")
CERT_ROOT = File.join(ROOT, "private", "certificates", "programs")
TRUSTED_ROOT_CERT = File.join(RESOURCES, "program-signing-root.pem")
DEVELOPERS = File.join(CERT_ROOT, "developers")
PRIVATE = File.join(CERT_ROOT, "private")

def usage
  warn "Usage:"
  warn "  ruby tools/program-certificates.rb init --name \"Dawid Pieper\""
  warn "  ruby tools/program-certificates.rb developer --name \"Name\" --root-key PATH --root-cert PATH"
  exit 1
end

def arg_value(args, name, default = nil)
  index = args.index(name)
  return default if index == nil
  value = args[index + 1]
  usage if value == nil || value.start_with?("--")
  value
end

def slug(name)
  name.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
end

def write_file(path, data, mode = nil)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, data)
  File.chmod(mode, path) if mode != nil
end

def serial
  SecureRandom.random_number(2**128)
end

def extension_factory(subject, issuer)
  factory = OpenSSL::X509::ExtensionFactory.new
  factory.subject_certificate = subject
  factory.issuer_certificate = issuer
  factory
end

def build_root(name)
  key = OpenSSL::PKey::RSA.new(4096)
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = serial
  cert.subject = OpenSSL::X509::Name.parse("/C=PL/O=Elten/OU=Program Signing/CN=#{name}")
  cert.issuer = cert.subject
  cert.public_key = key.public_key
  cert.not_before = Time.now.utc - 60
  cert.not_after = Time.now.utc + 20 * 365 * 24 * 60 * 60
  factory = extension_factory(cert, cert)
  cert.add_extension(factory.create_extension("basicConstraints", "CA:TRUE,pathlen:1", true))
  cert.add_extension(factory.create_extension("keyUsage", "keyCertSign,cRLSign", true))
  cert.add_extension(factory.create_extension("subjectKeyIdentifier", "hash", false))
  cert.add_extension(factory.create_extension("authorityKeyIdentifier", "keyid:always", false))
  cert.sign(key, OpenSSL::Digest::SHA256.new)
  [cert, key]
end

def build_developer(name, root_cert, root_key)
  key = OpenSSL::PKey::RSA.new(3072)
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = serial
  cert.subject = OpenSSL::X509::Name.parse("/C=PL/O=Elten/OU=Program Authors/CN=#{name}")
  cert.issuer = root_cert.subject
  cert.public_key = key.public_key
  cert.not_before = Time.now.utc - 60
  cert.not_after = Time.now.utc + 5 * 365 * 24 * 60 * 60
  factory = extension_factory(cert, root_cert)
  cert.add_extension(factory.create_extension("basicConstraints", "CA:FALSE", true))
  cert.add_extension(factory.create_extension("keyUsage", "digitalSignature", true))
  cert.add_extension(factory.create_extension("extendedKeyUsage", "codeSigning", false))
  cert.add_extension(factory.create_extension("subjectKeyIdentifier", "hash", false))
  cert.add_extension(factory.create_extension("authorityKeyIdentifier", "keyid:always", false))
  cert.sign(root_key, OpenSSL::Digest::SHA256.new)
  [cert, key]
end

command = ARGV.shift
usage if command == nil

case command
when "init"
  name = arg_value(ARGV, "--name", "Dawid Pieper")
  root_name = arg_value(ARGV, "--root-name", "Elten Program Signing Root")
  root_cert_path = TRUSTED_ROOT_CERT
  root_key_path = File.join(PRIVATE, "elten_program_root.key.pem")
  if File.file?(root_cert_path) && File.file?(root_key_path)
    root_cert = OpenSSL::X509::Certificate.new(File.binread(root_cert_path))
    root_key = OpenSSL::PKey.read(File.binread(root_key_path))
  else
    root_cert, root_key = build_root(root_name)
    write_file(root_cert_path, root_cert.to_pem)
    write_file(root_key_path, root_key.to_pem, 0o600)
  end
  dev_cert, dev_key = build_developer(name, root_cert, root_key)

  write_file(File.join(DEVELOPERS, "#{slug(name)}.crt.pem"), dev_cert.to_pem)
  write_file(File.join(PRIVATE, "#{slug(name)}.key.pem"), dev_key.to_pem, 0o600)

  puts "Root certificate: #{root_cert_path}"
  puts "Root SHA256: #{OpenSSL::Digest::SHA256.hexdigest(root_cert.to_der)}"
  puts "Developer certificate: #{File.join(DEVELOPERS, "#{slug(name)}.crt.pem")}"
  puts "Developer key: #{File.join(PRIVATE, "#{slug(name)}.key.pem")}"
when "developer"
  name = arg_value(ARGV, "--name")
  root_cert_path = arg_value(ARGV, "--root-cert", TRUSTED_ROOT_CERT)
  root_key_path = arg_value(ARGV, "--root-key", File.join(PRIVATE, "elten_program_root.key.pem"))
  usage if name.to_s == ""
  root_cert = OpenSSL::X509::Certificate.new(File.binread(root_cert_path))
  root_key = OpenSSL::PKey.read(File.binread(root_key_path))
  dev_cert, dev_key = build_developer(name, root_cert, root_key)
  write_file(File.join(DEVELOPERS, "#{slug(name)}.crt.pem"), dev_cert.to_pem)
  write_file(File.join(PRIVATE, "#{slug(name)}.key.pem"), dev_key.to_pem, 0o600)
  puts "Developer certificate: #{File.join(DEVELOPERS, "#{slug(name)}.crt.pem")}"
  puts "Developer key: #{File.join(PRIVATE, "#{slug(name)}.key.pem")}"
else
  usage
end
