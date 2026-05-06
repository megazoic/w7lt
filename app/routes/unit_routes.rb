module MemberTracker
  module UnitRoutes
    def self.registered(app)

      app.get '/m/unit/list/:unit_type' do
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
          unit_meta = {unit_creator: AuthUser[u.a_user_id].member.callsign, unit_created_at: u.ts.strftime("%m-%d-%y"),
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
            rd = Member[u.members.first.id].mbrship_renewal_date
            if !rd.nil?
              renew_date = rd.to_datetime.strftime('%b %Y')
            else
              renew_date = "NA"
            end
            unit_meta[:unit_notes] = "Renew: #{renew_date}"
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

      app.get '/m/unit/create' do
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

      app.post '/m/unit/create' do
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
        l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: Action.get_action_id("unit"))
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

      app.get '/m/unit/edit/:id' do
        #response['Cache-Control'] = "public, max-age=0, must-revalidate"
        @unit = Unit[params[:id].to_i]
        #get a list of member ids that belong to this unit
        #also, if the unit is an elmer, find that elmer member
        @unit_creator_callsign = AuthUser[@unit.a_user_id].member.callsign
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

      app.post '/m/unit/update' do
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
        l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, notes: augmented_notes, action_id: Action.get_action_id("unit"))
        ################get ready for update#####################
        have_payment = false
        unit_pay_date_latest = Time.new(1999,01,01)
        unit_pay_id_latest = 0
        if unit.unit_type.type == 'family'
          #look for payments
          unit.log.each do |ul|
            if !ul.payment.nil?
              have_payment = true
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
                  when "mbr_type"
                    m.mbr_type = a[1][3]
                    augmented_notes << "\nsetting mbr_type for #{m.callsign} to #{m.mbr_type}"
                    #remove audit log
                    AuditLog[a[1][0]].delete
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
                unit_pay_date_latest = Time.new(1999,01,01)
                unit_pay_id_latest = 0
                unit.log.each do |ul|
                  if !ul.payment.nil?
                    have_payment = true
                    if ul.payment.ts > unit_pay_date_latest
                      unit_pay_date_latest = ul.payment.ts
                      unit_pay_id_latest = ul.payment.id
                    end
                  end
                end
                if have_payment == true #if not, then this mbr has already been added no other changes need to be made
                  al = AuditLog.new("a_user_id" => session[:auth_user_id], "column" => "mbr_type",
                          "changed_date" => Time.now, "old_value" => m.mbr_type, "new_value" => "family",
                          "mbr_id" => m.id, "pay_id" => unit_pay_id_latest, "unit_id" => unit.id)
                  al.save
                  m.mbr_type = 'family'
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

      app.get '/m/unit/type/create/:id?' do
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

      app.post '/m/unit/type/create/:id?' do
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
        l = Log.new(a_user_id: session[:auth_user_id], ts: Time.now, action_id: Action.get_action_id("unit"))
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

      app.get '/m/unit/display/fam_unit/status' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        units = DB[:units].where(unit_type_id: 2)
        @fam_mbrship_details = []
        units.each do |u|
          fam_hash = {}
          fam_hash = {unit_id: u[:id], active: u[:active]}
          mbrs_array = []
          MemberTracker::Unit[u[:id]].members.each do |m|
            #convert mbrship_renewal_date
            renew_due = false
            rd = nil
            if !m[:mbrship_renewal_date].nil?
              rd = m[:mbrship_renewal_date].strftime("%D")
              test_rd = m[:mbrship_renewal_date].to_date
              if test_rd < (Date.today - 365)
                renew_due = true
              end
            else
              rd = "NA"
            end
            mbr_array = [m[:id], m[:fname], m[:lname], rd, renew_due]
            mbrs_array << mbr_array
          end
          fam_hash[:mbrs] = mbrs_array
          @fam_mbrship_details << fam_hash
        end
        erb :display_fam_renewal, :layout => :layout_w_logout
      end

    end
  end
end
