module MemberTracker
  module FollowupRoutes
    def self.registered(app)

      app.get '/m/followup/show' do
        expired = MemberAction.expire_stale_call_actions(session[:auth_user_id])
        session[:msg] = "#{expired} stale call-me action(s) were automatically completed." if expired > 0
        @tmp_msg = session[:msg]
        session[:msg] = nil
        # first, get call member actions and test if logs exist
        @action_type = {}
        @action_type[:callme] = DB[:member_action_types].where(name: 'call_member').first
        ma_type_id = MemberActionType[name: 'call_member'].id
        @mbr_call_me_actions = MemberAction.get_member_actions(ma_type_id)
        # next, get non-renew followup actions and test if logs exist
        @action_type[:nonrenewal] = DB[:member_action_types].where(name: 'non_renew_followup').first
        ma_type_id = MemberActionType[name: 'non_renew_followup'].id
        @mbr_non_renewal_actions = MemberAction.get_member_actions(ma_type_id)
        @completed_call_me_actions = MemberAction.get_completed_call_actions

        erb :m_followup_show, :layout => :layout_w_logout
      end

      app.get '/m/member_action/add_note' do
        #the params are {"mbr_action_id"=>"1", "type"=>"call_member" or "non_renew_followup"}
        #check to see if the mbr_action_id is present
        if params[:mbr_action_id].nil?
          session[:msg] = "No member action id was provided"
          redirect '/m/followup/show'
        end
        #check to see if the type is present
        if params[:type].nil?
          session[:msg] = "No member action type was provided"
          redirect '/m/followup/show'
        end
        #check to see if the type is valid
        if !['call_member', 'non_renew_followup'].include?(params[:type])
          session[:msg] = "Invalid member action type provided"
          redirect '/m/followup/show'
        end
        #get the member action record
        @mbr_action = DB[:member_actions].where(id: params[:mbr_action_id]).first
        if @mbr_action.nil?
          session[:msg] = "No member action record found for id: #{params[:mbr_action_id]}"
          redirect '/m/followup/show'
        end
        #get the member target
        @mbr_action[:target_member_name] = "#{Member[@mbr_action[:member_target]].fname} #{Member[@mbr_action[:member_target]].lname}"
        @mbr_action[:target_member_id] = @mbr_action[:member_target]
        #get the name of the member tasked to this action
        if @mbr_action[:tasked_to_mbr_id].nil?
          @mbr_action[:tasked_to_mbr_name] = "NONE"
        else
          @mbr_action[:tasked_to_mbr_name] = "#{Member[@mbr_action[:tasked_to_mbr_id]].fname} #{Member[@mbr_action[:tasked_to_mbr_id]].lname}"
        end
        #get additional logs for this member action
        if params[:type] == 'call_member'
          action_id = Action[type: 'mbr_call_me'].id
        else
          #params[:type] == 'non_renew_followup'
          action_id = Action[type: 'member_not_renew_followup'].id
        end
        @logs = DB[:logs].where(action_id: action_id, mbr_action_id: @mbr_action[:id]).all
        if @logs.empty?
          @logs = nil
        else
          @logs.each do |l|
            l[:a_user_name] = "#{AuthUser[l[:a_user_id]].member.fname} #{AuthUser[l[:a_user_id]].member.lname}"
            #l[:ts] = l[:ts].strftime("%m/%d/%Y")
            l[:notes] = l[:notes].gsub(/\n/, '<br>')
          end
        end
        erb :m_member_action_add_note, :layout => :layout_w_logout
      end

      app.post '/m/member_action/add_note' do
        #params are {"mbr_action_id"=>"1", _method"=>"post", "notes"=>"some notes"}
        #check to see if the mbr_action_id is present
        if params[:mbr_action_id].nil?
          session[:msg] = "No member action id was provided"
          redirect '/m/followup/show'
        end
        #check to see if the notes are present
        if params[:note].nil? || params[:note].empty?
          session[:msg] = "No notes were provided"
          redirect '/m/followup/show'
        end
        #get the member action record
        mbr_action = DB[:member_actions].where(id: params[:mbr_action_id]).first
        if mbr_action.nil?
          session[:msg] = "No member action record found for id: #{params[:mbr_action_id]}"
          redirect '/m/followup/show'
        end
        #get the member target
        mbr_action[:target_member_name] = "#{Member[mbr_action[:member_target]].fname} #{Member[mbr_action[:member_target]].lname}"
        mbr_action[:target_member_id] = mbr_action[:member_target]
        #get the action type
        mbr_action_type = DB[:member_action_types].where(id: mbr_action[:member_action_type_id]).first
        log_action_id = nil
        if mbr_action_type[:name] == 'call_member'
          #get the action id for call_member
          log_action_id = Action.get_action_id("mbr_call_me")
        elsif mbr_action_type[:name] == 'non_renew_followup'
          #get the action id for non_renew_followup
          log_action_id = Action.get_action_id("member_not_renew_followup")
        else
          session[:msg] = "Invalid member action type provided"
          redirect '/m/followup/show'
        end
        #create a new log entry for this member action
        l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, notes: params[:note],
          mbr_action_id: params[:mbr_action_id], action_id: log_action_id, mbr_id: mbr_action[:member_target])
        begin
          DB.transaction do
            l.save
            session[:msg] = 'Note was successfully added to member action'
          end
        rescue StandardError => e
          log_error(e)
          session[:msg] = "The note was not added to the member action"
        end
        redirect '/m/followup/show'
      end

      app.get '/m/mbr_callme/edit/:id' do
        @mbr_action = DB[:member_actions].where(id: params[:id]).first
        @mbr_action[:tasked_to_mbr_id] = @mbr_action[:tasked_to_mbr_id].nil? ? "NONE" : @mbr_action[:tasked_to_mbr_id]
        @mbr_action[:target_member_name] = "#{Member[@mbr_action[:member_target]].fname} #{Member[@mbr_action[:member_target]].lname}"
        @mbr_action[:target_member_id] = @mbr_action[:member_target]
        @mbr_action[:action_type] = DB[:member_action_types].where(id: @mbr_action[:member_action_type_id]).first[:descr]
        #get list of members that are authorized users to assign to this action
        mbr_id_hash = DB[:auth_users].select(:mbr_id).exclude(role_id: Role[:name => "inactive"].id).all
        mbr_ids = mbr_id_hash.map{|x| x[:mbr_id]}
        @mbrs = DB[:members].select(:id, :fname, :lname, :callsign).where(id: mbr_ids).all
        erb :m_callme_edit, :layout => :layout_w_logout
      end

      app.post '/m/mbr_callme/update/:id' do
        #used to _update_ a member action record for call_me, _not_ to add a note
        #params are {"id"=>"1", "tasked_to_mbr_id"=>"NNN SOME NAME", "completed"=>"false", "notes"=>"some notes"}
        #extract the member id from the tasked_to_mbr_id
        #check to see if there is a member id in the tasked_to_mbr_id if not set nil
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
        if (mbr_action[:tasked_to_mbr_id] != updated_mbr_action[:tasked_to_mbr_id] ||
           mbr_action[:notes] != updated_mbr_action[:notes] ||
           mbr_action[:completed] != updated_mbr_action[:completed])
          log_notes = MemberAction.build_log_notes(mbr_action, updated_mbr_action)
          begin
            DB.transaction do
              DB[:member_actions].where(id: params[:id]).update(updated_mbr_action)
              #add log entry for this action
              l = Log.new(mbr_id: mbr_action[:member_target], a_user_id: session[:auth_user_id], ts: Time.now,
                notes: log_notes, action_id: Action.get_action_id("mbr_call_me"),
                mbr_action_id: params[:id].to_i)
              l.save
            end
            session[:msg] = 'Member action was successfully updated'
          rescue StandardError => e
            log_error(e)
            session[:msg] = "The member action was not updated"
          end
        end
        redirect '/m/followup/show'
      end

      app.get '/m/mbr_callme/new/:id' do
        #need to associate with a member (the :id in the url)
        @target_mbr = DB[:members].select(:id, :fname, :lname, :callsign).where(id: params[:id]).first
        if @target_mbr.nil?
          session[:msg] = "No member found with id: #{params[:id]}"
          redirect '/m/followup/show'
        end
        #get list of members that are authorized users to assign to this action
        mbr_id_hash = DB[:auth_users].select(:mbr_id).exclude(role_id: Role[:name => "inactive"].id).all
        mbr_ids = mbr_id_hash.map{|x| x[:mbr_id]}
        @mbrs = DB[:members].select(:id, :fname, :lname, :callsign).where(id: mbr_ids).all
        #get the member action type
        @mbr_action_type = DB[:member_action_types].where(name: 'call_member').first
        if @mbr_action_type.nil?
          session[:msg] = "No member action type found for 'call_member'"
          redirect '/m/followup/show'
        end
        @tmp_msg = session[:msg]
        session[:msg] = nil
        erb :m_callme_new, :layout => :layout_w_logout
      end

      app.post '/m/mbr_callme/new' do
        #Params: {"mbr_action_id"=>"1", "_method"=>"post", "target_mbr_id"=>"652", "mbr_tasked_to"=>"438", "note"=>"a note"}
        #check to see if the member_target is present
        if params[:target_mbr_id].nil? || params[:target_mbr_id].empty?
          session[:msg] = "No member target was provided"
          redirect '/m/followup/show'
        end
        #check to see if the notes are present
        if params[:note].nil? || params[:note].empty?
          session[:msg] = "No notes were provided"
          redirect '/m/followup/show'
        end
        #extract the member id from the tasked_to_mbr_id
        #check to see if there is a member id in the tasked_to_mbr_id if not set nil
        tasked_to_mbr_id = nil
        if params[:mbr_tasked_to] != 'NONE'
          tasked_to_mbr_id = params[:mbr_tasked_to].to_i
        end
        #create a new member action record for call_member
        mbr_action = DB[:member_actions]
        begin
          DB.transaction do
            ma_id = nil
            ma_id = mbr_action.insert(member_target: params[:target_mbr_id], tasked_to_mbr_id: tasked_to_mbr_id,
              a_user_id: session[:auth_user_id], notes: params[:note], ts: DateTime.now,
              completed: false, member_action_type_id: MemberActionType[name: 'call_member'].id)
            #add log entry for this action
            l = Log.new(mbr_id: params[:target_mbr_id], a_user_id: session[:auth_user_id], ts: Time.now,
              notes: "Added member action for call_member _not_ via renewal", action_id: Action.get_action_id("mbr_call_me"),
              mbr_action_id: ma_id)
            l.save
            session[:msg] = 'Member action was successfully recorded'
          end
        rescue StandardError => e
          log_error(e)
          session[:msg] = "The data was not entered successfully"
        end
        redirect '/m/followup/show'
      end

    end
  end
end
