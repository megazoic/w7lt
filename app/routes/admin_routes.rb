module MemberTracker
  module AdminRoutes
    def self.registered(app)

      app.get '/api/mbr_renewal/find/:secret', :provides => 'json' do
        if params[:secret] != ENV['MBRRENEW_SECRET']
          return JSON.generate("sorry")
        end
        #find most recent date email reminders were sent out or date only individuals without emails were retreived
        start_date = MbrRenewal.getRenewRangeStart(session[:auth_user_id])
        if start_date == "error"
          return JSON.generate("bad date range")
        elsif start_date == "wait"
          return JSON.generate("already checked today")
        end
        #end date is (two weeks from today - 365)
        end_date = Date.today.prev_year + MbrRenewal::RENEWAL_WINDOW
        mbrs = DB[:members]
        # Don't want to keep shortening a members annual membership when they renew before membership expires so...
        # Have 2 ways to find out who needs reminder. 1) via payment records (mbrs2renw_pmt hash), 2) via Member::mbrship_renewal_date
        # (mbrs2renw_mbrRnwl hash)
        # Both methods use same date range to determine members who's renewal date is coming up (from today -- MbrRenewal::RENEWAL_WINDOW)
        # These two collections need to be compared to generate (5) separate categories with different actions for each
        # A) those falling in both categories, B) in pmt and have mbr date later in time, C) in pmt and have mbr date earlier
        # D) in mbr and have pmt date later in time, E) in mbr and have pmt date earlier. Actions A) send reminder, B) no action,
        # C) send reminder + update Member::mbrship_renewal_date, D) update Member::mbrship_renewal_date, E) send reminder
        # arrays with members who need an action taken, rest are ignored
        update_mbrship_renewal_date = []
        pmts_in_range = Payment.where(payment_type_id: 5, ts: start_date..end_date)
        mbrRenwls_in_range = Member.where(mbrship_renewal_date: start_date..end_date)
        mbrs2renw_pmt = {}
        mbrs2renw_mbrRnwl = {}
        pmts_in_range.each do |p|
          #must first check to see if there are any later payments for a member and exclude this payment
          later_dues_pmt = false
          Member[p[:mbr_id]].payments.each do |mp|
            if (mp[:ts] > p[:ts] && mp[:payment_type_id] == 5)
              later_dues_pmt = true
              break
            end
          end
          if later_dues_pmt == true
            #ignore this payment
            next
          end
          mbrs2renw_pmt.update({Member[p[:mbr_id]].id => {:fname => Member[p[:mbr_id]].fname, :lname => Member[p[:mbr_id]].lname,
          :callsign => Member[p[:mbr_id]].callsign, :email => Member[p[:mbr_id]].email,
          :pay_date => p[:ts]}})
        end
        #check to see if unsubscribed or about to exceed number of contacts allowed
        mbrs2renw_pmt.delete_if{|k,v|
          (Member[k].mbrship_renewal_halt == true) || (Member[k].mbrship_renewal_contacts >= 2)}
        mbrRenwls_in_range.each do |mr|
          #only take those who have not unsubscribed to renewal reminders and previous contact attempts < 2
          if (mr[:mbrship_renewal_halt] == 0) && (mr[:mbrship_renewal_contacts] < 2)
            mbrs2renw_mbrRnwl << {mr[:id] => {:fname => mr[:fname], :lname => mr[:lname],
            :callsign => mr[:callsign], :email => mr[:email], :mbr_type => mr[:mbr_type]}}
          end
        end
        #need to check to see if any are of mbr_type 'family' in which case, only the paying member should be included here
        mbrs2renw_mbrRnwl = MbrRenewal.findAndPurgeFamily(mbrs2renw_mbrRnwl)
        #merge the two (removing duplicates) mbrs2renw_pmt values are kept when keys(ids) same in both hashes
        mbrs2renw_all = mbrs2renw_mbrRnwl.merge(mbrs2renw_pmt)
        #extract the keys
        pmt_arry_ids = []
        mbrs2renw_pmt.each {|k,v| pmt_arry_ids << k}
        mbrRnwl_arry_ids = []
        mbrs2renw_mbrRnwl.each {|k,v| mbrRnwl_arry_ids << k}
        #now want the two difference sets
        diff_pmt_arry_ids = pmt_arry_ids - mbrRnwl_arry_ids #unique to pmt
        diff_mbrRnwl_arry_ids = mbrRnwl_arry_ids - pmt_arry_ids #unique to mbrRnwl
        #need the intersection set
        send_reminder = pmt_arry_ids & mbrRnwl_arry_ids
        #now need to separate within these two groups (unique to pmt [diff_pmt_arry_ids] or to mbrRnwl
        #[diff_mbrRnwl_arry_ids]) those who's mbr_renewal_date or last dues payment dates
        #occur after the end date for the window (from today -- MbrRenewal::RENEWAL_WINDOW)
        #so, have to iterate through each looking for corresponding records after end_date of range
        all_latr_pmts = Payment.where(ts: end_date..Date.today, payment_type_id: 5).select(:mbr_id, :ts)
        #union of diff_mbrRnwl_arry_ids with all_latr_pmts = member is late making a payment
        all_latr_pmts.each {|lp|
          if diff_mbrRnwl_arry_ids.include?(lp[:mbr_id])
            update_mbrship_renewal_date << lp
            diff_mbrRnwl_arry_ids.delete(lb[:mbr_id])
          end
        }
        #now diff_mbrRnwl_arry_ids only contains ids that need a reminder sent
        send_reminder.concat(diff_mbrRnwl_arry_ids)
        #next work with other difference array. here, we have to use these ids to get Member::mbrship_renewal_date
        #and delete from array those ids with Member::mbrship_renewal_date > end_date (let them drop, they will come up again later)
        diff_pmt_arry_ids.each {|dp|
          if Date.parse(Member[dp].mbrship_renewal_date.to_s) > end_date
            diff_pmt_arry_ids.delete(dp)
          end
        }
        #those remaining diff_pmt_arry_ids go into update and send reminder
        send_reminder.concat(diff_pmt_arry_ids)
        update_mbrship_renewal_date.concat(diff_pmt_arry_ids)
        #to follow up on updating the Member table, use update_mbrship_renewal_date with mbrs2renw_all
        #dont need to set Member::mbrship_renewal_active for these
        if !update_mbrship_renewal_date.empty?
          update_mbrship_renewal_date.each {|mbr_id|
            mbrs.where(id: mbr_id).update(mbrship_renewal_date: mbrs2renw_all[mbr_id][:pay_date])
          }
        end
        #return remaining mbrs who need reminders sent, but first look for missing emails and record to Member table
        missing_email = []
        send_reminders_out = ["remember to enter reminder sent or missing email in mbr_renewals table"]
        send_reminder.each{|mbr_id|
          #set members here as Member::mbrship_renewal_active true
          mbrs.where(id: mbr_id).update(mbrship_renewal_active: true)
          send_reminders_out << mbrs2renw_all[mbr_id]
          if mbrs2renw_all[mbr_id][:email][0] == 'NA'
            missing_email << mbr_id
          end
        }
        #deal with missing emails
        if !missing_email.empty?
          missing_email.each do |mbr_id|
            #need to record this in Mbr_renewals (a_user_id, mbr_id, renewal_event_type_id, notes)
            MbrRenewal.create(a_user_id: session[:auth_user_id], mbr_id: mbr_id, renewal_event_type_id: RenewalEventType.getID('missing email'),
            notes: 'automated entry', ts: DateTime.now)
          end
        end
        #log this event to estabilish beginning of next renewal window
        l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: Action.get_action_id("mbr_renew_check"))
        l.save

        if send_reminders_out[1].nil?
          JSON.generate("empty search")
        else
          JSON.generate(send_reminders_out)
        end
      end

      app.get '/api/mbr_renewal/2nd_notice/:secret', :provides => 'json' do
        #just looking for those with mbr_renewals 'reminder sent' in window 3 - 2 wks ago and mbrship_renewal_active
        if params[:secret] != ENV['MBRRENEW_SECRET']
          return JSON.generate("sorry")
        end
        mbrs_to_2nd_reminder = []
        mbrs_to_2nd_reminder = MbrRenewal.get2ndNotice
        JSON.generate(mbrs_to_2nd_reminder)
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
          session[:msg] = "The data was not entered successfully\n#{e}"
        end
        redirect '/a/auth_user/list'
      end

      app.get '/a/auth_user/role/set/:id' do
        @sel_au_mbr = Member.select(:id, :fname, :lname, :callsign, :email)[params[:id].to_i]
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
          session[:msg] = "error: could not create authorized user.\n#{e}"
          redirect "/a/auth_user/create"
        end
      end

    end
  end
end
