require 'sinatra/base'
require 'json'
require_relative 'member'

module MemberTracker
  class API < Sinatra::Base
    def initialize(addrbook: Addrbook.new)
      @addrbook = addrbook
      super()
    end
    post '/members' do
      member = JSON.parse(request.body.read)
      result = @addrbook.record(member)
      if result.success?
        JSON.generate('member_id' => result.member_id)
      else
        status 422
        JSON.generate('error' => result.error_message)
      end
    end
  end
end