require 'sinatra/base'
require 'json'
require_relative 'member'

module MemberTracker
  class API < Sinatra::Base
    def initialize(member: Member.new)
      @member = member
      super()
    end
    
    post '/members' do
      member = JSON.parse(request.body.read)
      result = @member.record(member)
      if result.success?
        JSON.generate('member_id' => result.member_id)
      else
        status 422
        JSON.generate('error' => result.error_message)
      end
    end
    get '/members/:name' do
      JSON.generate(@member.members_with_lastname(params[:name]))
    end
  end
end