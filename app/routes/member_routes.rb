module MemberTracker
  module MemberRoutes
    def self.registered(app)

      app.get '/r/member/mbr_survey' do
        #used to select members by their answers to jotform survey
        @codes = [{T1: "Portable Operating, SOTA POTA", T2:"Contesting", T3: "Beginner operating tutorials",
        T4: "Technical theory & construction", T5: "Product Demos", T6: "Radio History", T7: "Distance Comms, DX, DXpeditions",
        T8: "Digital Modes: FT8 etc", T9: "Propagation and antennas", T10: "Emergency Preparedness, ARES, RACES",
        T11: "Other"}, {F1: "HF", F2: "VHF/UHF", F3: "Microwave", F4: "Low Frequency (LF)",
        F5: "None of these"}, {M1: "Voice Phone (SSB, FM, etc)", M2: "CW", M3: "Digital (FT8, RTTY, etc)",
        M4: "None, new at this", M5: "Other"},
        {CB1: "Yes, I would like a callback", CB2: "No, I do not want a callback"}]
        #get a summary of the responses
        survey_responses = @member.get_jf_data
        @response_tally = {T1: 0, T2: 0, T3: 0, T4: 0, T5: 0, T6: 0, T7: 0, T8: 0, T9: 0, T10: 0, T11: 0,
          F1: 0, F2: 0, F3: 0, F4: 0, F5: 0, M1: 0, M2: 0, M3: 0, M4: 0, M5: 0, CB1: 0, CB2: 0}
        #tally up the responses by adding to the @codes
        @other_choices = ""
        survey_responses.each do |r|
          r[1].each do |code|
            @response_tally[code.to_sym] += 1
          end
          if !r[3].empty?
            @other_choices << "#{r[3]}\r"
          end
        end
        erb :m_survey, :layout => :layout_w_logout
      end

      app.post '/r/member/mbr_survey' do
        codes = {T1: "Portable Operating, SOTA POTA", T2: "Contesting", T3: "Beginner operating tutorials",
        T4: "Technical theory & construction", T5: "Product Demos", T6: "Radio History", T7: "Distance Comms, DX, DXpeditions",
        T8: "Digital Modes: FT8 etc", T9: "Propagation and antennas", T10: "Emergency Preparedness, ARES, RACES",
        T11: "Topics other", F1: "HF", F2: "VHF/UHF", F3: "Microwave", F4: "Low Frequency (LF)", M1: "Voice Phone (SSB, FM, etc)",
        M2: "CW", M3: "Digital (FT8, RTTY, etc)", M4: "None, new at this", M5: "Modes other", CB1: "Yes, I would like a callback",
        CB2: "No, I do not want a callback"}
        #load query questions passed in params
        @responses_selected_display = []
        responses_selected = []
        col_count = 0
        row_array = []
        params.each do |k,v|
          if col_count > 0
            col_count = 0
            row_array[1] = codes[k.to_sym]
            @responses_selected_display << row_array
          else
            col_count = 1
            row_array = [codes[k.to_sym]]
          end
        end
        if col_count == 1
          @responses_selected_display << row_array
        end
        #now extract members who responded accordingly
        #get symbols for parsing mbrs survey results
        params.each do |k, v|
          responses_selected << k
        end
        mbrs_with_survey_results = @member.get_jf_data
        #pull out those with responses that match query
        mbrs_selected_ids = []
        mbrs_with_survey_results.each do |mbr|
          mbr[1].each do |resp_code|
            #at this point if _any one_ code matches an answer given on jotform, the mbr is added
            #this approach would need to change if wanted to implement AND logic
            if responses_selected.include?(resp_code)
              mbrs_selected_ids << [mbr[0], mbr[2]]
              break
            end
          end
        end
        #get details on the members
        @mbrs_in_survey = []
        emails = []
        @members = DB[:members].as_hash(:id, [:lname, :fname, :callsign, :mbrship_renewal_date,
          :email, :mbr_since])
        mbrs_selected_ids.each do |ids|
          h = {}
          mbr = @members[ids[0]]
          emails << mbr[4]
          h[:mbr_id] = ids[0]
          h[:fname] = mbr[0]
          h[:lname] = mbr[1]
          h[:callsign] = mbr[2]
          h[:ren_date] = mbr[3].strftime("%Y-%m")
          h[:email] = mbr[4].strip
          h[:mbr_since] = mbr[5]
          h[:log_id] = ids[1]
          @mbrs_in_survey << h
        end
        @emails = ""
        emails.each do |em|
          @emails << "#{em.strip}, "
        end
        erb :m_survey_result, :layout => :layout_w_logout
      end

      app.get '/r/member/mbr_rpt' do

        #@current_yr = Date.year
        erb :m_rpt_date_query, :layout => :layout_w_logout
      end

      app.post '/r/member/mbr_rpt' do
        #params: {"date"=>"date_other", "newDate"=>"10/02/22"}
        #{"date"=>"date_today", "newDate"=>""}
        #validate date
        chk_date = nil
        if params[:date] == "date_other"
          begin
             chk_date = Date.strptime(params[:newDate],'%D').prev_year
          rescue StandardError => e
             session[:msg] = "The existing renewal could not be updated\n#{e}"
             redirect '/m/mbr_renewals/show'
          end
        else
          chk_date = Date.today.prev_year
        end
        #members with mbrship_renewal_date > chk_date will be current
        m = DB[:members]
        active_mbrs = m.where{mbrship_renewal_date > chk_date}
        @voting_email = []
        @voting_other = []
        #get contact info for voting purposes
        active_mbrs.each do |am|
          if am[:mbr_type] == 'honorary'
            next
          end
          if am[:email].to_s.empty?
            contact_phone = "#{am[:fname]},#{am[:lname]}"
            [:phw, :phh, :phm].each do |phone|
              if !am[phone].to_s.empty?
                contact_phone << ", #{am[phone]}"
                break
              end
            end
            @voting_other << contact_phone
          else
            contact_email =  "#{am[:fname]},#{am[:lname]},#{am[:email].strip}"
            @voting_email << contact_email
          end
        end
        @rpt = Hash.new
        @rpt[:not_arrl] = active_mbrs.where(arrl: 0).count
        @rpt[:arrl] = active_mbrs.where(arrl: 1).count
        @rpt[:lic_none] = active_mbrs.where(license_class: "none").count
        @rpt[:lic_tech] = active_mbrs.where(license_class: "tech").count
        @rpt[:lic_gen] = active_mbrs.where(license_class: "general").count
        @rpt[:lic_extra] = active_mbrs.where(license_class: "extra").count
        @rpt[:lic_GMRS] = active_mbrs.where(license_class: "GMRS").count
        @rpt[:type_honorary] = active_mbrs.where(mbr_type: "honorary").count
        @rpt[:type_lifetime] = active_mbrs.where(mbr_type: "lifetime").count
        @rpt[:type_family] = active_mbrs.where(mbr_type: "family").count
        @rpt[:type_full] = active_mbrs.where(mbr_type: "full").count
        @rpt[:type_student] = active_mbrs.where(mbr_type: "student").count
        @rpt[:total] = active_mbrs.count
        erb :m_rpt, :layout => :layout_w_logout
      end

      app.get '/r/dump/:table' do
        if params[:table] == 'mbr'
          @m = nil
          @m = Member.all
          @m.each do |m|
            #if !m[:modes].nil?
            #  m[:modes].gsub!(",", "|")
            #end
            #clear out commas and replace callsign
            replaceCallSign = 0
            m.each do |k,v|
              if !m[k].nil? && m[k].is_a?(String)
                m[k].gsub!(",", "|")
                if k == :license_class && m[k] == 'none'
                  replaceCallSign = 1
                end
              end
            end
            if replaceCallSign == 1
              m[:callsign] = 'NO CALL'
            end
          end
          @modes = Member.modes
          erb :m_dump
        else
          redirect '/home'
        end
      end

      app.get '/m/query' do
        erb :query, :layout => :layout_w_logout
      end

      app.post '/m/query' do
        #param keys can be... "paid_up_q", :paid_up_q,
        #  "mbr_full", :mbr_full, "mbr_student", :mbr_student, :mbr_family,
        #  ":mbr_honoqsetrary, "arrl", :arrl, "ares", :ares, "pdxnet", :pdxnet,
        #  "ve", :ve, "elmer", :elmer
        members_temp = nil
        @members = nil
        query_keys = [:paid_up_q, :mbr_full, :mbr_student, :mbr_family,
          :mbr_honorary, :mbr_lifetime, :mbr_none, :arrl, :ares, :pdxnet, :ve, :elmer, :sota]
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
            when  :mbr_full, :mbr_student, :mbr_family, :mbr_honorary, :mbr_none, :mbr_lifetime
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
        #were any keys added to the qset hash?
        if !qset.empty?
          members_temp = Member.select(:id, :fname, :lname, :callsign, :mbrship_renewal_date, :mbr_type).where(qset)
        else
          members_temp = Member.select(:id, :fname, :lname, :callsign, :mbrship_renewal_date, :mbr_type)
        end
        #.as_hash(:id, [:fname, :lname, :callsign, :mbrship_renewal_date, :mbr_type])
        if pu.active == true
          #there is a request for paid up status
          if pu.condition == true
            #asking for members who are paid up through the current year (ie. mbrship_renewal_date > (Today - 1year))
            #@members = Member.where(qset){mbrship_renewal_date >= (Time.now.to_date - 365)}
            paid_up_mbrs = Member.select(:id, :fname, :lname, :callsign, :mbrship_renewal_date, :mbr_type).where{mbrship_renewal_date >= (Time.now.to_date - 365)}
          else
            #asking for members who are NOT paid up through the current year
            paid_up_mbrs = Member.select(:id, :fname, :lname, :callsign, :mbrship_renewal_date, :mbr_type).where{mbrship_renewal_date < (Time.now.to_date - 365)}.exclude(mbr_type: 'none')
          end
          #find intersection of the two
          @members = members_temp.intersect(paid_up_mbrs)
        else
          @members = members_temp
        end
        erb :m_list, :layout => :layout_w_logout
      end

      app.get '/r/member/list/?:event?' do
        @members = DB[:members].select(:id, :lname, :fname, :callsign, :mbrship_renewal_date, :mbr_type).order(:lname, :fname).all
        @tmp_msg = session[:msg]
        session[:msg] = nil
        #if looking for an event contact
        @event = false
        if !params[:event].nil?
          @event = true
        end
        erb :m_list, :layout => :layout_w_logout
      end

      app.get '/r/member/show/:id' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        @member = Member[params[:id]]
        if @member.nil?
          session[:msg] = "Member not found"
          redirect '/r/member/list'
        end
        #look for requests for a callby this member
        @call_requests = MemberAction.where(member_target: params[:id], completed: false).all
        @mbr_renewals = DB[:mbr_renewals].select(:id, :a_user_id, :renewal_event_type_id,
          :notes, :ts).where(mbr_id: params[:id]).all
        #replace authorized user id, event type id
        if !@mbr_renewals.empty?
          @mbr_renewals.each do |mr|
            mr.store(:a_user_id, AuthUser[mr[:a_user_id]].member.callsign)
            mr.store(:renewal_type, RenewalEventType[mr[:renewal_event_type_id]].name)
          end
        end
        mbr_dues_payments = DB[:payments].select(:id, :ts, :a_user_id).where(payment_type_id: 5, mbr_id: params[:id]).all
        #replace authorized user id, and add event type = renewal
        if !mbr_dues_payments.empty?
          mbr_dues_payments.each do |md|
            md.store(:a_user_id, AuthUser[md[:a_user_id]].member.callsign)
            md.store(:renewal_type, "dues payment")
          end
        end
        @mbr_renewals.concat(mbr_dues_payments)
        @mbr_renewals.sort_by!{|r| r[:ts]}

        #build mbr donations hash
        @mbr_donations = {}
        tmp_mbr_donations = DB[:payments].select(:id, :payment_type_id, :ts, :payment_amount)
          .where(payment_type_id: [1,2,3,4], mbr_id: params[:id]).reverse_order(:ts).all
        tmp_mbr_donations.each do |d|
          p_type_str = DB[:payment_types].where(id: d[:payment_type_id]).first
          @mbr_donations[d[:id]] = {payment_type: p_type_str[:type], date: d[:ts].strftime("%m/%d/%Y"), amount: d[:payment_amount]}
        end
        #convert mbrship_renewal_date
        if !@member[:mbrship_renewal_date].nil?
          rd = @member[:mbrship_renewal_date].to_date + 365
          if rd < Date.today
            @member[:renew_due] = true
          else
            @member[:renew_due] =  false
          end
        end
        @modes = Member.modes
        if @member[:modes] == '' || @member[:modes].nil?
          @member[:modes] = 'none'
        end
        erb :m_show, :layout => :layout_w_logout
      end

      app.get '/m/member/edit/:id' do
        @existing_mbrs = []
        @member = Member[params[:id]]
        if @member.nil?
          session[:msg] = "Member not found"
          redirect '/r/member/list'
        end
        @modes = Member.modes
        if @member[:modes] == '' || @member[:modes].nil?
          @member[:modes] = 'none'
        end
        #look for requests to call from this member and if there is one, check that it is the only one uncompleted
        call_requests = []
        member_call_action_type_id = MemberActionType.where(name: "call_member").first[:id]
        @member.member_actions.each do |ma|
          if ma.member_action_type_id == member_call_action_type_id
            call_requests << ma
          end
        end
        #if there are any call requests, check that they are all completed
        call_request_count = 0
        if call_requests.length > 0
          #check that only one is uncompleted
          call_requests.each do |cr|
            if cr.completed == false
              call_request_count += 1
              if call_request_count > 1
                #we have more than one uncompleted call request
                @member[:call_request] = "There are multiple uncompleted call requests for this member"
                break
              else
                #we have only one uncompleted call request
                if cr.notes != ''
                  @member[:call_request] = cr.notes
                else
                  @member[:call_request] = 'none'
                end
              end
            end
          end
        else
          @member[:call_request] = nil
        end
        @member[:call_request_length] = call_request_count
        erb :m_edit, :layout => :layout_w_logout
      end

      app.get '/m/member/create' do
        #need to avoid dups when creating a new member
        @existing_mbrs = []
        #removed , :mbrship_renewal_date => DateTime.now
        @member = {:lname => '', :modes => ''}
        @modes = Member.modes
        erb :m_edit, :layout => :layout_w_logout
      end

      app.post '/m/member/create' do
        params_hash = params.to_hash
        #{"fname"=>"DAVE", "lname"=>"BURLEIGH", "callsign"=>"kn6tdv", "email"=>"", "callme"=>"on", "callwhy"=>"", "email_bogus"=>"false", "ok_to_email"=>"true", "street"=>"", "city"=>"", "state"=>"", "zip"=>"", "phh"=>"", "phh_pub"=>"0", "phw"=>"", "phw_pub"=>"0", "phm"=>"", "phm_pub"=>"0", "license_class"=>"tech", "mbr_since"=>"2022-03", "notes"=>"", "refer_type_id"=>"none", "mbrship_renewal_date"=>"", "arrl"=>"0", "ares"=>"0", "net"=>"0", "ve"=>"0", "elmer"=>"0", "id"=>"827", "mode_phone"=>"0", "mode_cw"=>"0", "mode_rtty"=>"0", "mode_msk:ft8/jt65"=>"0", "mode_digital:other"=>"0", "mode_packet"=>"0", "mode_psk31/63"=>"0", "mode_video:sstv"=>"0", "mode_mesh"=>"0"}
        #this route used to update an existing member or save a new member
        #have to deal with request for a call from this member
        call_request = params_hash["callme"]
        params_hash.reject!{|k,v| k == "callme"}
        call_why = params_hash["callwhy"]
        params_hash.reject!{|k,v| k == "callwhy"}
        #these will be used to avoid dups when creating a new member
        @existing_mbrs = []
        @mbr = {}
        #this action is also logged
        mbr_id = params_hash[:id]
        #save notes for log
        notes = params_hash[:notes]
        params_hash.reject!{|k,v| k == 'notes'}
        logPayment = params_hash[:payment]
        params_hash.reject!{|k,v| k == 'payment'}
        #the js form validator that uses regex inserts a captures key
        #in the returning params. need to pull this out too
        params_hash.reject!{|k,v| k == "captures"}
        if params_hash[:refer_type_id] == 'none'
          params_hash.reject!{|k,v| k == 'refer_type_id'}
        end
        #need to pack all of the modes
        modes = ""
        params_hash.each do |k,v|
          mode_key = /mode_(.*)$/.match(k)
          if  mode_key.respond_to?("[]") && v == "1"
            modes << "#{Member.modes.key(mode_key[1])},"
          end
        end
        #remove these k,v pairs and add packed modes back
        params_hash.reject! {|k,v| /mode_/.match(k)}
        params_hash["modes"] = modes[0...-1]
        #this could be a new member or existing member
        if mbr_id == ''
          #new member
          params_hash.reject!{|k,v| k == "id"}
          #the start date has been set in the erb file
          params_hash[:mbr_since] = Date.strptime(params_hash[:mbr_since], '%Y-%m')
          #set the character case to upper for name and email
          params_hash[:fname] = params_hash[:fname].upcase
          params_hash[:lname] = params_hash[:lname].upcase
          params_hash[:email] = params_hash[:email].upcase.lstrip
          #if coming back with override = 1, let this go through, else...
          if !params_hash.has_key?("override")
            #need to validate that this member is not already in the db
            #@existing_mbrs = Member.where(fname: params[:fname], lname: params[:lname]).all
            dupe_test_result = @member.validate_dupes({fname: params_hash[:fname], lname: params_hash[:lname]})
            if dupe_test_result > 0
              #we have a possible existing member here
              @member = Member[dupe_test_result]
              @mbr = params_hash
              @modes = Member.modes
              @member[:modes] = 'none' if @member[:modes].nil? || @member[:modes].empty?
              @member[:call_request] = nil
              @member[:call_request_length] = 0
              #Send this back for validation
              @tmp_msg = "looks like this member has already been entered into our db, need to update?"
              return erb :m_edit, :layout => :layout_w_logout
            end
          end
          #set the default mbr_type until a payment is made (this is also done on mbrs table)
          #note, none is also used to describe a 'guest'
          params_hash[:mbr_type] = 'none'
          #check callsign and license class TODO also, this should be an associate member if paying
          if params_hash[:license_class] == 'none'
            if params_hash[:callsign] == ''
              #need to put a standardized non-callsign if empty
              params_hash[:callsign] = 'NO CALL'
            else
              #TODO reject this as there has to be a license class with a callsign
              #still need to pass existing params_hash back to new/edit member form
              #session[:msg] = "The new member could not be created\nneed a license class"
              #redirect "/r/member/show/#{mbr_id}"
            end
          else
            if params_hash[:callsign] == ''
              #TODO reject this need a callsign if license class is other than none
              #still need to pass existing params back to new/edit member form
              #session[:msg] = "The new member could not be created\nneed a callsign"
              #redirect "/r/member/show/#{mbr_id}"
            end
          end
          mbr_record = Member.new(params_hash)
          begin
            DB.transaction do
              #save the new member
              mbr = mbr_record.save
              mbr_id = mbr.id
              #log the action
              augmented_notes = "**** New Member entry\n#{notes}"
              l = Log.new(mbr_id: mbr_id, a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes, action_id: Action.get_action_id("mbr_edit"))
              l.save
              #if there is a call request, add it to the member_actions table
              if call_request == 'on'
                #create a new member action
                ma = MemberAction.new(member_id: mbr.id, member_action_type_id: MemberActionType.where(name: "call_member").first.id,
                  notes: call_why, completed: false, a_user_id: session[:auth_user_id])
                ma.save
                log_call = Log.new(mbr_id: mbr.id, a_user_id: session[:auth_user_id], ts: Time.now,
                  notes: "call request:#{call_why}", action_id: Action.get_action_id("mbr_call_me"))
                log_call.save
              end
              #if there is a referral type, add it to the member_actions table
              if !params_hash[:refer_type_id].nil?
                if params_hash[:refer_type_id] != 'none'
                  ma = MemberAction.new(member_id: mbr.id, member_action_type_id: MemberActionType.where(name: "referral").first.id,
                    notes: params_hash[:refer_type_id], completed: false, a_user_id: session[:auth_user_id])
                  ma.save
                end
              end
            end
            session[:msg] = "The new member was successfully entered"
          rescue StandardError => e
            session[:msg] = "The new member could not be created\n#{e}"
          end
        else
          #existing member
          mbr_record = Member[params_hash[:id]]
          params_hash.reject!{|k,v| k == "id"}
          params_hash["mbr_since"] = Date.strptime(params_hash["mbr_since"], '%Y-%m')
          #set the character case to upper for name, email and callsign
          params_hash["fname"] = params_hash["fname"].upcase
          params_hash["lname"] = params_hash["lname"].upcase
          params_hash["email"] = params_hash["email"].upcase.lstrip
          #fix renewal date if there is one
          if params_hash["mbrship_renewal_date"] != ""
            params_hash["mbrship_renewal_date"] = Date.strptime(params_hash["mbrship_renewal_date"],'%D')
          else #remove this key
            params_hash.delete("mbrship_renewal_date")
          end
          params_hash["callsign"].empty? ? nil : params_hash["callsign"] = params_hash["callsign"].upcase
          #log a change in callsign
          if !mbr_record["callsign"].nil?
            if params_hash["callsign"] != mbr_record["callsign"].upcase
              augmented_notes << "\nchange_call:#{mbr_record["callsign"]}:#{params_hash["callsign"]}"
            end
          else
            if !params_hash["callsign"].empty?
              if notes.empty?
                notes << "add_call:#{params_hash["callsign"]}"
              else
                notes << "\nadd_call:#{params_hash["callsign"]}"
              end
            end
          end
          begin
            DB.transaction do
              mbr_record.update(params_hash)
              augmented_notes = "**** Existing Member update\n#{notes}"
              l = Log.new(mbr_id: mbr_record.id, a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes, action_id: Action.get_action_id("mbr_edit"))
              l.save
              #if there is a call request, add it to the member_actions table
              if call_request == 'on'
                #create a new member action
                ma = MemberAction.new(member_target: mbr_record.id, member_action_type_id: MemberActionType.where(name: "call_member").first.id,
                  notes: call_why, completed: false, a_user_id: session[:auth_user_id], ts: Time.now)
                ma.save
                log_call = Log.new(mbr_id: mbr_record.id, a_user_id: session[:auth_user_id], ts: Time.now,
                  notes: "call request:#{call_why}", action_id: Action.get_action_id("mbr_call_me"))
                log_call.save
              end
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

      app.get '/m/member/refer/type/list/:id' do
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

      app.get '/m/member/refer/type/create/?:id?' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        @edit_refer_type = nil
        if !params[:id].nil?
          @edit_refer_type = ReferType[params[:id]]
        end
        @refer_types = ReferType.all
        erb :m_refer_type_create, :layout => :layout_w_logout
      end

      app.post '/m/member/refer/type/create/:id?' do
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
          l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, notes: rt_notes, action_id: Action.get_action_id("mbr_edit"))
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

    end
  end
end
