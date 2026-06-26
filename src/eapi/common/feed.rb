# A part of Elten - EltenLink / Elten Network desktop client.
# Copyright (C) 2014-2026 Dawid Pieper
# Elten is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.
# Elten is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with Elten. If not, see <https://www.gnu.org/licenses/>.

module EltenAPI
  module Common
    private
class FeedMessage
attr_accessor :id, :user, :time, :message, :response, :responses, :liked, :likes
def initialize(id=0, user="", time=0, message="", response=0, responses=0, liked=false, likes=0)
@id, @user, @time, @message, @response, @responses, @liked, @likes = id, user, time, message, response, responses, liked, likes
@user=self.class.utf8(@user)
@message=self.class.utf8(@message)
@time=0 if !@time.is_a?(Integer) || @time<0
end
def self.utf8(value)
str=value.to_s.dup
str.force_encoding(Encoding::UTF_8) if str.encoding!=Encoding::UTF_8
str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
end
def to_h
return {'id'=>@id, 'message'=>@message, 'time'=>@time, 'user'=>@user, 'response'=>@response, 'responses'=>@responses, 'liked'=>@liked, 'likes'=>@likes}
end
end
  end
end
