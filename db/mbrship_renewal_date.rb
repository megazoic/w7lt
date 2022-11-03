#script to apply latest dues payment date to members#mbrship_renewal_date
mbr_ids = DB[:members].select(:id).all
mbr_ids.each do |mbr_id_hash|
  latest_dues_payment_date  = nil
  if !MemberTracker::Member[mbr_id_hash[:id]].payments.empty?
    MemberTracker::Member[mbr_id_hash[:id]].payments.each do |p|
      if p[:payment_type_id] == 5
        if !latest_dues_payment_date.nil?
          latest_dues_payment_date < p[:ts] ? latest_dues_payment_date = p[:ts] : nil
        else
          latest_dues_payment_date = p[:ts]
        end
      end
    end
    puts "setting mbr_id: #{mbr_id_hash[:id]} with payment date #{latest_dues_payment_date}"
    m = MemberTracker::Member[mbr_id_hash[:id]].set(mbrship_renewal_date: latest_dues_payment_date)
    m.save
  else
    puts "mbr_id #{mbr_id_hash[:id]} has no payments"
  end
end