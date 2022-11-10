mbrs = DB[:members].select(:id, :fname, :lname, :callsign, :mbrship_renewal_date, :mbr_type)
curnt = mbrs.where(mbrship_renewal_date: (Date.today - 365)..(Date.today))
@fam_count = 0
@full_count = 0
@hon_count = 0
curnt.each do |m|
  if m[:mbr_type]=="family"
    MemberTracker::Member[m[:id]].units.each do |u|
      if u.unit_type_id == MemberTracker::UnitType.getID("family")
        puts "***********************************************************\nmember #{m[:id]} is assoc w/ fam #{u[:id]}"
        u.members.each do |um|
          puts "fam mbr #{um[:id]} has renewal date #{um[:mbrship_renewal_date].nil?}"
          if um.callsign != 'NO CALL'
            @fam_count = @fam_count + 1
          end
        end
        puts "*******************END FAMILY #{u[:id]} *******************"
      end
    end
  elsif m[:mbr_type]=="full"
    @full_count = @full_count + 1
  elsif m[:mbr_type]=="honorary"
    @hon_count = @hon_count + 1
  end
end