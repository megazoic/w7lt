require 'sinatra/base'
require 'json'
require_relative 'member'
require_relative 'auth_user'
require_relative 'groups_sync'
require_relative 'role'

module MemberTracker
  #using modular (cf classical) approach (see https://www.toptal.com/ruby/api-with-sinatra-and-sequel-ruby-tutorial)
  class API < Sinatra::Base
    def initialize()
      @member = Member.new
      @auth_user = Auth_user.new
      super()
    end
    
    enable :sessions

    before do # need to comment this for RSpec
      next if request.path_info == '/login'
      if session[:auth_user_id].nil?
        redirect '/login'
      end
    end
    before '/admin/*' do
      authorize!
    end
    
    def authorize!
      if !session[:auth_user_roles].include?('auth_u')
        session[:flash_msg] = "Sorry, you don't have permission"
        redirect '/home'
      end
    end
    get '/' , :provides => 'html' do
      puts 'in get and html'
    end
    get '/' , :provides => 'json' do
      puts 'in get and json'
    end
    get '/dump/:table' , :provides => 'html' do
      if params[:table] = 'mbr'
        @m = Member.all
        erb :dump
      else
        redirect '/home'
      end
    end
    get '/home' do
      @member_lnames = Member.select(:id, :lname).order(:lname).all
      @err_msg = session[:flash_msg]
      session[:flash_msg] = nil
      erb :home, :layout => :layout_w_logout
    end
    get '/groupsio' do
      #get members who have no Groups.io account record
      @mbrs_wo_gio = Member.select(:id, :fname, :lname).where(Sequel.lit('gio_id IS NULL')).all
      gio = GroupsioData.new
      if gio.setToken == 0
        #success, retrieve data
        if gio.getMbrData == 0
          #success, find unmatched emails
          gio.compareEmails
        end
      end
      if gio.groupsIOError["error"].to_i == 0
        @unmatched = gio.unmatched
        erb :groupsio, :layout => :layout_w_logout
      else
        #failed send message
        @gioerror = gio.groupsIOError["errorMsg"]
        erb :errorMsg, :layout => :layout_w_logout
      end
    end
    post '/groupsio' do
      #if params has any numbered keys these are parc_mbr ids that need to
      #be updated with the value, first remove the captures key
      #Params returned with the form have name=mbr_id value=email from the
      #first table and name=gio_id, value=mbr_id from the second table
      params.reject!{|k,v| k == "captures"}
      params.reject!{|k,v| v == "none"}
      if params.length > 0
        mbrs = []
        params.each{|k,v|
          if /\d+/.match(k)
            #there is an id need to update a record in Members based on which
            #id we're dealing with here Groups.io or this database
            if k.to_i > 10000
              #this is a groups.io id use value to get member from this db
              mbr = Member[v.to_i]
              mbr.gio_id = k.to_i
              if mbr.save
                mbrs << v.to_i
              end
            else #this is a parc-mbr database id use key to get member
              mbr = Member[k.to_i]
              mbr.email = v
              if mbr.save
                mbrs << k.to_i
              end
            end
          end
        }
        #return successful updates
        @mbrs = Member.select(:id, :fname, :lname, :callsign, :email).where(id: mbrs).all
        erb :list_saved, :layout => :layout_w_logout
      else #nothing was sent
        erb :home, :layout => :layout_w_logout
      end
    end
    get '/query' do
      erb :query, :layout => :layout_w_logout
    end
    post '/query' do
      query_keys = Hash["dues_status", :dues_status,
        "mbr_full", :mbr_full, "mbr_student", :mbr_student, "mbr_family", :mbr_family,
        "mbr_honorary", :mbr_honorary, "arrl", :arrl, "ares", :ares, "pdxnet", :pdxnet,
        "ve", :ve, "elmer", :elmer]
        @qset = Hash.new
        query_keys.each do |k,v|
          if ["", nil].include?(params[v])
            #skip
          else
            case k
            when "dues_status"
              @qset[:paid_up] = params[v]
            when "arrl"
              @qset[:arrl] = 1
            when "ares"
              @qset[:ares] = 1
            when "membership"
              @qset[:mbr_type] = params[v]
            when "pdxnet"
              @qset[:net] = 1
            when "elmer"
              @qset[:elmer] = 1
            when "ve"
              @qset[:ve] = 1
            else
              puts "error"
            end
          end
        end
        
        @member = Member.where(@qset)
        erb :m_list, :layout => :layout_w_logout
    end
    post '/query2' do
      case params[:query_type]
      when "unpaid"
        @type_of_query="unpaid"
        @member = Member.where(paid_up: 0).all
      when "paid"
        @type_of_query="paid"
        @member = Member.where(paid_up: 1).all
      when "ve"
        @type_of_query="ve"
        @member = Member.where(ve: 1).all
      when "arrl"
        @type_of_query="arrl"
        @member = Member.where(arrl: 1).all
      when "ares"
        @type_of_query="ares"
        @member = Member.where(ares: 1).all
      when "full"
        @type_of_query="mbr_full"
        @member = Member.where(mbr_type: "full").all
      when "student"
        @type_of_query="mbr_student"
        @member = Member.where(mbr_type: "student").all
      when "family"
        @type_of_query="mbr_family"
        @member = Member.where(mbr_type: "family").all
      when "honorary"
        @type_of_query="mbr_honorary"
        @member = Member.where(mbr_type: "honorary").all
      else
        redirect '/query'
      end
      erb :m_list, :layout => :layout_w_logout
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
        session[:auth_user_roles] = auth_user_result['auth_user_roles']
        
        puts "auth roles is #{session[:auth_user_roles]}"
        #########end web configuration ############
        redirect '/home'
      else
        #there is an error message in the auth_user_result if needed
        redirect '/login'
      end
    end
    get '/admin/create_auth_user' do
      erb :create_au, :layout => :layout_w_logout
    end
    post '/admin/create_auth_user' do
      before do
        #check authorization
        if session[:auth_user_role] != 'admin'
          #block this user with message
          redirect '/'
        end
      end
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
      erb :m_list, :layout => :layout_w_logout
    end
    get '/show/member/:id' do
      @member = Member[params[:id].to_i]
      erb :m_show, :layout => :layout_w_logout
    end
    get '/edit/member/:id' do
      @member = Member[params[:id].to_i]
      erb :m_edit, :layout => :layout_w_logout
    end
    get '/new/member' do
      @record = {:fname => '', :lname => '', :email => '', :apt => '',
        :city => '', :street => '', :zip => '', :state => '', :callsign => '',
        :phm => '', :phm_pub => '', :phh => '', :phh_pub => '',
        :phw => '', :phw_pub => '', :license_class => '', :mbr_type => '',
        :paid_up => '', :arrl => '', :arrl_expire => '', :ares => '',
        :net => '', :ve => '', :elmer => ''}
      erb :m_edit, :layout => :layout_w_logout
    end
    post '/save/member' do
      mbr_id = params[:id]
      #the js form validator that uses regex inserts a captures key
      #in the returning params. need to pull this out too
      params.reject!{|k,v| k == "captures"}
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
    get '/test_role' do
      before do
        #check authorization
        if session[:auth_user_roles].include?('admin')
          #allow
        else
          #block this user with message
          redirect '/'
        end
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
  end
end