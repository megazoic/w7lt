module MemberTracker
  module RenewalRoutes
    def self.registered(app)

      app.get '/m/mbr_renewals/show' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        #get members with active renewals
        @active_members = []
        DB[:members].select(:id, :fname, :lname, :callsign, :mbrship_renewal_contacts, :mbrship_renewal_date).where(mbrship_renewal_active: true).each do |am|
          @active_members << am
        end
        #need to change the renewal date to add 1 yr and add k,v for renewals active > 4 weeks
        @active_members.each do |am|
          if !am[:mbrship_renewal_date].nil?
            am[:mbrship_renewal_date] = am[:mbrship_renewal_date].to_date.next_year
            if am[:mbrship_renewal_date] < Date.today << 1
              am[:is_past_due] = true
            else
              am[:is_past_due] = false
            end
          else
            #substitue the missing date
            am[:mbrship_renewal_date] = "no date"
          end
        end
        #get data from table mbr_renewals and display
        mrs = DB[:mbr_renewals].where(ts: (Date.today - 365)..(Date.today)).order(:ts).all
        @renewals = []
        mrs.each do |mr|
          @renewals << {id: mr[:id], fname: Member[mr[:mbr_id]].fname, lname: Member[mr[:mbr_id]].lname,
            callsign: Member[mr[:mbr_id]].callsign, recorded_by: AuthUser[mr[:a_user_id]].member.callsign,
            event_type: RenewalEventType[mr[:renewal_event_type_id]].name, mbr_id: mr[:mbr_id],
            notes: mr[:notes], ts: mr[:ts]}
        end
        mbr_dues_payments = DB[:payments].select(:id, :ts, :a_user_id, :mbr_id).where(payment_type_id: 5, ts: (Date.today - 365)..(Date.today)).order(:ts).all
        #replace authorized user id, and add event type = renewal
        if !mbr_dues_payments.empty?
          mbr_dues_payments.each do |md|
            md.store(:recorded_by, AuthUser[md[:a_user_id]].member.callsign)
            md.store(:event_type, "dues payment")
            md.store(:fname, Member[md[:mbr_id]].fname)
            md.store(:lname, Member[md[:mbr_id]].lname)
            md.store(:callsign, Member[md[:mbr_id]].callsign)
          end
        end
        @renewals.concat(mbr_dues_payments)
        @renewals.sort_by!{|r| r[:ts]}
        @renewals.reverse!
        erb :m_rnwal_show, :layout => :layout_w_logout
      end

      app.get '/m/mbr_renewals/edit/:id' do
        mr = MbrRenewal[params[:id]].values
        @mbr_renewal = {mbrship_renewal_date: Member[mr[:mbr_id]].mbrship_renewal_date,
          mbrship_renewal_halt: Member[mr[:mbr_id]].mbrship_renewal_halt,
          mbrship_renewal_active: Member[mr[:mbr_id]].mbrship_renewal_active,
          mbrship_renewal_contacts: Member[mr[:mbr_id]].mbrship_renewal_contacts,
          fname: Member[mr[:mbr_id]].fname, lname: Member[mr[:mbr_id]].lname}
        @mbr_renewal.merge!(mr)
        @renewal_event_types_array = DB[:renewal_event_types].select(:id, :name).all
        erb :m_rnwal_edit, :layout => :layout_w_logout
      end

      app.post '/m/mbr_renewals/edit' do
        #{"rnwal_id"=>"1", "mbrship_renewal_date"=>"10/22/22", "mbrship_renewal_halt"=>"true", "mbrship_renewal_active"=>"false", "mbrship_renewal_contacts"=>"0", "event_type"=>"2", "notes"=>"test new"}
        #check date
        begin
           Date.strptime(params[:mbrship_renewal_date],'%D')
        rescue StandardError => e
           session[:msg] = "The existing renewal could not be updated\n#{e}"
           redirect '/m/mbr_renewals/show'
        end
        rdate = Date.strptime(params[:mbrship_renewal_date],'%D')
        if (rdate.year < 2020 || rdate.year > Date.today.year + 2)
          session[:msg] = "The existing renewal could not be updated: Incorrect renewal year"
          redirect '/m/mbr_renewals/show'
        end
        mbr_renewal_record =
         DB[:mbr_renewals].select(:a_user_id, :renewal_event_type_id, :notes, :ts, :mbr_id).where(id: params[:rnwal_id]).first
        member_record = DB[:members].select(:mbrship_renewal_date, :mbrship_renewal_halt,
         :mbrship_renewal_active, :mbrship_renewal_contacts, :email_bogus).where(id: mbr_renewal_record[:mbr_id]).first
        #check to see what has changed and enter that into log
        member_record[:mbrship_renewal_date] = member_record[:mbrship_renewal_date].strftime("%D")
        augmented_notes = ""
        #if there is event_type pointing to 'bogus email' then need to set that field to 'true'
        bogus_email_id = RenewalEventType::getID("bogus email").to_s
        if bogus_email_id == params[:event_type]
          if member_record[:email_bogus] == false
            #replace params k,v with :email_bogus = true
            params.delete(:event_type)
            params[:email_bogus] = true
          end
        end
        member_record.each do |k, v|
          if v.to_s != params[k]
            augmented_notes << "#{k}: old record #{member_record[k]}, new record #{params[k]}\n"
          end
        end
        if params.has_key?(:event_type)
          if mbr_renewal_record[:renewal_event_type_id] != params[:event_type].to_i
            augmented_notes << "old event type: #{RenewalEventType[mbr_renewal_record[:renewal_event_type_id]].name},
            new event type: #{RenewalEventType[params[:event_type].to_i].name}\n"
          end
        else
          #dealing with 'bogus email' event type
          augmented_notes << "old event type: #{RenewalEventType[mbr_renewal_record[:renewal_event_type_id]].name},
          new event type: bogus email\n"
          #need to add the key :event_type back in
          params[:event_type] = bogus_email_id
        end
        if mbr_renewal_record[:notes] != params[:notes]
          augmented_notes << "old notes #{mbr_renewal_record[:notes]},
          new notes #{params[:notes]}\n"
        end
        old_a_user_cs = Member[AuthUser[mbr_renewal_record[:a_user_id]].values[:mbr_id]].callsign
        new_a_user_cs = Member[AuthUser[session[:auth_user_id]].values[:mbr_id]].callsign
        if old_a_user_cs != new_a_user_cs
          augmented_notes << "old authorized user: #{old_a_user_cs}, new authorized user: #{new_a_user_cs}"
        end
        begin
          DB.transaction do
            MbrRenewal[params[:rnwal_id]].update({a_user_id: session[:auth_user_id], renewal_event_type_id: params["event_type"],
              notes: params[:notes], ts: DateTime.now})
            params.delete_if{|k,v| ["rnwal_id", "event_type", "notes"].any?(k)}
            #only update values that have changed
            params.each do |k,v|
              #:mbrship_renewal_date, :mbrship_renewal_halt, :mbrship_renewal_active, :mbrship_renewal_contacts
              if member_record[k] == v
                params.delete(k)
              end
            end
            #need to change params[:mbrship_renewal_date] to date
            params[:mbrship_renewal_date] = Date.strptime(params[:mbrship_renewal_date],'%D')
            Member[mbr_renewal_record[:mbr_id]].update(params)
            l = Log.new(mbr_id: mbr_renewal_record[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes, action_id: Action.get_action_id("mbr_renew"))
            l.save
          end
          session[:msg] = "The existing renewal record was successfully updated"
        rescue StandardError => e
          session[:msg] = "The existing renewal could not be updated\n#{e}"
        end
        redirect '/m/mbr_renewals/show'
      end

      app.get '/m/mbr_renewals/new/:id' do
        #need to associate with a member (the :id in the url)
        @mbr_renewal = DB[:members].select(:id, :lname, :fname, :callsign, :mbrship_renewal_date, :mbrship_renewal_halt,
        :mbrship_renewal_active, :mbrship_renewal_contacts).where(id: params[:id]).first
        @tmp_msg = session[:msg]
        session[:msg] = nil
        @renewal_event_types_array = DB[:renewal_event_types].select(:id, :name).all
        erb :m_rnwal_new, :layout => :layout_w_logout
      end

      app.post '/m/mbr_renewals/new' do
        #params are: {"mbr_id"=>"330", "mbrship_renewal_date"=>"02/01/22", "mbrship_renewal_halt"=>"false", "mbrship_renewal_active"=>"false", "mbrship_renewal_contacts"=>"1", "event_type"=>"3", "notes"=>"Enter notes here"}
        #----------------------check date------------------------------------------
        begin
           Date.strptime(params[:mbrship_renewal_date],'%D')
        rescue StandardError => e
           session[:msg] = "The existing renewal could not be updated\n#{e}"
           redirect '/m/mbr_renewals/show'
        end
        rdate = Date.strptime(params[:mbrship_renewal_date],'%D')
        if (rdate.year < 2020 || rdate.year > Date.today.year + 2)
          session[:msg] = "The existing renewal could not be updated: Incorrect renewal year"
          redirect '/m/mbr_renewals/show'
        end
        #fix params date string to date object
        params[:mbrship_renewal_date] = Date.strptime(params["mbrship_renewal_date"],'%D')
        #----------------------end check date--------------------------------------
        #see if there are any changes to be made to the members table
        member = DB[:members].select(:mbrship_renewal_date, :mbrship_renewal_halt,
          :mbrship_renewal_active, :mbrship_renewal_contacts).where(id: params[:mbr_id]).first
        #clean up params
        mbr_id = params.delete(:mbr_id)
        event_type = params.delete(:event_type)
        notes = params.delete(:notes)
        #need to convert the member record datetime to a date
        member[:mbrship_renewal_date] = member[:mbrship_renewal_date].to_date
        #remove from hash if no change to be made
        member.delete_if {|k,v| params[k] == v}
        #update the remaining member hash with values from param
        member.each do |k,v|
          member[k] = params[k]
        end
        #if mbr_renewal_event_type is bogus_email need to update email_bogus in members table
        if event_type == RenewalEventType::getID("bogus email").to_s
          member[:email_bogus] = true
        end
        #create a new membership renewal data point
        mbr_renewals = DB[:mbr_renewals]
        begin
          DB.transaction do
            #write members table data
            if !member.empty?
              DB[:members].where(id: mbr_id).update(member)
            end
            #write renewals table data
            DB[:mbr_renewals].insert(a_user_id: session[:auth_user_id], mbr_id: mbr_id, renewal_event_type_id: event_type,
              notes: notes, ts: DateTime.now)
              #check if renewal_event_type_id is 'no response' and if so, add to members_actions table
              #need to add a non_renew_followup action
            if event_type == RenewalEventType::getID("no response").to_s
              #need to add a member action for followup
              mbr_action = DB[:member_actions]
              mbr_action.insert(member_target: mbr_id, member_action_type_id: MemberActionType[name: 'non_renew_followup'].id,
                tasked_to_mbr_id: nil, a_user_id: session[:auth_user_id], notes: "Follow up with member for non-renewal",
                ts: DateTime.now, completed: false)
              #add log entry for this action
              l = Log.new(mbr_id: mbr_id, a_user_id: session[:auth_user_id], ts: Time.now,
                notes: "Added member action for non-renewal followup", action_id: Action.get_action_id("mbr_renew"))
              l.save
            end
          end
          session[:msg] = 'Renewal was successfully recorded'
        rescue StandardError => e
          session[:msg] = "The data was not entered successfully\n#{e}"
        end
        redirect '/m/mbr_renewals/show'
      end

      app.get '/m/mbr_renewals/destroy/:id' do
        renewal_record = MbrRenewal[params[:id]]
        @mbr_renewal_record = {id: params[:id], fname: Member[renewal_record[:mbr_id]].fname, lname: Member[renewal_record[:mbr_id]].lname,
            recorded_by: AuthUser[renewal_record[:a_user_id]].member.callsign, mbr_callsign: Member[renewal_record[:mbr_id]].callsign,
            event_type: RenewalEventType[renewal_record[:renewal_event_type_id]].name,
            notes: renewal_record[:notes], ts: renewal_record[:ts]}
        erb :rnwl_record_destroy, :layout => :layout_w_logout
      end

      app.post '/m/mbr_renewals/destroy' do
        if params[:confirm] != 'Yes'
          #js not enabled, need to find another way to confirm this action
          session[:msg] = "Rnwl Record was not deleted, please enable Javascript on your browser"
          redirect '/m/mbr_renewals/show'
        end
        mbr_renewal_records = DB[:mbr_renewals]
        rnwl = mbr_renewal_records.where(id: params[:rnwl_id]).first
        rnwl_auser = AuthUser[rnwl[:a_user_id]].member.callsign
        rnwl_event_type = RenewalEventType[rnwl[:renewal_event_type_id]][:name]
        rnwl_event_date = rnwl[:ts].strftime("%D")
        autmented_notes = "deletion of member renewal record. Prev notes: #{rnwl[:notes]}\nReason for delete notes: #{params[:notes]}\nPrev authorized by #{rnwl_auser},
          rnwl event type: #{rnwl_event_type}\n, on date #{rnwl_event_date}"
        l = Log.new(mbr_id: rnwl[:mbr_id], a_user_id: session[:auth_user_id],
          ts: Time.now, notes: autmented_notes, action_id: Action.get_action_id("mbr_renew"))
        begin
          mbr_renewal_records.where(id: params[:rnwl_id]).delete
          l.save
          session[:msg] = 'Renewal record was SUCCESSFULLY deleted'
        rescue StandardError => e
          session[:msg] = "The renewal record WAS NOT deleted\n#{e}"
        end
        redirect '/m/mbr_renewals/show'
      end

      app.get '/m/mbr_non_renewals/edit/:id' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        @mbr_action = DB[:member_actions].where(id: params[:id]).first
        @mbr_action[:tasked_to_mbr_id] = @mbr_action[:tasked_to_mbr_id].nil? ? "NONE" : @mbr_action[:tasked_to_mbr_id]
        @mbr_action[:target_member_name] = "#{Member[@mbr_action[:member_target]].fname} #{Member[@mbr_action[:member_target]].lname}"
        @mbr_action[:target_member_id] = @mbr_action[:member_target]
        @mbr_action[:action_type] = DB[:member_action_types].where(id: @mbr_action[:member_action_type_id]).first[:descr]
        #get list of members that are authorized users to assign to this action
        mbr_id_hash = DB[:auth_users].select(:mbr_id).exclude(role_id: Role[:name => "inactive"].id).all
        mbr_ids = mbr_id_hash.map{|x| x[:mbr_id]}
        @mbrs = DB[:members].select(:id, :fname, :lname, :callsign).where(id: mbr_ids).all
        erb :m_non_renew_edit, :layout => :layout_w_logout
      end

      app.post '/m/mbr_non_renewals/update/:id' do
        #used to _update_ a member action record for non_renewals, _not_ to add a note
        #params are {"id"=>"AN ID IN MEMBER_ACTIONS TABLE", "tasked_to_mbr_id"=>"A MEMBER ID", "completed"=>"" (OR "on"), "notes"=>"some notes"}
        #get existing member action
        mbr_action = DB[:member_actions].where(id: params[:id]).first
        updated_mbr_action = {}
        updated_mbr_action[:a_user_id] = session[:auth_user_id]
        updated_mbr_action[:notes] = params[:notes]
        updated_mbr_action[:ts] = DateTime.now
        updated_mbr_action[:completed] = params[:completed].nil? ? false : true
        updated_mbr_action[:id] = params[:id].to_i
        updated_mbr_action[:tasked_to_mbr_id] = nil
        if params[:tasked_to_mbr_id] != ''
          updated_mbr_action[:tasked_to_mbr_id] = params[:tasked_to_mbr_id].to_i
        end
        #check to see if there are any changes to be made to the member_actions table
        if mbr_action[:tasked_to_mbr_id] != updated_mbr_action[:tasked_to_mbr_id] ||
           mbr_action[:notes] != updated_mbr_action[:notes] ||
           mbr_action[:completed] != updated_mbr_action[:completed]
          begin
            DB.transaction do
              DB[:member_actions].where(id: params[:id]).update(updated_mbr_action)
              #add log entry for this action
              log_notes = MemberAction.build_log_notes(mbr_action, updated_mbr_action)
              l = Log.new(mbr_id: mbr_action[:member_target], a_user_id: session[:auth_user_id], ts: Time.now,
                notes: log_notes, action_id: Action.get_action_id("member_not_renew_followup"))
              l.save
            end
            session[:msg] = 'Member action was successfully updated'
          rescue StandardError => e
            session[:msg] = "The member action was not updated\n#{e}"
          end
        else
          session[:msg] = 'No changes were made to the member action'
        end
        redirect '/m/followup/show'
      end

      app.get '/m/mbr_non_renewals/destroy/:id' do
        #pull the member action record
        @member_action = DB[:member_actions].where(id: params[:id]).first
        @member_action[:target_member_name] = "#{Member[@member_action[:member_target]].fname} #{Member[@member_action[:member_target]].lname}"
        @member_action[:member_action_type] = DB[:member_action_types].where(id: @member_action[:member_action_type_id]).first[:name]
        erb :m_member_action_destroy, :layout => :layout_w_logout
      end

      app.post '/m/mbr_non_renewals/destroy/:id' do
        #params are {"_method"=>"delete", "id"=>"100"}
        if params[:_method] != 'delete'
          #js not enabled, need to find another way to confirm this action
          session[:msg] = "Member action was not deleted, please enable Javascript on your browser"
          redirect '/m/followup/show'
        end
        #get the member action record
        mbr_action = DB[:member_actions].where(id: params[:id]).first
        #get the member action type
        action_type = DB[:member_action_types].where(id: mbr_action[:member_action_type_id]).first
        #get the member target
        tm = Member[mbr_action[:member_target]]
        target_member_name = "#{tm.fname} #{tm.lname}"
        #get the authorized user
        au = AuthUser[mbr_action[:a_user_id]]
        auth_user_name = "#{au.member.fname} #{au.member.lname}"
        #get the tasked to member
        tasked_to_mbr_name = mbr_action[:tasked_to_mbr_id].nil? ? "none" : "#{Member[mbr_action[:tasked_to_mbr_id]].fname} #{Member[mbr_action[:tasked_to_mbr_id]].lname}"
        #log this deletion event
        log_notes = "deleting member action record id: #{params[:id]}\n"
        log_notes << "target member_name: #{target_member_name}, tasked to: #{tasked_to_mbr_name}\n"
        log_notes << "date: #{mbr_action[:ts].strftime("%m/%d/%Y")}\n"
        log_notes << "completed: #{mbr_action[:completed] ? "yes" : "no"}\n"
        log_notes << "authorized user: #{auth_user_name}\n"
        log_notes << "action type: #{action_type}\n"
        l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, notes: log_notes,
          action_id: Action.get_action_id("member_not_renew_followup"))
        begin
          DB.transaction do
            #write log entry
            l.save
            #delete the log entries associated with this member action
            DB[:logs].where(mbr_action_id: mbr_action[:id]).delete
            #delete the member action record
            DB[:member_actions].where(id: params[:id]).delete
            session[:msg] = 'Member action was SUCCESSFULLY deleted'
          end
        rescue StandardError => e
          session[:msg] = "The member action WAS NOT deleted\n#{e}"
        end
        redirect '/m/mbr_non_renewals/show'
      end

    end
  end
end
