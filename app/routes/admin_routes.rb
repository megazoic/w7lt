module MemberTracker
  module AdminRoutes
    def self.registered(app)

      app.helpers do
        def renewal_find_result
          start_date = MbrRenewal.getRenewRangeStart(session[:auth_user_id])
          if start_date == "error"
            return JSON.generate("bad date range")
          elsif start_date == "wait"
            return JSON.generate("already checked today")
          end
          end_date = Date.today.prev_year + MbrRenewal::RENEWAL_WINDOW
          mbrs = DB[:members]
          update_mbrship_renewal_date = []
          pmts_in_range = Payment.where(payment_type_id: 5, ts: start_date..end_date)
          mbrRenwls_in_range = Member.where(mbrship_renewal_date: start_date..end_date)
          mbrs2renw_pmt = {}
          mbrs2renw_mbrRnwl = {}
          pmt_mbr_ids = pmts_in_range.map { |p| p[:mbr_id] }.uniq
          pmt_members = Member.where(id: pmt_mbr_ids).all.each_with_object({}) { |m, h| h[m.id] = m }
          dues_by_mbr = Payment.where(mbr_id: pmt_mbr_ids, payment_type_id: 5)
                               .select(:mbr_id, :ts).all
                               .group_by { |p| p[:mbr_id] }
          pmts_in_range.each do |p|
            mbr_dues = dues_by_mbr[p[:mbr_id]] || []
            next if mbr_dues.any? { |mp| mp[:ts] > p[:ts] }
            m = pmt_members[p[:mbr_id]]
            mbrs2renw_pmt[m.id] = { fname: m.fname, lname: m.lname,
              callsign: m.callsign, email: m.email, pay_date: p[:ts] }
          end
          mbrs2renw_pmt.delete_if { |k, _|
            m = pmt_members[k]
            m.mbrship_renewal_halt == true || m.mbrship_renewal_contacts >= 2 }
          mbrRenwls_in_range.each do |mr|
            if (mr[:mbrship_renewal_halt] == 0) && (mr[:mbrship_renewal_contacts] < 2)
              mbrs2renw_mbrRnwl[mr[:id]] = { fname: mr[:fname], lname: mr[:lname],
                callsign: mr[:callsign], email: mr[:email], mbr_type: mr[:mbr_type] }
            end
          end
          mbrs2renw_mbrRnwl = MbrRenewal.findAndPurgeFamily(mbrs2renw_mbrRnwl)
          mbrs2renw_all = mbrs2renw_mbrRnwl.merge(mbrs2renw_pmt)
          pmt_arry_ids = []
          mbrs2renw_pmt.each {|k,v| pmt_arry_ids << k}
          mbrRnwl_arry_ids = []
          mbrs2renw_mbrRnwl.each {|k,v| mbrRnwl_arry_ids << k}
          diff_pmt_arry_ids = pmt_arry_ids - mbrRnwl_arry_ids
          diff_mbrRnwl_arry_ids = mbrRnwl_arry_ids - pmt_arry_ids
          send_reminder = pmt_arry_ids & mbrRnwl_arry_ids
          all_latr_pmts = Payment.where(ts: end_date..Date.today, payment_type_id: 5).select(:mbr_id, :ts)
          all_latr_pmts.each {|lp|
            if diff_mbrRnwl_arry_ids.include?(lp[:mbr_id])
              update_mbrship_renewal_date << lp
              diff_mbrRnwl_arry_ids.delete(lp[:mbr_id])
            end
          }
          send_reminder.concat(diff_mbrRnwl_arry_ids)
          diff_pmt_arry_ids.each {|dp|
            if Date.parse(Member[dp].mbrship_renewal_date.to_s) > end_date
              diff_pmt_arry_ids.delete(dp)
            end
          }
          send_reminder.concat(diff_pmt_arry_ids)
          update_mbrship_renewal_date.concat(diff_pmt_arry_ids)
          if !update_mbrship_renewal_date.empty?
            update_mbrship_renewal_date.each {|mbr_id|
              mbrs.where(id: mbr_id).update(mbrship_renewal_date: mbrs2renw_all[mbr_id][:pay_date])
            }
          end
          missing_email = []
          send_reminders_out = ["remember to enter reminder sent or missing email in mbr_renewals table"]
          send_reminder.each{|mbr_id|
            mbrs.where(id: mbr_id).update(mbrship_renewal_active: true)
            send_reminders_out << mbrs2renw_all[mbr_id]
            if mbrs2renw_all[mbr_id][:email][0] == 'NA'
              missing_email << mbr_id
            end
          }
          if !missing_email.empty?
            missing_email.each do |mbr_id|
              MbrRenewal.create(a_user_id: session[:auth_user_id], mbr_id: mbr_id, renewal_event_type_id: RenewalEventType.getID('missing email'),
              notes: 'automated entry', ts: DateTime.now)
            end
          end
          l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: Action.get_action_id("mbr_renew_check"))
          l.save
          send_reminders_out[1].nil? ? JSON.generate("empty search") : JSON.generate(send_reminders_out)
        end

        def renewal_2nd_notice_result
          JSON.generate(MbrRenewal.get2ndNotice)
        end
      end

      # Admin browser routes — protected by before '/a/*' (auth_u required), no secret needed
      app.get '/a/mbr_renewal/1st_notice' do
        renewal_find_result
      end

      app.get '/a/mbr_renewal/2nd_notice' do
        renewal_2nd_notice_result
      end

      # External API routes — no login required, secret required
      app.get '/api/mbr_renewal/find/:secret' do
        return JSON.generate("sorry") if params[:secret] != ENV['MBRRENEW_SECRET']
        renewal_find_result
      end

      app.get '/api/mbr_renewal/2nd_notice/:secret' do
        return JSON.generate("sorry") if params[:secret] != ENV['MBRRENEW_SECRET']
        renewal_2nd_notice_result
      end

      app.get '/api/mbr_sync/SP2ejIsG/:secret' , :provides => 'json' do
        if params[:secret] != ENV['MBRSYNC_SECRET']
          return JSON.generate("sorry")
        end
        #puts 'in get and json'
        #members with mbrship_renewal_date > renewal date - 1 year will be current
        m = DB[:members]
        active_mbrs = m.where{mbrship_renewal_date >= Date.today.prev_year}.as_hash(:id, [:fname, :lname, :email])
        #build out payload
        JSON.generate(active_mbrs)
      end

      app.get '/a/auth_user/list' do
        @au_list = []
        #get a 2D array of [[mbr_id, auth_user_id]] for each auth_user
        #except for currently logged in admin
        au = AuthUser.exclude(id: session[:auth_user_id]).select(:id, :mbr_id).map(){|x| [x.mbr_id, x.id]}
        #fill this array with additional info
        au.each do |u|
          au_hash = Hash.new
          m = Member.select(:id, :fname, :lname, :callsign).where(id: u[0]).first
          au_hash["mbr_id"] = m.values[:id]
          au_hash["fname"] = m.values[:fname]
          au_hash["lname"] = m.values[:lname]
          au_hash["callsign"] = m.values[:callsign]
          #get_roles returns a 2D array [[role_id, role_descr],[]] or nil
          roles = AuthUser[u[1]].get_roles
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

      app.get '/a/auth_user/role/update/:id' do
        @mbr_to_update = Member.select(:id, :fname, :lname, :callsign, :email)[params[:id].to_i]
        #get role associated with this auth_user
        au = AuthUser.where(mbr_id: params[:id]).first
        @mbr_to_update[:role] = au.role
        @au_roles = Role.map(){|x| [x.rank, x.id, x.description]}
        @au_roles.sort!
        erb :au_roles_update, :layout => :layout_w_logout
      end

      app.post '/a/auth_user/update' do
        notes_only = false
        #start building the log string
        l = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now, action_id: Action.get_action_id("auth_u"))
        au = AuthUser.where(mbr_id: params[:mbr_id]).first
        if au.nil? || Role[params[:role_id]].nil?
          session[:msg] = "Invalid member or role"
          redirect '/a/auth_user/list'
        end
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
          #need to update time_pwd_set
          au.time_pwd_set = Time.now
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
          log_error(e)
          session[:msg] = "The data was not entered successfully"
        end
        redirect '/a/auth_user/list'
      end

      app.get '/a/auth_user/role/set/:id' do
        @sel_au_mbr = Member.select(:id, :fname, :lname, :callsign, :email)[params[:id].to_i]
        if @sel_au_mbr.nil?
          session[:msg] = "Member not found"
          redirect '/a/auth_user/list'
        end
        #won't be setting a newly authorized member as inactive, so pull this from the list
        @roles = Role.exclude(name: 'inactive').order(:rank)
        erb :au_roles_set, :layout => :layout_w_logout
      end

      app.get '/a/auth_user/create' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        #only want members who are not already auth users
        existing_au_mbr_ids = AuthUser.map{|x| x.mbr_id}
        @sel_au_from_mbrs = Member.exclude(id: existing_au_mbr_ids).select(:id, :fname, :lname, :callsign, :email).all
        erb :au_create, :layout => :layout_w_logout
      end

      app.post '/a/auth_user/create' do
        #expecting params keys :notes, :mbr_id, :role_id
        email = Member[params[:mbr_id].to_i].email
        #test for existing user with these credentials
        existing_auth_user = AuthUser.first(mbr_id: params[:mbr_id])
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
            auth_user = AuthUser.new(:password => encrypted_pwd, :mbr_id => params[:mbr_id].to_i,
              :time_pwd_set => Time.now, :new_login => 1, :last_login => Time.now, :role_id => params[:role_id])
            auth_user.save
            l = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now, action_id: Action.get_action_id("auth_u"))
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
          log_error(e)
          session[:msg] = "error: could not create authorized user."
          redirect "/a/auth_user/create"
        end
      end

    end
  end
end
