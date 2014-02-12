# Copyright (C) 2013-2014 Droonga Project
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
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require "json"

require "droonga/catalog/version1"

module Droonga
  class CatalogLoader
    def initialize(path)
      @path = path
    end

    def load
      data = File.open(@path) do |file|
        JSON.parse(file.read)
      end
      Catalog::Version1.new(data, File.dirname(@path))
    rescue JSON::ParserError => error
      raise InvalidCatalog.new("Syntax error in #{@path}", error)
    end
  end
end
