require_relative '../config/sequel'

module MemberTracker
  class Member < Sequel::Model
    one_to_one :auth_user, :class=>"MemberTracker::Auth_user", key: :mbr_id
    one_to_many :logs, :class=>"MemberTracker::Log", key: :mbr_id
    many_to_many :units, left_key: :mbr_id, right_key: :unit_id, join_table: :members_units
    many_to_many :events, left_key: :mbr_id, right_key: :event_id, join_table: :members_events
    one_to_many :payments, :class=>"MemberTracker::Payment", key: :mbr_id
    one_to_many :audit_logs, :class=>"MemberTracker::AuditLog", key: :mbr_id
    many_to_one :refer_types, :class=>"MemberTracker::ReferType", key: :refer_type_id
    #keep sk last so can remove for payment route
    @mbr_types = ['family', 'student', 'full', 'honorary', 'none', 'sk']
    @modes = {'1' => 'phone', '2' => 'cw', '3' => 'rtty', '4' => 'msk:ft8/jt65', '5' => 'digital:other',
      '6' => 'packet', '7' => 'psk31/63', '8' => 'video:sstv', '9' => 'mesh network'}
    class << self
      attr_reader :mbr_types, :modes
    end
    
    def record(member_data)
      unless member_data.key?('lname')
        message = 'Invalid member: \'lname\' is required'
        return RecordResult.new(false, nil, message)
      end
      member = Member.new(member_data)
      member.save
      RecordResult.new(true, member.id, nil)
    end
    def members_with_lastname(name)
      matching_members = Member.where(lname: name).all
      matching_members
      #data_out = []
      #matching_members.each {|m| data_out << m.values}
      #data_out
    end
    def validate_dupes(guest_to_test)
      #expecting guests_to_test is hash containing at least 2/3 [:fname, :lname, :callsign]
      #mbrs = Member.select(:fname, :lname, :callsign, :email).all
      #first, need to make sure hash is in correct format
      need_to_transform = false
      guest_to_test.each do |k,v|
        if k.is_a?(String)
          need_to_transform = true
        end
      end
      if need_to_transform == true
        guest_to_test.transform_keys!(&:to_sym)
      end
      dupe_member = Member.where(guest_to_test).first
      if !dupe_member.nil?
        return 1
      end
      return 0
    end
  end
end