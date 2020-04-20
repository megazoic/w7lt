require 'sinatra/base'
require 'json'
require 'bcrypt'
require_relative 'member'
require_relative 'unit'
require_relative 'unitType'
require_relative 'auth_user'
require_relative 'groupsIoData'
require_relative 'role'
require_relative 'action'
require_relative 'log'
require_relative 'payment'
require_relative 'paymentType'
require_relative 'paymentMethod'
require_relative 'auditLog'

module MemberTracker
  #using modular (cf classical) approach (see https://www.toptal.com/ruby/api-with-sinatra-and-sequel-ruby-tutorial)
  RecordResult = Struct.new(:success?, :member_id, :message)
  Paid_up = Struct.new(:active, :condition)
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
        #elsif session[:auth_user_id] == 'reset'
        #redirect "/reset_password/#{XXX}"
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
        session[:msg] = "Sorry, you don't have permission"
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
      @mbrs_wo_gio = Member.select(:id, :fname, :lname).where(Sequel.lit('gio_id IS NULL')).order(:lname).all
      count_gio_noparc = 0
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
              mbr.email = v.upcase
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
      #param keys can be... "paid_up_q", :paid_up_q,
      #  "mbr_full", :mbr_full, "mbr_student", :mbr_student, :mbr_family,
      #  ":mbr_honorary, "arrl", :arrl, "ares", :ares, "pdxnet", :pdxnet,
      #  "ve", :ve, "elmer", :elmer
      query_keys = [:paid_up_q, :mbr_full, :mbr_student, :mbr_family,
        :mbr_honorary, :mbr_none, :arrl, :ares, :pdxnet, :ve, :elmer, :sota]
      qset = Hash.new
      qset[:mbr_type] = []
      pu = Paid_up.new(false, false)
      query_keys.each do |k|
        if ["", nil].include?(params[k])
          #skip
        else
          case k
          when :paid_up_q
            #values can be '0', '1', or '' empty string
            if params[k] == '0'
              #looking for members who are not paid up through current year
              pu.active = true
              pu.condition = false
            elsif params[k] == '1'
              #looking for members who are paid up through current year
              pu.active = true
              pu.condition = true
            else
              #keep default pu values (false,false)
            end
          when  :arrl
            qset[:arrl] = 1
          when  :ares
            qset[:ares] = 1
          when  :mbr_full, :mbr_student, :mbr_family, :mbr_honorary, :mbr_none
            qset[:mbr_type] << params[k]
          when  :pdxnet
            qset[:net] = 1
          when  :elmer
            qset[:elmer] = 1
          when  :ve
            qset[:ve] = 1
          when  :sota
            qset[:sota] = 1
          else
            puts "error"
          end
        end
      end
      if qset[:mbr_type].empty?
        qset.delete(:mbr_type)
      end
      if pu.active == true
        #there is a request for paid up status
        if pu.condition == true
          puts "in looking for paid up members"
          #asking for members who are paid up through the current year
          @member = Member.where(qset){paid_up >= Time.now.strftime("%Y").to_i}
        else
          #asking for members who are NOT paid up through the current year
          @member = Member.where(qset){paid_up < Time.now.strftime("%Y").to_i}
        end
      else
        #asking for all recorded members
        @member = Member.where(qset)
      end
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
      @tmp_msg = session[:msg]
      session[:msg] = nil
      erb :login, :layout => :layout
    end
    post '/login' do
      # only if passes test in auth_user
      #puts "request body is #{request.body.read}"
      #puts "params pwd is #{params[:password]} and email is #{params[:email]}"
      #for RSpec test JSON.parse() request.body.read )
      auth_user_result = @auth_user.authenticate(params)
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
      elsif auth_user_result['error']== 'inactive'
        session.clear
        session[:msg] = "Please contact admin, your account has been deactivated."
        redirect "/login"
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
      session[:msg] = nil
      erb :m_list, :layout => :layout_w_logout
    end
    get '/show/member/:id' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
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
      #get action id
      action_id = nil
      Action.select(:id, :type).map(){|x|
        if x.type == "mbr_edit"
          action_id = x.id
        end
      }
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
        #set the character case to upper for name and email
        params["fname"] = params["fname"].upcase
        params["lname"] = params["lname"].upcase
        params["email"] = params["email"].upcase
        mbr_record = Member.new(params)
        begin
          DB.transaction do
            #save the new member
            mbr = mbr_record.save
            mbr_id = mbr.id
            #log the action
            augmented_notes = "**** New Member entry\n#{notes}"
            l = Log.new(mbr_id: mbr_id, a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes, action_id: action_id)
            l.save
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
        #set the character case to upper for name and email
        params["fname"] = params["fname"].upcase
        params["lname"] = params["lname"].upcase
        params["email"] = params["email"].upcase
        begin
          DB.transaction do
            mbr_record.update(params)
            augmented_notes = "**** Existing Member update\n#{notes}"
            l = Log.new(mbr_id: mbr_record.id, a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes, action_id: action_id)
            l.save
          end
          session[:msg] = "The existing member was successfully updated"
        rescue StandardError => e
          session[:msg] = "The existing member could not be updated\n#{e}"
        end
      end
      if logPayment == "1"
        if session[:auth_user_roles].include?('auth_u')
          redirect "/admin/payment/new/#{mbr_id}"
        else
          session[:msg] << "\nyou need to be an admin to add a payment record"
        end
      end
      redirect "/show/member/#{mbr_id}"
    end
    get '/list/units/:unit_type' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      units = nil
      if params[:unit_type] == 'all'
        units = Unit.reverse_order(:active).all
      else
        units = Unit.where(:unit_type_id => UnitType.where(:type => params[:unit_type]).first.id).reverse_order(:active).all
      end
      #iterate through array of Unit objects pulling out meta data and member names
      #put this in a unit container @u_c
      @u_c = [params[:unit_type]]
      units.each do |u|
        elmer_mbr = "N/A"
        elmer_id = nil
        unit_array = []
        unit_meta = {unit_creator: Auth_user[u.a_user_id].member.callsign, unit_created_at: u.ts.strftime("%m-%d-%y"),
          unit_active: u.active, unit_type: u.unit_type.type}
        #check if listing elmer or family units; need to add info specific to these
        if @u_c[0] == 'elmer' || unit_meta[:unit_type] == 'elmer'
          #find elmer
          u.members.each do |mbr|
            if mbr.elmer == 1
              elmer_mbr = "#{mbr.fname} #{mbr.lname}: #{mbr.callsign}"
              elmer_id = mbr.id
            end
          end
          unit_meta[:unit_notes] = "Elmer: #{elmer_mbr}"
        elsif @u_c[0] == 'family' || unit_meta[:unit_type] == 'family'
          unit_meta[:unit_notes] = "Paid_up: #{Member[u.members.first.id].paid_up}"
        else
          (!u.name.nil? && u.name != '') ? unit_meta[:unit_notes] = "#{u.name}" : unit_meta[:unit_notes] = "N/A"
        end
        unit_array << unit_meta
        unit_array << u.id
        #load the members of this unit (excluding elmer if unit is elmer)
        mbrs_list = ""
        u.members.each do |mbr|
          #if elmer, don't want in unit_array bc already in unit_meta
          unless elmer_id == mbr.id
            mbrs_list << "#{mbr.fname} #{mbr.lname}: #{mbr.callsign}, "
          end
        end
        #add list of member to the array
        unit_array << mbrs_list[0...-2]
        @u_c << unit_array
      end
      erb :u_list, :layout => :layout_w_logout
    end
    get '/new/unit' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @unit_type = DB[:unit_types].select(:id, :type).all
      @member = DB[:members].select(:id, :lname, :fname, :callsign, :elmer).order(:lname, :fname).all
      @member.each do |mbr|
        if mbr[:elmer] == 1
          mbr[:elmer] = 'Yes'
        else
          mbr[:elmer] = 'No'
        end
      end
      erb :u_new, :layout => :layout_w_logout
    end
    post '/new/unit' do
      #get the string unit_type
      unit_type_id = params[:unit_type_id].to_i
      unit_type_name = UnitType[unit_type_id].type
      params.reject!{|k,v| k == 'unit_type_id'}
      #get name field
      unit_name = params[:unit_name]
      params.reject!{|k,v| k == 'unit_name'}
      #get name field
      unit_notes = params[:unit_notes]
      params.reject!{|k,v| k == 'unit_notes'}
      #get member ids for this unit
      mbrs = []
      params.each do |k,v|
        mbrs << /id:(\d+)/.match(k)[1]
      end
      #need to create a log for this transaction
      #first get action id
      actions = {}
      Action.select(:id, :type).map(){|x| actions[x.type]= x.id}
      action_id = actions["unit"]
      l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: action_id)
      mbr_names = ""
      mbrs.each do |mbr_id|
        mbr_names << "#{Member[mbr_id].fname} #{Member[mbr_id].lname}, "
      end
      l.notes = "creating new unit of type #{unit_type_name} with members #{mbr_names[0...-2]}"
      if unit_notes != ''
        l.notes << "\nfrom the authUser #{unit_notes}"
      end
      #build unit
      u = Unit.new(:unit_type_id => unit_type_id, :active => 1, :name => unit_name, :a_user_id => session[:auth_user_id], :ts => Time.now)
      begin
        DB.transaction do
          u.save
          mbrs.each do |mbr|
            m = Member[mbr.to_i]
            #family type also is related to member_type ('full', 'family', 'student', 'honorary')
            #since this isn't a payment however, don't update paid_up status
            if unit_type_name == 'family'
              m.mbr_type = unit_type_name
            end
            m.add_unit(u)
            m.save
          end
          l.unit_id = u.id
          l.save
        end
        session[:msg] = "The unit was successfully created"
        redirect "/list/units/#{unit_type_name}"
      rescue StandardError => e
        session[:msg] = "The unit could not be created\n#{e}"
        redirect '/home'
      end
    end
    get '/edit/unit/:id' do
      response['Cache-Control'] = "public, max-age=0, must-revalidate"
      @unit = Unit[params[:id].to_i]
      #get a list of member ids that belong to this unit
      #also, if the unit is an elmer, find that elmer member
      @unit_creator_callsign = Auth_user[@unit.a_user_id].member.callsign
      unit_mbrs = []
      @unit_elmer = nil
      @unit.members.each do |mbr|
        if @unit.unit_type.type == "elmer"
          if mbr.elmer == 1
            @unit_elmer = mbr.callsign
          end
        end
        unit_mbrs << mbr.id
      end
      @member = DB[:members].select(:id, :lname, :fname, :callsign, :elmer).order(:lname, :fname).all
      @member.each do |mbr|
        if mbr[:elmer] == 1
          mbr[:elmer] = 'Yes'
        else
          mbr[:elmer] = 'No'
        end
        #add key for member's inclusion in this unit
        if unit_mbrs.include?(mbr[:id])
          mbr[:included] = '1'
        else
          mbr[:included] = '0'
        end
      end
      erb :u_edit, :layout => :layout_w_logout
    end
    post '/update/unit' do
      #expecting keys "unit_id", "name", some mbrs like {"id:nnn" => 1, ...} where nnn is the member id
      #if :active is missing is then 0
      #save notes for log
      notes = params["notes"]
      params.reject!{|k,v| k == "notes"}
      #get action id
      action_id = nil
      Action.select(:id, :type).map(){|x|
        if x.type == "unit"
          action_id = x.id
        end
      }
      #load unit and check values
      unit = Unit[params["unit_id"].to_i]
      augmented_notes = "updating unit_id:#{params["unit_id"]}"
      augmented_notes << "\nfrom AuthUser #{notes}\n" if notes != ''
      mbrs_new = []
      params.each do |k,v|
        mbr = /id:(\d+)/.match(k)
        if !mbr.nil?
          mbrs_new << mbr[1].to_i
        end
      end
      #build a list of old members
      mbrs_old = []
      unit.members.each do |mbr|
        mbrs_old << mbr.id
        #add elmer from this unit to mbrs_new since not found in params
        if unit.unit_type.type == 'elmer' && mbr.elmer == 1
          mbrs_new << mbr.id
        end
      end
      #compare the two sets of members
      mbrs_old_out = mbrs_old - mbrs_new #these have been removed
      #need to test for unit type family cuz cant remove family members through this route yet
      if unit.unit_type.type == 'family' && !mbrs_old_out.empty?
        session[:msg] = "The existing unit could not be updated. Removing family members can only be done via a membership renewal"
        redirect "/list/units/all"
      end
      mbrs_new_in = mbrs_new - mbrs_old #these have been added
      #look at changes in active status and name of unit
      name_new = params["name"]
      if name_new != unit.name
        unit.name = name_new
        augmented_notes << "\nname changed from #{unit.name} to #{name_new}"
      end
      active_new = params.has_key?("active") ? 1 : 0
      if active_new != unit.active
        augmented_notes << "\nactive status changed from #{unit.active.to_s} to #{active_new.to_s}"
        unit.active = active_new
      end
      #build new unit and change members in the unit
      mbrs_old_out.each do |mbr|
        unit.remove_member(mbr)
        augmented_notes << "\nUnit mbr association[-mbr_id:#{m.id}], #{m.fname} #{m.lname} has been removed"
      end
      mbrs_new_in.each do |mbr|
        unit.add_member(mbr)
        m = Member[mbr]
        augmented_notes << "\nUnit mbr association[+mbr_id:#{mbr}], #{m.fname} #{m.lname} has been added"
        #need to set mbr_type to family if this is a family unit
        if unit.unit_type.type == 'family'
          m.mbr_type = 'family'
          m.save
        end
      end
      l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes, action_id: action_id)
      begin
        DB.transaction do
          unit.save
          l.save
          session[:msg] = "The existing unit was successfully updated"
          #need to build this route
          #redirect "/show/unit/#{unit.id}"
          redirect "/list/units/#{unit.unit_type.type}"
        end
      rescue StandardError => e
        session[:msg] = "The existing unit could not be updated\n#{e}"
        redirect "/list/units/all"
      end
    end
    
    ################### START MEMBER MGR ##################
    get '/reset_password/:id' do
      #use @is_pwdreset to load password script from script.js by setting <body id="PwdReset"> in layout
      @is_pwdreset = true;
      @mbr = Member.select(:id, :fname, :lname, :callsign).where(id: params[:id]).first
      erb :reset_password, :layout => :layout
    end
    post '/reset_password' do
      @auth_user.update(params[:password], params[:mbr_id])
      session.clear
      session[:msg] = 'Password successfully reset, please login with your new password'
      redirect '/login'
    end
    ################### START ADMIN #######################
    get '/admin/view_log/:type' do
      case params[:type]
      when "auth_user" #view only current logged in users logs
        @type = "auth_user"
        @logs = []
        au = Auth_user[session[:auth_user_id]]
        #are there any logs for this auth_user?
        if au.logs.length == 0
          session[:msg] = "there are no logs to view"
          redirect '/home'
        end
        au.logs.each do |l|
          h = Hash.new
          if !l.member.nil?
            h[:mbr_name] = "#{l.member.fname} #{l.member.lname}"
          end
          ts = l.ts.strftime("%m-%d-%Y")
          h[:time] = "#{ts}"
          h[:notes] = l.notes
          h[:action] = l.action.type
          @logs << h
        end
      when "all"
        @type = "all"
        aus = Auth_user.all
        @logs = []
        no_logs = true
        aus.each do |au|
          if au.logs.length > 0
            no_logs = false
            au.logs.each do |l|
              h = Hash.new
              if !l.member.nil?
                h[:mbr_name] = "#{l.member.fname} #{l.member.lname}"
              end
              ts = l.ts.strftime("%m-%d-%Y")
              h[:time] = "#{ts}"
              h[:notes] = l.notes
              h[:action] = l.action.type
              h[:au_name] = "#{l.auth_user.member.fname} #{l.auth_user.member.lname}"
              @logs << h
            end
          end
        end
        if no_logs == true
          session[:msg] = "there are no logs to view"
          redirect '/home'
        end
      else
        #shouldn't be here
      end
      erb :list_logs, :layout => :layout_w_logout
    end
    get '/admin/log/' do
      @mbr_list = DB[:members].select(:id, :fname, :lname, :callsign).order(:lname, :fname).all
      erb :log_action, :layout => :layout_w_logout
    end
    get '/admin/payment/new/:id' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @mbr_pay = Member.select(:id, :fname, :lname, :callsign, :paid_up, :mbr_type)[params[:id].to_i]
      #if mbr_type is 'family' then count all family members that will be updated
      @mbr_family = []
      if @mbr_pay.mbr_type == 'family'
        #find the id for the family unit
        fu_id = nil
        @mbr_pay.units.each do |mu|
          if mu.unit_type_id == UnitType.where(:type => 'family').first.id
            fu_id = mu.id
          end
        end
        #load members in this family
        Unit[fu_id].members.each do |f_member|
          #load names other than the current member
          if f_member.id != params[:id].to_i
            @mbr_family << "#{f_member.fname} #{f_member.lname}"
          end
        end
      end
      @payType = PaymentType.all
      @payMethod = PaymentMethod.all
      erb :m_pay, :layout => :layout_w_logout
    end
    post '/admin/payment/new' do
      #this is used to renew a membership but also to record other payment types
      #{mbr_id, mbr_type_old=>(eg.)full, mbr_paid_up_old, payment_type=>2, mbr_type, paid_up, payment_method=>1, payment_amt, notes=>}
      #need to create a log for this transaction, first get action id
      actions = {}
      Action.select(:id, :type).map(){|x| actions[x.type]= x.id}
      augmented_notes = params[:notes]
      log_pay = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now)
      log_unit = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now, action_id: actions["unit"])
      #load AuditLog in case needed
      al_paid_up = AuditLog.new()
      al_mbr_type = AuditLog.new()
      al_active = AuditLog.new()
      #only record an audit log if needed
      al_save = false
      #check to see if 'dues' is selected as :payment_type to store family ids
      mbr_family = []
      mbr_family_unit_id = nil
      if PaymentType[params[:payment_type]].type == 'Dues'
        #going to put this info in the log
        log_pay.action_id = actions["mbr_renew"]
        m = Member[params[:mbr_id]]
        if params[:mbr_type] == 'family'
          #get other family members; find the id for the family unit
          m.units.each do |mu|
            if mu.unit_type_id == UnitType.where(:type => 'family').first.id
              mbr_family_unit_id = mu.id
            end
          end
          #validate this member is already a member of a family, need to set that up first
          if mbr_family_unit_id.nil?
            session[:msg] = "Payment FAILED; please set up the family unit first"
            redirect "/new/unit"
          end
          #associate logs with this unit
          log_pay.unit_id = mbr_family_unit_id
          log_unit.unit_id = mbr_family_unit_id
          #load members in this family, first test for existance of this unit
          Unit[mbr_family_unit_id].members.each do |f_member|
            #load ids for all besides the current member
            mbr_family << f_member.id if f_member.id != params[:id].to_i
          end
        elsif params[:mbr_type_old] == 'family'
          #member was previously in a family unit but no longer is paying as one
          #breaking from unit by either leaving an active unit or deactivating unit
          #find unit
          m.units.each do |mu|
            if mu.unit_type_id == UnitType.where(:type => 'family').first.id
              mbr_family_unit_id = mu.id
            end
          end
          u = Unit[mbr_family_unit_id]
          #add unit id to the mbr_renew and unit log so can trace this member back to this unit in rollback
          log_pay.unit_id = u.id
          log_unit.unit_id = u.id
          if m.paid_up < Time.now.year
            #unit hasn't paid (yet), find unit
            #change unit active to 0 (not a functional unit)
            old_active = u.active
            u.active = 0
            u.save
            #remove this member from the unit
            u.remove_member(m)
            #log this change to the unit
            log_unit.notes = "Unit mbr association[-mbr_id:#{m.id}], #{m.fname} #{m.lname} has been removed\n"
            #add to AuditLog to enable rollback
            if old_active != 0
              #will add pay id after pay is saved in DB.transaction
              al_active.set("a_user_id" => session[:auth_user_id], "column" => "active",
                "changed_date" => Time.now, "old_value" => old_active, "new_value" => 0)
              al_save = true
            end
            #log this change to the unit
            log_unit.notes << "unit id: #{u.id} active status has gone from #{old_active} to 0"
          else#family already paid up but maybe family member splitting off?
            #check to see if there are only 2 members of this unit
            if augmented_notes != ''
              augmented_notes << "\n"
            end
            if u.members.length < 3
              #unlikely event and cause this to fail
              augmented_notes << "\n****member currently paid up is trying to pay again*****\nRecord NOT updated"
              session[:msg] = "The data was not entered successfully\nthis member in fam unit that already paid"
              log_pay.notes = augmented_notes
              log_pay.save
              redirect "/list/members"
            else
              #remove this member from unit it is assumed they are too old to use family membership
              augmented_notes << "\n****member currently paid up is trying to pay again*****\nwill remove from fam unit"
              Unit[mbr_family_unit_id].remove_member(m)
              #log this change to the unit
              log_unit.notes = "Unit mbr association[-mbr_id:#{m.id}], #{m.fname} #{m.lname} has been removed"
            end
          end
        end #of if mbr_type is family elsif mbr_type_old is famly
        #if family then the other family members paid_up status happens in the DB.transaction
        m.paid_up = params[:paid_up]
        m.mbr_type = params[:mbr_type]
        #if params[:mbr_paid_up_old] != params[:paid_up]
        if augmented_notes != ''
          augmented_notes << "\n"
        end
        if params[:paid_up] != params[:mbr_paid_up_old]
          augmented_notes << "**** Paid_up changed from #{params[:mbr_paid_up_old]} to #{params[:paid_up]}"
        end
        if params[:mbr_type] != params[:mbr_type_old]
          augmented_notes << "**** Member type changed from #{params[:mbr_type_old]} to #{params[:mbr_type]}"
        end
      else #end if Dues
        #payment must be a donation, set up for log
        log_pay.action_id = actions["donation"]
      end
      pay = Payment.new(:mbr_id => params[:mbr_id], :a_user_id => session[:auth_user_id], :payment_type_id => params[:payment_type],
        :payment_method_id => params[:payment_method], :payment_amount => params[:payment_amt], :ts => Time.now)
      begin
        DB.transaction do
          if PaymentType[params[:payment_type]].type == 'Dues'
            m.save
            if params[:mbr_type] == 'family'
              #update other family members
              fam_names = ""
              #if there is temporarily only one family member of this unit, this will be skipped
              mbr_family.each do |mbr_id|
                fm = Member[mbr_id]
                fm.paid_up = params[:paid_up]
                fm.mbr_type = 'family'
                fm.save
                fam_names << "\nmbr_id#:#{fm.id}, #{fm.fname}, #{fm.lname}"
              end
              if mbr_family.length == 0
                log_unit.notes = "there is only one member of this family, sad"
              else
                #add names to log
                log_unit.notes = "#{fam_names.sub("\n",'')} were also updated"
              end
              #make sure family unit is active
              fu = Unit[mbr_family_unit_id]
              if fu.active == 0
                #need to set to 1 so keep auditLog record
                al_active.set("a_user_id" => session[:auth_user_id], "column" => "active",
                  "changed_date" => Time.now, "old_value" => 0, "new_value" => 1)
                al_save = true
              end
              fu.active = 1
              fu.save
            end
            #log these to the auditlog table
            if (params[:mbr_paid_up_old] != params[:paid_up])
              al_paid_up.set("a_user_id" => session[:auth_user_id], "column" => "paid_up",
              "changed_date" => Time.now, "old_value" => params[:mbr_paid_up_old], "new_value" => params[:paid_up])
              al_save = true
            end
            if (params[:mbr_type_old] != params[:mbr_type])
              al_mbr_type.set("a_user_id" => session[:auth_user_id], "column" => "mbr_type",
              "changed_date" => Time.now, "old_value" => params[:mbr_type_old], "new_value" => params[:mbr_type])
              al_save = true
            end
            #only expecting to record unit logs if paying dues and is/was a member of a family unit
            #***** this may change however ***********
            if params[:mbr_type] == 'family' || params[:mbr_type_old] == 'family'
              log_unit.save
            end
          end
          #may need to associate the two logs (payment and unit)
          if !log_unit.id.nil?
            augmented_notes << "\nPayment Log Association[unit_log_id:#{log_unit.id}]"
          end
          log_pay.notes = augmented_notes
          log_pay.save
          #associate the log entry with this payment
          pay[:log_id] = log_pay.values[:id]
          pay.save
          #associate this payment record with any changes to member paid_up and mbr_type fields
          if al_save == true
            #if instance for specific (paid_up, mbr_type) auditLog been written to yet, then link payment record
            if !al_paid_up.a_user_id.nil?
              al_paid_up.pay_id = pay.id
              al_paid_up.mbr_id = params[:mbr_id]
              if params[:mbr_type] == 'family'
                al_paid_up.unit_id = mbr_family_unit_id
              end
              al_paid_up.save
            end
            if !al_mbr_type.a_user_id.nil?
              al_mbr_type.pay_id = pay.id
              al_mbr_type.mbr_id = params[:mbr_id]
              if params[:mbr_type] == 'family'
                al_mbr_type.unit_id = mbr_family_unit_id
              end
              al_mbr_type.save
            end
            if !al_active.a_user_id.nil?
              al_active.pay_id = pay.id
              al_active.mbr_id = params[:mbr_id]
              #we already know that a familly unit is involved (either previous or current mbr_type)
              al_active.unit_id = mbr_family_unit_id
              al_active.save
            end
          end          
        end
        session[:msg] = 'Payment was successfully recorded'
      rescue StandardError => e
        session[:msg] = "The data was not entered successfully\n#{e}"
      end
      redirect "/admin/payments/show"
    end
    get '/admin/payments/edit/:id' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @pay = Payment.select(:id, :mbr_id, :payment_type_id, :payment_method_id, :payment_amount, :log_id)[params[:id].to_i]
      @mbr = Member.select(:id, :fname, :lname, :callsign, :mbr_type)[@pay[:mbr_id]]
      @log = Log.select(:id, :notes)[@pay[:log_id]]
      @log[:notes] << "\n**** edited ******"
      @payType = PaymentType.all
      @payMethod = PaymentMethod.all
      erb :p_edit, :layout => :layout_w_logout
    end
    post '/admin/payments/edit' do
      #params are {"pay_id"=>"28", "pay_log_id"=>"552", "payment_type"=>"2", "payment_method"=>"2", "payment_amt"=>"18.0", "notes"=>"some notes"}
      #only changing payment type, method, amount and log notes
      payTypes = {}
      PaymentType.select(:id, :type).map(){|x| payTypes[x.id]= x.type}
      log = Log[params[:pay_log_id]]
      augmented_notes = params[:notes]
      augmented_notes << Time.now.strftime("\nEdited on %m/%d/%Y")
      log.notes = augmented_notes
      ts = Time.now
      pay = Payment[params[:pay_id]]
      #validate
      pm = params[:payment_method]
      pt = params[:payment_type]
      pa = params[:payment_amt]
      if (pa == "" || pm == "" || pt == "")
        session[:msg] = 'Edit payment was UNSUCCESSFUL please make sure all fields are entered'
        redirect "/admin/payments/edit/#{params[:pay_id]}"
      elsif (pt != pay.paymentType.to_s && (payTypes[pt] == "Dues" || payTypes[pay.paymentType.id] == "Dues"))
        #need to ask user to delete rather than edit this payment, then start over
        session[:msg] = 'Edit payment was UNSUCCESSFUL (cannot change dues type) please delete this payment and start over'
        redirect "/admin/payments/edit/#{params[:pay_id]}"
      end
      pay.payment_method_id = pm
      pay.payment_type_id = pt
      pay.payment_amount = pa
      begin
        DB.transaction do
          log.save
          pay.save
        end
        session[:msg] = 'Edited payment was successfully recorded'
      rescue StandardError => e
        session[:msg] = "The data was not entered successfully\n#{e}"
      end
      redirect "/admin/payments/show"
    end
    get '/admin/payments/show' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      #build array of hashes to load payment data
      @pay = []
      pay = Payment.order(:ts, :a_user_id).all
      pay.each do |pmt|
        out = Hash.new
        out[:id] = pmt.id
        out[:mbr_name] = "#{pmt.member.fname} #{pmt.member.lname}"
        out[:auth_name] = "#{pmt.auth_user.member.fname} #{pmt.auth_user.member.lname}"
        out[:type] = pmt.paymentType.type
        out[:method] = pmt.paymentMethod[:method]
        out[:amount] = pmt.payment_amount
        if !pmt.log_id.nil?
          out[:notes] = pmt.log.notes
        else
          out[:notes] = "none"
        end
        out[:ts] = pmt.ts.strftime("%m-%d-%Y")
        @pay << out
      end
      erb :p_show, :layout => :layout_w_logout
    end
    get '/admin/payments/destroy/:id' do
      @payment = Payment[params[:id]]
      erb :p_destroy, :layout => :layout_w_logout
    end
    post '/admin/payments/destroy' do
      #params are {"pay_id"=>"28", "notes"=>"some notes", "confirm"=>"yes"}
      #should only be here to delete Dues payments
      if params[:confirm] != 'Yes'
        #js not enabled, need to find another way to confirm this action
        session[:msg] = "Payment was not deleted, please enable Javascript on your browser"
        redirect '/admin/payments/show'
      end
      payment = Payment[params[:pay_id]]
      #if this payment is associated with a unit, look for more recent payments that would need to roll back 1st
      more_recent_payments = Hash.new
      if !payment.log.unit.nil?
        unit_log_all = Log.where(unit: payment.log.unit)
        unit_log_all.each do |ul|
          if !ul.payment.nil?
            #get the time the payment associated with this unit if greater than current payment
            if ul.payment.ts > payment.ts
              more_recent_payments[ul.payment.id.to_s] = ul.payment.ts
            end
          end
        end
      end
      if !more_recent_payments.empty?
        #need to alert the user and exit out of this route
        session[:msg] = "UNSUCCESSFUL, first delete payments made after this one in reverse order, {id=>Time} #{more_recent_payments}"
        redirect '/admin/payments/show'
      end
      #build the log notes
      old_au_id = payment.a_user_id
      auth_users_callsigns = {"old" => Auth_user[old_au_id].member.callsign, "new" => Auth_user[session[:auth_user_id]].member.callsign}
      #need to edit the log for this payment
      augmented_notes = params[:notes].empty? ? "" : "#{params[:notes]}\n"
      log_pay = Log[payment.log_id]
      augmented_notes = augmented_notes.empty? ? log_pay.notes : "#{augmented_notes}\n#{log_pay.notes}"
      #first what type of payment is this; get paymentTypes id
      paymentTypes = {}
      PaymentType.select(:id, :type).map(){|x| paymentTypes[x.type]= x.id}
      #see issue 267 need to allow other payment types to be deleted
      if payment.payment_type_id == paymentTypes["Dues"]
        #this is a dues payment then need to roll back from audit log
        audit_logs = []
        #load any auditLogs associated with this payment
        #expecting at most, three types of audit logs based on auditLog::column [paid_up, mbr_type, active]. generate a hash for each
        array_of_audit_log_hashes = []
        #if there is no audit log throw an error
        if payment.auditLog.empty?
          #need to alert the user and exit out of this route
          session[:msg] = "UNSUCCESSFUL, this payment record does not have an audit trail, cannot delete payment id: #{payment.id}"
          augmented_notes << "\nattempt to delete payment id: #{payment.id} by #{Auth_user[session[:auth_user_id]].member.callsign} failed on #{Time.now.strftime("%m-%d-%y:%H:%M:%S")}"
          log_pay.notes = augmented_notes
          log_pay.save
          redirect '/admin/payments/show'
        end
        payment.auditLog.each do |al|
          h = {"a_user_id" => al.a_user_id, "column" => al.column, "old_value" => al.old_value, "new_value" => al.new_value}
          array_of_audit_log_hashes << h
          audit_logs << al.id
        end
        array_of_audit_log_hashes.each do |alh|
          augmented_notes << "rolling back payment with #{alh["column"]} new value: #{alh["old_value"]} old value: #{alh["new_value"]}\n"
        end
      else
        augmented_notes << "deleting payment, see notes\n"
      end
      #set the log info
      augmented_notes << "executed by #{auth_users_callsigns["new"]}; originally by #{auth_users_callsigns["old"]} at #{log_pay.ts.strftime("%m-%d-%y:%H:%M:%S")}"
      log_pay.notes = augmented_notes
      log_pay.ts = Time.now
      begin
        DB.transaction do
          log_pay.save
          if payment.payment_type_id == paymentTypes["Dues"]
            #roll back member status on paid_up and possibly, mbr_type (if not a family)
            #if current member type is family need to rollback paid_up for all family members
            m = Member[payment.mbr_id]
            if m.mbr_type == 'family'
              #only working with paid_up and active state changing; get all members of this unit
              u = Unit[log_pay.unit_id]
              u.members.each do |m|
                array_of_audit_log_hashes.each do |alh|
                  if alh["column"] == "paid_up"
                    m.paid_up = alh["old_value"]
                    m.save
                  elsif alh["column"] == "active"
                    u.active = alh["old_value"].to_i
                    u.save
                  end
                end
              end
            else
              #only have to work with one member; might need a unit log to update
              log_unit = nil
              array_of_audit_log_hashes.each do |alh|
                if alh["column"] == "paid_up"
                  m.paid_up = alh["old_value"]
                elsif alh["column"] == "mbr_type"
                  m.mbr_type = alh["old_value"]
                  if alh["old_value"] == 'family'
                    #add this mbr to unit, change unit active => 1
                    u = Unit[log_pay.unit_id]
                    u.add_member(m.id)
                    u.save
                    #update old unit log, first find unit log associated with this payment
                    #looking for Payment Log Association[unit_log_id:719]
                    notes = log_pay.notes
                    unit_log_id = /unit_log_id:(\d+)/.match(notes)
                    if !unit_log_id[1].nil?
                      log_unit = Log[unit_log_id[1].to_i]
                      old_notes = log_unit.notes
                      old_notes << "\nUnit mbr association[+mbr_id:#{m.id}], #{m.fname} #{m.lname} has been added"
                      log_unit.notes = old_notes
                      log_unit.save
                    else
                      puts "notes in destroy payment for old unit not matching: #{notes}"
                    end
                  end
                elsif alh["column"] == "active"
                  u = Unit[log_pay.unit_id]
                  u.active = alh["old_value"].to_i
                  u.save
                  old_notes = log_unit.notes
                  old_notes << "\nUnit id [#{u.id}], active status has gone from #{alh["new_value"]} to #{alh["old_value"]}"
                  log_unit.notes = old_notes
                  log_unit.save
                end
              end
              m.save
              old_notes = log_unit.notes
              old_notes << "\nexecuted by #{auth_users_callsigns["new"]}; originally by #{auth_users_callsigns["old"]} at #{log_pay.ts.strftime("%m-%d-%Y:%S")}"
              log_unit.notes = old_notes
              log_unit.save
            end
            audit_logs.each do |al|
              AuditLog[al].delete
            end
          end#end if dues, nothing special to do for other payments
          payment.delete
        end
        session[:msg] = 'Payment was SUCCESSFULLY deleted'
      rescue StandardError => e
        session[:msg] = "The payment WAS NOT deleted\n#{e}"
      end
      redirect '/admin/payments/show'
    end
    get '/admin/list_auth_users' do
      @au_list = []
      #get a 2D array of [[mbr_id, auth_user_id]] for each auth_user
      #except for currently logged in admin
      au = Auth_user.exclude(id: session[:auth_user_id]).select(:id, :mbr_id, :active).map(){|x| [x.mbr_id, x.id, x.active]}
      #fill this array with additional info
      au.each do |u|
        au_hash = Hash.new
        m = Member.select(:id, :fname, :lname, :callsign).where(id: u[0]).first
        au_hash["mbr_id"] = m.values[:id]
        au_hash["fname"] = m.values[:fname]
        au_hash["lname"] = m.values[:lname]
        au_hash["callsign"] = m.values[:callsign]
        au_hash["active"] = u[2]
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
      #see if this is an active member
      @mbr_to_update[:active] = au.active
      #need to fill out au_has_role with 0 or 1 for :update_au_roles erb
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
      #get action_id
      action_id = nil
      Action.select(:id, :type).map(){|x|
        if x.type == "auth_u"
          action_id = x.id
        end
      }
      #start building the log string
      l = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now, action_id: action_id)
      au = Auth_user.where(mbr_id: params[:mbr_id]).first
      #if there's something in notes put a newline after it and add it to the log
      l.notes = params[:notes] == '' ? '' : "#{params[:notes]}\n"
      #test for change in status
      deactivate = false
      if (params[:status] == '0' && au.active == 0) || (params[:status] == '1' && au.active == 1)
        #no change
      elsif params[:status] == '0' && au.active == 1
        #set auth_user.active to false
        deactivate = true
        l.notes << "Auth User was DEactivated\n"
      else
        l.notes << "Auth User was Activated\n"
      end
      au.active = params[:status].to_i
      #need to remove all existing roles before updating with new
      #example params[:roles]
      #{"1"=>"1", "2"=>"1"} where both roles were selected 
      #that needs to change currently, role 1 is auth_u and 2 mbr_mgr
      #store this users roles in case the transaction fails, then can add them back
      mbrs_roles = au.roles
      begin
        DB.transaction do
          roles = []
          #dont need to add to the log anything about old roles if this user was inactive
          diff_roles = ''
          if !au.roles.empty?
            diff_roles = 'Old roles: '
            au.roles.each {|r| diff_roles << "#{r.name}, "}
            diff_roles.chomp!(", ")
            au.remove_all_roles
          end
          if deactivate == false
            diff_roles << 'New roles: '
            params[:roles].each do |k,v|
              au.add_role(Role[k.to_i])
              roles << Role[k.to_i].name
            end
            roles.each {|r| diff_roles << "#{r}, "}
            diff_roles.chomp!(", ")
            l.notes << diff_roles
          else
            l.notes << diff_roles
          end
          l.save
          au.save
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
      @tmp_msg = session[:msg]
      session[:msg] = nil
      mbr_id = Auth_user[session[:auth_user_id]].mbr_id
      @sel_au_from_mbrs = Member.exclude(id: mbr_id).select(:id, :fname, :lname, :callsign, :email).all
      erb :create_au, :layout => :layout_w_logout
    end
    post '/admin/create_auth_user' do
      #expecting params keys :notes, :mbr_id, :roles (a hash)
      email = Member[params[:mbr_id].to_i].email
      #test for existing user with these credentials
      existing_auth_user = Auth_user.first(mbr_id: params[:mbr_id])
      if !existing_auth_user.nil?
        session[:msg] = 'this auth_user already exists, select update instead of create new'
        redirect "/admin/create_auth_user"
      end
      #test for duplicate emails in members table for this user
      member_set = Member.select(:id, :fname, :lname, :callsign, :email).where(email: email).all
      if member_set.length > 1
        puts "there is more than one member with this email"
        mbrs_w_same_email = ""
        member_set.each do |m|
          mbrs_w_same_email << "#{m.fname} #{m.lname}, #{m.callsign}\n"
          puts "#{m.fname} #{m.lname}, #{m.callsign}, #{m.email}"
        end
        mbrs_w_same_email.chomp!()
        session[:msg] = "this auth_user shares email (#{email}) with\n#{mbrs_w_same_email}"
        redirect "/admin/create_auth_user"
      end
      #all criteria are passing, go ahead and save this auth_user
      password = SecureRandom.hex[0,6]
      encrypted_pwd = BCrypt::Password.create(password)
      #get action id
      action_id = nil
      Action.select(:id, :type).map(){|x|
        if x.type == "auth_u"
          action_id = x.id
        end
      }
      roles = ""
      params[:roles].each do |k,v|
        roles << "#{Role[k].name}, "
      end
      roles.chomp!(', ')
      role_names = []
      begin
        DB.transaction do
          auth_user = Auth_user.new(:password => encrypted_pwd, :mbr_id => params[:mbr_id].to_i,
            :time_pwd_set => Time.now, :new_login => 1, :active => 1, :last_login => Time.now)
          auth_user.save
          l = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now, action_id: action_id)
          l.notes = "New authorized user added\nwith following roles #{roles}\nNotes: #{params[:notes]}"
          l.save
          #set the the roles for this user
          params[:roles].each do |k,v|
            auth_user.add_role(Role[k.to_i])
          end
        end
        session[:msg] = "Success; temp password for member #{member_set[0].values[:callsign]} and username #{member_set[0].values[:email]} is #{password}"
        redirect "/admin/list_auth_users"
      rescue StandardError => e
        session[:msg] = "error: could not create authorized user.\n#{e}"
        redirect "/admin/create_auth_user"
      end
    end
    get '/admin/create_unit_type/:id?' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @edit_unit_type = nil
      if params[:id] != 'null'
        @edit_unit_type = UnitType[params[:id]]
      end
      @unit_types = UnitType.all
      #build a list of existing unit type names to validate duplicates
      @old_type_names = ""
      @unit_types.each do |ut|
        @old_type_names << "#{ut.type},"
      end
      @old_type_names = @old_type_names[0...-1]
      erb :create_unit_type, :layout => :layout_w_logout
    end
    post '/admin/create_unit_type/:id?' do
      #expecting {"unit_type_name"=>"type5", "unit_type_descr"=>"a new type"}
      if params[:id].nil?
        #creating new type
        ut = UnitType.new(:type => params["unit_type_name"], :descr => params["unit_type_descr"])
      else
        #updating existing type
        ut = UnitType[params[:id]]
        ut.type = params["unit_type_name"]
        ut.descr = params["unit_type_descr"]
      end
      #need to create a log for this transaction
      #first get action id
      actions = {}
      Action.select(:id, :type).map(){|x| actions[x.type]= x.id}
      action_id = actions["unit"]
      l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: action_id)
      l.notes = "creating new unit type: #{params["unit_type_name"]}"
      begin
        DB.transaction do
          ut.save
          l.save
        end
        session[:msg] = "The unit type was successfully created"
        l.save
      rescue StandardError => e
        session[:msg] = "Error; the unit type could not be created\n#{e}"
      end
      redirect '/admin/create_unit_type/'
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
