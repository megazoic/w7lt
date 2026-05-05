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
        when "auth_user" #view only current logged in users logs
          @type = "auth_user"
          @logs = []
          au = AuthUser[session[:auth_user_id]]
          #are there any logs for this auth_user?
          if au.logs.length == 0
            session[:msg] = "there are no logs to view"
            redirect '/home'
          end
          Log.where(a_user_id: session[:auth_user_id]).reverse_order(:ts).order_append(:action_id).each do |l|
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
            h[:id] = l.id
            @logs << h
          end
        when "all"
          @type = "all"
          aus = AuthUser.all
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
                h[:id] = l.id
                @logs << h
                @logs.reverse!
              end
            end
          end
          if no_logs == true
            session[:msg] = "there are no logs to view"
            redirect '/home'
          end
        when "general"
          @logs = []
          Action[Action.get_action_id("general_log")].logs_dataset.order(:id).each do |l|
            @logs << {:au_name => l.auth_user.member.callsign, :notes => l.notes, :time => l.ts.strftime("%m-%d-%Y"), :id => l.id}
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

    end
  end
end
