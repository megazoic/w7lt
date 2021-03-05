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
require_relative 'event'
require_relative 'eventType'
require_relative 'referType'

module MemberTracker
  #using modular (cf classical) approach (see https://www.toptal.com/ruby/api-with-sinatra-and-sequel-ruby-tutorial)
  RecordResult = Struct.new(:success?, :member_id, :message)
  Paid_up = Struct.new(:active, :condition)
  class API < Sinatra::Base
    def initialize()
      @payment = Payment.new
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
    before '/a/*' do
      authorize!("auth_u")
    end
    before '/m/*' do
      #need to make exception for read_only editing their own profile
      ro_test_route = params['splat'][0].split('/')
      ro_action = ro_test_route.shift
      mbr_id = Auth_user[session[:auth_user_id]].mbr_id.to_s
      #test for matching id
      allow = false
      if ro_action == 'save'
        if params[:id] == mbr_id
          allow = true
        end
      elsif ro_action == 'edit'
        if ro_test_route.pop == mbr_id
          allow = true
        end
      end
      unless allow == true
        authorize!("mbr_mgr")
      end
    end
    before '/r/*' do
      authorize!("read_only")
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
      elsif auth_user_result['error'] == 'inactive'
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
    get '/home' do
      @member_lnames = Member.select(:id, :lname).order(:lname).all
      @tmp_msg = session[:msg]
      session[:msg] = nil
      erb :home, :layout => :layout_w_logout
    end
    ################### START MEMBER MGR ##################
    get '/r/dump/:table' do
      if params[:table] == 'mbr'
        @m = nil
        @m = Member.all
        @m.each do |m|
          #if !m[:modes].nil?
          #  m[:modes].gsub!(",", "|")
          #end
          #clear out commas
          m.each do |k,v|
            if !m[k].nil? && m[k].is_a?(String)
              m[k].gsub!(",", "|")
            end
          end
        end
        @modes = Member.modes
        erb :m_dump
      else
        redirect '/home'
      end
    end
    get '/m/query' do
      erb :query, :layout => :layout_w_logout
    end
    post '/m/query' do
      #param keys can be... "paid_up_q", :paid_up_q,
      #  "mbr_full", :mbr_full, "mbr_student", :mbr_student, :mbr_family,
      #  ":mbr_honorary, "arrl", :arrl, "ares", :ares, "pdxnet", :pdxnet,
      #  "ve", :ve, "elmer", :elmer
      query_keys = [:paid_up_q, :mbr_full, :mbr_student, :mbr_family,
        :mbr_honorary, :mbr_none, :arrl, :ares, :pdxnet, :ve, :elmer, :sota]
      @qset = Hash.new
      @qset[:mbr_type] = []
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
      if @qset[:mbr_type].empty?
        @qset.delete(:mbr_type)
      end
      if pu.active == true
        #there is a request for paid up status
        if pu.condition == true
          #asking for members who are paid up through the current year
          @members = Member.where(@qset){paid_up >= Time.now.strftime("%Y").to_i}
          @qset[:paid_up] = "true"
        else
          #asking for members who are NOT paid up through the current year
          @members = Member.where(@qset){paid_up < Time.now.strftime("%Y").to_i}
          @qset[:paid_up] = "false"
        end
      else
        #asking for all recorded members
        @members = Member.where(@qset)
      end
      erb :m_list, :layout => :layout_w_logout
    end
    get '/m/event/edit/:id' do
      @event = Event[params[:id]]
      @event_types = EventType.all
      @mbrs = Member.select(:id, :fname, :lname, :callsign).all
      #need to parse the log; should be in two parts 1) general notes 2) guest's not added to db
      #notes = @event.log.first.notes.split("\n")
      prev_event_log = @event.log_dataset.order(:id).where(action_id: @action.get_action_id("event")).all.pop
      notes = prev_event_log.notes.split("\n")
      @guest_notes = ''
      @pared_notes = ''
      if notes.length > 1
        @guest_notes = notes.pop
        #remove 'guest attendees:'
        m = /guest attendees:(.*)/.match(@guest_notes)
        if !m.nil?
          @guest_notes = m[1]
        end
        @pared_notes = notes * "-"
      end
      #get members who have already been entered as attending this event
      @mbrs_attending = []
      @event.members.each do |mbr|
        @mbrs_attending << mbr.id
      end
      erb :e_edit, :layout => :layout_w_logout
    end
    get '/m/event/create' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @event_types = EventType.all
      @mbrs = Member.select(:id, :fname, :lname, :callsign).all
      erb :e_create, :layout => :layout_w_logout
    end
    post '/m/event/create' do
=begin
      params {"general_notes"=>"a newer one", "event_type_id"=>"1", "name"=>"andSo", "descr"=>"a desc",
      "duration"=>"3" OR "none", "duration_units"=>"hrs", "guest_notes"=>"last,name;last2,name2",
      "g0:fname"=>"Myron", "g0:lname"=>"Dembo", "g0:callsign"=>"A7MYR", "g0:email"=>"*guest email",
      "g0:notes"=>"some notes for guest0",..., "mbr_id"=>"478", "id:481"=>"1", "id:479"=>"1"}
=end
      ######validate presence of contact member, event type, date, if duration also units ###########
      valid_form = true
      if params[:mbr_id].nil?
        #invalid cuz no event contact
        session[:msg] = "Error; the event could not be created\nEvent contact missing"
        valid_form = false
      elsif params[:event_type_id] == "none"
        #invalid cuz need an event type
        session[:msg] = "Error; the event could not be created\nEvent type missing"
        valid_form = false
      elsif !/202\d-[01]\d-[0-3]\d\s+[012]\d:[0-5]\d/.match(params[:event_date]) #'MM-DD-YYYY HH:MM'
        session[:msg] = "Error; the event could not be created\nEvent date incorrectly formatted"
        valid_form = false
      elsif (params[:duration] != "none" && params[:duration_units].nil?) ||
        (params[:duration] == "none" && !params[:duration_units].nil?)
        session[:msg] = "Error, both a duration and a duration units must be selected"
        valid_form = false
      end
      if valid_form == false
        redirect "/m/event/create"
      end
      ################################### end of form validation #####################################
      #are we updating an existing event?
      existing_event_id = nil
      if !params[:event_id].nil?
        existing_event_id = params[:event_id].to_i
        params.delete(:event_id)
      end
      #remove member and guest info from params
      params.delete("has_guests")
      count = 0
      #Guest = Struct.new(:number, :attendees, :new_guests, :tmp_vitals, :msng_values, :duplicate)
      #Struct holds attendees (mbrs who are already in db), new_guests (those to be entered, array of hashes),
      #vitals a temp hash, new_guests hash may have the following keys ("fname", "lname", "callsign", "notes")
      guest = Event::Guest.new(nil,[],[],{},'',[])
      params.each do |k,v|
        #expect "id:481"=>"1"
        m_attendees = /id:(\d+)/.match(k)
        #expect "g0:fname"=>"Myron"
        m_new_guests = /g(\d):(.*)/.match(k)
        if !m_attendees.nil?
          guest.attendees << m_attendees[1].to_i
          params.delete(k)
        elsif !m_new_guests.nil?
          #want only boxes that were filled out (eg. not default "g2:callsign"=>"*guest callsign")
          if m_new_guests[1].to_i != guest.number
            #reset the guest we are collecting info on
            guest.number = m_new_guests[1].to_i
            if !guest.tmp_vitals.empty?
              guest.new_guests << guest.tmp_vitals
              guest.tmp_vitals = {}
            end
          end
          #do we have data to enter for this guest?
          if v[0...2] != "*g" && v != ''
            #upcase everything but the general_notes
            if !/notes/.match(k)
              v.upcase!
            end
            #build temp hash "fname" => "GUESTSFIRSTNAME"
            guest.tmp_vitals["#{m_new_guests[2]}"] = v.strip
          end
          params.delete(k)
        end
      end
     #add coordinator to attendee list if not already there
      if !guest.attendees.include?(params[:mbr_id].to_i)
        guest.attendees << params[:mbr_id].to_i
      end
      if !guest.tmp_vitals.empty?
        #add this hash to the array of new guest hashes
        guest.new_guests << guest.tmp_vitals
      end
      l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: @action.get_action_id("event"))
      #look for existing log
      recent_log_vitals = {:a_user => nil, :ts => nil, :log_id => nil}
      if !existing_event_id.nil?
        recent_log = Event[existing_event_id].log_dataset.order(:id).all.shift
        auth_user = "#{recent_log.auth_user.member.fname} #{recent_log.auth_user.member.lname}, #{recent_log.auth_user.member.callsign}"
        recent_log_vitals = {:a_user => auth_user, :ts => recent_log[:ts].strftime("%m-%d-%y"),
        :log_id => recent_log[:id]}
      end
      if !params[:general_notes].nil?
        if existing_event_id.nil?
          l.notes = "#{params[:general_notes]}"
        else
          l.notes = "MODIFIED EVENT NOTES: previous auth user: #{recent_log_vitals[:a_user]},\n" +
            " previous notes made back on #{recent_log_vitals[:ts]}, that log id: #{recent_log_vitals[:log_id]}" +
            "\nNEW NOTES: #{params[:general_notes]}"
        end
        params.delete(:general_notes)
      end
      if !params[:guest_notes].nil?
        ga = "guest attendees:#{params[:guest_notes]}"
        params.delete(:guest_notes)
        l.notes.nil? ? l.notes = ga : l.notes << ("\n" + ga)
      end
      params[:ts] = "#{DateTime.parse(params[:event_date])}"
      params.delete(:event_date)
      if params[:duration] == "none"
        params.delete(:duration)
        params.delete(:duration_units)
      end
      #at this point params should be params are {"event_type_id"=>"1", "name"=>"fdim :update ;update2", "descr"=>"a desc :update :update2", "duration"=>"3", "duration_units"=>"hrs", "mbr_id"=>"481", "ts"=>"2020-05-15 15:01:28 -0700"}
      #OR "duration"=> key removed, "duration_units"=> key removed
      event = nil
      if !existing_event_id.nil?
        event = Event[existing_event_id]
        event.update(params)
      else
        event = Event.new(params)
      end
      event[:a_user_id] = session[:auth_user_id]
      begin
        DB.transaction do
          event.save
          l.event_id = event.id
          if !existing_event_id.nil?
            #remove old attendees before adding new
            event.remove_all_members
          end
          guest.attendees.each do |mbr_id|
            event.add_member(mbr_id)
          end
          if !guest.new_guests.empty? && existing_event_id.nil?
            #we don't expect to have new guests with event update
            guest.new_guests.each do |ng|
              #expecting 2 out of 4 keys (not including "notes")
              guest_notes = ''
              if ng.has_key?("notes")
                guest_notes = ng["notes"]
                ng.delete("notes")
              end
              if ng.size < 2
                guest.msng_values = "This guest has too few fields entered #{ng}; enter as new member and add to event attendee list"
                next
              end
              #test for duplicates. expecting 0 not a dupe, 1 is a dupe
              if @member.validate_dupes(ng) == 1
                #Houston, we have a problem
                guest.duplicate << ng
                guest.msng_values = "A guest with same credentials as a member was found. #{ng}"
                next
              end
              #need to add guests to database before adding them to this event
              log_guest = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: @action.get_action_id("mbr_edit"), event_id: event.id)
              #need to check for which keys are present, the members table only needs an email
              #and need to use dummy email if other fields are present
              if !ng.has_key?("email")
                ng["email"] = "guest@w7lt.org"
              end
              new_guest_mbr = Member.new(ng)
              new_guest_mbr.save
              event.add_member(new_guest_mbr.id)
              log_guest.notes = "New guest:#{ng}\n#{guest_notes}"
              log_guest.save
            end
          end
          l.save
        end
        out_msg = ''
        if !guest.duplicate.empty?
          out_msg << "these duplicates were not entered. add them via event update\n#{guest.duplicate}"
        end
        if !guest.msng_values.empty?
          out_msg << guest.msng_values
        end
        session[:msg] = "Success; the event was created"
        if !out_msg.empty?
          session[:msg] << ": However, #{out_msg}"
        end
      rescue StandardError => e
        session[:msg] = "Error; the event could not be created\n#{e}"
        #puts "error #{e.backtrace}"
      end
      redirect "/m/event/list/#{params[:event_type_id]}"
    end
    get '/m/event/type/create/:id?' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @edit_event_type = nil
      if !params[:id].nil?
        @edit_event_type = EventType[params[:id]]
      end
      @event_types = EventType.all
      #build a list of existing event type names to validate duplicates
      @old_type_names = ""
      @event_types.each do |et|
        @old_type_names << "#{et.name},"
      end
      @old_type_names = @old_type_names[0...-1]
      erb :e_type_create, :layout => :layout_w_logout
    end
    post '/m/event/type/create/:id?' do
      #expecting {"event_type_name"=>"type5", "event_type_descr"=>"a new type"}
      if params[:id].nil?
        #creating new type
        et = EventType.new(:name => params["event_type_name"], :descr => params["event_type_descr"], :a_user_id => session[:auth_user_id])
      else
        #updating existing type
        et = EventType[params[:id]]
        et.name = params["event_type_name"]
        et.descr = params["event_type_descr"]
      end
      #need to create a log for this transaction
      l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: @action.get_action_id("event"))
      if et.id.nil?
        l.notes = "creating new event type: #{params["event_type_name"]}"
      else
        l.notes = "modifying existing event type: type creator #{et.auth_users.member.callsign}"
      end
      begin
        DB.transaction do
          et.save
          l.save
        end
        session[:msg] = "The event type was successfully created"
        l.save
      rescue StandardError => e
        session[:msg] = "Error; the event type could not be created\n#{e}"
      end
      redirect '/m/event/type/create/'
    end
    get '/m/event/list/:id' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @events = nil
      @event_type = 'all'
      if params[:id] == 'all'
        @events = Event.order(:ts, :event_type_id).all
      else
        @events = Event.where(:event_type_id => EventType.where(:id => params[:id]).first.id)
        @event_type = EventType.where(:id => params[:id]).first.name
      end
      erb :e_list, :layout => :layout_w_logout
    end
    get '/m/event/attendees/show/:id' do
      @event = Event[params[:id]]
      @attendees =[]
      #create hash with 2 keys, :same, :other  and a count of number times attended that event type
      etypes = []
      MemberTracker::EventType.select(:id).each do |et|
        if et != @event.event_type_id
          etypes << et.id
        end
      end
      @event.members.each do |mbr|
        #set up hash to hold counts of attendance
        et_hash = {:same => 0, :other => 0}
        etypes.each{|et| et_hash[et] = 0}
        mbr_tmp_hash = {:mbr_id => mbr.id, :fname => mbr.fname, :lname => mbr.lname,
          :callsign => mbr.callsign, :paid_up => mbr.paid_up, :attendance => et_hash}
        mbr.events.each do |event|
          #only events within the last year
          if Date.parse(event.ts.to_s) > Date.today.prev_year
            #is it the same event type?
            if event.event_type_id == @event.event_type_id
              mbr_tmp_hash[:attendance][:same] += 1
            else
              mbr_tmp_hash[:attendance][:other] += 1
            end
          end
        end
        @attendees << mbr_tmp_hash
        mbr_tmp_hash = {}
      end
      #look for guest attendees in the log notes
      @guests = []
      @event.log.each do |l|
        case l.action.type
        when 'mbr_edit'
          #expect "New guest:{"fname" => "name"...}
          #there may be more than one line (new guest)
          gs = l.notes.split("\n")
          gs.each do |g|
            m = /:({.*})/.match(g)
            if !m.nil?
              @guests << m[1]
            end
          end
        when 'event'
          g = l.notes.split("\n").last
          # expect "guest attendees:guest1;guest2;guest3"
          if g.include?(";")
            m = /attendees:(.*)/.match(g)
            if !m.nil?
              @guests << m[1].split(";")
            end
          end
        else
        end
      end
      @e_contact = Member.select(:fname, :lname, :callsign).where(id: @event.mbr_id).first
      erb :e_attendees, :layout => :layout_w_logout
    end
    get '/m/log/create/:id?' do
      if params[:id].nil?
        #creating a general log
        @type = 'general'
      else
        @type = 'member'
        @member = Member[params[:id]]
      end
      erb :l_create, :layout => :layout_w_logout
    end
    post '/m/log/create' do
      l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, notes: params[:notes])
      
      if params[:mbr_id].nil?
        #a general log (for now)
        l.action_id = @action.get_action_id("general_log")
        l.save
        session[:message] = "Log successfully saved"
        redirect '/m/log/view/auth_user'
      else
        #adding a note to a member
        l.mbr_id = params[:mbr_id]
        l.action_id = @action.get_action_id("mbr_edit")
        l.save
        session[:message] = "Log successfully saved"
        redirect "/r/member/show/#{params[:mbr_id]}"
      end
    end
    get '/m/log/view/:type' do
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
        Log.where(a_user_id: session[:auth_user_id]).order(:ts, :action_id).each do |l|
          h = Hash.new
          if !l.member.nil?
            h[:mbr_name] = "#{l.member.fname} #{l.member.lname}"
          else
            h[:mbr_name] = "N/A"
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
              else
                h[:mbr_name] = "N/A"
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
      when "general"
        @logs = []
        Action[@action.get_action_id("general_log")].logs_dataset.order(:id).each do |l|
          @logs << {:au_name => l.auth_user.member.callsign, :notes => l.notes, :time => l.ts.strftime("%m-%d-%Y")}
        end
        if @logs.length == 0
          session[:msg] = "there are no logs to view"
          redirect '/home'
        end
     else
        #shouldn't be here
      end
      erb :l_list, :layout => :layout_w_logout
    end
    get '/r/member/list/?:event?' do
      @members = DB[:members].select(:id, :lname, :fname, :callsign, :paid_up, :mbr_type).order(:lname, :fname).all
      @tmp_msg = session[:msg]
      session[:msg] = nil
      #if looking for an event contact
      @event = false
      if !params[:event].nil?
        @event = true
      end
      erb :m_list, :layout => :layout_w_logout
    end
    get '/r/member/show/:id' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @member = Member[params[:id].to_i]
      @modes = Member.modes
      if @member[:modes] == ''
        @member[:modes] = 'none'
      end
      erb :m_show, :layout => :layout_w_logout
    end
    get '/m/member/edit/:id' do
      @existing_mbrs = []
      @mbr = Member[params[:id].to_i]
      @modes = Member.modes
      erb :m_edit, :layout => :layout_w_logout
    end
    get '/m/member/create' do
      #need to avoid dups when creating a new member
      @existing_mbrs = []
      @mbr = {:lname => '', :modes => ''}
      @modes = Member.modes
      erb :m_edit, :layout => :layout_w_logout
    end
    post '/m/member/create' do
      #this route used to update an existing member or save a new member
      #these will be used to avoid dups when creating a new member
      @existing_mbrs = []
      @mbr = {}
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
      if params[:refer_type_id] == 'none'
        params.reject!{|k,v| k == 'refer_type_id'}
      end
      #need to pack all of the modes
      modes = ""
      params.each do |k,v|
        mode_key = /mode_(.*)$/.match(k)
        if  mode_key.respond_to?("[]") && v == "1"
          modes << "#{Member.modes.key(mode_key[1])},"
        end
      end
      #remove these k,v pairs and add packed modes back
      params.reject! {|k,v| /mode_/.match(k)}
      params["modes"] = modes[0...-1]
      #this could be a new member or existing member
      if mbr_id == ''
        #new member
        params.reject!{|k,v| k == "id"}
        #the start date has been set in the erb file
        params[:mbr_since] = Date.strptime(params[:mbr_since], '%Y-%m')
        #set the character case to upper for name and email
        params[:fname] = params[:fname].upcase
        params[:lname] = params[:lname].upcase
        params[:email] = params[:email].upcase
        #if coming back with override = 1, let this go through, else...
        if !params.has_key?("override")
          #need to validate that this member is not already in the db
          #@existing_mbrs = Member.where(fname: params[:fname], lname: params[:lname]).all
          if @member.validate_dupes({fname: params[:fname], lname: params[:lname]}) == 1
            #we have a possible existing member here
            @mbr = params
            @modes = Member.modes
            #Send this back for validation
            @tmp_msg = "looks like this member has already been entered into our db, need to update?"
            return erb :m_edit, :layout => :layout_w_logout
          end
        end
        #set the default mbr_type until a payment is made (this is also done on mbrs table)
        #note, none is also used to describe a 'guest'
        params[:mbr_type] = 'none'
        mbr_record = Member.new(params)
        begin
          DB.transaction do
            #save the new member
            mbr = mbr_record.save
            mbr_id = mbr.id
            #log the action
            augmented_notes = "**** New Member entry\n#{notes}"
            l = Log.new(mbr_id: mbr_id, a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes, action_id: @action.get_action_id("mbr_edit"))
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
        #set the character case to upper for name, email and callsign
        params["fname"] = params["fname"].upcase
        params["lname"] = params["lname"].upcase
        params["email"] = params["email"].upcase
        params["callsign"].empty? ? nil : params["callsign"] = params["callsign"].upcase
        #log a change in callsign
        if !mbr_record["callsign"].nil?
          if params["callsign"] != mbr_record["callsign"].upcase
            augmented_notes << "\nchange_call:#{mbr_record["callsign"]}:#{params["callsign"]}"
          end
        else
          if !params["callsign"].empty?
            if notes.empty?
              notes << "add_call:#{params["callsign"]}"
            else
              notes << "\nadd_call:#{params["callsign"]}"
            end
          end
        end
        begin
          DB.transaction do
            mbr_record.update(params)
            augmented_notes = "**** Existing Member update\n#{notes}"
            l = Log.new(mbr_id: mbr_record.id, a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes, action_id: @action.get_action_id("mbr_edit"))
            l.save
          end
          session[:msg] = "The existing member was successfully updated"
        rescue StandardError => e
          session[:msg] = "The existing member could not be updated\n#{e}"
        end
      end
      if logPayment == "1"
        if session[:auth_user_roles].include?('auth_u')
          redirect "/m/payment/new/#{mbr_id}"
        else
          session[:msg] << "\nyou need to be an admin to add a payment record"
        end
      end
      redirect "/r/member/show/#{mbr_id}"
    end
    get '/m/member/refer/type/list/:id' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @referrals = nil
      @refer_type = 'all'
      if params[:id] == 'all'
        @members = Member.order(:lname, :refer_type_id).exclude(refer_type_id: nil).all
        @qset = {"refer_type" => @refer_type}
      else
        @members = Member.where(:refer_type_id =>params[:id]).all
        @refer_type = ReferType.where(:id => params[:id]).first.name
        #remind the user about which refer type you are displaying
        @qset = {"refer_type" => @refer_type}
      end
      erb :m_list, :layout => :layout_w_logout
    end
    get '/m/member/refer/type/create/?:id?' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @edit_refer_type = nil
      if !params[:id].nil?
        @edit_refer_type = ReferType[params[:id]]
      end
      @refer_types = ReferType.all
      erb :m_refer_type_create, :layout => :layout_w_logout
    end
    post '/m/member/refer/type/create/:id?' do
      #params are {"refer_type_name"=>"instagram", "refer_type_descr"=>"instagram.com", "id"=>nil}
      #first validate that the fields are filled out
      if params[:refer_type_name].empty?
        session[:msg] = "The referal type could not be created/updated\nmissing name field for refer type"
        redirect "/m/member/refer/type/list/all"
      end
      rt_notes = ''
      if !params[:id].nil?
        rt_notes = "made change to refer type: old name is #{params[:old_type_name]}, old descr is #{params[:old_type_descr]}\n"
        rt_notes = rt_notes << "new name is #{params[:refer_type_name]}, new descr is #{params[:refer_type_descr]}"
        if params[:refer_type_notes] != 'Notes for this action'
          rt_notes << "\n#{params[:refer_type_notes]}"
        end
      end
      DB.transaction do
        #if id => nil, creating a new type else, editing an existing referal type
        rt = nil
        if params[:id].nil?
          rt = ReferType.new(name: params[:refer_type_name], descr: params[:refer_type_descr])
          rt_notes = "added new referral type; name #{params[:refer_type_name]}, descr #{params[:refer_type_descr]}"
          if params[:refer_type_notes] != 'Notes for this action'
            rt_notes << "\n#{params[:refer_type_notes]}"
          end
        else
          rt = ReferType[params[:id]]
          rt.update(name: params[:refer_type_name], descr: params[:refer_type_descr])
        end
        l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, notes: rt_notes, action_id: @action.get_action_id("mbr_edit"))
        l.save
        rt.save
      rescue StandardError => e
          session[:msg] = "The referal type could not be created/updated\n#{e}"
          redirect "/m/member/refer/type/list/all"
      end
      if params[:id].nil?
        session[:msg] = "The referal type was successfully created"
        redirect "/m/member/refer/type/list/all"
      else
        session[:msg] = "The referal type was successfully edited"
        redirect "/m/member/refer/type/list/#{params[:id]}"
      end
    end
    get '/m/unit/list/:unit_type' do
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
    get '/m/unit/create' do
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
    post '/m/unit/create' do
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
      mbr_ids = []
      params.each do |k,v|
        mbr_ids << /id:(\d+)/.match(k)[1]
      end
      #need to create a log for this transaction
      l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: @action.get_action_id("unit"))
      mbr_names = ""
      mbr_ids.each do |mbr_id|
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
          mbr_ids.each do |mbr_id|
            m = Member[mbr_id.to_i]
            #family type also is related to member_type ('full', 'family', 'student', 'honorary', 'none')
            #since this isn't a payment however, don't update paid_up status
            if unit_type_name == 'family'
              #need to test if any member is already a member of a family unit
              fu_already = []
              m.units.each do |u|
                if UnitType[u.unit_type_id].type == 'family'
                  #oops, need to bail and alert who is already a member of a fam unit
                  fu_already << {"mbr_id" => m.id, "unit_id" => u.id}
                end
              end
              if !fu_already.empty?
                session[:msg] = "Unit creation UNSUCCESSFUL: member(s) are already in a family unit #{fu_already}"
                redirect "/m/unit/list/family"
              end
              #set mbr_type to none, record this change in auditLogs if mbr_type changed
              #when payment is made this member will change type to family
              if m.mbr_type != "none"
                al = AuditLog.new("a_user_id" => session[:auth_user_id], "column" => "mbr_type",
                        "changed_date" => Time.now, "old_value" => m.mbr_type, "new_value" => "none",
                        "mbr_id" => m.id, "unit_id" => u.id)
                al.save
              end
            end
            m.add_unit(u)
            m.save
          end
          l.unit_id = u.id
          l.save
        end
        session[:msg] = "The unit was successfully created"
        redirect "/m/unit/list/#{unit_type_name}"
      rescue StandardError => e
        session[:msg] = "The unit could not be created\n#{e}"
        redirect '/home'
      end
    end
    get '/m/unit/edit/:id' do
      #response['Cache-Control'] = "public, max-age=0, must-revalidate"
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
    post '/m/unit/update' do
      #expecting keys "unit_id", "name", some mbrs like {"id:nnn" => 1, ...} where nnn is the member id
      #if :active is missing is then 0
      #save notes for log
      notes = params["notes"]
      params.reject!{|k,v| k == "notes"}
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
      mbrs_ids_old_out = mbrs_old - mbrs_new #these have been removed
      mbrs_ids_new_in = mbrs_new - mbrs_old #these have been added
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
      l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes, action_id: @action.get_action_id("unit"))
      ################get ready for update#####################
      have_payment = false
      paid_up_status = 0
      unit_pay_date_latest = Time.new(1999,01,01)
      unit_pay_id_latest = 0
      if unit.unit_type.type == 'family'
        #look for payments
        unit.log.each do |ul|
          if !ul.payment.nil?
            have_payment = true
            paid_up_status = ul.payment.member.paid_up
            if ul.payment.ts > unit_pay_date_latest
              unit_pay_date_latest = ul.payment.ts
              unit_pay_id_latest = ul.payment.id
            end
          end
        end
      end
      ##################end get ready for update###################
      begin
        DB.transaction do
          #change members in the unit
          #-------------------- BEGIN REMOVING MEMBERS FROM UNIT ---------------------
          #need to get mbr back to original state before added to unit
          mbrs_ids_old_out.each do |mbr_id|
            #is this mbr associated with the most recent payment?
            if have_payment == true && Payment[unit_pay_id_latest].mbr_id == mbr_id
              #can't do this, need to rollback that payment and associate it with another remaining unit mbr
              session[:msg] = "FAILED: The unit could not be updated. Most recent payment (id: #{unit_pay_id_latest}) is still associated with member (id: #{mbr_id}) you are trying to remove"
              redirect "/m/unit/list/all"
            end
            m = Member[mbr_id]
            unit.remove_member(m)
            #roll back mbr's paid_up and type status
            ###########################2nd part of changes################
            hash_of_audit_logs = Hash.new
            m.audit_logs.each do |al|
              #only get auditlogs for this unit
              if al.unit_id == unit.id
                #["al_id", "a_user_id", "column",  "old_value", "new_value"]
                hash_of_audit_logs[al.changed_date] = [al.id, al.a_user_id, al.column, al.old_value, al.new_value]
              end
            end
            #sort by timestamp and walk back in time
            array_of_sorted_auditlogs = hash_of_audit_logs.sort
            #hash[al.changed_date] = ["al_id", "a_user_id", "column",  "old_value", "new_value"]
            #[[1999-01-08 04:05:06 -0800, ["al_id", "a_user_id", "column",  "old_value", "new_value"]]
            while a = array_of_sorted_auditlogs.pop
              if a[0] >= unit.ts
                case a[1][2] 
                when "paid_up"
                  m.paid_up = a[1][3]
                  augmented_notes << "\nsetting paid_up for #{m.callsign} to #{m.paid_up}"
                  #remove audit log
                  AuditLog[a[1][0]].delete
                when "mbr_type"
                  m.mbr_type = a[1][3]
                  augmented_notes << "\nsetting mbr_type for #{m.callsign} to #{m.mbr_type}"
                  #remove audit log
                  AuditLog[a[1][0]].delete
                else
                  #shouldn't be here
                end
                m.save
              end
            end
            #######################end 2nd part of changes################
            augmented_notes << "\nUnit mbr association[-mbr_id:#{m.id}], #{m.fname} #{m.lname} has been removed"
          end
          #-------------------- END REMOVING MEMBERS FROM UNIT ---------------------
          #-------------------- BEGIN ADDING MEMBERS TO UNIT ---------------------
          mbrs_ids_new_in.each do |mbr_id|
            unit.add_member(mbr_id)
            m = Member[mbr_id]
            augmented_notes << "\nUnit mbr association[+mbr_id:#{mbr_id}], #{m.fname} #{m.lname} has been added"
            #set mbr_type to family if this is a family unit but only if there are prior payments made on this unit
            if unit.unit_type.type == 'family'
              #look for payments
              have_payment = false
              paid_up_status = 0
              unit_pay_date_latest = Time.new(1999,01,01)
              unit_pay_id_latest = 0
              unit.log.each do |ul|
                if !ul.payment.nil?
                  have_payment = true
                  paid_up_status = ul.payment.member.paid_up
                  if ul.payment.ts > unit_pay_date_latest
                    unit_pay_date_latest = ul.payment.ts
                    unit_pay_id_latest = ul.payment.id
                  end
                end
              end
              if have_payment == true #if not, then this mbr has already been added no other changes need to be made
                #do we need to record paid_up audit log?
                if m.paid_up != paid_up_status
                  al = AuditLog.new("a_user_id" => session[:auth_user_id], "column" => "paid_up",
                          "changed_date" => Time.now, "old_value" => m.paid_up, "new_value" => paid_up_status,
                          "mbr_id" => m.id, "pay_id" => unit_pay_id_latest, "unit_id" => unit.id)
                  al.save
                end
                al = AuditLog.new("a_user_id" => session[:auth_user_id], "column" => "mbr_type",
                        "changed_date" => Time.now, "old_value" => m.mbr_type, "new_value" => "family",
                        "mbr_id" => m.id, "pay_id" => unit_pay_id_latest, "unit_id" => unit.id)
                al.save
                  #we have a prior payment for this unit go ahead and set this member.mbr_type to family
                m.mbr_type = 'family'
                m.paid_up = paid_up_status
                #need to create audit log so this action will be rolled back if the payments that established the
                #paid_up status of the other family units are rolled back
                m.save
              end
            end
          end
          #-------------------- END OF ADDING MEMBERS TO UNIT ---------------------
          unit.save
          l.save
          session[:msg] = "The existing unit was successfully updated"
          #need to build this route
          #redirect "/show/unit/#{unit.id}"
          redirect "/m/unit/list/#{unit.unit_type.type}"
        end
      rescue StandardError => e
        session[:msg] = "The existing unit could not be updated\n#{e}"
        redirect "/m/unit/list/all"
      end
    end
    get '/m/unit/type/create/:id?' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @edit_unit_type = nil
      if !params[:id].nil?
        @edit_unit_type = UnitType[params[:id]]
      end
      @unit_types = UnitType.all
      #build a list of existing unit type names to validate duplicates
      @old_type_names = ""
      @unit_types.each do |ut|
        @old_type_names << "#{ut.type},"
      end
      @old_type_names = @old_type_names[0...-1]
      erb :u_type_create, :layout => :layout_w_logout
    end
    post '/m/unit/type/create/:id?' do
      #expecting {"unit_type_name"=>"type5", "unit_type_descr"=>"a new type"}
      if params[:id].nil?
        #creating new type
        ut = UnitType.new(:type => params["unit_type_name"], :descr => params["unit_type_descr"], :a_user_id => session[:auth_user_id])
      else
        #updating existing type
        ut = UnitType[params[:id]]
        ut.type = params["unit_type_name"]
        ut.descr = params["unit_type_descr"]
      end
      #need to create a log for this transaction
      l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: @action.get_action_id("unit"))
      if ut.id.nil?
        l.notes = "creating new unit type: #{params["unit_type_name"]}"
      else
        l.notes = "modifying existing user type: type creator #{ut.auth_users.member.callsign}"
      end
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
      redirect '/m/unit/type/create/'
    end
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
    get '/m/member/groupsio' do
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
        #puts "in groups.io and unmatched is #{@unmatched}"
        erb :groupsio, :layout => :layout_w_logout
      else
        #failed send message
        @err_msg = gio.groupsIOError["errorMsg"]
        erb :errorMsg, :layout => :layout_w_logout
      end
    end
    post '/m/member/groupsio' do
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
        erb :g_list, :layout => :layout_w_logout
      else #nothing was sent
        erb :home, :layout => :layout_w_logout
      end
    end
    get '/m/payment/new/:id' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      @mbr_pay = Member.select(:id, :fname, :lname, :callsign, :paid_up, :mbr_type)[params[:id].to_i]
      #if mbr_type is 'family' then count all family members that will be updated
      @mbr_family = []
      if @mbr_pay.mbr_type == 'family' || @mbr_pay.mbr_type == 'none'
        #find the id for the family unit
        fu_id = nil
        #does this member have any family units?
        if !@mbr_pay.units.empty?
          @mbr_pay.units.each do |mu|
            if mu.unit_type_id == UnitType.where(:type => 'family').first.id
              fu_id = mu.id
            end
          end
        end
        if !fu_id.nil?
          #load members in this family
          Unit[fu_id].members.each do |f_member|
            #load names other than the current member
            if f_member.id != params[:id].to_i
              @mbr_family << "#{f_member.fname} #{f_member.lname}"
            end
          end
        end
      end
      #so that selected option for mbr_type in form defaults correctly, want those with none to be family if
      #they just joined a family unit
      @mbr_type_selected = ''
      if !@mbr_family.empty?
        #want to default the dues payment to family even if mbr_type is none
        @mbr_type_selected = "family"
      else #otherwise, just stick with existing mbr_type
        @mbr_type_selected = @mbr_pay.mbr_type
      end
      #need to remove sk from this array
      @mbrTypes = []
      Member.mbr_types.each { |mt| @mbrTypes << mt }
      @mbrTypes.pop
      @payType = PaymentType.all
      @payMethod = PaymentMethod.all
      @payFees = Payment.fees
      erb :m_pay, :layout => :layout_w_logout
    end
    post '/m/payment/new' do
      #this is used to renew a membership but also to record other payment types
      #{mbr_id, mbr_type_old=>(eg.)full, mbr_paid_up_old, payment_type=>2, mbr_type,
      #paid_up, payment_method=>1, [pay_amt, other_pmt] notes=>}
      #need to create a log for this transaction
      puts params
      augmented_notes = params[:notes]
      log_pay = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now)
      log_unit = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now, action_id: @action.get_action_id("unit"))
      #create hash to hold all of the audit logs associated with this transaction
      auditlog_hash = {}
      #load AuditLog in case needed this is associated with the paying member ie params[:mbr_id]
      auditlog_hash["pay_mbr_paid_up"] = AuditLog.new()
      auditlog_hash["pay_mbr_mbr_type"] = AuditLog.new()
      auditlog_hash["al_active"] = AuditLog.new()
      #only record an audit log if needed (this goes for any type of audit log)
      al_save = false
      #check to see if 'dues' is selected as :payment_type if so, store family ids
      mbr_family_ids = []
      pay_amt = nil
      mbr_family_unit_id = nil
      if PaymentType[params[:payment_type]].type == 'Dues'
        #going to put this info in the log
        log_pay.action_id = @action.get_action_id("mbr_renew")
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
            redirect "/m/unit/create"
          end
          #associate logs with this unit
          log_pay.unit_id = mbr_family_unit_id
          log_unit.unit_id = mbr_family_unit_id
          #load members in this family, first test for existance of this unit
          Unit[mbr_family_unit_id].members.each do |f_member|
            #load ids for all besides the current member
            mbr_family_ids << f_member.id if f_member.id != params[:mbr_id].to_i
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
            #were there only two members in this family unit?
            if u.members.length < 3
              #rename unit
              u.name = "retired: #{u.name}, #{m.fname} #{m.lname}"
              #change member type of remaining member to 'none'
              u.members.each do |m|
                if m.id != :mbr_id
                  m_to_change = Member[m.id]
                  m_to_change.mbr_type = 'none'
                  m_to_change.save
                end
              end
            end
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
              auditlog_hash["al_active"].set("a_user_id" => session[:auth_user_id], "column" => "active",
                "changed_date" => Time.now, "old_value" => old_active, "new_value" => 0,
                    "mbr_id" => params[:mbr_id])
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
              redirect "/r/member/list"
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
        #dues payment can be from other_pmt or pay_amt depending on which entry chosen
        if params.has_key?(:other_pmt)
          pay_amt = params[:other_pmt].to_i
        else #need to find amt from payment model
          payFees = Payment.fees
          pay_amt = payFees[params[:mbr_type]]
        end
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
        log_pay.action_id = @action.get_action_id("donation")
      end
      pay = Payment.new(:mbr_id => params[:mbr_id], :a_user_id => session[:auth_user_id], :payment_type_id => params[:payment_type],
        :payment_method_id => params[:payment_method], :payment_amount => pay_amt, :ts => Time.now)
      begin
        DB.transaction do
          if PaymentType[params[:payment_type]].type == 'Dues'
            m.save
            if params[:mbr_type] == 'family'
              #update other family members
              fam_names = ""
              #if there is temporarily only one family member of this unit, this will be skipped
              #since that member has been removed from mbr_family_ids
              mbr_family_ids.each do |mbr_id|
                fm = Member[mbr_id]
                #test to see if any family member's paid up status is > than this one
                if fm.paid_up > params[:paid_up].to_i
                  #bail with error
                  session[:msg] = "UNSUCCESSFUL; family mbr #{fm.fname} #{fm.lname}: paid up, #{fm.paid_up} conflicts with #{m.fname} #{m.lname}: paid_up #{params[:paid_up]}"
                  redirect '/m/unit/list/family'
                end
                fam_names << "\nmbr_id#:#{fm.id}, #{fm.fname}, #{fm.lname}"
                #need to set up audit logs for these guys
                #test to see if paid_up old is different from what is happening with this payment
                if (fm.paid_up != params[:paid_up])
                  fm.paid_up = params[:paid_up]
                  auditlog_hash["#{fm.id}_mbr_paid_up"] = AuditLog.new()
                  auditlog_hash["#{fm.id}_mbr_paid_up"].set("a_user_id" => session[:auth_user_id], "column" => "paid_up",
                    "changed_date" => Time.now, "old_value" => params[:mbr_paid_up_old], "new_value" => params[:paid_up],
                    "mbr_id" => fm.id)
                end
                #test to see if mbr_type old is different from what is happening with this payment
                if (fm.mbr_type != 'family')
                  fm.mbr_type = 'family'
                  auditlog_hash["#{fm.id}_mbr_mbr_type"] = AuditLog.new()
                  auditlog_hash["#{fm.id}_mbr_mbr_type"].set("a_user_id" => session[:auth_user_id], "column" => "mbr_type",
                    "changed_date" => Time.now, "old_value" => params[:mbr_type_old], "new_value" => params[:mbr_type],
                    "mbr_id" => fm.id)
                end
                fm.save
              end
              if mbr_family_ids.length == 0
                log_unit.notes = "there is only one member of this family, sad"
              else
                #add names to log
                log_unit.notes = "#{fam_names.sub("\n",'')} were also updated"
              end
              #make sure family unit is active
              fu = Unit[mbr_family_unit_id]
              if fu.active == 0
                #need to set to 1 so keep auditLog record
                auditlog_hash["al_active"].set("a_user_id" => session[:auth_user_id], "column" => "active",
                  "changed_date" => Time.now, "old_value" => 0, "new_value" => 1)
                al_save = true
              end
              fu.active = 1
              fu.save
            end
            #log these to the auditlog table for the paying member
            if (params[:mbr_paid_up_old] != params[:paid_up])
              auditlog_hash["pay_mbr_paid_up"].set("a_user_id" => session[:auth_user_id], "column" => "paid_up",
              "changed_date" => Time.now, "old_value" => params[:mbr_paid_up_old], "new_value" => params[:paid_up],
              "mbr_id" => params[:mbr_id])
              al_save = true
            end
            if (params[:mbr_type_old] != params[:mbr_type])
              auditlog_hash["pay_mbr_mbr_type"].set("a_user_id" => session[:auth_user_id], "column" => "mbr_type",
              "changed_date" => Time.now, "old_value" => params[:mbr_type_old], "new_value" => params[:mbr_type],
              "mbr_id" => params[:mbr_id])
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
          #also consider impact that this payment makes to the active status of a unit
          if al_save == true
            #if instance for specific (paid_up, mbr_type) auditLog been written to yet, then link payment record
            auditlog_hash.each do |k,v|
              if !v.a_user_id.nil?
                v.pay_id = pay.id
                if params[:mbr_type] == 'family'
                  v.unit_id = mbr_family_unit_id
                end
                v.save
              end
            end
          end          
        end
        session[:msg] = 'Payment was successfully recorded'
      rescue StandardError => e
        session[:msg] = "The data was not entered successfully\n#{e}"
      end
      redirect "/m/payments/show"
    end
    get '/m/payments/edit/:id' do
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
    post '/m/payments/edit' do
      puts "params #{params}"
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
        redirect "/m/payments/edit/#{params[:pay_id]}"
      elsif (pt != pay.paymentType.id.to_s && (payTypes[pt] == "Dues" || payTypes[pay.paymentType.id] == "Dues"))
        #expecting params to be passing ids rather than the text representation
        #need to ask user to delete rather than edit this payment, then start over
        session[:msg] = 'Edit payment was UNSUCCESSFUL (cannot change dues type) please delete this payment and start over'
        redirect "/m/payments/edit/#{params[:pay_id]}"
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
      redirect "/m/payments/show"
    end
    get '/m/payments/show' do
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
        out[:mode] = pmt.paymentMethod[:mode]
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
    get '/m/payments/destroy/:id' do
      @payment = Payment[params[:id]]
      erb :p_destroy, :layout => :layout_w_logout
    end
    post '/m/payments/destroy' do
      #params are {"pay_id"=>"28", "notes"=>"some notes", "confirm"=>"yes"}
      #should only be here to delete Dues payments
      if params[:confirm] != 'Yes'
        #js not enabled, need to find another way to confirm this action
        session[:msg] = "Payment was not deleted, please enable Javascript on your browser"
        redirect '/m/payments/show'
      end
      payment = Payment[params[:pay_id]]
      #if this payment is associated with a unit, look for more recent payments that would need to roll back 1st
      #also, need to test if this payment is associated with a family unit
      #if it is will need to see if other eariler payments were made on this unit
      more_recent_payments = Hash.new
      earlier_dues_unit_payments = false
      if !payment.log.unit.nil?
        unit_log_all = Log.where(unit: payment.log.unit)
        unit_log_all.each do |ul|
          if !ul.payment.nil?
            #get the time the payment associated with this unit if greater than current payment
            if ul.payment.ts > payment.ts
              more_recent_payments[ul.payment.id.to_s] = ul.payment.ts
            elsif ul.payment.ts < payment.ts && PaymentType[payment.payment_type_id].type == "Dues"
              #keep a record of earlier payments for this unit if true, then dont have to change mbr_type to none
              #for all members of the family unit
              earlier_dues_unit_payments = true
            end
          end
        end
      end
      if !more_recent_payments.empty?
        #need to alert the user and exit out of this route
        session[:msg] = "UNSUCCESSFUL, first delete payments made after this one in reverse order, #{more_recent_payments}"
        redirect '/m/payments/show'
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
        audit_log_ids = []
        #load any auditLogs associated with this payment
        #expecting at most, three types of audit logs based on auditLog::column [paid_up, mbr_type, active]
        #generate a hash for each
        array_of_audit_log_hashes = []
        #if there is no audit log throw an error
        if payment.auditLog.empty?
          #need to alert the user and exit out of this route
          session[:msg] = "UNSUCCESSFUL, this payment record does not have an audit trail, cannot delete payment id: #{payment.id}"
          augmented_notes << "\nattempt to delete payment id: #{payment.id} by #{Auth_user[session[:auth_user_id]].member.callsign} failed on #{Time.now.strftime("%m-%d-%y:%H:%M:%S")}"
          log_pay.notes = augmented_notes
          log_pay.save
          redirect '/m/payments/show'
        end
        payment.auditLog.each do |al|
          h = {"a_user_id" => al.a_user_id, "column" => al.column, "old_value" => al.old_value, "new_value" => al.new_value,
            "mbr_id" => al.mbr_id, "unit_id" => al.unit_id}
          array_of_audit_log_hashes << h
          audit_log_ids << al.id
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
            array_of_audit_log_hashes.each do |alh|
              case alh["column"]
              when "paid_up"
                m = Member[alh["mbr_id"]]
                m.paid_up = alh["old_value"]
                m.save
              when "mbr_type"
                m = Member[alh["mbr_id"]]
                if m.mbr_type != alh["old_value"] && alh["old_value"] == 'family'
                  #placing mbr back in a family unit, then need to find unit and add back
                  unit_id = alh["unit_id"]
                  if !unit_id.empty?
                    u = Unit[alh["unit_id"]]
                    u.add_member(m)
                  end
                end
                m.mbr_type = alh["old_value"]
                m.save
              when "active"
                u = Unit[alh["unit_id"]]
                u.active = alh["old_value"]
                u.save
              else
                    #shouldn't be here cuz only three values column
              end
            end
            #enter into existing log (pay?, unit?)
            #check for unit_id, if present, need to add this
            audit_log_ids.each do |al_id|
              AuditLog[al_id].delete
            end
          end#end if dues, nothing special to do for other payments
          payment.delete
        end
        session[:msg] = 'Payment was SUCCESSFULLY deleted'
      rescue StandardError => e
        session[:msg] = "The payment WAS NOT deleted\n#{e}"
      end
      redirect '/m/payments/show'
    end
    get '/m/payments/report/:type/:format?' do
      @rpt_type = "all"
      if !params[:type].nil? #if optional parameter :type is not missing
        @rpt_type = params[:type]
      end
      @pay = []
      if @rpt_type == 'all'
        Payment.join(:members, id: :mbr_id).order(:ts, :payment_type_id, :lname).each do |p|
          temp = {}
          temp[:lname] = p.member.lname
          temp[:fname] = p.member.fname
          temp[:callsign] = p.member.callsign.empty? ? "N/A" : p.member.callsign
          temp[:pay_type] = p.paymentType.type
          temp[:pay_method] = p.paymentMethod.mode
          temp[:pay_amount] = p.payment_amount
          temp[:auth_user] = "#{p.auth_user.member.fname} #{p.auth_user.member.lname}"
          temp[:date] = p.ts.strftime(("%m-%d-%y"))
          temp[:hour] = p.ts.strftime(("%H"))
          @pay << temp
        end
      end
      #need to send :lname, :fname, :callsign, :pay_type, :pay_method, :pay_amount, :auth_user, :date
      if params[:format] == 'csv'
        erb :p_report_csv, :layout => :layout_w_logout
      else
        erb :p_report_html, :layout => :layout_w_logout
      end
    end
    ################### START ADMIN #######################
    get '/a/auth_user/list' do
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
        #get_roles returns a 2D array [[role_id, role_descr],[]] or nil
        roles = Auth_user[u[1]].get_roles
        if roles.nil?
          roles = 'na'
        else
          #need to walk thru and obtain descriptions only
          tmp_roles = []
          roles.each do |r|
            tmp_roles << r[1]
          end
          roles = tmp_roles
        end
        au_hash["roles"] = roles
        @au_list << au_hash
      end
      @au_list
      @tmp_msg = session[:msg]
      session[:msg] = nil
      erb :au_list, :layout => :layout_w_logout
    end
    get '/a/auth_user/role/update/:id' do
      @mbr_to_update = Member.select(:id, :fname, :lname, :callsign, :email)[params[:id].to_i]
      #get role associated with this auth_user
      au = Auth_user.where(mbr_id: params[:id]).first
      @mbr_to_update[:role] = au.role
      @au_roles = Role.map(){|x| [x.rank, x.id, x.description]}
      @au_roles.sort!
      erb :au_roles_update, :layout => :layout_w_logout
    end
    post '/a/auth_user/update' do
      notes_only = false
      #start building the log string
      l = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now, action_id: @action.get_action_id("auth_u"))
      au = Auth_user.where(mbr_id: params[:mbr_id]).first
      old_au_role = au.role.name
      new_au_role = Role[params[:role_id]].name
      #if there's something in notes put a newline after it and add it to the log
      l.notes = params[:notes] == '' ? '' : "#{params[:notes]}\n"
      #was there a role change?
      new_pwd = ''
      if new_au_role == old_au_role
        #look to see if notes were taken
        if params[:notes] == ''
          #nothing was changed get out of here
          session[:msg] = "The Auth User's new role was not different from old: No Change made"
          redirect '/a/auth_user/list'
        else
          notes_only = true
        end
      elsif old_au_role == "inactive"
        #reactivating this auth user so need to reset password
        au.new_login = 1
        #reset password
        new_pwd = SecureRandom.hex[0,6]
        au.password = BCrypt::Password.create(new_pwd)
      end
      l.notes << "role changed from #{old_au_role} to #{new_au_role}"
      begin
        DB.transaction do
          l.save
          if notes_only == false
            au.role_id = params[:role_id]
            au.save
          end
          out_msg = "Success the Auth User has been reassigned"
          if !new_pwd.empty?
            out_msg << "\n new password is #{new_pwd} with username #{Member[params[:mbr_id]].email}, 48 hrs to reset password"
          end
          session[:msg] = out_msg
        end
      rescue StandardError => e
        session[:msg] = "The data was not entered successfully\n#{e}"
      end
      redirect '/a/auth_user/list'
    end
    get '/a/auth_user/role/set/:id' do
      @sel_au_mbr = Member.select(:id, :fname, :lname, :callsign, :email)[params[:id].to_i]
      #won't be setting a newly authorized member as inactive, so pull this from the list
      @roles = Role.exclude(name: 'inactive').order(:rank)
      erb :au_roles_set, :layout => :layout_w_logout
    end
    get '/a/auth_user/create' do
      @tmp_msg = session[:msg]
      session[:msg] = nil
      #only want members who are not already auth users
      existing_au_mbr_ids = Auth_user.map{|x| x.mbr_id}
      @sel_au_from_mbrs = Member.exclude(id: existing_au_mbr_ids).select(:id, :fname, :lname, :callsign, :email).all
      erb :au_create, :layout => :layout_w_logout
    end
    post '/a/auth_user/create' do
      #expecting params keys :notes, :mbr_id, :role_id
      email = Member[params[:mbr_id].to_i].email
      #test for existing user with these credentials
      existing_auth_user = Auth_user.first(mbr_id: params[:mbr_id])
      if !existing_auth_user.nil?
        session[:msg] = 'this auth_user already exists, select update instead of create new'
        redirect "/a/auth_user/create"
      end
      #test for duplicate emails in members table for this user
      member_set = Member.select(:id, :fname, :lname, :callsign, :email).where(email: email).all
      if member_set.length > 1
        mbrs_w_same_email = ""
        member_set.each do |m|
          mbrs_w_same_email << "#{m.fname} #{m.lname}, #{m.callsign}\n"
        end
        mbrs_w_same_email.chomp!()
        session[:msg] = "this auth_user shares email (#{email}) with\n#{mbrs_w_same_email}"
        redirect "/a/auth_user/create"
      end
      #all criteria are passing, go ahead and save this auth_user
      password = SecureRandom.hex[0,6]
      encrypted_pwd = BCrypt::Password.create(password)
      begin
        DB.transaction do
          auth_user = Auth_user.new(:password => encrypted_pwd, :mbr_id => params[:mbr_id].to_i,
            :time_pwd_set => Time.now, :new_login => 1, :last_login => Time.now, :role_id => params[:role_id])
          auth_user.save
          l = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now, action_id: @action.get_action_id("auth_u"))
          l.notes = "New authorized user added\nwith following role #{Role[params[:role_id]].name}"
          if !params[:notes].empty?
            l.notes << "\nNotes: #{params[:notes]}"
          end
          l.save
        end
        session[:msg] = "Success; temp password is #{password} for member #{member_set[0].values[:callsign]} with username #{member_set[0].values[:email]}\n
        they have 48 hrs to reset their password"
        redirect "/a/auth_user/list"
      rescue StandardError => e
        session[:msg] = "error: could not create authorized user.\n#{e}"
        redirect "/a/auth_user/create"
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
