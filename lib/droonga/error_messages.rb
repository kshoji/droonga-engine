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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

require "droonga/error"
require "droonga/status_code"

module Droonga
  module ErrorMessages
    class InternalServerError < ErrorMessage
      STATUS_CODE = StatusCode::INTERNAL_SERVER_ERROR
    end

    class BadRequest < ErrorMessage
      STATUS_CODE = StatusCode::BAD_REQUEST
    end

    class NotFound < ErrorMessage
      STATUS_CODE = StatusCode::NOT_FOUND
    end
  end
end
