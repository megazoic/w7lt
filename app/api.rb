require 'sinatra/base'
require 'json'
require_relative 'member'
require_relative 'auth_user'

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
      auth_user_result = @auth_user.authenticate(auth_user_credentials)
      if auth_user_result.has_key?('auth_user_id')
        response.set_cookie "auth_user_id", :value => auth_user_result['auth_user_id']
        response.set_cookie "auth_user_authority",
          :value => auth_user_result['authority']
        redirect '/'
      else
        #there is an error message in the auth_user_result if needed
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
    post '/create_auth_user' do
      auth_user_data = JSON.parse(request.body.read)
      #expecting Auth_user#create to return a hash with
      #the new auth_user id and authority on success or
      #error message
      create = @auth_user.create(auth_user_data)
      if create.has_key?('auth_user_id')
        JSON.generate(create)
      else
        status 422
        JSON.generate(create)
      end
    end
  end
end