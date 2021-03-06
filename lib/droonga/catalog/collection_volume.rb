# Copyright (C) 2014 Droonga Project
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License version 2.1 as published by the Free Software Foundation.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require "digest/sha1"
require "zlib"

require "droonga/catalog/slice"

module Droonga
  module Catalog
    class CollectionVolume
      def initialize(dataset, data)
        @dataset = dataset
        @data = data
        compute_continuum if ratio_scaled_slicer?
      end

      def dimension
        @data["dimension"] || "_key"
      end

      def slicer
        @data["slicer"] || "hash"
      end

      def slices
        @slices ||= @data["slices"].collect do |raw_slice|
          Slice.new(@dataset, raw_slice)
        end
      end

      def select_slices(range=0..-1)
        slices.sort_by(&:label)[range]
      end

      def choose_slice(record)
        return slices.first unless ratio_scaled_slicer?

        key = stringify_key(record[dimension])
        hash = Zlib.crc32(key)
        min = 0
        max = @continuum.size - 1
        while (min < max)
          index = (min + max) / 2
          value, key = @continuum[index]
          return key if value == hash
          if value > hash
            max = index
          else
            min = index + 1
          end
        end
        @continuum[max][1]
      end

      def ratio_scaled_slicer?
        slicer == "hash"
      end

      def all_nodes
        @all_nodes ||= collect_all_nodes
      end

      private
      def compute_continuum
        total_weight = compute_total_weight
        continuum = []
        n_slices = slices.size
        slices.each do |slice|
          weight = slice.weight
          points = n_slices * 160 * weight / total_weight
          points.times do |point|
            hash = Digest::SHA1.hexdigest("#{@dataset.name}:#{point}")
            continuum << [hash[0..7].to_i(16), slice]
          end
        end
        @continuum = continuum.sort do |a, b|
          a[0] - b[0]
        end
      end

      def compute_total_weight
        slices.reduce(0) do |result, slice|
          result + slice.weight
        end
      end

      def stringify_key(key)
        case key
        when Integer
          key.to_s
        else
          key
        end
      end

      def collect_all_nodes
        nodes = []
        slices.each do |slice|
          nodes += slice.all_nodes
        end
        nodes.uniq.sort
      end
    end
  end
end
