require 'sinatra/base'
require 'json'
require_relative 'member'
require_relative 'auth_user'
require_relative 'groups_sync'
require_relative 'role'
require_relative 'action'
require_relative 'log'

module MemberTracker
  #using modular (cf classical) approach (see https://www.toptal.com/ruby/api-with-sinatra-and-sequel-ruby-tutorial)
  RecordResult = Struct.new(:success?, :member_id, :message)
  class API < Sinatra::Base
    def initialize()
      @member = Member.new
      @auth_user = Auth_user.new
      @role = Role.new
      @log = Log.new
      @action = Action.new
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
      authorize!("auth_u")
    end
    before '/mbrmgr/*' do
      authorize!("mbr_mgr")
    end
    def authorize!(role)
      if !session[:auth_user_roles].include?(role)
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
      @tmp_msg = session[:msg]
      session[:msg] = nil
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
        @err_msg = gio.groupsIOError["errorMsg"]
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
      #param keys can be... "dues_status", :dues_status,
      #  "mbr_full", :mbr_full, "mbr_student", :mbr_student, :mbr_family,
      #  ":mbr_honorary, "arrl", :arrl, "ares", :ares, "pdxnet", :pdxnet,
      #  "ve", :ve, "elmer", :elmer
      query_keys = [:paid_up, :mbr_full, :mbr_student, :mbr_family,
        :mbr_honorary, :mbr_none, :arrl, :ares, :pdxnet, :ve, :elmer, :sota]
      @qset = Hash.new
      @qset[:mbr_type] = []
      query_keys.each do |k|
        if ["", nil].include?(params[k])
          #skip
        else
          case k
          when :paid_up
            if params[k] == 0
              @qset[:paid_up] = 0
            else
              @qset[:paid_up] = 1
            end
          when  :arrl
            @qset[:arrl] = 1
          when  :ares
            @qset[:ares] = 1
          when  :mbr_full, :mbr_student, :mbr_family, :mbr_honorary, :mbr_none
            @qset[:mbr_type] << params[k]
          when  :pdxnet
            @qset[:net] = 1
          when  :elmer
            @qset[:elmer] = 1
          when  :ve
            @qset[:ve] = 1
          when  :sota
            @qset[:sota] = 1
          else
            puts "error"
          end
        end
      end
      puts "qset is..."
      puts @qset
      puts "params are..."
      puts params
      #@member = Member.where(@qset)
      #erb :m_list, :layout => :layout_w_logout
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
      @tmp_msg = session[:msg]
      session[:msg] = nil
      erb :login, :layout => :layout
    end
    post '/login' do
      # only if passes test in auth_user
      #puts "request body is #{request.body.read}"
      #puts "params pwd is #{params[:password]} and email is #{params[:email]}"
      #for RSpec test JSON.parse() request.body.read )
      auth_user_credentials = params
      auth_user_result = @auth_user.authenticate(auth_user_credentials)
      if auth_user_result['error'] == 'expired'
        #this auth_user has been removed and needs to be reset by admin
        session.clear
        session[:msg] = "The grace period for new user login has expired. Please contact admin."
        redirect "/login"
      elsif auth_user_result['error'] == 'new_user'
        #need to reset password
        session[:auth_user_id] = auth_user_result['auth_user_id']
        session[:auth_user_roles] = auth_user_result['auth_user_roles']
        mbr_id = Auth_user[auth_user_result['auth_user_id']].mbr_id
        redirect "/reset_password/#{mbr_id}"
      elsif auth_user_result.has_key?('auth_user_id')
        ######begin for rack testing ########
        #response.set_cookie "auth_user_id", :value => auth_user_result['auth_user_id']
        #response.set_cookie "auth_user_authority",
        #  :value => auth_user_result['authority']
        #########end for rack testing###########
        #########begin web configuration ############
        session[:auth_user_id] = auth_user_result['auth_user_id']
        session[:auth_user_roles] = auth_user_result['auth_user_roles']
        #########end web configuration ############
        redirect '/home'
      else
        #there is an error message in the auth_user_result if needed
        @tmp_msg = auth_user_result['error']
        session.clear
        redirect '/login'
      end
    end
    post '/logout' do
      session.clear
      session[:msg] = 'you have successfully logged out'
      redirect '/login'
    end
    get '/list/members' do
      @member = DB[:members].select(:id, :lname, :fname, :callsign, :paid_up).order(:lname, :fname).all
      @tmp_msg = session[:msg]
      session[:msg] = ''
      erb :m_list, :layout => :layout_w_logout
    end
    get '/show/member/:id' do
      @tmp_msg = session[:msg]
      session[:msg] = ''
      @member = Member[params[:id].to_i]
      erb :m_show, :layout => :layout_w_logout
    end
    get '/edit/member/:id' do
      @member = Member[params[:id].to_i]
      erb :m_edit, :layout => :layout_w_logout
    end
    get '/new/member' do
      @member = {:lname => ''}
      erb :m_edit, :layout => :layout_w_logout
    end
    post '/save/member' do
      #this route used to update an existing member or save a new member
      #this action is also logged
      mbr_id = params[:id]
      #save notes for log
      notes = params[:notes]
      params.reject!{|k,v| k == 'notes'}
      logPayment = params[:payment]
      params.reject!{|k,v| k == 'payment'}
      #the js form validator that uses regex inserts a captures key
      #in the returning params. need to pull this out too
      params.reject!{|k,v| k == "captures"}
      #this could be a new member or existing member
      if mbr_id == ''
        #new member
        params.reject!{|k,v| k == "id"}
        #the start date has been set in the erb file
        params["mbr_since"] = Date.strptime(params["mbr_since"], '%Y-%m')
        mbr_record = Member.new(params)
        begin
          DB.transaction do
            #save the new member
            mbr = mbr_record.save
            mbr_id = mbr.id
            #log the action
            augmented_notes = "**** New Member entry\n#{notes}"
            l = Log.new(mbr_id: mbr_id, a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes)
            l.save
            l.add_action(Action.where(type: 'mbr_edit').first.id)
          end
          session[:msg] = "The new member was successfully entered"
        rescue StandardError => e
          session[:msg] = "The new member could not be created\n#{e}"
        end
      else
        #existing member
        mbr_record = Member[params[:id].to_i]
        params.reject!{|k,v| k == "id"}
        params["mbr_since"] = Date.strptime(params["mbr_since"], '%Y-%m')
        begin
          DB.transaction do
            mbr_record.update(params)
            augmented_notes = "**** Existing Member update\n#{notes}"
            l = Log.new(mbr_id: mbr_record.id, a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes)
            l.save
            l.add_action(Action.where(type: 'mbr_edit').first.id)
          end
          session[:msg] = "The existing member was successfully updated"
        rescue StandardError => e
          session[:msg] = "The existing member could not be updated\n#{e}"
        end
      end
      if logPayment == "1"
        if session[:auth_user_roles].include?('auth_u')
          redirect "/admin/member/pay/#{mbr_id}"
        else
          session[:msg] << "\nyou need to be an admin to add a payment record"
        end
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
    ################### START MEMBER MGR ##################
    get '/reset_password/:id' do
      @mbr = Member.select(:id, :fname, :lname, :callsign).where(id: params[:id]).first
      erb :reset_password, :layout => :layout_w_logout
    end
    post '/reset_password' do
      @auth_user.update(params[:password], params[:mbr_id])
      session.clear
      session[:msg] = 'Password successfully reset, please login with your new password'
      redirect '/login'
    end
    ################### START ADMIN #######################
    get '/admin/view_log/:type' do
      if params[:type] == "auth_user"
        #need to build dataset
        log_dataset = Log.association_join(:actions)
        @this_aus_log_dataset = log_dataset.select(:mbr_id, :ts, :notes, :type).where(a_user_id: session[:auth_user_id]).all
        #get member info
        @this_aus_log_dataset.each do |log|
          log.values[:fname] = Member.select(:fname)[log.values[:mbr_id]][:fname]
          log.values[:lname] = Member.select(:lname)[log.values[:mbr_id]][:lname]
        end
      end
      erb :list_logs, :layout => :layout_w_logout
    end
    get '/admin/log/' do
      @mbr_list = DB[:members].select(:id, :fname, :lname, :callsign).order(:lname, :fname).all
      erb :log_action, :layout => :layout_w_logout
    end
    get '/admin/member/renew/:id' do
      @tmp_msg = session[:msg]
      session[:msg] = ''
      @mbr_pay = Member.select(:id, :fname, :lname, :callsign, :paid_up, :mbr_type)[params[:id].to_i]
      erb :m_renew, :layout => :layout_w_logout
    end
    post '/admin/member/renew' do
      #need to create a log for this transaction
      augmented_notes = params[:notes]
      l = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now)
      if params[:paid_yr] != params[:mbr_paid_up_old]
        augmented_notes << "\n**** Paid_up changed from #{params[:mbr_paid_up_old]} to #{params[:paid_yr]}"
      end
      if params[:mbr_type] != params[:mbr_type_old]
        augmented_notes << "\n**** Member type changed from #{params[:mbr_type_old]} to #{params[:mbr_type]}"
      end
      l.notes = augmented_notes
      m = Member[params[:mbr_id]]
      m.paid_up = params[:paid_yr]
      m.mbr_type = params[:mbr_type]
      begin
        DB.transaction do
          m.save
          l.save
          l.add_action(Action.where(type: 'mbr_renew').first.id)
        end
        session[:msg] = 'Payment was successfully recorded'
      rescue StandardError => e
        session[:msg] = "The data was not entered successfully\n#{e}"
      end
      redirect "/list/members"
    end
    get '/admin/list_auth_users' do
      @au_list = []
      #get a 2D array of [[mbr_id, auth_user_id]] for each auth_user
      #except for currently logged in admin
      au = Auth_user.exclude(id: session[:auth_user_id]).select(:id, :mbr_id).map(){|x| [x.mbr_id, x.id]}
      #fill this array with additional info
      au.each do |u|
        au_hash = Hash.new
        m = Member.select(:id, :fname, :lname, :callsign).where(id: u[0]).first
        au_hash["mbr_id"] = m.values[:id]
        au_hash["fname"] = m.values[:fname]
        au_hash["lname"] = m.values[:lname]
        au_hash["callsign"] = m.values[:callsign]
        au_hash["roles"] = []
        
        Auth_user[u[1]].roles.each do |r|
          au_hash["roles"] << r.description
        end
        @au_list << au_hash
      end
      @au_list
      @tmp_msg = session[:msg]
      session[:msg] = nil
      erb :list_auth_users, :layout => :layout_w_logout
    end
    get '/admin/update_au_roles/:id' do
      @mbr_to_update = Member.select(:id, :fname, :lname, :callsign, :email)[params[:id].to_i]
      #build 2D array of [role_id, role_description, au_has_role]
      @au_roles = Role.map(){|x| [x.id, x.description]}
      au = Auth_user.where(mbr_id: params[:id]).first
      Auth_user[au.values[:id]].roles.each do |r|
        count = 0
        @au_roles.each do |au_role|
          if au_role[0] == r.id
            #this au has this role
            @au_roles[count] << 1
          end
          count += 1
        end
      end
      count = 0
      #fill the cases where au has no role
      @au_roles.each do |au_role|
        if au_role.length < 3
          @au_roles[count] << 0
        end
        count += 1
      end
      erb :update_au_roles, :layout => :layout_w_logout
    end
    post '/admin/update_auth_user' do
      #need to remove all existing roles before updating with new
      #example params[:roles]
      #{"1"=>"1", "2"=>"1"} where both roles were selected 
      #that needs to change currently, role 1 is auth_u and 2 mbr_mgr
      au = Auth_user.where(mbr_id: params[:mbr_id]).first
      l = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now)
      #if there's something in notes put a newline after it and add it to the log
      l.notes = params[:notes] == '' ? '' : "#{params[:notes]}\n"
      #store this users roles in case the transaction fails, then can add them back
      mbrs_roles = au.roles
      begin
        DB.transaction do
          diff_roles = 'Old roles: '
          au.roles.each {|r| diff_roles << "#{r.name}, "}
          diff_roles.chomp!(", ")
          diff_roles << 'New roles: '
          au.remove_all_roles
          roles = []
          params[:roles].each do |k,v|
            au.add_role(Role[k.to_i])
            roles << Role[k.to_i].name
          end
          roles.each {|r| diff_roles << "#{r}, "}
          diff_roles.chomp!(", ")
          l.notes << diff_roles
          l.save
          l.add_action(Action.where(type: 'auth_u').first.id)
          session[:auth_user_roles] = roles
        end
      rescue StandardError => e
        #restore roles to this member
        mbrs_roles.each do |r|
          au.add_role(r)
        end
        session[:msg] = "The data was not entered successfully\n#{e}"
      end
      redirect '/admin/list_auth_users'
    end
    get '/admin/set_au_roles/:id' do
      @sel_au_mbr = Member.select(:id, :fname, :lname, :callsign, :email)[params[:id].to_i]
      @roles = Role.all
      erb :set_au_roles, :layout => :layout_w_logout
    end
    get '/admin/create_auth_user' do
      #first, remove current user from this list
      mbr_id = Auth_user[session[:auth_user_id]].mbr_id
      @sel_au_from_mbrs = Member.exclude(id: mbr_id).select(:id, :fname, :lname, :callsign, :email).all
      erb :create_au, :layout => :layout_w_logout
    end
    post '/admin/create_auth_user' do
      roles = params[:roles]
      email = Member.select(:email)[params[:mbr_id].to_i].email
      l = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now)
      l.notes = "New authorized user added\n" + params[:notes]
      begin
        DB.transaction do
          @auth_user.create(params[:mbr_id], roles, email)
          l.save
          l.add_action(Action.where(type: 'auth_u').first.id)
          session[:msg] = "Authorized user successfully created"
        end
      rescue StandardError => e
        session[:msg] = "there was an error:\n#{e}"
      end
      redirect "/admin/list_auth_users"
    end
    get '/admin/delete_auth_user/:id' do
      mbr_id = params[:id]
      au = Auth_user.where(mbr_id: mbr_id).first
      au.remove_all_roles
      au.delete
      redirect '/admin/list_auth_users'
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
    #################### END ADMIN #############################
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
        JSON.generate('error' => result.message)
      end
    end
    #################### end from test environment ##########
  end
end