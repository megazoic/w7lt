#script to apply latest dues payment date to members#mbrship_renewal_date
mbr_ids = DB[:members].select(:id).all
mbr_ids.each do |id|
  if /^\s/.match(DB[:members][id].email)
    puts "got it: #{id}"
  end
end
