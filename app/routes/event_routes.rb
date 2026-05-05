module MemberTracker
  module EventRoutes
    def self.registered(app)

      app.get '/r/event/attendance' do
        #build event type selection list
        @event_types = EventType::EVENT_TYPE_OPTIONS
        erb :e_attendance_query, :layout => :layout_w_logout
      end

      app.post '/r/event/attendance' do
        #temporary warning for unavailable data
        @no_data = nil
        #for now only building attendance report for general meetings
        @attendance_data = nil
        event_type_options = EventType::EVENT_TYPE_OPTIONS
        #which option was selected?
        selected_type = nil
        event_type_options.each do |key, value|
          if params["event_type_id"] == key
            selected_type = key
            break
          end
        end
        if selected_type.nil?
          session[:msg] = "Invalid event type selection"
          redirect '/r/event/attendance'
        else
          #set up switch for selected type
          case selected_type
          when '1' #general meeting
            member_mtng_counts = @event.member_count()
            #combine hashes by event_date keeping counts separate for each event type
            #want data structure like:
            # {event_date1: {old_format: x, inperson: y, zoom: z}, event_date2: {...}, ...}
            # first get list of all event dates
            event_dates = []
            member_mtng_counts.each do |mtng|
              if !event_dates.include?(mtng[:event_date])
                event_dates << mtng[:event_date]
              end
            end
            #now build out the combined hash
            #for now (monthly-inperson => 10, monthly-on_zoom => 11 and monthly meeting OLD => 2)
            #obtaind from EventType::EVENT_TYPE_OPTIONS
            combined_counts = Hash.new
            event_dates.each do |ed|
              combined_counts[ed] = {old_format: 0, inperson: 0, zoom: 0}
              member_mtng_counts.each do |mtng|
                if mtng[:event_date] == ed
                  case mtng[:event_type_id]
                  when 2 #old format meeting
                    combined_counts[ed][:old_format] = mtng[:member_count]
                  when 10 #inperson meeting
                    #puts "found inperson meeting for date #{ed} and count #{mtng[event_type_id: 10][:member_count]}\n"
                    combined_counts[ed][:inperson] = mtng[:member_count]
                  when 11 #zoom meeting
                    combined_counts[ed][:zoom] = mtng[:member_count]
                  else
                    puts "unknown meeting type #{mtng[:event_type_id]}\n"
                    #do nothing
                  end
                  #add :id, :name and :descr from mtng to @attendance_data
                  combined_counts[ed][:event_id] = mtng[:event_id]
                  combined_counts[ed][:name] = mtng[:event_name]
                  combined_counts[ed][:descr] = mtng[:description]
                end
                @attendance_data = combined_counts
              end
            end
          when '2' #POTA
            puts "POTA selected"
          when '3' #field day
            puts "field day selected"
          when '4' #holiday & bbq
            puts "holiday & bbq selected"
          when '5' #board meeting
            puts "board meeting selected"
          else
            puts "other event type selected"
          end
        end
        if combined_counts.nil?
          puts "no data found"
        else
          #summarize by event date
          event_date_sum = 0
          #select only member count keys
          @attendance_data.each do |k,v|
            v.each do |type, count|
              if [:old_format, :inperson, :zoom].include?(type)
                event_date_sum += count
              end
            end
            #add event date total to hash
            v[:event_date_total] = event_date_sum
            event_date_sum = 0 #reset for next date
          end
        end
        #finally, sort by event date descending
        @attendance_data = @attendance_data.sort_by{|k,v| k}.reverse.to_h
        erb :e_attendance, :layout => :layout_w_logout
      end

      app.get '/m/event/edit/:id' do
        @event = Event[params[:id]]
        if @event.nil?
          session[:msg] = "Event not found"
          redirect '/m/event/list/all'
        end
        @event_types = EventType.all
        @mbrs = Member.select(:id, :fname, :lname, :callsign).all
        #need to parse the log; should be in two parts 1) general notes 2) guest's not added to db
        #notes = @event.log.first.notes.split("\n")
        prev_event_log = @event.log_dataset.order(:id).where(action_id: Action.get_action_id("event")).all.pop
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

      app.get '/m/event/create' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        @event_types = EventType.all
        @mbrs = Member.select(:id, :fname, :lname, :callsign).all
        erb :e_create, :layout => :layout_w_logout
      end

      app.post '/m/event/create' do
       #params {"general_notes"=>"a newer one", "event_type_id"=>"1", "name"=>"andSo", "descr"=>"a desc",
        #"duration"=>"3" OR "none", "duration_units"=>"hrs", "guest_notes"=>"last,name;last2,name2",
        #"g0:fname"=>"Myron", "g0:lname"=>"Dembo", "g0:callsign"=>"A7MYR", "g0:email"=>"*guest email",
        #"g0:notes"=>"some notes for guest0",..., "mbr_id"=>"478", "id:481"=>"1", "id:479"=>"1"}

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
        l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: Action.get_action_id("event"))
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
                #test for duplicates. expecting 0 not a dupe, any mbr_id is a dupe
                if @member.validate_dupes(ng) > 0
                  #Houston, we have a problem
                  guest.duplicate << ng
                  guest.msng_values = "A guest with same credentials as a member was found. #{ng}"
                  next
                end
                #need to add guests to database before adding them to this event
                log_guest = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: Action.get_action_id("mbr_edit"), event_id: event.id)
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

      app.get '/m/event/type/create/:id?' do
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

      app.post '/m/event/type/create/:id?' do
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
        l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: Action.get_action_id("event"))
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

      app.get '/m/event/list/:id' do
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

      app.get '/m/event/attendees/show/:id' do
        @event = Event[params[:id]]
        @attendees =[]
        @attendee_emails = ''
        @attendee_list = ''
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
            :callsign => mbr.callsign, :mbrship_renewal_date => mbr.mbrship_renewal_date,
            :mbrship_renewal_active => mbr.mbrship_renewal_active, :mbr_type => mbr.mbr_type, :attendance => et_hash}
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
          #look for honorary members and give them a current mbrship_renewal_date and move renewal date up one year
          if mbr_tmp_hash[:mbr_type] == 'honorary'
            mbr_tmp_hash[:mbrship_renewal_date] = Date.today >> 1
          elsif !mbr_tmp_hash[:mbrship_renewal_date].nil?
            mbr_tmp_hash[:mbrship_renewal_date] = mbr_tmp_hash[:mbrship_renewal_date].to_date.next_year
          else
            mbr_tmp_hash[:mbrship_renewal_date] = 'none'
          end
          @attendees << mbr_tmp_hash
          @attendee_list << "#{mbr_tmp_hash[:fname]} #{mbr_tmp_hash[:lname]}, "
          if !mbr.email.nil?
            @attendee_emails << "#{mbr.email},"
          end
          mbr_tmp_hash = {}
        end
        #clean up attendee list
        @attendee_list.chomp!(', ')
        #clean up email list
        @attendee_emails.chomp!(',')
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

    end
  end
end
