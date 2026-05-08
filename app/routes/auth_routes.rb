module MemberTracker
  module AuthRoutes
    def self.registered(app)

      app.get '/', :provides => 'html' do
      end

      app.get '/check/mbrship/status' do
        #puts ENV["RACK_ENV"]
        @tmp_msg = session[:msg]
        session[:msg] = nil
        erb :mbrship_status, :layout => :layout
      end

      app.post '/check/mbrship/status' do
        identifier = params[:mbrIdentifier].to_s.strip.upcase
        parts = identifier.split(' ', 2)
        member = Member.first(callsign: identifier) ||
                 Member.first(email: identifier) ||
                 (parts.length == 2 && Member.first(fname: parts[0], lname: parts[1]))
        if !member
          "Member not found"
        elsif member.mbrship_renewal_date && member.mbrship_renewal_date.to_date >= Date.today.prev_year
          "Your membership is active"
        else
          "Your membership has expired"
        end
      end

      app.get '/login' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        erb :login, :layout => :layout
      end

      app.post '/login' do
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
          mbr_id = AuthUser[auth_user_result['auth_user_id']].mbr_id
          redirect "/reset_password/#{mbr_id}"
        elsif auth_user_result['error'] == 'inactive'
          session.clear
          session[:msg] = "Please contact admin, your account has been deactivated."
          redirect "/login"
        elsif auth_user_result.has_key?('auth_user_id')
          session[:auth_user_id] = auth_user_result['auth_user_id']
          session[:auth_user_roles] = auth_user_result['auth_user_roles']
          redirect '/home'
        else
          #there is an error message in the auth_user_result if needed
          @tmp_msg = auth_user_result['error']
          session.clear
          redirect '/login'
        end
      end

      app.post '/logout' do
        session.clear
        session[:msg] = 'you have successfully logged out'
        redirect '/login'
      end

      app.get '/home' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        if @tmp_msg.nil?
          latest_renew_check = DB.from(:logs).where(action_id: Action.get_action_id("mbr_renew_check")).reverse_order(:ts).first
          @tmp_msg = latest_renew_check[:ts].strftime("Renewals last checked on %m/%d/%Y")
        end
        @q = (params[:q] || '').strip
        ds = Member.select(:id, :fname, :lname).order(:lname, :fname)
        unless @q.empty?
          parts = @q.split(' ', 2)
          if parts.length == 2
            ds = ds.where(Sequel.ilike(:fname, "%#{parts[0]}%") & Sequel.ilike(:lname, "%#{parts[1]}%"))
          else
            ds = ds.where(Sequel.ilike(:lname, "%#{@q}%"))
          end
        end
        @total_count = ds.count
        @total_pages = [(@total_count / PER_PAGE.to_f).ceil, 1].max
        @page = [[params[:page].to_i, 1].max, @total_pages].min
        @member_lnames = ds.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).all
        erb :home, :layout => :layout_w_logout
      end

      app.get '/reset_password/:id' do
        #use @is_pwdreset to load password script from script.js by setting <body id="PwdReset"> in layout
        @is_pwdreset = true
        @mbr = Member.select(:id, :fname, :lname, :callsign).where(id: params[:id]).first
        if @mbr.nil?
          session[:msg] = "Member not found"
          redirect '/home'
        end
        erb :reset_password, :layout => :layout
      end

      app.post '/reset_password' do
        @auth_user.update(params[:password], params[:mbr_id])
        session.clear
        session[:msg] = 'Password successfully reset, please login with your new password'
        redirect '/login'
      end

      app.get '/m/auth_user/change_password' do
        @is_pwdreset = true
        @tmp_msg = session[:msg]
        session[:msg] = nil
        erb :au_change_password, :layout => :layout_w_logout
      end

      app.post '/m/auth_user/change_password' do
        if @auth_user.change_password(session[:auth_user_id], params[:current_password], params[:password])
          session[:msg] = 'Password successfully changed'
          redirect '/home'
        else
          session[:msg] = 'Current password is incorrect'
          redirect '/m/auth_user/change_password'
        end
      end

    end
  end
end
