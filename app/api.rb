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
    
    enable :sessions

    #before do # need to remove this for testing!!!
      #tried this regex but ruby didn't like the ^ /^(?!.*\/login)/
      #next if request.path_info == '/login'
      #if session[:auth_user_id].nil?
        #redirect '/login'
        #end
    #end
    
    get '/' , :provides => 'html' do
      puts 'in get and html'
    end
    get '/' , :provides => 'json' do
      puts 'in get and json'
    end
    get '/login' do
      erb :login
    end
    post '/login' do
      # only if passes test in auth_user
      #puts "request body is #{request.body.read}"
      #puts "params pwd is #{params[:password]} and email is #{params[:email]}"
      auth_user_credentials = JSON.parse(request.body.read)
      auth_user_result = @auth_user.authenticate(auth_user_credentials)
      if auth_user_result.has_key?('auth_user_id')
      ######begin for rack testing ########
        response.set_cookie "auth_user_id", :value => auth_user_result['auth_user_id']
        response.set_cookie "auth_user_authority",
          :value => auth_user_result['authority']
        #########end for rack testing###########
        #########begin web configuration ############
        #session[:auth_user_id] = auth_user_result['auth_user_id']
        #session[:auth_user_authority] = auth_user_result['auth_user_authority']
        #########end web configuration ############
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
    get '/members/:name', :provides => 'json' do
      JSON.generate(@member.members_with_lastname(params[:name]))
    end
    get '/members/:name', :provides => 'html' do
      output = ''
      @member.members_with_lastname(params[:name]).each  {|mbr|
        output << "<p>#{mbr}</p>\n"
      }
      output
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
    post '/log_out' do
      session.clear
      redirect '/login'
    end
    helpers do
      def authenticate
        #need to test session here for auth_user_id
        #and auth_user_authority
      end
    end
  end
end