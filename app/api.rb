require 'sinatra/base'
require 'json'
require_relative 'member'

module MemberTracker
  class API < Sinatra::Base
    def initialize(member: Member.new, auth_user: Auth_user.new)
      @member = member
      @auth_user = auth_user
      super()
    end
    get '/' do
      puts 'in get'
    end
    get '/login' do
    end
    post '/login' do
      # only if passes test in auth_user
      auth_user_credentials = JSON.parse(request.body.read)
      if @auth_user.authenticate(auth_user_credentials)
        response.set_cookie "auth_user_id", :value => 24
        redirect '/'
      else
        redirect '/login'
      end
    end
    post '/members' do
      member_data = JSON.parse(request.body.read)
      result = @member.record(member_data)
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