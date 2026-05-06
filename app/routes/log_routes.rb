module MemberTracker
  module LogRoutes
    def self.registered(app)

      app.get '/r/log/logNote/show/:id' do
        logs = DB[:logs]
        @note = logs.where(id: params[:id]).get(:notes)
        if @note.nil?
          session[:msg] = "Log note not found"
          redirect '/home'
        end
        erb :l_note_show, :layout => :layout_w_logout
      end

      app.get '/m/log/create/:id?' do
        if params[:id].nil?
          #creating a general log
          @type = 'general'
        else
          #need to get action type and id in a hash--select only member_general_note and member_not_renew_followup
          @log_action = Hash.new
          Action.where(type: ['member_general_note', 'member_not_renew_followup']).each do |a|
            @log_action[a.type.to_sym] = a.id
          end
          @member = Member[params[:id]]
        end
        erb :l_create, :layout => :layout_w_logout
      end

      app.post '/m/log/create' do
        l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, notes: params[:notes])

        if params[:mbr_id].nil?
          #a general log (for now)
          l.action_id = Action.get_action_id("general_log")
          l.save
          session[:message] = "Log successfully saved"
          redirect '/m/log/view/auth_user'
        else
          #adding a note to a member
          l.mbr_id = params[:mbr_id]
          l.action_id = Action[params[:log_action]].id
          l.save
          session[:message] = "Log successfully saved"
          redirect "/r/member/show/#{params[:mbr_id]}"
        end
      end

      app.get '/m/log/view/:type' do
        case params[:type]
        when "auth_user"
          @type = "auth_user"
          total = Log.where(a_user_id: session[:auth_user_id]).count
          if total == 0
            session[:msg] = "there are no logs to view"
            redirect '/home'
          end
          @total_pages = [(total / PER_PAGE.to_f).ceil, 1].max
          @page = [[params[:page].to_i, 1].max, @total_pages].min
          @logs = Log.where(a_user_id: session[:auth_user_id])
                     .reverse_order(:ts).order_append(:action_id)
                     .limit(PER_PAGE).offset((@page - 1) * PER_PAGE).map do |l|
            { mbr_name: l.member ? "#{l.member.fname} #{l.member.lname}" : "N/A",
              time: l.ts.strftime("%m-%d-%Y"), notes: l.notes,
              action: l.action.type, id: l.id }
          end
        when "all"
          @type = "all"
          total = Log.count
          if total == 0
            session[:msg] = "there are no logs to view"
            redirect '/home'
          end
          @total_pages = [(total / PER_PAGE.to_f).ceil, 1].max
          @page = [[params[:page].to_i, 1].max, @total_pages].min
          @logs = Log.reverse_order(:ts).limit(PER_PAGE).offset((@page - 1) * PER_PAGE).map do |l|
            { mbr_name: l.member ? "#{l.member.fname} #{l.member.lname}" : "N/A",
              time: l.ts.strftime("%m-%d-%Y"), notes: l.notes,
              action: l.action.type,
              au_name: "#{l.auth_user.member.fname} #{l.auth_user.member.lname}",
              id: l.id }
          end
        when "general"
          @type = "general"
          general_action_id = Action.get_action_id("general_log")
          total = Log.where(action_id: general_action_id).count
          if total == 0
            session[:msg] = "there are no logs to view"
            redirect '/home'
          end
          @total_pages = [(total / PER_PAGE.to_f).ceil, 1].max
          @page = [[params[:page].to_i, 1].max, @total_pages].min
          @logs = Log.where(action_id: general_action_id)
                     .reverse_order(:ts).limit(PER_PAGE).offset((@page - 1) * PER_PAGE).map do |l|
            { au_name: l.auth_user.member.callsign, notes: l.notes,
              time: l.ts.strftime("%m-%d-%Y"), id: l.id }
          end
        end
        erb :l_list, :layout => :layout_w_logout
      end

    end
  end
end
