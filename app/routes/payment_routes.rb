module MemberTracker
  module PaymentRoutes
    def self.registered(app)

      app.get '/m/payment/new/:id' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        @mbr_pay = Member.select(:id, :fname, :lname, :callsign, :mbrship_renewal_date,
        :mbr_type, :mbrship_renewal_contacts, :mbrship_renewal_active, :mbrship_renewal_halt)[params[:id].to_i]
        #want to get a date range over the last year from today then order dues payments, pick most recent
        today = DateTime.now
        yr_ago = DateTime.parse((Date.parse(today.to_s) -365).to_s)
        last_dues_payment = Payment.select(:ts).where(payment_type_id: 5, mbr_id: params[:id].to_i).order(:ts).last
        #test for no payments
        if last_dues_payment.nil?
          @mbr_pay[:last_dues_pmt_date] = "none prior"
        else
          @mbr_pay[:last_dues_pmt_date] = last_dues_payment[:ts].strftime('%d, %b %Y')
        end
        #if a renewal, need to warn if the member is paying too early
        #(before 11 mo have passed since renewal date)
        if !@mbr_pay[:mbrship_renewal_date].nil?
          earliest_renew_date = Date.parse(@mbr_pay[:mbrship_renewal_date].to_s) + MemberTracker::MbrRenewal::RENEW_TOO_EARLY
          if today < earliest_renew_date
            @mbr_pay[:renewal_too_early] = 1
          end
        end
        #set the new renewal date to display on form
        @mbr_pay[:new_renewal_date] = MbrRenewal.getNewMbrshipRenewalDate(params[:id].to_i, 'bogus')
        @mbr_renewal_events = MbrRenewal.select(:ts, :renewal_event_type_id, :notes).where(mbr_id: params[:id].to_i).all
        #get the renewal event types
        @mbr_renewal_events.each do |event|
          event_type = RenewalEventType.select(:name).where(id: event.values[:renewal_event_type_id]).first
          event.values[:renewal_event_type] = event_type.values[:name]
          event.values.reject!{|k,v| k == :renewal_event_type_id}
        end
        #if mbr_type is 'family' then count all family members that will be updated
        @mbr_family = []
        if @mbr_pay.mbr_type == 'family' || @mbr_pay.mbr_type == 'none'
          #find the id for the family unit
          fu_id = nil
          #does this member have any family units?
          if !@mbr_pay.units.empty?
            @mbr_pay.units.each do |mu|
              if mu.unit_type_id == UnitType.where(:type => 'family').first.id
                fu_id = mu.id
              end
            end
          end
          if !fu_id.nil?
            #load members in this family
            Unit[fu_id].members.each do |f_member|
              #load names other than the current member
              if f_member.id != params[:id].to_i
                @mbr_family << "#{f_member.fname} #{f_member.lname}"
              end
            end
          end
        end
        #so that selected option for mbr_type in form defaults correctly, want those with none to be family if
        #they just joined a family unit
        @mbr_type_selected = ''
        if !@mbr_family.empty?
          #want to default the dues payment to family even if mbr_type is none
          @mbr_type_selected = "family"
        else #otherwise, just stick with existing mbr_type
          @mbr_type_selected = @mbr_pay.mbr_type
        end
        #need to remove sk from this array
        @mbrTypes = []
        Member.mbr_types.each { |mt| @mbrTypes << mt }
        @mbrTypes.pop
        @payType = PaymentType.all
        @payMethod = PaymentMethod.all
        @payFees = Payment.fees
        erb :m_pay, :layout => :layout_w_logout
      end

      app.post '/m/payment/new' do
        #this is used to renew a membership but also to record other payment types
        #{mbr_id, mbr_type_old=>(eg. full), payment_type=>2, mbr_type,
        #payment_method=>1, [pay_amt, other_pmt] notes=>}
        #note, if dues pmt, change to Member::mbrship_renewal_date value is handled here, not in the m_pay.erb view get '/m/payment/new/:id' route
        #need to create a log for this transaction
        augmented_notes = params[:notes]
        log_pay = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now)
        log_unit = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id], ts: Time.now, action_id: Action.get_action_id("unit"))
        #create hash to hold all of the audit logs associated with this transaction
        auditlog_hash = Hash.new
        #use next (ach affected_cols_hash) to hold old/new values for all columns (member, unit tables)
        #with col name as key and [old, new] as value in the hash
        ach = Hash.new
        #if a dues payment and a new member, skip audit log process
        new_mbr = false
        #only record an audit log if needed (this goes for any type of audit log) also, this is used to
        #associate Payment::id with AuditLog::pay_id at end of transaction
        al_save = false
        #check to see if 'dues' is selected as :payment_type if so, store ids of affected members
        fam_mbr_ids = []
        #use this to track a member who is splitting off a family unit with a recent payment of not-family
        mbr_split_frm_fam_unit = false
        pay_amt = nil
        mbr_family_unit_id = nil
        #puts "augmented_notes are #{augmented_notes}"
        #look for jotform survey response in notes requesting a call from club members
        log_action = Log.new(mbr_id: params[:mbr_id], a_user_id: session[:auth_user_id],
        ts: Time.now, action_id: Action.get_action_id("mbr_call_me"))
        if /leader\?\s+Yes/.match(augmented_notes)
          #need to add to member_actions table
          DB[:member_actions].insert(member_action_type_id: 1, member_target: params[:mbr_id],
            a_user_id: session[:auth_user_id], completed: false,
            notes: "Jotform request for a call from club members", ts: DateTime.now)
          log_action.notes = "Jotform request for a call from club members"
        end
        if PaymentType[params[:payment_type]].type == 'Dues'
          #this could be a new member, an existing member renewing or a previous member with a lapse in dues payments
          #need an auditlog for this transaction
          al_save = true
          #If a new member, would have Member::mbrship_renewal_date == nil
          if Member[params[:mbr_id]].mbrship_renewal_date == nil
            #new member, set affected cols
            new_mbr = true
            if ['honorary', 'lifetime'].include?(params[:mbr_type])
              ach["mbrship_renewal_date"] = ['nil', DateTime.new(2100,01,01)]
            else
              ach["mbrship_renewal_date"] =['nil', Time.now]
            end
            ach["mbrship_renewal_halt"] = ['nil', false]
            ach["mbrship_renewal_active"] = ['nil', false]
            ach["mbrship_renewal_contacts"] = ['nil', 0]
            ach["mbr_type"] = ['none', params[:mbr_type]]
          else
            #a returning member, there are three possible scenarios, this renewal occurs
            #1) within time window [> 1 mo before due ... 2 wks after due] --this is okay, new mbrship_renewal_date = old + 365
            #2) before above window --auth user was warned and the new new mbrship_renewal_date = today (shortening previous dues payment)
            #3) after above window --new new mbrship_renewal_date = today
            #retrieve old values from members table for columns listed in AuditLog::COLS_TO_TRACK
            #note: AuditLog::COLS_TO_TRACK doesn't contain "dropped_unit" which is recording members_units join table row
            AuditLog::COLS_TO_TRACK.each do |mf|
              if mf != "fam_unit_active"
                #get old value from members table
                ach[mf] = [Member[params[:mbr_id]][mf.to_sym], nil]
              end
            end
            #expect a Time object for mbrship_renewal_date so check for that here
            if !ach["mbrship_renewal_date"][0].is_a?(DateTime)
              ach["mbrship_renewal_date"][0] = DateTime.parse(ach["mbrship_renewal_date"][0].to_s)
            end
            #since renewing membership, reset these for new values
            ach["mbrship_renewal_halt"][1] = false
            ach["mbrship_renewal_active"][1] = false
            ach["mbrship_renewal_contacts"][1] = 0
            #load new mbrship_renewal_date for this member
            ach["mbrship_renewal_date"][1] = MbrRenewal.getNewMbrshipRenewalDate(params[:mbr_id], params[:mbr_type])
            #finally, add the mbr_type
            ach["mbr_type"][1] = params[:mbr_type]
          end
          #going to put this info in the log
          log_pay.action_id = Action.get_action_id("mbr_renew")
          m = Member[params[:mbr_id]]
          if params[:mbr_type] == 'family'
            #get other family members; find the id for the family unit
            m.units.each do |mu|
              if mu.unit_type_id == UnitType.getID('family')
                mbr_family_unit_id = mu.id
              end
            end
            #validate this member is already a member of a family, need to set that up first
            if mbr_family_unit_id.nil?
              session[:msg] = "Payment FAILED; please set up the family unit first"
              redirect "/m/unit/create"
            end
            #associate logs with this unit
            log_pay.unit_id = mbr_family_unit_id
            log_unit.unit_id = mbr_family_unit_id
            #load members in this family, first test for existance of this unit
            Unit[mbr_family_unit_id].members.each do |f_member|
              #load ids for all besides the current member
              if f_member.id.to_s != params[:mbr_id]
                fam_mbr_ids << f_member.id
              end
            end
          elsif params[:mbr_type_old] == 'family'
            #member was previously in a family unit but no longer is paying as one
            #breaking from unit by either leaving an active unit or deactivating unit
            #find unit
            m.units.each do |mu|
              if mu.unit_type_id == UnitType.getID('family')
                mbr_family_unit_id = mu.id
              end
            end
            u = Unit[mbr_family_unit_id]
            #add unit id to the mbr_renew and unit log so can trace this member back to this unit in rollback
            log_pay.unit_id = u.id
            log_unit.unit_id = u.id
            if (Date.today.prev_year..Date.today).cover?(ach["mbrship_renewal_date"][0].to_date)
              #family already paid up but maybe family member splitting off?
              #check to see if there are only 2 members of this unit
              if augmented_notes != ''
                augmented_notes << "\n"
              end
              if u.members.length < 3
                #unlikely event and cause this to fail
                augmented_notes << "\n****member currently paid up is trying to pay again*****\nRecord NOT updated"
                session[:msg] = "The data was not entered successfully\nthis member in fam unit that already paid"
                log_pay.notes = augmented_notes
                log_pay.save
                redirect "/r/member/list"
              else
                #remove this member from unit it is assumed they are too old to use family membership
                augmented_notes << "\n****member currently paid up is trying to pay again*****\nwill remove from fam unit"
                Unit[mbr_family_unit_id].remove_member(m)
                #log this change to the unit
                log_unit.notes = "Unit mbr association[-mbr_id:#{m.id}], #{m.fname} #{m.lname} has been removed"
                mbr_split_frm_fam_unit = true
              end
            else#unit hasn't paid (yet)
              #are there only two members in this family unit?
              if u.members.length < 3
                #rename unit
                old_unit_name = u.name
                #need to test for null here
                if old_unit_name.nil?
                  old_unit_name = 'null'
                end
                u.name = "retired: #{u.name}, #{m.fname} #{m.lname}"
                auditlog_hash["unit_name"] = AuditLog.new
                auditlog_hash["unit_name"].set({"a_user_id" => session[:auth_user_id], "column" => "name",
                "changed_date" => Time.now, "old_value" => old_unit_name, "new_value" => u.name,
                "unit_id" =>  mbr_family_unit_id, "mbr_id" => params[:mbr_id]})
                #change member type of remaining member to 'none'
                u.members.each do |m2chng|
                  if m2chng.id != params[:mbr_id].to_i
                    m_to_change = Member[m2chng.id]
                    if ['honorary', 'lifetime'].include?(params[:mbr_type])
                      m_to_change.mbr_type = params[:mbr_type]
                      m_to_change.mbrship_renewal_date = DateTime.new(2100,01,01)
                    else
                      m_to_change.mbr_type = 'none'
                    end
                    m_to_change.save
                    #need to add to auditlog_hash so that auditlog record will be written for this member
                    auditlog_hash["mbr_type2"] = AuditLog.new
                    auditlog_hash["mbr_type2"].set({"a_user_id" => session[:auth_user_id], "column" => "mbr_type",
                      "changed_date" => Time.now, "old_value" => "family", "new_value" => "none",
                          "mbr_id" => m2chng.id})
                   end
                end
              elsif ['honorary', 'lifetime'].include?(params[:mbr_type]) #need to account for family becoming lifetime or honorary
                u.members.each do |m2chng|
                  m_to_change = Member[m2chng.id]
                  m_to_change.mbr_type = params[:mbr_type]
                  m_to_change.mbrship_renewal_date = DateTime.new(2100,01,01)
                  m_to_change.save
                end
              end
              #change unit active to 0 (not a functional unit)
              ach["fam_unit_active"] = []
              ach["fam_unit_active"][0] = u.active
              ach["fam_unit_active"][1] = 0
              u.active = 0
              u.save
              #remove this member from the unit
              mbr_split_frm_fam_unit = true
              u.remove_member(m)
              #log this change to the unit
              log_unit.notes = "Unit mbr association[-mbr_id:#{m.id}], #{m.fname} #{m.lname} has been removed\n"
              #add to AuditLog to enable rollback
              if ach["fam_unit_active"][0] != 0
                #will add pay id after pay is saved in DB.transaction
                auditlog_hash["fam_unit_active"] = AuditLog.new
                auditlog_hash["fam_unit_active"].set({"a_user_id" => session[:auth_user_id], "column" => "fam_unit_active",
                  "changed_date" => Time.now, "old_value" => ach["fam_unit_active"][0], "new_value" => ach["fam_unit_active"][1],
                      "mbr_id" => params[:mbr_id], "unit_id" => u.id})
              end
              #log this change to the unit
              log_unit.notes << "unit id: #{u.id} active status has gone from #{ach["fam_unit_active"][0]} to 0"
            end
          end #of if mbr_type is family elsif mbr_type_old is famly
          #if family then the other family members Members table change happens in the DB.transaction
          #now, for this member
          m.update({mbr_type: ach["mbr_type"][1], mbrship_renewal_date: ach["mbrship_renewal_date"][1],
            mbrship_renewal_halt: ach["mbrship_renewal_halt"][1], mbrship_renewal_contacts: ach["mbrship_renewal_contacts"][1],
            mbrship_renewal_active: ach["mbrship_renewal_active"][1]})
          #how much was paid?
          #dues payment can be from other_pmt or pay_amt depending on which entry chosen
          if params.has_key?(:other_pmt)
            pay_amt = params[:other_pmt].to_i
          else #need to find amt from payment model
            payFees = Payment.fees
            pay_amt = payFees[params[:mbr_type]]
          end
          if augmented_notes != ''
            augmented_notes << "\n"
          end
          if ach["mbrship_renewal_date"][0] != ach["mbrship_renewal_date"][1]
            augmented_notes << "**** Mbrship renewal date changed from #{ach["mbrship_renewal_date"][0]} to #{ach["mbrship_renewal_date"][1]}"
          end
          if params[:mbr_type] != params[:mbr_type_old]
            augmented_notes << "**** Member type changed from #{params[:mbr_type_old]} to #{params[:mbr_type]}"
          end
        else #end if Dues
          #payment must be a donation, set up for log
          log_pay.action_id = Action.get_action_id("donation")
          #find pay amount
          pay_amt = params[:nonDues_pmt]
        end
        pay = Payment.new(:mbr_id => params[:mbr_id], :a_user_id => session[:auth_user_id], :payment_type_id => params[:payment_type],
          :payment_method_id => params[:payment_method], :payment_amount => pay_amt, :ts => Time.now)
        begin
          DB.transaction do
            if PaymentType[params[:payment_type]].type == 'Dues'
              if ['honorary', 'lifetime', 'family'].include?(params[:mbr_type])
                #find out if this lifetime/honorary member
                is_fam = nil
                if params[:mbr_type] != 'family'
                  #does this person also belong to a family unit?
                  mus = Member[params[:mbr_id]].units
                  if mus.nil?
                    is_fam = false
                  else
                    mus.each do |mu|
                      if mu.unit_type_id == UnitType.getID('family')
                        mbr_family_unit_id = mu.id #get the id for logging purposes
                        Unit[mbr_family_unit_id].members.each do |f_member|
                          #load ids for all besides the current member
                          if f_member.id.to_s != params[:mbr_id]
                            fam_mbr_ids << f_member.id
                          end
                        end
                        is_fam = true
                      end
                    end
                  end
                else
                  is_fam = true
                end
                if is_fam == true #otherwise don't have other family members to update
                  #update other family members
                  fam_names = ""
                  #if there is temporarily only one family member of this unit, this will be skipped
                  #since that member has been removed from fam_mbr_ids
                  fam_mbr_ids.each do |mbr_id|
                    fm = Member[mbr_id]
                    #test to see if any family member's paid up status is > than this one
                    #need to check that there is a renewal date assoc w/ this family member convert Time obj to DateTime
                    rd = fm.mbrship_renewal_date
                    if !rd.nil?
                      mrd = DateTime.parse(rd.to_s)
                      if !fm.mbrship_renewal_date.nil? && (mrd > ach["mbrship_renewal_date"][1])
                        #bail with error
                        session[:msg] = "UNSUCCESSFUL; family mbr #{fm.fname} #{fm.lname}: mbrship renewal date, #{fm.mbrship_renewal_date} conflicts with #{m.fname} #{m.lname}: mbrship renewal date #{m.mbrship_renewal_date}"
                        redirect '/m/unit/list/family'
                      end
                    end
                    fam_names << "\nmbr_id#:#{fm.id}, #{fm.fname}, #{fm.lname}"
                    #add all cols in AuditLog::COLS_TO_TRACK
                    fm.mbrship_renewal_date = ach["mbrship_renewal_date"][1]
                    fm.mbrship_renewal_halt = ach["mbrship_renewal_halt"][1]
                    fm.mbrship_renewal_active = ach["mbrship_renewal_active"][1]
                    fm.mbrship_renewal_contacts = ach["mbrship_renewal_contacts"][1]
                    #test to see if mbr_type old is different from what is happening with this payment
                    if (fm.mbr_type != 'family' && fm.mbr_type != 'none')
                      fm.mbr_type = 'family'
                      auditlog_hash["#{fm.id}_mbr_mbr_type"] = AuditLog.new()
                      AuditLog::COLS_TO_TRACK.each do |ctt|
                        if ctt != "fam_unit_active"
                          auditlog_hash["#{fm.id}_mbr_mbr_type"].set({"a_user_id" => session[:auth_user_id], "column" => ctt,
                            "changed_date" => Time.now, "old_value" => fm[ctt.to_sym], "new_value" => ach[ctt][1],
                            "mbr_id" => fm.id})
                        end
                      end
                    elsif fm.mbr_type == 'none'
                      #only need to record mbr_type change in audit_log table
                      auditlog_hash["#{fm.id}_mbr_mbr_type"] = AuditLog.new()
                      auditlog_hash["#{fm.id}_mbr_mbr_type"].set({"a_user_id" => session[:auth_user_id], "column" => "mbr_type",
                        "changed_date" => Time.now, "old_value" => 'none', "new_value" => "family",
                        "mbr_id" => fm.id})
                    end
                    #reset this member's Member table row
                    fm.update({mbr_type: ach["mbr_type"][1], mbrship_renewal_date: ach["mbrship_renewal_date"][1],
                      mbrship_renewal_halt: ach["mbrship_renewal_halt"][1], mbrship_renewal_contacts: ach["mbrship_renewal_contacts"][1],
                      mbrship_renewal_active: ach["mbrship_renewal_active"][1]})
                    fm.save
                  end
                  if fam_mbr_ids.length == 0
                    log_unit.notes = "there is only one member of this family, sad"
                  else
                    #add names to log
                    log_unit.notes = "#{fam_names.sub("\n",'')} were also updated"
                  end
                  #make sure family unit is active
                  fu = Unit[mbr_family_unit_id]
                  if fu.active == 0
                    #need to set to 1 so keep auditLog record
                    auditlog_hash["fam_unit_active"] = AuditLog.new
                    auditlog_hash["fam_unit_active"].set({"a_user_id" => session[:auth_user_id], "column" => "fam_unit_active",
                      "changed_date" => Time.now, "old_value" => 0, "new_value" => 1})
                  end
                  fu.active = 1
                  fu.save
                end
              end #if params[:mbr_type] == 'family'
              #log these to the auditlog table for the paying member
              ach.each do |k,v|
                if k != "fam_unit_active" && ach["mbr_type"][0] != "none"
                  #only want to record all fields if previously, this mbr had mbr_type != 'none'
                  #test for difference between new and old
                  if v[0] != v[1]
                    auditlog_hash[k] = AuditLog.new
                    auditlog_hash[k].set({"a_user_id" => session[:auth_user_id], "column" => k,
                      "changed_date" => Time.now, "old_value" => v[0], "new_value" => v[1], "mbr_id" => params[:mbr_id]})
                  end
                  if k == "mbr_type" && mbr_split_frm_fam_unit == true
                    #have a family member paying as non-family, splitting off
                    #need to record audit_log changes to members_units join table
                    auditlog_hash["dropped_unit"] = AuditLog.new
                    auditlog_hash["dropped_unit"].set({"a_user_id" => session[:auth_user_id], "column" => "dropped_unit",
                    "changed_date" => Time.now, "old_value" => mbr_family_unit_id, "new_value" => "none",
                    "unit_id" =>  mbr_family_unit_id, "mbr_id" => params[:mbr_id]})
                  end
                elsif ach["mbr_type"][0] == "none"
                  #just logging this key to the audit_log table all others will be by default reset
                  auditlog_hash["mbr_type"] = AuditLog.new
                  auditlog_hash["mbr_type"].set({"a_user_id" => session[:auth_user_id], "column" => "mbr_type",
                    "changed_date" => Time.now, "old_value" => ach["mbr_type"][0], "new_value" => ach["mbr_type"][1], "mbr_id" => params[:mbr_id]})
                end
              end
              #only expecting to record unit logs if paying dues and is/was a member of a family unit
              #***** this may change however ***********
              if params[:mbr_type] == 'family' || params[:mbr_type_old] == 'family'
                log_unit.save
              end
              #finally, record the member data
              m.save
            end #if PaymentType[params[:payment_type]].type == 'Dues'
            #may need to associate the two logs (payment and unit)
            if !log_unit.id.nil?
              augmented_notes << "\nPayment Log Association[unit_log_id:#{log_unit.id}]"
            end
            log_pay.notes = augmented_notes
            log_pay.save
            #associate the log entry with this payment
            pay[:log_id] = log_pay.values[:id]
            pay.save
            #wrap up log for action if there needs to be one
            if (!log_action.notes.nil? || log_action.notes != "")
              log_action.save
            end
            #associate this payment record with any changes to member mbrship_renewal_date and mbr_type fields
            #also consider impact that this payment makes to the active status of a unit
            if al_save == true
              #if instance for specific (mbrship_renewal_date, mbr_type) auditLog been written to yet, then link payment record
              auditlog_hash.each do |k,v|
                if !v.a_user_id.nil?
                  v.pay_id = pay.id
                  if params[:mbr_type] == 'family'
                    v.unit_id = mbr_family_unit_id
                  end
                  v.save
                end
              end
            end
          end
          session[:msg] = 'Payment was successfully recorded'
        rescue StandardError => e
          session[:msg] = "The data was not entered successfully\n#{e}"
        end
        redirect "/m/payments/show"
      end

      app.get '/m/payments/edit/:id' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        @pay = Payment.select(:id, :mbr_id, :payment_type_id, :payment_method_id, :payment_amount, :log_id)[params[:id].to_i]
        @mbr = Member.select(:id, :fname, :lname, :callsign, :mbr_type)[@pay[:mbr_id]]
        @log = Log.select(:id, :notes)[@pay[:log_id]]
        @log[:notes] << "\n**** edited ******"
        @payType = PaymentType.all
        @payMethod = PaymentMethod.all
        erb :p_edit, :layout => :layout_w_logout
      end

      app.post '/m/payments/edit' do
        #params are {"pay_id"=>"28", "pay_log_id"=>"552", "payment_type"=>"2", "payment_method"=>"2", "payment_amt"=>"18.0", "notes"=>"some notes"}
        #only changing payment type, method, amount and log notes
        payTypes = {}
        PaymentType.select(:id, :type).map(){|x| payTypes[x.id]= x.type}
        log = Log[params[:pay_log_id]]
        augmented_notes = params[:notes]
        augmented_notes << Time.now.strftime("\nEdited on %m/%d/%Y")
        log.notes = augmented_notes
        ts = Time.now
        pay = Payment[params[:pay_id]]
        #validate
        pm = params[:payment_method]
        pt = params[:payment_type]
        pa = params[:payment_amt]
        if (pa == "" || pm == "" || pt == "")
          session[:msg] = 'Edit payment was UNSUCCESSFUL please make sure all fields are entered'
          redirect "/m/payments/edit/#{params[:pay_id]}"
        elsif (pt != pay.paymentType.id.to_s && (payTypes[pt] == "Dues" || payTypes[pay.paymentType.id] == "Dues"))
          #expecting params to be passing ids rather than the text representation
          #need to ask user to delete rather than edit this payment, then start over
          session[:msg] = 'Edit payment was UNSUCCESSFUL (cannot change dues type) please delete this payment and start over'
          redirect "/m/payments/edit/#{params[:pay_id]}"
        end
        pay.payment_method_id = pm
        pay.payment_type_id = pt
        pay.payment_amount = pa
        begin
          DB.transaction do
            log.save
            pay.save
          end
          session[:msg] = 'Edited payment was successfully recorded'
        rescue StandardError => e
          session[:msg] = "The data was not entered successfully\n#{e}"
        end
        redirect "/m/payments/show"
      end

      app.get '/m/payment/show/:id' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        @pay = Payment.select(:id, :mbr_id, :payment_type_id, :payment_method_id, :payment_amount, :log_id)[params[:id].to_i]
        #replace paymenyt_type_id and payment_method_id with the text representation
        #@pay[:payment_type] = PaymentType[@pay[:payment_type_id]].type
        @pay[:payment_type] = PaymentType.select(:type)[@pay[:payment_type_id]].values[:type]
        @pay[:payment_method] = PaymentMethod.select(:mode)[@pay[:payment_method_id]].values[:mode]
        #load the member and log info
        @mbr = Member.select(:id, :fname, :lname, :callsign, :mbr_type)[@pay[:mbr_id]]
        @log = Log.select(:id, :notes)[@pay[:log_id]]
        erb :p_show_one, :layout => :layout_w_logout
      end

      app.get '/m/payments/show' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        #build array of hashes to load payment data
        @pay = []
        pay = Payment.reverse_order(:ts, :a_user_id).all
        pay.each do |pmt|
          out = Hash.new
          out[:id] = pmt.id
          out[:mbr_name] = "#{pmt.member.fname} #{pmt.member.lname}"
          out[:auth_name] = "#{pmt.auth_user.member.fname} #{pmt.auth_user.member.lname}"
          out[:type] = pmt.paymentType.type
          out[:mode] = pmt.paymentMethod[:mode]
          out[:amount] = pmt.payment_amount
          if !pmt.log_id.nil?
            out[:notes] = pmt.log.notes
          else
            out[:notes] = "none"
          end
          out[:ts] = pmt.ts.strftime("%m-%d-%Y")
          @pay << out
        end
        erb :p_show, :layout => :layout_w_logout
      end

      app.get '/m/payments/destroy/:id' do
        @payment = Payment[params[:id]]
        erb :p_destroy, :layout => :layout_w_logout
      end

      app.post '/m/payments/destroy' do
        #params are {"pay_id"=>"28", "notes"=>"some notes", "confirm"=>"yes"}
        #should only be here to delete Dues payments
        if params[:confirm] != 'Yes'
          #js not enabled, need to find another way to confirm this action
          session[:msg] = "Payment was not deleted, please enable Javascript on your browser"
          redirect '/m/payments/show'
        end
        payment = Payment[params[:pay_id]]
        #if this payment is associated with a unit, look for more recent payments that would need to roll back 1st
        #also, need to test if this payment is associated with a family unit
        #if it is will need to see if other eariler payments were made on this unit
        more_recent_payments = Hash.new
        earlier_dues_unit_payments = false
        if !payment.log.unit.nil?
          unit_log_all = Log.where(unit: payment.log.unit)
          unit_log_all.each do |ul|
            if !ul.payment.nil?
              #get the time the payment associated with this unit if greater than current payment
              if ul.payment.ts > payment.ts
                more_recent_payments[ul.payment.id.to_s] = ul.payment.ts
              elsif ul.payment.ts < payment.ts && PaymentType[payment.payment_type_id].type == "Dues"
                #keep a record of earlier payments for this unit if true, then dont have to change mbr_type to none
                #for all members of the family unit
                earlier_dues_unit_payments = true
              end
            end
          end
        end
        if !more_recent_payments.empty?
          #need to alert the user and exit out of this route
          session[:msg] = "UNSUCCESSFUL, first delete payments made after this one in reverse order, #{more_recent_payments}"
          redirect '/m/payments/show'
        end
        #build the log notes
        old_au_id = payment.a_user_id
        auth_users_callsigns = {"old" => AuthUser[old_au_id].member.callsign, "new" => AuthUser[session[:auth_user_id]].member.callsign}
        #need to edit the log for this payment
        augmented_notes = params[:notes].empty? ? "" : "#{params[:notes]}\n"
        log_pay = Log[payment.log_id]
        augmented_notes = augmented_notes.empty? ? log_pay.notes : "#{augmented_notes}\n#{log_pay.notes}"
        #first what type of payment is this; get paymentTypes id
        paymentTypes = {}
        PaymentType.select(:id, :type).map(){|x| paymentTypes[x.type]= x.id}
        #see issue 267 need to allow other payment types to be deleted
        if payment.payment_type_id == paymentTypes["Dues"]
          #this is a dues payment then need to roll back from audit log
          audit_log_ids = []
          #load any auditLogs associated with this payment
          #expecting at most, six types of audit logs based on auditLog::COLS_TO_TRACK
          #"mbrship_renewal_date", "mbrship_renewal_halt", "mbrship_renewal_active",
          #"mbrship_renewal_contacts", "mbr_type", "fam_unit_active", "dropped_unit"
          #generate a hash for each
          array_of_audit_log_hashes = []
          #if there is no audit log throw an error
          if payment.auditLog.empty?
            #need to alert the user and exit out of this route
            session[:msg] = "UNSUCCESSFUL, this payment record does not have an audit trail, cannot delete payment id: #{payment.id}"
            augmented_notes << "\nattempt to delete payment id: #{payment.id} by #{AuthUser[session[:auth_user_id]].member.callsign} failed on #{Time.now.strftime("%m-%d-%y:%H:%M:%S")}"
            log_pay.notes = augmented_notes
            log_pay.save
            redirect '/m/payments/show'
          end
          payment.auditLog.each do |al|
            h = {"a_user_id" => al.a_user_id, "column" => al.column, "old_value" => al.old_value, "new_value" => al.new_value,
              "mbr_id" => al.mbr_id, "unit_id" => al.unit_id}
            array_of_audit_log_hashes << h
            audit_log_ids << al.id
          end
          array_of_audit_log_hashes.each do |alh|
            augmented_notes << "rolling back payment with #{alh["column"]} new value: #{alh["old_value"]} old value: #{alh["new_value"]}\n"
          end
        else
          augmented_notes << "deleting payment, see notes\n"
        end
        #set the log info
        augmented_notes << "executed by #{auth_users_callsigns["new"]}; originally by #{auth_users_callsigns["old"]} at #{log_pay.ts.strftime("%m-%d-%y:%H:%M:%S")}"
        log_pay.notes = augmented_notes
        log_pay.ts = Time.now
        begin
          DB.transaction do
            log_pay.save
            if payment.payment_type_id == paymentTypes["Dues"]
              #roll back member status on paid_up and possibly, mbr_type (if not a family)
              #if current member type is family need to rollback paid_up for all family members
              array_of_audit_log_hashes.each do |alh|
                case alh["column"]
                  #**************start of working on member table here **************
                when "mbrship_renewal_date"
                  m = Member[alh["mbr_id"]]
                  if alh["old_value"] == 'nil'
                    alh["old_value"] = nil
                  end
                  m[alh["column"].to_sym] = alh["old_value"]
                  m.save
                when "mbrship_renewal_halt", "mbrship_renewal_active","mbrship_renewal_contacts"
                  m = Member[alh["mbr_id"]]
                  m[alh["column"].to_sym] = alh["old_value"]
                  m.save
                when "mbr_type"
                  m = Member[alh["mbr_id"]]
                  if m.mbr_type != alh["old_value"] && alh["old_value"] == 'family'
                    #placing mbr back in a family unit, then need to find unit and add back
                    unit_id = alh["unit_id"]
                    if !unit_id.nil?
                      u = Unit[alh["unit_id"]]
                      u.add_member(m)
                    end
                  end
                  m.mbr_type = alh["old_value"]
                  if alh["old_value"] == 'none'
                    #this will be the only auditlog for this member but other columns need to be reset
                    m.mbrship_renewal_date = nil
                    m.mbrship_renewal_halt = false
                    m.mbrship_renewal_active = false
                    m.mbrship_renewal_contacts = 0
                  end
                  m.save
                when "mbr_leave_unit"
                  u = Unit[alh["unit_id"]]
                  m = Member[alh["mbr_id"]]
                  m.add_unit(u)
                  m.save
                  #**************END member table START unit table**************
                when "fam_unit_active"
                  u = Unit[alh["unit_id"]]
                  u.active = alh["old_value"]
                  u.save
                when "name"
                  u = Unit[alh["unit_id"]]
                  u.name = alh["old_value"]
                  u.save
                when "dropped_unit" #a member has separated from a family unit by paying independently as 'full'
                  u = Unit[alh["unit_id"]]
                  m = Member[alh["mbr_id"]]
                  m.add_unit(u)#add to join table members_units
                  m.save
                else
                  #shouldn't be here
                end
              end
              #enter into existing log (pay?, unit?)
              #check for unit_id, if present, need to add this
              audit_log_ids.each do |al_id|
                AuditLog[al_id].delete
              end
            end#end if dues, nothing special to do for other payments
            payment.delete
          end
          session[:msg] = 'Payment was SUCCESSFULLY deleted'
        rescue StandardError => e
          session[:msg] = "The payment WAS NOT deleted\n#{e}"
        end
        redirect '/m/payments/show'
      end

      app.get '/m/payments/report/:type/:format?' do
        @rpt_type = "all"
        if !params[:type].nil? #if optional parameter :type is not missing
          @rpt_type = params[:type]
        end
        @pay = []
        if @rpt_type == 'all'
          Payment.join(:members, id: :mbr_id).order(:ts, :payment_type_id, :lname).each do |p|
            temp = {}
            temp[:lname] = p.member.lname
            temp[:fname] = p.member.fname
            temp[:callsign] = p.member.callsign.empty? ? "N/A" : p.member.callsign
            temp[:pay_type] = p.paymentType.type
            temp[:pay_method] = p.paymentMethod.mode
            temp[:pay_amount] = p.payment_amount
            temp[:auth_user] = "#{p.auth_user.member.fname} #{p.auth_user.member.lname}"
            temp[:date] = p.ts.strftime(("%m-%d-%y"))
            temp[:hour] = p.ts.strftime(("%H"))
            @pay << temp
          end
        end
        #need to send :lname, :fname, :callsign, :pay_type, :pay_method, :pay_amount, :auth_user, :date
        if params[:format] == 'csv'
          erb :p_report_csv, :layout => :layout_w_logout
        else
          erb :p_report_html, :layout => :layout_w_logout
        end
      end

    end
  end
end
