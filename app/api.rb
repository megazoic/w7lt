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

    before do # need to remove this for testing!!!
      next if request.path_info == '/login'
      if session[:auth_user_id].nil?
        redirect '/login'
      end
    end
    
    get '/' , :provides => 'html' do
      puts 'in get and html'
    end
    get '/' , :provides => 'json' do
      puts 'in get and json'
    end
    get '/home' do
      erb :home
    end
    get '/query' do
      erb :query
    end
    post '/query' do
      case params[:type]
      when "paid_up"
        @member = Member.where(paid_up: 0)
      when "ve"
        @member = Member.where(ve: 1)
      when "arrl"
        @member = Member.where(arrl: 1)
      when "ares"
        @member = Member.where(ares: 1)
      else
        redirect '/query'
      end
      erb :m_list
    end
    get '/login' do
      erb :login
    end
    post '/login' do
      # only if passes test in auth_user
      #puts "request body is #{request.body.read}"
      #puts "params pwd is #{params[:password]} and email is #{params[:email]}"
      #for RSpec test JSON.parse() request.body.read )
      auth_user_credentials = params
      auth_user_result = @auth_user.authenticate(auth_user_credentials)
      if auth_user_result.has_key?('auth_user_id')
      ######begin for rack testing ########
        #response.set_cookie "auth_user_id", :value => auth_user_result['auth_user_id']
        #response.set_cookie "auth_user_authority",
        #  :value => auth_user_result['authority']
        #########end for rack testing###########
        #########begin web configuration ############
        session[:auth_user_id] = auth_user_result['auth_user_id']
        session[:auth_user_authority] = auth_user_result['auth_user_authority']
        #########end web configuration ############
        redirect '/home'
      else
        #there is an error message in the auth_user_result if needed
        redirect '/login'
      end
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
    post '/logout' do
      session.clear
      redirect '/login'
    end
    get '/list/members' do
      @member = Member.all
      erb :m_list
    end
    get '/show/member/:id' do
      @member = Member[params[:id].to_i]
      erb :m_show
    end
    get '/edit/member/:id' do
      @member = Member[params[:id].to_i]
      erb :m_edit
    end
    get '/new/member' do
      @record = {:fname => '', :lname => '', :email => '', :apt => '',
        :city => '', :street => '', :zip => '', :state => '', :callsign => '',
        :phm => '', :phm_pub => '', :phh => '', :phh_pub => '',
        :phw => '', :phw_pub => '', :license_class => '', :mbr_type => '',
        :paid_up => '', :arrl => '', :arrl_expire => '', :ares => '',
        :net => '', :ve => '', :elmer => ''}
      erb :m_edit
    end
    post '/save/member' do
      mbr_id = params[:id]
      if mbr_id == ''
        params.reject!{|k,v| k == "id"}
        mbr_record = Member.new(params)
        mbr = mbr_record.save
        mbr_id = mbr.id
      else
        mbr_record = Member[params[:id].to_i]
        params.reject!{|k,v| k == "id"}
        mbr_record.update(params)
      end
      redirect "/show/member/#{mbr_id}"
    end
    post '/destroy/member/:id' do
      mbr_record = Member[params[:id].to_i]
      mbr_result = mbr_record.destroy
      if mbr_result.exists?
        redirect "/show/member/#{mbr_result.id}"
      else
        redirect "/list/members"
      end
    end
    #################### start from test environment ##########
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
    #################### end from test environment ##########
    helpers do
      def authenticate
        #need to test session here for auth_user_id
        #and auth_user_authority
      end
    end
  end
end