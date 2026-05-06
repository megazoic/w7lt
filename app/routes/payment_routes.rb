module MemberTracker
  module PaymentRoutes
    def self.registered(app)

      app.get '/m/payment/new/:id' do
        @tmp_msg = session[:msg]
        session[:msg] = nil
        @mbr_pay = Member.select(:id, :fname, :lname, :callsign, :mbrship_renewal_date,
        :mbr_type, :mbrship_renewal_contacts, :mbrship_renewal_active, :mbrship_renewal_halt)[params[:id].to_i]
        if @mbr_pay.nil?
          session[:msg] = "Member not found"
          redirect '/r/member/list'
        end
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
        result = PaymentService.call(params, session[:auth_user_id])
        session[:msg] = result.message
        redirect result.redirect_path
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
          log_error(e)
          session[:msg] = "The data was not entered successfully"
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
          log_error(e)
          session[:msg] = "The payment WAS NOT deleted"
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
