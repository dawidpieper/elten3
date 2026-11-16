# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

require "etc"

module Audio
  module SpatialMath
    module_function

    def scalar(value, name, min: nil, max: nil)
      number = Float(value)
      raise ArgumentError, "#{name} must be a finite 32-bit value" if !number.finite? || number.abs > 3.4028234663852886e38
      raise ArgumentError, "#{name} is out of range" if (min != nil && number < min) || (max != nil && number > max)
      number
    end

    def vector(value, name, size: 3, min: nil, max: nil)
      raise ArgumentError, "#{name} must contain #{size} values" if !value.is_a?(Array) || value.size != size
      value.map { |entry| scalar(entry, name, min: min, max: max) }.freeze
    end

    def unit(value)
      length = Math.sqrt(value.sum { |entry| entry * entry })
      raise ArgumentError, "Direction must not be zero" if length < 1.0e-8
      value.map { |entry| entry / length }.freeze
    end

    def cross(a, b)
      [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    end

    def dot(a, b)
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    end

    def direction(source, listener)
      position = listener[:position]
      offset = [source[0] - position[0], source[1] - position[1], source[2] - position[2]]
      return [0.0, 0.0, -1.0] if offset.all? { |entry| entry.abs < 1.0e-8 }
      unit([dot(offset, listener[:right]), dot(offset, listener[:up]), -dot(offset, listener[:forward])])
    end
  end

  class HRTF
    attr_reader :data, :volume, :normalisation

    def initialize(file: nil, data: nil, volume: 1.0, normalisation: :none)
      raise ArgumentError, "Specify either an HRTF file or data" if file != nil && data != nil
      data = File.binread(file) if file != nil
      raise ArgumentError, "SOFA data must be a non-empty string" if data != nil && (!data.is_a?(String) || data.empty?)
      @data = data&.b&.freeze
      @volume = SpatialMath.scalar(volume, "HRTF volume", min: 0)
      @normalisation = normalisation.to_sym
      raise ArgumentError, "HRTF normalisation must be :none or :rms" if ![:none, :rms].include?(@normalisation)
      freeze
    end
  end

  class AcousticMaterial
    attr_reader :absorption, :scattering, :transmission

    def initialize(absorption: [0.1, 0.1, 0.1], scattering: 0.1, transmission: [0.0, 0.0, 0.0])
      @absorption = SpatialMath.vector(absorption, "Absorption", min: 0, max: 1)
      @scattering = SpatialMath.scalar(scattering, "Scattering", min: 0, max: 1)
      @transmission = SpatialMath.vector(transmission, "Transmission", min: 0, max: 1)
      freeze
    end

    def to_a
      [*@absorption, @scattering, *@transmission]
    end
  end

  class SpatialPose
    def initialize(position: [0, 0, 0], forward: [0, 0, -1], up: [0, 1, 0], &changed)
      @mutex = Mutex.new
      @changed = changed
      @state = {}
      update(position: position, forward: forward, up: up)
    end

    def update(position: nil, forward: nil, up: nil)
      @mutex.synchronize do
        position = position == nil ? @state[:position] : SpatialMath.vector(position, "Position")
        forward = forward == nil ? @state[:forward] : SpatialMath.unit(SpatialMath.vector(forward, "Forward direction"))
        up = up == nil ? @state[:up] : SpatialMath.unit(SpatialMath.vector(up, "Up direction"))
        right = SpatialMath.unit(SpatialMath.cross(forward, up))
        up = SpatialMath.unit(SpatialMath.cross(right, forward))
        @state = {position: position, forward: forward, right: right, up: up}.freeze
      end
      @changed.call if @changed != nil
      self
    end

    def snapshot
      @mutex.synchronize { @state }
    end

    [:position, :forward, :up].each do |key|
      define_method(key) { snapshot[key] }
      define_method("#{key}=") { |value| update(**{key => value}); value }
    end
  end

  class SpatialGeometry
    IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1].freeze

    attr_reader :vertices, :triangles, :material_indices

    def initialize(scene, vertices:, triangles:, materials:, material_indices: nil, transform: IDENTITY)
      @scene = scene
      @mutex = Mutex.new
      @closed = false
      raise ArgumentError, "A mesh needs vertices and triangles" if vertices.empty? || triangles.empty?
      @vertices = vertices.map { |point| SpatialMath.vector(point, "Vertex") }.freeze
      @triangles = triangles.map do |triangle|
        raise ArgumentError, "A triangle needs three vertex indices" if !triangle.is_a?(Array) || triangle.size != 3
        indices = triangle.map do |index|
          raise ArgumentError, "Invalid vertex index" if !index.is_a?(Integer) || index < 0 || index >= @vertices.size
          index
        end
        a, b, c = indices.map { |index| @vertices[index] }
        area = SpatialMath.cross(b.zip(a).map { |x, y| x - y }, c.zip(a).map { |x, y| x - y })
        raise ArgumentError, "Degenerate triangle" if area.sum { |value| value * value } < 1.0e-16
        indices.freeze
      end.freeze
      @materials = validate_materials(materials)
      @material_indices = (material_indices || Array.new(@triangles.size, 0)).dup.freeze
      if @material_indices.size != @triangles.size || @material_indices.any? { |index| !index.is_a?(Integer) || index < 0 || index >= @materials.size }
        raise ArgumentError, "Invalid triangle material indices"
      end
      @transform = validate_transform(transform)
    end

    def snapshot
      @mutex.synchronize { {materials: @materials, transform: @transform, closed: @closed}.freeze }
    end

    def transform
      snapshot[:transform]
    end

    def transform=(value)
      value = validate_transform(value)
      @mutex.synchronize { raise IOError, "Geometry is closed" if @closed; @transform = value }
      @scene.wake
      value
    end

    def position
      transform.values_at(3, 7, 11)
    end

    def position=(value)
      position = SpatialMath.vector(value, "Position")
      matrix = transform.dup
      [3, 7, 11].zip(position).each { |index, coordinate| matrix[index] = coordinate }
      self.transform = matrix
      value
    end

    def materials
      snapshot[:materials]
    end

    def materials=(value)
      value = validate_materials(value)
      raise ArgumentError, "Missing triangle materials" if @material_indices.any? { |index| index >= value.size }
      @mutex.synchronize { raise IOError, "Geometry is closed" if @closed; @materials = value }
      @scene.wake
      value
    end

    def close
      @mutex.synchronize { @closed = true }
      @scene.wake
    end

    def closed?
      snapshot[:closed]
    end

    private

    def validate_materials(materials)
      unless materials.is_a?(Array) && !materials.empty? && materials.all? { |value| value.is_a?(AcousticMaterial) }
        raise ArgumentError, "Expected acoustic materials"
      end
      materials.dup.freeze
    end

    def validate_transform(value)
      matrix = SpatialMath.vector(value, "Transform", size: 16)
      raise ArgumentError, "Transform must be affine" if matrix.last(4) != [0, 0, 0, 1]
      determinant = SpatialMath.dot(matrix.values_at(0, 4, 8), SpatialMath.cross(matrix.values_at(1, 5, 9), matrix.values_at(2, 6, 10)))
      raise ArgumentError, "Transform must be invertible" if determinant.abs < 1.0e-8
      matrix
    end
  end
end
